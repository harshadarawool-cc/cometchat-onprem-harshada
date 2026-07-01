# CometChat on GCP RKE2 — The Full Project Journey

> **One document, start to finish.** What we set out to do, what we built, every
> blocker we hit and how we fixed it, the new tooling/techniques we introduced, how we
> tweaked the deploy pipeline, and the workarounds that made the obfuscated images run.
>
> This is the *narrative* overview. The companion docs hold the detail:
> - [PROBLEMS-AND-FIXES.md](PROBLEMS-AND-FIXES.md) — the build journal (every infra issue, baked-in fix)
> - [NETWORK-AND-SECURITY.md](NETWORK-AND-SECURITY.md) · [NETWORK-FLOW.md](NETWORK-FLOW.md) — networking & hardening
> - [EXTERNAL-DEPENDENCIES.md](EXTERNAL-DEPENDENCIES.md) — egress audit
> - [DATASTORE-ENDPOINTS.md](DATASTORE-ENDPOINTS.md) — datastore rewrite map
> - [HA-AND-SIZING-PLAN.md](HA-AND-SIZING-PLAN.md) — the deferred HA/right-sizing pass
> - [deploy/README.md](deploy/README.md) — the runbook
>
> Project `onprem-499712` · region `asia-south1-a` · VPC `cometchat-onprem-vpc` · domain `cometchat-cluster-2.in`
> _Last updated: 2026-06-24_

---

## 1. The mission

Migrate CometChat's containerized stack from **Akamai/Linode LKE** (managed Kubernetes) to
**RKE2 on plain GCP Compute Engine VMs**, so a **customer can run the entire stack on their own
machines**. This is not a lift-and-shift of a normal app — four constraints make it unusual:

1. **No CI/CD.** The customer gets pre-built images and deploys them. The Akamai
   Jenkins → Kaniko → Harbor flow does **not** carry over. The secrets bridge cannot depend on Jenkins.
2. **Obfuscated, licensed images.** Not the "normal code" Harbor images — these are hardened/
   ionCube/bytenode-obfuscated images from **ECR** (`894996064311.dkr.ecr.us-east-2.amazonaws.com/on-prem-docker-images`),
   each requiring a CometChat **on-prem license** mounted as a secret.
3. **Data must not leave the customer network.** Every networking and security decision is driven by
   **data residency** — private VMs, one minimal public edge, split-horizon DNS, default-deny egress.
4. **Production-copyable.** It's a test environment that must drop into the customer's production with
   minimal change.

**Source → target translation:**

| Akamai / LKE (source) | GCP RKE2 (target) |
|---|---|
| LKE managed control plane | self-managed **RKE2** (no cloud-controller) |
| Linode NodeBalancer (per-service) | one **Terraform-managed external TCP LB** → ingress-nginx |
| linode-block-storage StorageClass | local-path-provisioner / GCP PD |
| g6-* instance types | e2-standard VMs |
| Managed datastores in LKE | **dedicated DB VMs** (Mongo/Redis/Kafka/TiDB/MySQL) |
| Vault (standalone, per-service KV) | **direct k8s secrets**, built from a staging Vault dump, datastore-rewritten |
| Per-pod nginx TLS sidecar on every app | TLS only at the **edge ingress** + the 2 PHP pods |

---

## 2. What we built (as-built architecture)

**25 VMs**, prefix `cometchat-onprem-`, three private subnets, **no public IPs except one edge LB.**

```
                          Internet
                             │
                  external TCP Network LB  (terraform/lb.tf, dynamic IP)
                             │  :80/:443
              ┌──────────────┴───────────────┐
              │  ingress-nginx (DaemonSet,    │   edge subnet 10.20.30.0/24
              │  hostPort 80/443 on workers)  │   bastion 10.20.30.10
              └──────────────┬───────────────┘
   cluster subnet 10.20.20.0/24                data subnet 10.20.10.0/24
   ├ k8s-master-1   .11   (RKE2 server/etcd)   ├ mongo-1/2/3      .11/.12/.13   (rs0)
   ├ k8s-worker-1   .21                         ├ redis-shared    .21/.22/.23
   ├ k8s-worker-2   .22                         ├ redis-analytics .24/.25/.26
   └ k8s-worker-3   .23                         ├ redis-prometrics.27/.28/.29
                                                ├ redis-bullmq    .61/.62/.63
                                                ├ kafka-1/2/3     .31/.32/.33  (KRaft)
                                                ├ mysql-1         .41          (MySQL 8)
                                                └ tidb-1          .51          (TiDB + TiProxy)
```

- **4 dedicated Redis Sentinel clusters** (not one shared): `shared`, `analytics`, `prometrics`, `bullmq` — 3 VMs each, master = node-1, `mymaster`, ports 6379/26379. `bullmq` is offset to **.61** so it never collides with the .21–.29 block.
- **Kafka** is **KRaft** (no ZooKeeper), 3-broker quorum.
- **TiDB** runs PD+TiKV+TiDB+**TiProxy** under docker-compose on one VM (MySQL wire on :3306, control on :4000).
- **In-cluster support services:** OpenSearch (+ ES8 nginx proxy), Ollama, Mailpit, **SeaweedFS** (the S3/object-storage replacement = `media-onprem`), Qdrant.
- **App workloads:** ~18 services. Only **chatapi & mgmtapi** (PHP/Laravel) get an nginx sidecar (PHP-FPM is FastCGI-only); every Node/Python app serves HTTP natively as ClusterIP.

**Coexists with the OLD, kept-but-stopped infra** (`cometchat-ds-*` 10.40.x, `cometchat-gke` 10.10.x, old VPC) — **never touch it.** It's why we hit the SSD quota wall (see below).

---

## 3. The deployment pipeline (`deploy/deploy.sh`)

The whole build is encoded in **one phased, idempotent orchestrator** — the executable form of every
fix in this document. _"If I destroy this infra, one click should make it ready again, with all the
fixes baked in."_

```
./deploy.sh            # one-click INFRA rebuild (zero → datastores → RKE2 → seed)
./deploy.sh app-all    # gated APP phase (secrets → support → apps → ingress)
./deploy.sh all        # everything
./deploy.sh <phase>    # run a single phase by name
./deploy.sh status     # cluster status
```

**Phases:** `preflight → infra (terraform) → inventory → datastores-wait → datastores → rke2 → seed`
then the app side `secrets → support → apps → node-apps → ingress → verify`.

What the pipeline guarantees so old mistakes can't recur:
- Checks **INSTANCES quota** headroom before `terraform apply` (fails early, not mid-apply).
- Reads the **dynamic edge LB IP** from `terraform output edge_lb_ip` and propagates it — never hardcoded.
- After RKE2 comes up, **regenerates `kubeconfig-6444`/`kubeconfig-local`** from the fresh CA and opens **one IAP tunnel on :6444** for the app phase.
- Creates **both** ECR pull-secret names (`ecr-pull` *and* `ecr-pull-secret`).
- Generates+persists JWT keypair / wildcard TLS / SeaweedFS creds under `iac/.secrets/` (stable across reruns).
- Creates Kafka topics **the moment the broker quorum is up** (not via a late k8s Job).

**Supporting scripts** (`iac/scripts/`):

| Script | Role |
|---|---|
| `secret-sync.py` | (legacy bootstrap) Vault dump → k8s secrets, **datastore-endpoint rewrite only** (two-axis rule) |
| `secret-shapes.py` | (legacy bootstrap) reshapes per-app secrets (envFrom keys / config.json / fills) |
| `secrets-from-rendered.py` | **NEW (this session)** — rebuilds every secret **from `secrets-rendered/`**, the authoritative source |
| `secret-pull.py` | **NEW (this session)** — pulls live secret values back into `secrets-rendered/` (drift capture) |
| `apply-region.py` | propagates the region secret to all 12 consumers |
| `fix-group-a-urls.py` | one-shot fix of staging-URL leaks in secrets |
| `rename-domain.py` | reproducible domain rename across manifests/secrets/scripts |
| `deploy-node-apps.py` | deploys the node-only apps |
| `tunnels.sh` | **NEW (this session)** — one-stop local tunnels (kafka-ui, mongo, redis, etc.) |

---

## 4. The journey, phase by phase

### Phase 1 — Understand, then decide (don't scaffold early)
Inventoried the Akamai source (datastores, ports, ~27 services), locked the **networking decisions**
and the **two-axis secrets rule** with the user *before* writing any Terraform. This discipline avoided
a costly over-rotation (replicating exact staging IPs / rewriting service URLs).

### Phase 2 — Infrastructure (Terraform + Ansible)
Stood up the 25 VMs, the private subnets, IAP SSH, Cloud NAT egress, the edge LB, then configured every
datastore via Ansible (Mongo rs0, 4 Redis Sentinel clusters, Kafka KRaft + topics, TiDB, MySQL). All
datastores health-verified. RKE2 4-node cluster up (Canal CNI + CoreDNS + ingress-nginx DaemonSet).

### Phase 3 — Seed data
Restored the management/metrics/analytics MySQL dumps (3 staging RDS consolidated onto one MySQL VM),
the Mongo dumps, and the chatapi base schema; provisioned the exact Mongo app users the unchanged envs expect.

### Phase 4 — Apps boot (the obfuscated-image gauntlet)
Got all ~20 pods running. This is where the **per-app image gotchas** lived (section 6.I) — each
obfuscated image had its own non-obvious boot requirement. Dashboard login worked.

### Phase 5 — App integration (CometChat-specific)
Three integration issues surfaced once pods ran: split-horizon DNS leaking traffic to public staging,
inter-service TLS trust (417 errors), and the dashboard data-plane redirect. Fixed all three.

### Phase 6 — Real domain + real certs
Migrated off the fake split-horizon-only domain `cc-cluster-1.io` to a **real domain
`cometchat-cluster-2.in`** (public Route53 + Let's Encrypt via cert-manager). Retired dnsmasq and
self-signed certs. New license issued for the new `authorizedDomain`.

### Phase 7 — Make messaging + webhooks actually work end-to-end
Chased two subtle runtime breaks: a missing-Kafka-topic crash that killed real-time delivery, and an
`ACTIVE_TRIGGER` env-format bug that silently disabled all webhook trigger consumers. Both fixed.

### Phase 8 — Secrets become the source of truth (this session)
Consolidated to **one authoritative env file per app** in `secrets-rendered/`, and **rewired the deploy**
to build live secrets *from* those files (no more dependence on an ephemeral `/tmp` Vault dump). Added
local tunneling tooling. (Section 7.)

---

## 5. New things we introduced (techniques & tooling)

These were **not** in the Akamai setup — they're what "RKE2 on bare VMs + data residency" forced us to invent:

- **Google IAP TCP forwarding for SSH** — VMs have no public IP; Ansible reaches them via
  `ProxyCommand gcloud compute start-iap-tunnel %h 22`. Caller needs `roles/iap.tunnelResourceAccessor`.
- **Cloud NAT + Router** — outbound-only egress so private VMs can `apt`/pull from ECR during bootstrap, with zero inbound exposure.
- **Terraform-provisioned edge** instead of `type: LoadBalancer` — RKE2 ships **no cloud-controller**, so a Service LB stays `<pending>` forever. We provision an external TCP Network LB → instance group of agent nodes → ingress-nginx **DaemonSet with hostPort 80/443**.
- **KRaft Kafka** (ZooKeeper-less) with deterministic bootstrap (one cluster ID, quorum voters from inventory, format-once).
- **Split-horizon CoreDNS** — the data-residency mechanism. In-cluster, `*.cometchat-cluster-2.in` resolves to the in-cluster ingress, keeping east-west traffic internal instead of leaking to public Route53/Akamai.
- **cert-manager + Let's Encrypt DNS-01 (Route53)** — real wildcard certs, with the controller patched to use recursive nameservers (`8.8.8.8`/`1.1.1.1`) so its ACME self-check bypasses the split-horizon CoreDNS.
- **The two-axis secrets rule** — rewrite **datastore endpoints only**; leave **every service URL byte-for-byte** (scheme included). Staging/external hostnames are handled at the infra layer (CoreDNS / egress), never by editing envs.
- **Per-app secret "shapes"** — same data, different delivery (envFrom individual keys vs `.env` file vs `config.json`), because each obfuscated image reads its config differently.
- **An in-cluster ES8 nginx proxy** to satisfy the obfuscated service-search's Elasticsearch-8 client (missing `X-elastic-product` header).
- **`secrets-rendered/` as the single source of truth** + the pull/apply script pair (this session).

---

## 6. Every blocker and how we fixed it

> Condensed from [PROBLEMS-AND-FIXES.md](PROBLEMS-AND-FIXES.md). Format: **Symptom → Cause → Fix.**

### A. Quota & capacity
- **A1 — SSD quota maxed (`SSD_TOTAL_GB` 250 exceeded).** The kept OLD infra eats ~240 GB. → **All disks use `pd-standard` (HDD)**, which draws on the ample `DISKS_TOTAL_GB` pool. (`pd-balanced` *also* counts against SSD — don't use it either.)
- **A2 — INSTANCES quota (24 < 25 VMs).** → Quota raised 24→50; `deploy.sh preflight` checks headroom and aborts early.

### B. Networking & access
- **B1 — Private VMs: no SSH, no internet.** → Inbound via **IAP TCP forwarding**; outbound via **Cloud NAT + Router**.
- **B2 — `type: LoadBalancer` does nothing on RKE2.** → Provision the edge entirely in Terraform (TCP LB → agent instance group → hostPort ingress DaemonSet).
- **B3 — Stale hardcoded edge LB IP.** The edge IP is **dynamically allocated**. → Single source of truth = `terraform output -raw edge_lb_ip`; the orchestrator propagates it.
- **B4 — Two kubeconfigs / two tunnel ports, all stale after rebuild.** → Orchestrator **regenerates** both kubeconfigs from the fresh CA and standardizes on the **:6444** IAP tunnel.

### C. MongoDB (rs0)
- **C1 — No `noble` apt repo for Mongo 7.0 on Ubuntu 24.04.** → Use the **`jammy`** repo codename (runs fine on 24.04).
- **C2 — Replica-set + keyfile auth bootstrap.** → Generate keyfile once, distribute (0400, owner mongodb); `rs.initiate()` + first admin user via the localhost exception on the primary only.
- **C3 — Attached data disk must be mounted before mongod starts.** → Stop → wait_for device → `blkid` → `mkfs.ext4` if raw → mount `noatime` → chown → start. (Same pattern for mysql/tidb.)
- **C4 — Apps auth as users the DB doesn't have.** Staging envs (which we must not edit) connect as `admin`/`extadmin`/`webhookuser`. → A one-shot playbook provisions exactly those users (`fix-mongo-app-users.yml`, run in the seed phase).

### D. Redis (4 Sentinel clusters)
- **D1 — Sentinel latched onto `127.0.0.1`.** `bind 127.0.0.1 <ip>` makes Redis announce loopback. → **`bind 0.0.0.0`** in both redis.conf and sentinel.conf (`protected-mode no` on the private subnet).
- **D2 — Sentinel persists a stale master IP across re-runs** (sentinel.conf self-mutates). → The role queries `get-master-addr-by-name`; if wrong, **stop sentinel + delete `/etc/redis/sentinel.conf`** before redeploying.
- **D3 — 4 independent clusters, not one shared** — isolated so the `mymaster` name doesn't collide; `bullmq` offset to .61.

### E. Kafka (KRaft) — the topic-timing miss
- **E1 — Topics weren't created when Kafka came up.** The role *had* a "create topics" task but `kafka_topics` defaulted to `[]`; the real 31-topic list lived only in a late-running k8s Job → app-boot races. → Populated the authoritative topic set in **`ansible/group_vars/kafka.yml`**; topics now created the moment the quorum is up. (k8s Job kept as fallback.)
- **E2 — KRaft bootstrap must be deterministic.** → One cluster ID (`run_once`), quorum voters from inventory, format storage exactly once.

### F. TiDB & MySQL
- **F1 — TiDB single-VM** via docker-compose (PD+TiKV+TiDB+TiProxy); MySQL-wire :3306, control :4000.
- **F2 — Three staging RDS consolidated onto one MySQL VM** (`10.20.10.41`). `secret-sync.py` rewrites each app's MySQL host; the restore playbook loads all three dumps. MySQL 8 needs `mysql_native_password` + remote `root@'%'` + `bind 0.0.0.0`.

### G. Secrets — the two-axis rule
- **G1 — Don't rewrite service URLs, only datastore endpoints.** Rewriting inter-service URLs / flipping http↔https breaks signed URLs, TLS expectations, and licensing-tied hostnames. → Axis 1 rewrites datastores; Axis 2 leaves every service URL byte-for-byte. External hosts handled by CoreDNS/egress, never env edits.
- **G2 — Apps consume secrets in different shapes** (`secret-shapes.py`): envFrom individual keys (globalwebhooks, service-search, calls-relay, notificationscore, metrics-pro); a dotenv **file** for calls-relay (`.env.staging`); JSON config files for sql-consumer/extensions; validator-only fills for ai-agent-service; comma-separated Kafka brokers for globalwebhooks; `SENTRY={}` for websocket.

### H. RKE2
- **H1 — Join token must be stable across re-runs.** → Generate once, persist to `ansible/.rke2_token`.
- **H2 — Fetched kubeconfig points at 127.0.0.1.** → Rewrite to the master's private IP; reach via the IAP tunnel.

### I. App-phase image gotchas (the obfuscated ECR images)
| # | App | Symptom → Fix |
|---|-----|---------------|
| I1 | ECR pull secrets | `ImagePullBackOff` → **two** secret names needed: `ecr-pull` *and* `ecr-pull-secret` |
| I2 | License + JWT | old license.key rejected → mount only **`license.txt`** in app root; new OpenSSL JWT keypair (`private.pem`/`public.pem` to sign on chatapi/mgmtapi; public as **`jwtrsakey.pem`** to verify on websocket/analytics) |
| I3 | OpenSearch ES8 | service-search HTTP 406 (missing `X-elastic-product`) → transparent **nginx ES8 proxy**; repoint the `opensearch` Service to it |
| I4 | notificationscore | one worker per host CPU → instability → `--require single-cpu.js` shim forces `os.cpus().length=1` |
| I5 | sql-consumer | entrypoint points at non-existent path; non-numeric USER → run `node dist/loader.js`, pin `runAsUser/Group: 999`, mount real `config.json` |
| I6 | calls-relay | bytenode `SyntaxError` on `.jsc` → preload `node -r bytenode src/app.js`; mount dotenv file at `/app/src/.env.staging` |
| I7 | metrics-pro | PM2 crashes (`/home/appuser` missing) → `PM2_HOME=/tmp/.pm2`; provide real env vars via envFrom |
| I8 | extensions | reads `env.<NODE_ENV>.json` → mount `extensions-config` + `NODE_ENV=staging` |
| I9 | globalwebhooks | health probe pings undeployed helpers → probe `/v1/webhooks/health-check`; needs Mongo `webhookuser` |
| I10 | mgmtapi | baked CMD calls dropped artisan cmds → trimmed startup `migrate → php-fpm`; long startupProbe |
| I11 | sidecars | only chatapi + mgmtapi (PHP-FPM) get an nginx sidecar; every Node/Python app serves HTTP natively |
| I12 | service-search ordering | apply support-services (+ ES8 proxy) **before** service-search |

### App-integration fixes (CometChat-specific, Phase 5)
- **Split-horizon DNS leak.** In-cluster, `api-us.<domain>` resolved (via public Route53 → Akamai) to **public staging**, so mgmtapi provisioned apps *there*. → CoreDNS override returns the in-cluster ingress ClusterIP for `<domain>:53`. Created a stable `rke2-ingress-nginx-internal` ClusterIP (the ingress is a hostPort DaemonSet with no ClusterIP otherwise).
- **Inter-service TLS trust → 417.** mgmtapi (`ADMIN_API_USE_SSL=true`) → `https://api-us` failed cert-verify → app creation returned **417**. → Mount `wildcard-tls` as a CA into mgmtapi+chatapi (`CURL_CA_BUNDLE`/`SSL_CERT_FILE`); Node services use `NODE_EXTRA_CA_CERTS`.
- **Dashboard data-plane redirect.** The dashboard SPA hardcodes public `api.cometchat.com` for the chat data API. → Add SANs + ingress rules routing `api.cometchat.com`/`apiclient-us` → chatapi.

### Runtime correctness (Phase 7)
- **Real-time delivery broke** — messages only appeared after refresh. Kafka was *healthy*; the **websocket build subscribed to 2 topics that didn't exist** (`internal-events-restapi-delivered-receipt`, `internal-events-campaigns-notifications`) → KafkaJS `UNKNOWN_TOPIC_OR_PARTITION` thrown as an **uncaughtException crashed ALL** its consumers. → Created the 2 topics (added to `group_vars/kafka.yml`); all 9 consumer groups formed.
- **Webhooks never fired** — `ACTIVE_TRIGGER` was stored as quoted-JSON (`["MESSAGE_SENT", ...]`). global_event_consumers does a bare `.split(',')` + `configService.get(token)` with no trim/unquote → every token mismatched → **zero trigger consumers**. → `ACTIVE_TRIGGER` must be **bare comma-separated tokens, no quotes and no brackets**. The authoritative reference is the colleague's project `Downloads/CometChat-On-Prem-Docker-Swarm`. **Never store `ACTIVE_TRIGGER` quoted.**

### Region secret
- Old mgmt image baked `regions.hash` as a hardcoded literal (env was inert). The **new image (`689ac042`)** migration `onprem_setup` reads `ONPREM_REGION_SECRET` from `.env` and writes `regions.hash` automatically (proven by a sentinel test). → mgmtapi pins the new digest; the old `UPDATE regions` startup hack was **removed**. Region secret lives in `iac/.secrets/region_secret`, propagated to all 12 consumers via `apply-region.py`. (It's a one-time migration — a truly fresh mgmt DB is needed to (re)write the hash.)

### Domain / cert migration
- New image enforces a license `authorizedDomain` claim; the old license was for the old domain → **403 `ERR_LICENSE_DOMAIN_UNAUTHORIZED`**. → New `license.txt` (authorizedDomain `cometchat-cluster-2.in`); domain renamed everywhere via `rename-domain.py`; cert-manager issues a real wildcard cert that replaces the self-signed `wildcard-tls`.

### Analytics & metrics-pro (bytenode/PM2 quirks)
- **analytics** — bytecode `require('../config.json')` needs a JSON **file** at `/app/config.json` (not `.env`); the app binds **IPv6 loopback `[::1]:8080` only** → run a tiny node TCP forwarder `0.0.0.0:8080 → [::1]:8080` before `exec node -r bytenode loader.js`. Served at `metrics-onprem.<domain>`.
- **metrics-pro** — image ecosystem defines **two** PM2 apps → `EADDRINUSE` → start `--only pro-metrics`; API port is **3003** not 3000; `PM2_HOME=/tmp/.pm2`.

### Data-residency / staging-URL audit
A scan of decoded secrets found service URLs still pointing at `*.cometchat-staging.com` (the two-axis
rule deliberately left URLs untouched, so these slipped through). **Group A** (unambiguous on-prem
renames, incl. the live `ANALYTICS_HOST=metrics-us.cometchat-staging.com` leak) **fixed** via
`fix-group-a-urls.py`. **Group B** (no obvious on-prem host: analytics/recordings/bucket) and **Group C**
(genuinely third-party: SQS/Lambda/Composio/Firecrawl/Google) left for the egress-policy decision.

---

## 7. The secrets pipeline tweak (this session, 2026-06-24)

**Problem found:** the deploy built secrets from an **ephemeral `/tmp/cc-vault-envs-v2/` Vault dump** and
**skipped secret creation entirely if that dump was gone** (which it was). The persistent
`secrets-rendered/` files were just a *copy/record*, not the deploy source — so a rebuild would silently
produce no app secrets. Several live secrets had also **drifted** from the rendered baseline (live
`kubectl edit`s never written back).

**What we changed:**
1. **`secret-pull.py`** — pulls live secret values back into `secrets-rendered/` (handles both `.env`-file
   and envFrom shapes; dry-run by default, backs up before writing). Reconciled 8 drifted apps.
2. **One authoritative file per app** — removed backup duplicates; captured the two real config artifacts
   (`extensions-config.json`, `sql-consumer-config.json`) so `secrets-rendered/` is self-describing.
3. **`secrets-from-rendered.py`** — recreates **all 20 live secrets from `secrets-rendered/`** in the exact
   shape each pod consumes (`.env` file / envFrom keys / config file), with **no Vault dump and no
   re-rewriting** (the rendered values are already live-correct). Validated read-only: 18/20 byte-identical;
   the 2 differences are benign (a cosmetic trailing newline, and it *heals* a real `calls-relay` key divergence).
4. **Deploy rewired** ([deploy/deploy.sh](deploy/deploy.sh) `phase_secrets`) — `secrets-rendered/` is now the
   **primary source**; the old `secret-sync.py` + `secret-shapes.py` Vault path is demoted to a **one-time
   bootstrap fallback** used only if `secrets-rendered/` is absent.

**Result:** `secrets-rendered/` is the single source of truth, with a clean pull/apply pair:
`secret-pull.py` (live → rendered) and `secrets-from-rendered.py` (rendered → live).

### Local access tooling — `tunnels.sh`
Private VMs and ClusterIP services aren't reachable from a laptop. `iac/tunnels.sh` is a one-stop manager:
- **kubectl port-forward** for in-cluster UIs (kafka-ui, mailpit, opensearch, ollama, seaweedfs, dashboard) — auto-ensures the API-server IAP tunnel on :6444 first.
- **gcloud IAP tunnels** for datastore VMs (mongo, mysql/TiDB, the 4 redis clusters, kafka brokers).
- `./tunnels.sh up|down|status|list`. E.g. Mongo in Compass: tunnel `mongo`, then
  `mongodb://admin:<pw>@localhost:27017/?authSource=admin&directConnection=true` (single-node form through one tunnel).

---

## 8. Operating it — quick runbook

```bash
cd iac
# Cluster access (API server has no public IP)
./cluster.sh                 # ensure IAP tunnel + open k9s on the cometchat ns
./cluster.sh kubectl get pods -n cometchat
export KUBECONFIG=$PWD/kubeconfig-6444   # the working kubeconfig (rides the :6444 tunnel)

# Local tunnels to UIs / datastores
./tunnels.sh up kafka-ui mongo
./tunnels.sh status

# Secrets
python3 scripts/secret-pull.py            # preview live → rendered drift
python3 scripts/secrets-from-rendered.py  # preview rendered → live plan (add --apply to push)

# Rebuild
./deploy.sh            # infra
./deploy.sh app-all    # apps (needs aws profile 'staging', licence-new.txt)
./deploy.sh status
```

**Kubeconfigs:** only `kubeconfig-6444` is current (rides the :6444 IAP tunnel). `kubeconfig-local` (:6443)
and `ansible/kubeconfig` (private `10.20.20.11:6443`) won't work from a laptop without the matching tunnel.

---

## 9. Status: done vs pending

**Done & verified:**
- All 25 VMs + datastores up and health-checked; RKE2 4-node cluster healthy.
- ~20 app pods running; dashboard login, app provisioning, real-time messaging, and webhooks all working end-to-end.
- Real domain + Let's Encrypt certs; region secret automated; Group-A staging leaks fixed.
- Secrets consolidated to `secrets-rendered/` as the authoritative deploy source.

**Closed in the 2026-06-24 one-click audit (now automated in `deploy.sh all`):**
- **Node-only services are in the one-click now.** `node-apps` (websocket, moderationservice,
  visual-chat-builder, ai-agent-service, receipt-updater, notifications-delay-worker, dashboard) is
  folded into `app-all`/`all`. `scripts/deploy-node-apps.py` was trimmed to ONLY these so it can no
  longer clobber the curated `k8s/apps/*` services.
- **CoreDNS split-horizon is now a real, reconcile-safe manifest** (`k8s/coredns-split-horizon.yaml`
  — a `coredns-custom` zone + pinned internal-ingress ClusterIP), applied in the `coredns` phase and
  checked by `verify`. (Was the "needs a HelmChartConfig" TODO.)
- **DB schema needs no dump.** mgmt/chat images self-migrate (`php artisan migrate`); the seed dumps
  are optional *data* and skip cleanly if absent. Hardcoded `/Users/...` paths in the Python/Ansible
  helpers were made portable (derive from the repo, overridable via `customer.conf`).

**Pending (deliberately deferred — see the linked docs):**
- **Egress lockdown.** Egress is still **allow-all** (default-deny + allowlist rules are written but commented in `terraform/firewall.tf`, left open for ECR/OS/ACME during bootstrap). `deploy.sh lockdown` is the gated switch. **Do not hand over with egress open.**
- **Edge LB CIDR** still `0.0.0.0/0` — tighten `edge_allowed_cidrs` to the customer's real client/VPN ranges.
- **HA + right-sizing** — one clean pass after the workflow is validated (target 1,000 PCC; control plane 1→3, workers → 3× e2-standard-32, MySQL→InnoDB Cluster, TiDB→multi-node). Plan in [HA-AND-SIZING-PLAN.md](HA-AND-SIZING-PLAN.md).
- **Staging-URL Group B/C** — analytics/recordings/bucket + third-party (SQS/Lambda/Composio) await the egress-policy decision.
- **Hardening P0/P1** — secrets-encryption-at-rest, NetworkPolicies, Pod Security `restricted` ([NETWORK-AND-SECURITY.md](NETWORK-AND-SECURITY.md) §6).

---

## 10. The do-NOT-repeat checklist (the script enforces these)

1. **Don't** use `pd-ssd`/`pd-balanced` while the old infra holds the SSD quota → `pd-standard`.
2. **Don't** `terraform apply` without checking the INSTANCES quota first.
3. **Don't** install MongoDB with the `noble` repo → use `jammy`.
4. **Don't** leave Redis `bind 127.0.0.1`, and don't trust a self-rewritten `sentinel.conf` → reset it.
5. **Don't** rely on the k8s Job for Kafka topics → create them when Kafka comes up.
6. **Don't** rewrite service URLs or flip schemes in secrets → datastore endpoints **only**.
7. **Don't** hardcode the edge LB IP → read `terraform output edge_lb_ip`.
8. **Don't** forget the **second** ECR pull-secret name.
9. **Don't** mount the old license.key/fat keys → new `license.txt` + JWT keypair only.
10. **Don't** point `kubectl` at a stale checked-in kubeconfig after a rebuild → regenerate.
11. **Don't** create only the Mongo `root` user → apps need `admin`/`extadmin`/`webhookuser`.
12. **Don't** store `ACTIVE_TRIGGER` quoted/bracketed → bare comma-separated tokens.
13. **Don't** build secrets from the Vault dump anymore → `secrets-rendered/` is the source (`secrets-from-rendered.py`).
14. **Don't** hand the infra over with egress still allow-all.

---

*Authoritative references: the in-repo docs linked at the top, the scripts in `iac/scripts/`, and the
colleague's webhook reference at `Downloads/CometChat-On-Prem-Docker-Swarm`. When a detail here disagrees
with the live cluster, trust the cluster and update this doc.*
