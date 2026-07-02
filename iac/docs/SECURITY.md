# Security & data-residency posture

> What's enforced vs. what's a gated next step. Encryption detail: [ENCRYPTION-AT-REST](ENCRYPTION-AT-REST.md).
> Network model: [NETWORKING](NETWORKING.md). Egress paths: [INTERNAL-CONNECTIONS §4](INTERNAL-CONNECTIONS.md).

## Enforced now

| Control | Status | Where |
|---|---|---|
| No public IPs on datastore/RKE2 VMs | ✅ | `terraform/*.tf` (no `access_config` except HAProxy) |
| Only the edge is public — 2 HAProxy VMs, `:443` only | ✅ | `firewall.tf` `edge_haproxy` |
| Admin plane off the internet (SSH, kube-API, HAProxy stats via IAP only) | ✅ | `firewall.tf` `iap_*` |
| TLS at every pod (north-south + east-west) | ✅ | per-pod nginx sidecar, `wildcard-tls` |
| East-west stays in-VPC (split-horizon CoreDNS) | ✅ | `k8s/coredns-direct.yaml` |
| Disk encryption at rest (Google-managed or CMEK) | ✅ | all disks; `DISK_KMS_KEY` |
| Kubernetes Secrets / etcd encrypted at rest | ✅ | RKE2 `secrets-encryption: true` |
| SeaweedFS objects encrypted at rest (SSE, enforced) | ✅ | `30-filer-s3.yaml` guard + KEK |
| Fresh datastore creds per cluster (no reuse) | ✅ | `credgen` + `sync-app-db-creds.py` |
| Shielded VMs (secure boot, vTPM, integrity) | ✅ | `shielded_instance_config` on every VM |

## Firewall (ingress) — all else denied by GCP default

| Rule | From | To | Ports |
|---|---|---|---|
| `allow-internal` | the 3 subnet CIDRs | any VM | all (intra-VPC east-west) |
| `allow-iap-ssh` | IAP `35.235.240.0/20` | any VM | 22 |
| `allow-iap-k8s-api` | IAP | rke2-server | 6443 |
| `allow-edge-haproxy` | `edge_allowed_cidrs` | haproxy | 443 |
| `allow-iap-haproxy-stats` | IAP | haproxy | 8404 |
| `allow-haproxy-nodeports` | edge subnet | rke2-agent | 30000-32767 |

## Gated next steps (flagged — not silently enabled)

1. **Egress lockdown** — default-deny + allowlist rules are **written but commented** in
   `terraform/firewall.tf` (left open during bootstrap so nodes can pull ECR/OS/ACME). Enable post-bootstrap
   with an allowlist for: ECR ranges, Route53/ACME, and any approved third-party (OpenAI, Akamai, RTC,
   Composio). This is the switch that turns "works" into "meets data-residency".
2. **Tighten `edge_allowed_cidrs`** in `customer.conf` from `0.0.0.0/0` to real client/VPN ranges.
3. **NetworkPolicies** — the pod network is currently flat; add default-deny + per-service allows.
4. **PodSecurity `restricted`** — some pods harden (non-root, read-only rootfs), not all yet.
5. **mTLS east-west** — today apps trust the public LE CA over the sidecar TLS (no client certs); acceptable
   on the private VPC, upgradeable to mTLS.
6. **HAProxy VIP (keepalived)** — optional, if a single stable edge IP is preferred over DNS round-robin.

## Data that can leave the VPC (review before go-live)

Only via Cloud NAT, only these paths (see [INTERNAL-CONNECTIONS §4](INTERNAL-CONNECTIONS.md)): OpenAI
(ai-agent, moderation), Route53 (cert-manager), ECR/OS repos (pulls), and customer-enabled third parties.
Anything with live external API keys (e.g. S3/SQS/Lambda in ai-agent config) must be reviewed against the
residency requirement before enabling egress to it.

## Secrets handling

`secrets/**` is gitignored (only `*.env.example` + READMEs are tracked). Real values live locally / in the
cluster only. The SSE-KEK (`secrets/infra/seaweedfs/sse-kek`) and `ansible/.vault_pass` must be **backed up
out-of-band** — losing the KEK strands encrypted objects; losing the vault pass blocks re-runs.
