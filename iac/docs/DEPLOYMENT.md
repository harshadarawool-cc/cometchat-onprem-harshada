# Deployment — the one-click runbook

> Zero → fully-working CometChat backend on GCP + RKE2 with the HAProxy edge. One orchestrator
> (`deploy/deploy.sh`), every phase idempotent. Architecture: [ARCHITECTURE](ARCHITECTURE.md).

## Prerequisites

- CLIs: `gcloud` (authenticated, project set), `terraform`, `ansible`, `kubectl`, `jq`, `openssl`,
  `python3`, `aws` (profile `staging` for ECR + Route53).
- IAM: the caller needs `roles/iap.tunnelResourceAccessor` (all SSH + kube-API + HAProxy stats go via IAP).
- Files present (gitignored): `ansible/.vault_pass`, `ansible/ssh/cometchat_rke2` (+ `.pub`), the licence
  file at `LICENCE_FILE`, and `secrets/apps/*` for the app phase.
- Quotas: ≥ ~27 VM instances (25 datastore/RKE2 + 2 HAProxy) and disk `DISKS_TOTAL_GB` headroom
  (`pd-standard` avoids the SSD cap). `deploy.sh preflight` checks this.

## Configure (the one file you edit)

`deploy/customer.conf` — project/zone, `PREFIX`, subnet CIDRs, sizing, `DOMAIN`, `R53_ZONE_ID`,
`LICENCE_FILE`, `AWS_PROFILE`, **`HAPROXY_COUNT=2`**, and **`DISK_KMS_KEY`** (empty = Google-managed
encryption; set for CMEK — [ENCRYPTION-AT-REST](ENCRYPTION-AT-REST.md)).

## Deploy

```bash
cd iac/deploy
./deploy.sh config          # render terraform.tfvars from customer.conf
./deploy.sh all             # infra → datastores → seed → apps → edge → HAProxy → certs → verify  (~60–90 min)
cd .. && ./dns-point.sh     # point Route53 A-records (round-robin) at the 2 HAProxy IPs
./deploy/deploy.sh status
```

Or staged:
```bash
./deploy.sh                 # INFRA only (VMs incl. HAProxy, datastores, RKE2, seed)
./deploy.sh app-all         # APP phase (gated): secrets → … → edge → haproxy → certs → verify
```

## Phase order (encoded in `all`) — a dependency chain

```
preflight → infra → inventory → datastores-wait → credgen → datastores → rke2 → seed →
secrets → certs → coredns → support → storage → editors → apps → node-apps → edge → haproxy →
storage-seed → verify
```

**Why this exact order (the "apps come up healthy" rule):** an app must not start until everything it needs
at boot already exists —
1. **certs before apps** — the per-pod nginx sidecars load `wildcard-tls` **at startup**, so the *real*
   Let's Encrypt cert must be issued first (else east-west HTTPS verifies against the self-signed bootstrap
   cert `phase_secrets` created as a fallback).
2. **coredns before apps** — apps resolve each other by on-prem FQDN at boot (chatapi → `rule-onprem`,
   `notifications-onprem`, `media-onprem`, …). Split-horizon DNS must be live first, or those calls fail.
3. **backends before apps** — `support` (OpenSearch + es-indexes), `storage` (SeaweedFS + `seaweedfs-edge`),
   `editors` (etherpad DB) must exist before the apps that depend on them (service-search, chatapi media,
   document-embed).

Phase notes:
- **infra** — terraform: VPC, firewall, 25 datastore/RKE2 VMs + **2 HAProxy VMs** (+ 2 public IPs), encrypted disks.
- **inventory** — reads `terraform output haproxy_ips` → writes `edge_public_ips` into ansible group_vars.
- **credgen** — fresh per-cluster datastore passwords (synced into DBs *and* app secrets). [CREDENTIALS-FLOW](CREDENTIALS-FLOW.md)
- **datastores** — Mongo/Redis/Kafka(+topics)/TiDB/MySQL provisioned via ansible.
- **rke2** — 1 server (`secrets-encryption: true`) + 3 agents; kubeconfig via IAP tunnel.
- **seed** — MySQL dumps + Mongo/VCB/moderation seeds + Mongo app users. [SEEDING](SEEDING.md)
- **secrets** — app `.env`/config secrets, ECR pull secrets, JWT keys, **bootstrap self-signed wildcard-tls**.
- **certs** — cert-manager + Let's Encrypt wildcard (Route53 DNS-01) → replaces `wildcard-tls` with the real cert.
- **coredns** — applies `coredns-direct.yaml` (per-FQDN direct-to-Service split-horizon).
- **support/storage/editors** — OpenSearch(+es-indexes)/Ollama/Mailpit, SeaweedFS(+edge), etherpad DB.
- **apps/node-apps** — curated app manifests + node-only apps (websocket/moderation/vcb/ai-agent + workers).
- **edge** — applies `edge-nodeports.yaml` (facing `:443` → fixed NodePorts).
- **haproxy** — `ansible haproxy.yml` renders + validates `haproxy.cfg` on both edge VMs.
- **storage-seed** — LATE SeaweedFS public-bucket assets + ACLs (signs against `media-onprem`; needs certs+coredns).
- **verify** — datastores healthy, every `EXPECTED_WORKLOADS` Ready, split-horizon DNS correct.

## Verify (end-to-end)

```bash
# 1) infra + edge
terraform -chdir=terraform output haproxy_ips        # 2 IPs
gcloud compute start-iap-tunnel <prefix>-haproxy-1 8404 --local-host-port=localhost:8404 --zone <zone> &
curl -s localhost:8404/stats | grep -c ' UP'         # backends UP

# 2) SNI routing + pod-terminated cert
openssl s_client -servername api-onprem.cometchat-cluster-2.in -connect <haproxy-ip>:443 </dev/null 2>/dev/null | openssl x509 -noout -issuer

# 3) all 16 apps healthy through the live edge (see SERVICES.md for each health path)
for h in api-onprem:/health-check apimgmt:/health-check app:/ metrics-onprem:/ extensions-onprem:/v1/health-check notifications-onprem:/health-check; do
  host=${h%%:*}; path=${h#*:}; echo -n "$host$path → "; curl -s -o /dev/null -w '%{http_code}\n' "https://$host.cometchat-cluster-2.in$path"
done

# 4) split-horizon (east-west stays in-cluster)
kubectl -n cometchat run d --rm -it --image=busybox:1.36 --restart=Never -- nslookup api-onprem.cometchat-cluster-2.in   # → chatapi ClusterIP

# 5) encryption at rest
kubectl -n cometchat get secret seaweedfs-sse-kek -o jsonpath='{.data.kek}' | base64 -d | wc -c   # 64
sudo rke2 secrets-encrypt status        # (on a server node) AES provider active

# 6) object store
aws s3 cp /tmp/x.png s3://uploads/_probe/x.png --endpoint-url https://media-onprem.cometchat-cluster-2.in

./deploy.sh verify        # the aggregate check
```

## Common re-runs

```bash
./deploy.sh haproxy       # re-render HAProxy after changing the service map
./deploy.sh edge          # re-apply NodePort overlay
./deploy.sh coredns       # re-apply split-horizon
./deploy.sh storage       # converge SeaweedFS ; ./deploy.sh storage-seed for the late asset seed
./dns-point.sh            # re-point DNS after an IP change
```

## Teardown

```bash
cd deploy && ./destroy.sh        # terraform destroy (keeps the reserved addresses if you want stable IPs)
```
