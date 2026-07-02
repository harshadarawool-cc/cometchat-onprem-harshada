# Encryption at rest

> Requirement: **all storage encrypted at rest.** This build layers three independent mechanisms — disk,
> Kubernetes secrets/etcd, and object-store (SeaweedFS SSE) — so a compromise of any single layer does not
> expose plaintext data.

## Layer 1 — Disk (all GCP Persistent Disks)

**GCP Persistent Disks are ALWAYS encrypted at rest.** By default with **Google-managed keys** (AES-256);
this already satisfies "encrypted at rest" for every boot + data disk (RKE2 nodes, datastore VMs, HAProxy
VMs, SeaweedFS local-path volumes).

For **customer-managed keys (CMEK)**, set `DISK_KMS_KEY` in `deploy/customer.conf` to a Cloud KMS CryptoKey
self-link. Terraform threads it into **every** disk:

- boot disks — `boot_disk { kms_key_self_link = ... }` in `haproxy.tf`, `rke2.tf`, `datastores.tf`, `bastion.tf`
- datastore data disks — `disk_encryption_key { kms_key_self_link = ... }` in `datastores.tf`

```conf
# deploy/customer.conf
DISK_KMS_KEY="projects/<proj>/locations/<region>/keyRings/<ring>/cryptoKeys/<key>"   # empty = Google-managed
```

Prereq for CMEK: grant the Compute Engine service agent `roles/cloudkms.cryptoKeyEncrypterDecrypter` on the
key. Verify: `gcloud compute disks describe <disk> --format='value(diskEncryptionKey.kmsKeyName)'`.

## Layer 2 — Kubernetes Secrets / etcd (RKE2 secrets-encryption)

RKE2 is configured with **`secrets-encryption: true`** (`ansible/roles/rke2_server`), so Kubernetes
`Secret` objects are **encrypted at rest in etcd** (RKE2 manages the `EncryptionConfiguration` + AES-CBC
provider). Without this, secrets sit base64-only in etcd. This protects every credential the deploy stores
as a Secret: datastore passwords, JWT keys, licences, S3 keys, the SSE-KEK, TLS keys.

Verify:
```bash
# on a server node
sudo grep -q 'secrets-encryption: true' /etc/rancher/rke2/config.yaml && echo enabled
sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml \
  get --raw /api/v1/namespaces/cometchat/secrets/wildcard-tls | head -c0   # served decrypted to authorized API only
# etcd on disk is ciphertext: `rke2 secrets-encrypt status` shows the active AES provider
sudo rke2 secrets-encrypt status
```

## Layer 3 — Object store (SeaweedFS SSE-S3)

SeaweedFS 4.37 encrypts **object data on the volume servers** using an **SSE-S3 KEK**. This build
**enforces** it — the filer **refuses to start** without the key:

- `deploy.sh phase_secrets` (in `k8s/seaweedfs/deploy.sh`) generates the KEK **once**, persists it at
  `secrets/infra/seaweedfs/sse-kek`, and loads it into the `seaweedfs-sse-kek` Secret.
- `k8s/seaweedfs/30-filer-s3.yaml` sets `WEED_S3_SSE_KEY` from that Secret and wraps the entrypoint in a
  **guard**: `if [ -z "$WEED_S3_SSE_KEY" ]; then echo FATAL…; exit 1; fi` (CrashLoopBackOff instead of
  silently running unencrypted). `-s3.encryptVolumeData` is also set as an intent signal.

> ⚠️ **Back up `secrets/infra/seaweedfs/sse-kek`.** Losing it makes every encrypted object unrecoverable.
> It is generated once and never rotated (rotating it strands existing objects).

Verify: the filer boots (not CrashLoop) and `WEED_S3_SSE_KEY` is set:
```bash
kubectl -n cometchat get secret seaweedfs-sse-kek -o jsonpath='{.data.kek}' | base64 -d | wc -c   # 64
kubectl -n cometchat logs seaweedfs-filer-0 | grep -i 'S3 API' && echo "filer up with KEK"
```

## In transit (not "at rest", but part of the residency story)

- North-south + east-west: TLS at every pod (`wildcard-tls`), see [NETWORKING](NETWORKING.md).
- Datastore links ride the private VPC only (no public IPs); further hardening (mTLS, egress lockdown,
  NetworkPolicies) is tracked in [SECURITY](SECURITY.md).

## Summary

| Data | At-rest mechanism | Enforced by |
|---|---|---|
| All VM disks (boot + data) | GCP PD encryption (Google-managed or **CMEK**) | GCP + `DISK_KMS_KEY` in terraform |
| Datastore data (Mongo/Kafka/TiDB/MySQL/Redis) | the encrypted data disk under it | same |
| Kubernetes Secrets / etcd | RKE2 `secrets-encryption: true` (AES) | `ansible/roles/rke2_server` |
| SeaweedFS objects | SSE-S3 KEK (`WEED_S3_SSE_KEY`) + startup guard | `k8s/seaweedfs/30-filer-s3.yaml` + `deploy.sh` |
