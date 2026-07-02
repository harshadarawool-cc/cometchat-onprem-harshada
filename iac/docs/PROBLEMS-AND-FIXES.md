# CometChat on GCP RKE2 — Problems Faced & How We Fixed Them

> The build journal. Every non-obvious problem we hit bringing this infra up, the
> root cause, the fix, and **where the fix is baked in** so it never bites again.
> The automation (`deploy/deploy.sh`) encodes every one of these — this file is the
> "why" behind the script. Read this before changing any role/template.

> ### HAProxy re-architecture addendum (this repo)
> This build replaces the GCP L4 LB with **2 HAProxy VMs (SNI passthrough) + per-pod TLS**. The edge-,
> DNS-, and object-store-specific problems/fixes now live in the ★ docs, which supersede the LB-era
> networking sections below: **[NETWORKING](NETWORKING.md)** (CORS/503 triage, per-pod TLS,
> split-horizon), **[HAPROXY-EDGE](HAPROXY-EDGE.md)** (SNI→NodePort, add-a-service),
> **[SEAWEEDFS](SEAWEEDFS.md)** (SigV4 4.37 validation + 3.80 fallback, media-onprem dual path),
> **[ENCRYPTION-AT-REST](ENCRYPTION-AT-REST.md)**, **[MIGRATION-FROM-LB](MIGRATION-FROM-LB.md)**. The
> datastore / secrets / seeding / image fixes below are UNCHANGED and still authoritative.
>
> Project `onprem-499712` · region `asia-south1-a` · VPC `cometchat-onprem-vpc`.
> Coexists with the OLD (kept, stopped) `cometchat-ds-*` / `cometchat-gke` infra — **never touch it.**

Legend for each entry: **Symptom → Root cause → Fix → Baked into.**

---

## A. Quota & capacity (these block `terraform apply` outright)

### A1. SSD quota maxed → VMs won't create
- **Symptom:** `terraform apply` fails creating disks: `Quota 'SSD_TOTAL_GB' exceeded. Limit: 250.0`.
- **Root cause:** the kept OLD infra already consumes ~240 GB of the 250 GB regional SSD quota. Any `pd-ssd` / `pd-balanced` disk (boot *and* data) draws on the same `SSD_TOTAL_GB` pool.
- **Fix:** all disks use `pd-standard` (HDD), which draws on `DISKS_TOTAL_GB` (2048 GB, ample).
- **Baked into:** `terraform/variables.tf` → `variable "disk_type" { default = "pd-standard" }`, applied to every boot + data disk (`datastores.tf:39,57`, `rke2.tf:31`, `bastion.tf:18`). Revert to SSD only after the SSD quota is raised or the old infra's ~240 GB is freed.

### A2. Instance count quota
- **Symptom:** apply fails part-way: `Quota 'INSTANCES' exceeded` once ~25 VMs are requested.
- **Root cause:** default per-region instance quota (24) is below our 25-VM footprint (3 mongo + 12 redis + 3 kafka + 1 mysql + 1 tidb + 4 rke2 + 1 bastion).
- **Fix:** quota raised 24 → 50 (Google approved). `deploy.sh preflight` checks `INSTANCES` headroom and aborts early with a clear message instead of failing mid-apply.
- **Baked into:** `deploy/deploy.sh` preflight quota check.

---

## B. Networking & access

### B1. Private VMs — no SSH, no internet
- **Symptom:** VMs have no public IP (data-residency requirement) → `ssh` times out; `apt`, `curl https://get.rke2.io`, ECR pulls all fail during bootstrap.
- **Root cause:** intentional — no VM may be internet-reachable. But Ansible still needs to reach them, and they still need outbound to fetch packages/images during build.
- **Fix (inbound):** SSH over **Google IAP TCP forwarding** (`ProxyCommand gcloud compute start-iap-tunnel %h 22`). Firewall allows the IAP range `35.235.240.0/20` to :22. The caller needs IAM role `roles/iap.tunnelResourceAccessor`.
- **Fix (outbound):** **Cloud NAT + Router** gives the no-public-IP VMs egress for `apt` / `get.rke2.io` / ECR during bootstrap, with no inbound exposure.
- **Baked into:** `ansible/group_vars/all/main.yml` (`ansible_ssh_common_args` ProxyCommand), `ansible/ansible.cfg`, `terraform/firewall.tf` (`allow-iap-ssh`), `terraform/network.tf` (`router` + `nat`).

### B2. RKE2 ≠ GKE — `type: LoadBalancer` does nothing
- **Symptom:** a `Service type: LoadBalancer` stays `<pending>`; no public IP ever attaches.
- **Root cause:** RKE2 ships **no cloud-controller-manager**, so there's nothing to provision a GCP LB from a Service.
- **Fix:** provision the public edge entirely in Terraform — an **external regional TCP Network LB** → unmanaged instance group of the **agent** nodes → `ingress-nginx` running as a **DaemonSet with hostPort 80/443**. The LB's TCP backend hits the node ports directly.
- **Baked into:** `terraform/lb.tf` (address → forwarding-rule `:80,:443` → backend-service → instance-group `cometchat-onprem-agents` = the `k8s-worker-*` VMs; health check TCP:443), `terraform/firewall.tf` (`allow-edge-ingress` 0.0.0.0/0→:80,:443 on `rke2-agent`; `allow-health-checks` for GCP probe ranges).

### B3. Stale / hardcoded edge LB IP
- **Symptom:** docs and configs reference `8.231.119.155`, but the live LB answered on a different IP (`35.200.134.182` at one point). DNS / `tls-san` / ingress notes pointed at the wrong address.
- **Root cause:** the edge IP is **dynamically allocated** by Terraform (`google_compute_address.edge`). Hardcoding it anywhere goes stale the next time the address resource is recreated.
- **Fix:** treat `terraform output -raw edge_lb_ip` as the **single source of truth**. The orchestrator reads it after `terraform apply` and propagates it into `ansible/group_vars/all/main.yml` (`edge_lb_ip`, used in the RKE2 `tls-san`) and into `k8s/ingress.yaml` notes. Never hardcode it again.
- **Baked into:** `deploy/deploy.sh` (`inventory`/`ingress` phases). Stale literals remain in `group_vars/all/main.yml` and `ingress.yaml` headers — the script overwrites them on each run.

### B4. Two kubeconfigs, two tunnel ports
- **Symptom:** `kubeconfig-local` → `127.0.0.1:6443`, `kubeconfig-6444` → `127.0.0.1:6444`, `ansible/kubeconfig` → `10.20.20.11:6443`. The Python deploy scripts hardcode `kubeconfig-6444`; `kube-tunnel.sh` opens 6443. Easy to run `kubectl` against the wrong/stale context, and **all three go stale after a rebuild** (new cluster CA).
- **Root cause:** the API server is only reachable through an IAP tunnel, so the kubeconfig server must be a localhost port — and the convention drifted to two ports.
- **Fix:** after RKE2 comes up the orchestrator **regenerates** `kubeconfig-6444` and `kubeconfig-local` from the freshly-fetched `ansible/kubeconfig` (rewriting the server to `127.0.0.1:6444` / `:6443`), then opens **one** IAP tunnel on **6444** for the whole app phase (matching the scripts). No more stale certs after a rebuild.
- **Baked into:** `deploy/deploy.sh` (`rke2` phase regenerates kubeconfigs; `_open_tunnel` / `_close_tunnel` manage the 6444 tunnel).

---

## C. MongoDB (replica set rs0)

### C1. No `noble` apt repo for MongoDB 7.0
- **Symptom:** `apt-get install mongodb-org` 404s on Ubuntu 24.04 (`noble`).
- **Root cause:** MongoDB 7.0 publishes no `noble` repo.
- **Fix:** use the **`jammy`** repo codename; the jammy packages run fine on 24.04.
- **Baked into:** `ansible/roles/mongo/defaults/main.yml` → `mongo_repo_codename: "jammy"`.

### C2. Replica-set + keyfile auth bootstrap
- **Symptom:** members won't form a set / auth fails; `rs.initiate()` rejected; can't create the first user once `authorization: enabled`.
- **Root cause:** keyfile internal auth requires the **same** keyfile on all 3 members; the first admin user can only be created via the localhost exception before/at RS init.
- **Fix:** generate the keyfile **once**, distribute to all members (mode 0400, owner mongodb); init the set + create the admin user from a templated `rs_init.js` run via the localhost exception on the primary only.
- **Baked into:** `ansible/datastores.yml` (mongo `pre_tasks` keyfile gen/share, `post_tasks` rs_init), `roles/mongo/templates/{mongod.conf.j2,rs_init.js.j2}`.

### C3. Attached data disk must be mounted before mongod starts
- **Symptom:** Mongo writes to the boot disk; data not on the dedicated disk; or mongod won't start.
- **Root cause:** GCP attaches a raw, unformatted disk at `/dev/disk/by-id/google-data`; it must be formatted + mounted at `/var/lib/mongodb` **before** mongod initializes.
- **Fix:** stop mongod → `wait_for` the device → `blkid` check → `mkfs.ext4 -F` if unformatted → mount `noatime` → chown mongodb → start.
- **Baked into:** `ansible/roles/mongo/tasks/main.yml`. (Same disk-init pattern in the `mysql` and `tidb` roles.)

### C4. Apps connect with usernames the datastore doesn't have
- **Symptom:** apps fail Mongo auth even though the cluster is healthy.
- **Root cause:** staging app envs (which we must **not** edit — see G1) authenticate as `admin` / `extadmin` / `webhookuser` with specific passwords; the mongo role only creates `root`.
- **Fix:** a one-shot playbook provisions exactly those users (auth'ing as `root`) so the unchanged envs work: `admin`→`Cometchat2026*`, `extadmin`→`Q16d1Pe0DUq`, `webhookuser`→`zhyOR9TCNqlN8xRe` (globalwebhooks, `events` DB).
- **Baked into:** `ansible/fix-mongo-app-users.yml` (run in the `seed` phase).

---

## D. Redis (4 dedicated Sentinel clusters)

### D1. Sentinel latched onto `127.0.0.1`
- **Symptom:** Sentinel reports the master as `127.0.0.1`; replicas/clients connect to loopback and fail across VMs.
- **Root cause:** `bind 127.0.0.1 <ip>` makes Redis announce loopback; Sentinel records whatever the master announces.
- **Fix:** `bind 0.0.0.0` in both `redis.conf` and `sentinel.conf` (`protected-mode no` on the private subnet). Sentinel then records the real VM IP.
- **Baked into:** `roles/redis/templates/redis.conf.j2`, `sentinel.conf.j2` (both `bind 0.0.0.0`).

### D2. Sentinel persists a stale master IP across re-runs
- **Symptom:** even after fixing `bind`, Sentinel still reported a wrong/loopback master, because Sentinel **rewrites its own config** and kept the old value.
- **Root cause:** `sentinel.conf` is self-mutating; redeploying the template doesn't clear the recorded (stale) master.
- **Fix:** the role queries `sentinel get-master-addr-by-name`; if it ≠ the expected master IP, it **stops sentinel and deletes `/etc/redis/sentinel.conf`** before redeploying — a clean reset.
- **Baked into:** `roles/redis/tasks/main.yml` ("Reset stale sentinel state when master IP is wrong/unknown").

### D3. 4 independent clusters, not one shared
- **Decision:** `shared` (10.20.10.21-23), `analytics` (.24-26), `prometrics` (.27-29), `bullmq` (.61-63). Each = 3 VMs, master = node-1, ports 6379/26379, `master_name = mymaster`. Sets are isolated so the shared name doesn't collide. `secret-sync.py` maps each service's staging Redis endpoints to its assigned cluster's nodes.
- **Baked into:** `ansible/inventory/hosts.yml` (4 `redis_*` groups), `terraform/variables.tf` (`redis_clusters` map), `scripts/secret-sync.py` (`RCLUSTER` / `SVC_REDIS`). The `bullmq` offset is **61** (not 30) so it never collides with the 21-29 block.

---

## E. Kafka (KRaft) — ⭐ the topic-timing miss

### E1. Topics were not created when Kafka came up  ← root of app-boot races
- **Symptom:** apps that produce/consume on first boot failed because their topics didn't exist yet; topics only appeared much later.
- **Root cause:** the Ansible `kafka` role **has** a "Create topics" task, but `kafka_topics` defaulted to `[]` — so it created nothing. The real 31-topic list lived only in `k8s/kafka-topics-job.yaml`, a Kubernetes Job that runs in the **app phase**, long after the brokers are up. Kafka came up "empty"; topic creation was deferred and racy.
- **Fix:** topics are now created **the moment the broker quorum is up**, in the datastore phase. Populated the authoritative 31-topic set (partitions 3, RF 3, `min.insync.replicas` 2) so the role's existing idempotent (`--if-not-exists`) task actually does its job. The k8s Job is kept only as an in-cluster fallback.
- **Baked into:** **`ansible/group_vars/kafka.yml`** (new — overrides the role default `kafka_topics: []`), consumed by `roles/kafka/tasks/main.yml` "Create topics". `k8s/kafka-topics-job.yaml` retained as fallback.

### E2. KRaft (no ZooKeeper) bootstrap must be deterministic
- **Symptom:** brokers won't form a quorum on a fresh cluster, or re-runs reformat storage.
- **Root cause:** KRaft needs one shared cluster ID, consistent quorum-voter list, and storage formatted exactly once.
- **Fix:** generate the cluster ID **once** (`run_once`), build `controller.quorum.voters` from inventory `kafka_node_id@ip:9093`, and format storage only when `meta.properties` is absent.
- **Baked into:** `roles/kafka/tasks/main.yml`, `roles/kafka/templates/server.properties.j2`.

---

## F. TiDB & MySQL

### F1. TiDB single-VM cluster via docker-compose
- **Note:** TiDB runs as PD + TiKV + TiDB + **TiProxy** under docker-compose on one VM. Apps reach MySQL-wire on **:3306** (TiProxy) / control on **:4000** (TiDB). Root password set, app DB `cometchat` created. Disk-init pattern as C3.
- **Baked into:** `ansible/roles/tidb/{tasks/main.yml,templates/docker-compose.yml.j2}`.

### F2. Three staging RDS consolidated onto one MySQL VM
- **Symptom:** staging had 3 separate RDS (mgmtapi `pulsecustomerdb`, pro-metrics `metrics`, analytics `analytics_logs`); on-prem has one MySQL VM.
- **Fix:** consolidate all three databases onto `10.20.10.41`. `secret-sync.py` rewrites each app's MySQL host (`cometchat_mysql-db`, `us-pro-metrics-db.cometchat.io`, `us-analytics-rds.cometchat.io`) → `10.20.10.41`. The restore playbook loads all three dumps. MySQL 8 needs `mysql_native_password` + a remote `root@'%'` + `bind 0.0.0.0`.
- **Baked into:** `ansible/restore-mysql-dumps.yml`, `roles/mysql/tasks/main.yml`, `scripts/secret-sync.py` (`BLANKET`).

---

## G. Secrets — the two-axis rule

### G1. Don't rewrite service URLs — only datastore endpoints
- **Symptom (avoided):** an early instinct was to replicate exact staging IPs and rewrite inter-service URLs / flip http↔https. That breaks signed URLs, TLS expectations, and licensing-tied hostnames.
- **Rule (locked with the user):** **Axis 1** — rewrite datastore endpoints (Mongo/Redis/Kafka/TiDB/MySQL) to the GCP DB VMs. **Axis 2** — leave **every** service URL byte-for-byte, including scheme and leftover `cometchat-staging.com` hosts. The only env transformation is the Axis-1 datastore swap. Staging/external hostnames are handled at the **infra layer** (CoreDNS split-horizon for in-cluster twins; egress allow/deny for genuine externals) — never by editing envs.
- **Baked into:** `scripts/secret-sync.py` (`rewrite()` touches only datastore keys; `BLANKET`/`RCLUSTER` maps).

### G2. Apps consume secrets in different shapes
- **Symptom:** several apps crash on boot even with a correct `.env` — they expect a different shape.
- **Root cause / fixes (all in `scripts/secret-shapes.py`, run **after** `secret-sync.py`):**
  - `envFrom` apps (globalwebhooks, service-search, calls-relay, notificationscore, metrics-pro) need **individual key=value** env, not a single `.env` file.
  - `calls-relay` also needs a dotenv **FILE** at `/app/src/.env.staging` → secret `calls-relay-envfile`.
  - `sql-consumer` / `extensions` need a **JSON config file** → secrets `sql-consumer-config` (config.json), `extensions-config` (env.staging.json).
  - `ai-agent-service` refuses to start unless empty observability values are filled (`LOKI_HOST`, `METRICS_USERNAME/PASSWORD`) — validator-only fills.
  - `globalwebhooks` Kafka broker keys must be **comma-separated** host:port (app `.split(',')`, does not `JSON.parse`).
  - `websocket` needs `SENTRY={}` (zod requires an object, staging left it empty).

---

## H. RKE2 cluster

### H1. Join token must be stable across re-runs
- **Symptom:** on a re-run a new token is generated and agents can no longer join.
- **Fix:** generate the token **once** and persist to `ansible/.rke2_token`; reuse on every subsequent run.
- **Baked into:** `ansible/rke2.yml` (token generate/persist block).

### H2. Fetched kubeconfig points at 127.0.0.1
- **Symptom:** the kubeconfig RKE2 writes has `server: https://127.0.0.1:6443`, useless from the control machine.
- **Fix:** fetch it, rewrite `127.0.0.1` → the master's private IP, and reach it via the IAP tunnel (see B4).
- **Baked into:** `ansible/rke2.yml` post_tasks; orchestrator B4 regeneration.

---

## I. App-phase image gotchas (latest obfuscated ECR images)

| # | App | Symptom | Fix | Baked into |
|---|-----|---------|-----|------------|
| I1 | **Two ECR pull-secret names** | some pods `ImagePullBackOff` | chatapi + `deploy-node-apps.py` use **`ecr-pull`**; mgmtapi + all `k8s/apps/*` use **`ecr-pull-secret`** — **both** must exist | `deploy/deploy.sh secrets` creates both names from the same ECR token |
| I2 | **License + JWT scheme** | old license.key/license_public.pem rejected | mount only **`license.txt`** (new `licence-new.txt`) in app root; new OpenSSL JWT keypair: `private.pem`+`public.pem` on chatapi/mgmtapi (sign), public as **`jwtrsakey.pem`** on websocket/analytics (verify); drop all old fat keys | `k8s/chatapi.yaml`, `mgmtapi.yaml`, `k8s/apps/no-ref-apps.yaml`; secrets `cc-license`/`jwt-keys`/`jwt-public` |
| I3 | **OpenSearch ↔ ES8 client** | service-search gets HTTP 406; missing `X-elastic-product` header | transparent **nginx ES8 proxy**; repoint the `opensearch` Service to it (`opensearch-real` exposes real pods) | `k8s/opensearch-es8proxy.yaml` (apply, then repoint Service) |
| I4 | **notificationscore CPU storm** | one worker per host CPU (4+8 on 4-vCPU) → instability | `--require single-cpu.js` shim forces `os.cpus().length=1` | `k8s/apps/notificationscore.yaml` |
| I5 | **sql-consumer entrypoint** | `start` points at non-existent `dist/src/index.js`; non-numeric USER → `CreateContainerConfigError` | run `node dist/loader.js`; pin `runAsUser/Group: 999`; mount real `config.json` (baked one is an empty placeholder) | `k8s/apps/sql-consumer.yaml` |
| I6 | **calls-relay bytenode** | `SyntaxError: Invalid or unexpected token` on `.jsc` | preload `node -r bytenode src/app.js`; mount dotenv FILE at `/app/src/.env.staging` | `k8s/apps/calls-relay.yaml` |
| I7 | **metrics-pro PM2** | crashes: `/home/appuser` missing; no dotenv | `PM2_HOME=/tmp/.pm2`; provide real env vars (envFrom) | `k8s/apps/no-ref-apps.yaml` + `secret-shapes.py` |
| I8 | **extensions config file** | reads `env.<NODE_ENV>.json` | mount `extensions-config` + `NODE_ENV=staging` | `k8s/apps/no-ref-apps.yaml` |
| I9 | **globalwebhooks health** | `/v1/app/health` pings undeployed helpers | probe `/v1/webhooks/health-check`; needs Mongo `webhookuser` | `k8s/apps/globalwebhooks.yaml` + `fix-mongo-app-users.yml` |
| I10 | **mgmtapi startup** | baked CMD calls dropped `onprem:*`/`license:verify` artisan cmds | trimmed startup: `migrate` then `php-fpm`; license self-verified from `/var/www/license.txt`; long `startupProbe` (migrations take time) | `k8s/mgmtapi.yaml` |
| I11 | **Only PHP gets a sidecar** | which pods need nginx? | **only** chatapi + mgmtapi get an nginx sidecar (PHP-FPM FastCGI gateway); every Node/Python app serves HTTP natively, ClusterIP, no sidecar | `k8s/chatapi.yaml`, `mgmtapi.yaml` |
| I12 | **service-search needs OpenSearch first** | runs but search calls fail | apply support-services (+ ES8 proxy) **before** service-search | ordering in `deploy/deploy.sh` |

---

## J. Data residency / egress (the whole point — finish before handover)

- **Egress is still allow-all.** The default-deny + allowlist firewall rules are written but **commented** in `terraform/firewall.tf` (left open during bootstrap so nodes can pull from ECR / OS repos / `get.rke2.io`). **After bootstrap, switch to default-deny + the user's allowlist.** `deploy/deploy.sh lockdown` is the gated step for this.
- **Edge LB is open `0.0.0.0/0`.** Tighten `edge_allowed_cidrs` (`terraform.tfvars`) to the customer's real client/VPN ranges for production.
- **CoreDNS split-horizon** keeps inter-service `*-us.cometchat-cluster-2.in` traffic in-cluster (the data-residency mechanism). Apply after the app Services exist.

---

## L. Object storage (SeaweedFS) — ONE consolidated store in `cometchat`

### L1. Chat image upload landed nowhere — keyless `…/uploads/` URL, empty bucket
- **Symptom:** sending an image produced a broken thumbnail; the `<img>` URL was
  `https://media-onprem.cometchat-cluster-2.in/uploads/` (the base path, **no filename**);
  the bucket stayed empty; and the browser showed **no PUT** — only GETs to `/uploads/`.
- **Why "no PUT" is normal:** CometChat uploads are **server-side**. The browser POSTs the file
  to chatapi; **chatapi** does the S3 PUT internally. Never look for a browser PUT.
- **Root cause (config layering):** `k8s/chatapi.yaml` sets explicit container env
  `SECURED_AWS_ENDPOINT=http://seaweedfs.cometchat:8333` + `…PATH_STYLE=true`, and Laravel's
  dotenv **does not override real env vars** — so the endpoint in `secrets-rendered/chatapi.env`
  was silently ignored. Meanwhile the `.env` supplied a **different** identity
  (`SECURED_AWS_ACCESS_KEY_ID=cometchat169888916d79019e`) than the store knew → server-side
  PUT got **403 AccessDenied** → chatapi returned the bare `SECURED_S3_BASE_PATH` (no key).
- **Deeper cause — split brain:** TWO stores existed (old single-pod `seaweedfs` in `cometchat`
  vs HA stack in `cometchat-storage`) with TWO credential sets. chatapi hit one with the other's key.

### L2. Fix = collapse to one store (the akamai-projects-seaweedfs package) in `cometchat`
- HA SeaweedFS + cometchatFS console deployed by **`k8s/seaweedfs/deploy.sh all`** into ns `cometchat`
  (3 masters + 3 volumes + filer/S3 + console). It is now a standard `deploy.sh` phase (`storage`,
  between `support` and `apps`).
- The in-cluster name **`seaweedfs.cometchat:8333` is preserved** by `35-s3-service.yaml` (alias
  Service → `component=filer`), so **no app manifest changes**. chatapi's hardcoded endpoint just works.
- s3config carries **both** app identities (`cometchat169888916d79019e` SECURED-driver key +
  `cometchat-492ab378` default-driver key from `seaweedfs-s3-creds`) **+ an anonymous read** identity
  (so the browser `<img>` GET on the public `media-onprem` host needs no auth). Buckets `uploads`,`assets`.
- Verified: SECURED path-style PUT lands a real key; public anonymous GET = 200.

### L1b. …then the media DISPLAY URL still broke — presigned with the INTERNAL host
- **Symptom (after L1/L2 fixed the upload):** the image now landed in the bucket, but the `<img>`
  failed — the URL was `http://seaweedfs.cometchat:8333/uploads/<appId>/media/<file>.png?X-Amz-Signature=…`
  (a **presigned** GET pointing at the in-cluster service name the browser can't resolve).
- **Why:** chatapi serves media as **presigned** S3 GETs, and the AWS PHP SDK signs them against the
  S3 client **`endpoint`** = `SECURED_AWS_ENDPOINT`. The deployment hardcoded that to the internal
  `http://seaweedfs.cometchat:8333` (the L1 override), so the internal host leaked into the browser URL.
  `SECURED_S3_BASE_PATH` / `SECURED_AWS_URL` only affect *non-presigned* URL building — they can't
  relabel a presigned URL; **only `SECURED_AWS_ENDPOINT` is the lever.**
- **Fix:** set `SECURED_AWS_ENDPOINT=https://media-onprem.cometchat-cluster-2.in` (the **public** host)
  in `k8s/chatapi.yaml` (keep path-style). The same host resolves **in-cluster via split-horizon CoreDNS**
  (→ internal ingress → seaweedfs) for server-side PUTs, and **publicly** for the browser — the colleague's
  proven cluster-4 model. `AWS_ENDPOINT` (generic/data disk, server-side only) stays internal.
- **Verified:** a presigned GET built against the public endpoint, fetched through the edge LB, returns
  HTTP 200 + the exact PNG bytes; the SigV4 `host` signature verifies through ingress-nginx (Host preserved)
  and SeaweedFS path-style parsing (despite `-s3.domainName`). **Note:** presigned URLs are generated at
  message-read time, so existing messages self-heal on refresh.
- **If a non-presigned media path ever surfaces** (host shows `s3.amazonaws.com`), also set
  `SECURED_AWS_URL=https://media-onprem.cometchat-cluster-2.in` (the secured disk's `Storage::url()` host).

### L3. SeaweedFS 3.80 operational gotchas (from the colleague's runbook)
- **aws-cli ≥2.23 corrupts uploads on 3.80.** It adds a default CRC32 sent as `Content-Encoding:
  aws-chunked`; 3.80 stores the raw chunked stream → files render corrupt though they "download" fine.
  **Manual uploads (e.g. seeding sticker PNGs) MUST set** `AWS_REQUEST_CHECKSUM_CALCULATION=when_required`
  (+ `AWS_RESPONSE_CHECKSUM_VALIDATION=when_required`) or use `mc`. chatapi's PHP-SDK uploads are unaffected.
  Verify a PNG: `curl <url> | head -c4 | xxd` must be `89504e47`.
- **Pin `chrislusf/seaweedfs:3.80`** — 4.x's IAM/STS subsystem breaks S3 sigv4 (`SignatureDoesNotMatch`),
  and the encrypt flag renamed `-encryptVolumeData` → `-s3.encryptVolumeData` (mixing = crash).
- **After editing the s3config secret, restart the filer** (`rollout restart statefulset/seaweedfs-filer`)
  so it remounts. (Their separate `seaweedfs-edge` nginx also needs a restart; OUR setup fronts the filer
  with the shared ingress-nginx, which re-resolves endpoints automatically — the `seaweedfs` alias Service
  follows the new filer pod across restarts, verified.)
- **Three buckets:** `uploads` (chat media), `assets` (extension assets), `stickers` (default sticker PNGs).
  `assets`+`stickers` are public-read via the `anonymous` identity. Sticker PNGs are a MANUAL upload
  (the bytes must be hosted by us; see §M3).

---

## M. Extensions split + collaborative editors + stickers (cluster-2 adaptation of the colleague's runbook)

### M1. Networking — extensions core PRIVATE, features PUBLIC
- `extensions-onprem` + `*.extensions-onprem` = the marketplace/admin runtime → **internal** ingress
  (whitelisted; external = 403, verified). Nothing client-side references the bare host.
- The user-facing features → **public** edge, all Host-routed to the SAME `extensions` Service:80:
  `stickers-onprem`, `polls-onprem`, `document-onprem`, `whiteboard-onprem`. (Verified
  `stickers-onprem/stickers/v1/show-setting` → 401 = reached the app + auth gate.)
- The editor iframes → their own services: `document-embed-onprem` → `document-embed:9001`,
  `whiteboard-embed-onprem` → `whiteboard:9000` (WebSocket; ingress-nginx auto-upgrades, timeouts 3600).
- ⚠️ **Ingress host-move gotcha:** moving a host between the edge/internal Ingress objects fails the
  nginx admission webhook ("already defined in ingress …") because it validates against the *other*
  object's current state. Fix: `kubectl delete ingress cometchat-internal` first, then `apply` (the
  public edge stays up; only internal app→app hosts blip for seconds).
- Cert: add the 6 feature/editor hosts + `data-onprem` to `cometchat-wildcard` SANs (reissued). DNS:
  public A → edge LB for all 7. No CoreDNS change (the `*.cometchat-cluster-2.in` template already
  resolves everything in-cluster; the public/private split is purely which Ingress object the host is on).

### M2. document-embed (Etherpad) + whiteboard — both images are in OUR ECR
- The colleague's akamai-Harbor/VPN dependency is **obsolete** — `document-embed`, `whiteboard` (and
  `extensions`) are mirrored to `894996064311.dkr.ecr.us-east-2.amazonaws.com/on-prem-docker-images`.
  Pinned by digest in `k8s/apps/doc-whiteboard.yaml`.
- **Etherpad → MySQL:** `k8s/etherpad-db-init.job.yaml` creates the isolated `etherpad` DB + `etherpaduser`
  with `mysql_native_password` (Etherpad 1.8.4's old driver) on the mgmt MySQL `10.20.10.41` — which
  already had `native_password` ON (our 8.0.46, so NO server patch, unlike the colleague's 8.4). The Job
  reads root creds from the existing `mgmtapi-env` secret (never on a command line) + forces the `store`
  table to `utf8mb4`. `settings.json` (with the DB password) is a Secret rendered by `deploy.sh phase_editors`.
- **whiteboard:** our ECR image already ships its built `/app/dist` (the colleague's "Cannot GET /" gotcha
  does NOT apply); runs `node scripts/server.js --config=config.default.yml` (accessToken `board`, shared
  with the extensions whiteboard module). Both editors verified serving HTML over their public hosts.
- Deploy: `deploy.sh phase_editors` (DB + secrets) runs before `phase_apps` (which applies the manifests).

### M3. Stickers — static metadata, hosted PNGs (no Mongo seed for this build)
- The 202 default sticker PNGs (14 sets) are hosted in the `stickers` bucket at key `<set>/<file>.png`
  so the served URL is `https://data-onprem.cometchat-cluster-2.in/stickers/<set>/<file>.png`
  (`DefaultStickersData.js` builds `data-<region>.<domain>`). Upload from
  `…/cometchat-chat-api-infra-backend/extensions/extensions/stickers/resources/stickers` via `s3-onprem`,
  path-style, with `AWS_REQUEST_CHECKSUM_CALCULATION=when_required` (§L3 aws-chunked guard). Verified 200 + valid PNG.
- ⚠️ **No Mongo seeding needed** for THIS code build: `DefaultStickersData.js` is a static `require`d array
  (the source of the default picker), so the empty `extensions.stickers-default` collection is irrelevant —
  it's only for per-app overrides. (Contrast the runbook's "seed Mongo" note, which was a different build.)

---

## K. The mistakes — do NOT repeat (checklist the script enforces)

1. **Don't** use `pd-ssd`/`pd-balanced` while the old infra holds the SSD quota → `pd-standard`. *(A1)*
2. **Don't** start `terraform apply` without checking the `INSTANCES` quota first. *(A2)*
3. **Don't** install MongoDB with the `noble` repo → use `jammy`. *(C1)*
4. **Don't** leave Redis `bind 127.0.0.1` and **don't** trust a self-rewritten `sentinel.conf` — reset it. *(D1, D2)*
5. **Don't** rely on the k8s Job for Kafka topics — create them when Kafka comes up. *(E1)*
6. **Don't** rewrite service URLs or flip schemes in secrets — datastore endpoints **only**. *(G1)*
7. **Don't** hardcode the edge LB IP — read it from `terraform output edge_lb_ip`. *(B3)*
8. **Don't** forget the **second** ECR pull-secret name (`ecr-pull` *and* `ecr-pull-secret`). *(I1)*
9. **Don't** mount the old license.key / fat keys — new `license.txt` + JWT keypair scheme only. *(I2)*
10. **Don't** point `kubectl` at a stale checked-in kubeconfig after a rebuild — regenerate from the fresh one. *(B4)*
11. **Don't** create the Mongo `root` user and stop — apps need `admin`/`extadmin`/`webhookuser`. *(C4)*
12. **Don't** hand the infra over with egress still allow-all. *(J)*
13. **Don't** trust `.env` for chatapi's S3 endpoint — `k8s/chatapi.yaml` sets it as a real env var
    that **overrides** the `.env`. One store, one identity; verify with a server-side PUT, not a browser PUT. *(L1)*
14. **Don't** run two SeaweedFS stores — there is ONE: `k8s/seaweedfs/` in ns `cometchat`. *(L2)*
