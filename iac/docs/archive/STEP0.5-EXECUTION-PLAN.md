# Step 0.5 — Backup → Teardown → Rebuild (execution plan)

Status: **PLAN for your explicit go. Nothing destroyed yet.** Live cluster untouched.

## Decisions locked
- **Scrap `cometchat-onprem-test`** (the LIVE cluster serving `cometchat-cluster-2.in` → `34.14.165.34`, on `10.22.x`).
- **Build a NEW test-scale cluster** with the corrected foundation (Steps 1–3), then validate, then rebuild as HA.
- **`cometchat-onprem-v2`** (on `10.21.x`) — left untouched for now; flagged for later cleanup.
- **Ghost `cometchat-onprem`** (empty LB/IP/subnets on `10.20.x`, stale terraform state) — clean up separately.
- **NEW DB credentials** — fresh unique per-service users + strong passwords, no shared/root reuse (see §D).

---

## A. BACKUP `-test` first (safe, required — before any destroy)
Access: IAP tunnel to `cometchat-onprem-test-k8s-master-1` (10.22.20.11) + DB VMs (the stale `kube-tunnel.sh`
points at the ghost prefix — I'll target `-test` explicitly).

| Data | Source | Method → destination |
|---|---|---|
| MySQL | `10.22.10.41` | `mysqldump` `pulsecustomerdb`, `metrics`, `analytics_logs` (+ all) → `backups/test-<date>/mysql/` |
| TiDB | `10.22.10.51:4000` | dump `chatapi` + **every `cod_*` per-app DB** → `backups/test-<date>/tidb/` |
| MongoDB | `10.22.10.11` | `mongodump` all DBs (moderation, vcb, events, notifications-core-db, chat) → `.../mongo/` |
| Object store | SeaweedFS (in-cluster) | export media / stickers / uploads via `weed filer.copy`/S3 sync → `.../objects/` |
| Redis ×4 | `10.22.10.{21,24,27,61}` | `BGSAVE` snapshot (mostly cache — capture for safety) |
| k8s state | `-test` cluster | `kubectl get -A -o yaml` (all resources) + **all secrets** → `.../k8s/` |
| DNS | Route53 zone `Z04640112BJ8TJHK3I2RI` | fresh export → `.../route53.json` (already have a Jun-22 backup) |
| Config | `GCP_RKE2/iac` | `customer.conf`, `secrets-rendered/`, `terraform.tfstate` copied |

**I will confirm every backup's size/row-counts and print where they live before proceeding.** No teardown until
backups are verified AND you give the go.

## B. TEARDOWN `-test` (only after backup verified + your explicit YES)
**Destroy:** the 13 `-test` VMs + their disks · `cometchat-onprem-test-edge` LB (backend + forwarding-rule +
health-check) · `cometchat-onprem-test-edge-ip` (34.14.165.34) · the `-test` subnets (`10.22.x`).
**Keep:** `-v2` (untouched) · the shared VPC · Route53 zone (re-pointed to the new edge later) · all backups.
Method: `gcloud` targeted deletes (—test is outside the tracked tfstate) or a scoped destroy.
> Domain goes down when `-test` dies and comes back when the new cluster's edge IP is DNS-cut-over — expected,
> since you chose scrap-and-rebuild over keep-as-fallback.

## C. BUILD the new test cluster (corrected foundation)
- **Prefix / CIDR (proposed):** `cometchat-onprem-v3` on **`10.23.x`** (cluster `10.23.20`, data `10.23.10`,
  edge `10.23.30`) — clean, no collision with `-test`/`-v2`/ghost. Fresh terraform state in this folder.
- **Networking (Step 1):** firewall **inbound-closed** (443-only edge, IAP 22/6443, GCP health-checks; egress open),
  single **managed L4 LB + reserved IP**, RKE2 **1 master + 3 workers** (test-scale), **dedicated DB VMs**.
  **Per-pod TLS sidecars** + **CoreDNS direct-to-Service** + **wildcard cert** (DNS-01). Hybrid N-S edge.
- **Seeding (Step 2):** all 7 dumps in-repo + **onprem-features.sql** + **moderation** + **vcb.templates** +
  **ES indexes** + mgmt warm-up (portable, no dead external paths).
- **Apps (Step 3):** **latest image digests** (your 3 pins fixed), corrected env/mounts, **drop the shims**
  (extensions lp-patch, analytics `[::1]` forwarder, chatapi TiDB migrate-loop — verify).
- **Validate:** Create App · moderation loads · VCB template · search · link-preview on-send · realtime.
- **Then:** rebuild the same shape with **HA** (3 masters, multi-zone, DB replication).

## D. NEW DB credentials (your new requirement)
Replace the "same password everywhere" with **fresh, unique, per-service users + strong random passwords**
(`openssl rand`), least-privilege where feasible, wired into each app's env + the k8s secrets:
| Datastore | New users (scoped) |
|---|---|
| **MySQL** | admin + per-DB app users: `mgmt`→`pulsecustomerdb`, `metricspro`→`metrics`, `analytics`→`analytics_logs` |
| **TiDB** | `chatapi` app user + a `creator` user (needs `CREATE DATABASE` for per-app `cod_*` provisioning — privileged by necessity) |
| **MongoDB** | per-service app users: chatapi, moderation, vcb, notifications, webhooks — each scoped to its DB |
| **Redis ×4** | a distinct `requirepass` per cluster (shared/analytics/bullmq/prometrics) |
| **Kafka / OpenSearch** | currently no-auth (matches reference); enabling SASL/security = optional hardening — flag |

The `db-users` playbook creates the users; `secrets-rendered/<svc>.env` + the k8s secrets carry the new creds
(`DB_PASSWORD`, `MONGO_URI`, `REDIS_PASSWORD`, …). Passwords generated fresh, never committed in plaintext to git.

---
## The go I need
1. **Start the `-test` backup now?** (safe, read-only-ish — connects to the live DBs and dumps them)
2. Confirm the new cluster **prefix/CIDR** (`cometchat-onprem-v3` / `10.23.x`) — or your preferred name.
3. After backups are verified, **explicit YES to destroy `-test`** (I'll re-confirm at that point).
