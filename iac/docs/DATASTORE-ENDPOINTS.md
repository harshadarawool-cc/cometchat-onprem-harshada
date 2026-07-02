# Datastore Endpoints (GCP RKE2) — for env / secret wiring

All IPs are **static** (pinned in Terraform `data` subnet `10.20.10.0/24`), so these are
final once `terraform apply` runs. Apps connect to **our GCP datastores only**.

**Rule of thumb:** we keep the app envs the same and only rewrite the **datastore host/IP**
(Axis 1). DB **credentials are provisioned to match staging**, so usually *only the host
changes* — the username/password in a Mongo URI etc. stays identical.

> Namespace for in-cluster datastores assumed `cometchat` (confirm). In-cluster service
> DNS = `<svc>.cometchat.svc.cluster.local`.

---

## 1. Canonical endpoints

| Datastore | GCP endpoint(s) | Port | Auth |
|---|---|---|---|
| **MongoDB** (rs0) | `10.20.10.11`, `10.20.10.12`, `10.20.10.13` | 27017 | root user (same creds as staging) |
| **Kafka** (KRaft) | `10.20.10.31`, `10.20.10.32`, `10.20.10.33` | 9092 | none (VPC-private) |
| **TiDB** (MySQL wire) | `10.20.10.51` | 3306 | root (same as staging) |
| **MySQL** | `10.20.10.41` | 3306 | root (same as staging) |
| **Redis** (4 dedicated Sentinel clusters) | see §2 — 12 VMs (3 per cluster) | 6379 / 26379 | optional |
| OpenSearch (in-cluster) | `opensearch.cometchat.svc.cluster.local` | 9200 | none |
| Qdrant (in-cluster) | `qdrant.cometchat.svc.cluster.local` | 6333 | API key |
| Ollama (in-cluster) | `ollama.cometchat.svc.cluster.local` | 11434 | none |
| Mailpit (in-cluster) | `mailpit.cometchat.svc.cluster.local` | 1025/8025 | none |
| media-onprem / object storage | `media-onprem.cometchat-cluster-2.in` | 443 | S3 keys |

**Mongo connection string (GCP):**
```
mongodb://<user>:<pass>@10.20.10.11:27017,10.20.10.12:27017,10.20.10.13:27017/<db>?replicaSet=rs0&authSource=admin
```

**Kafka brokers (GCP):** `10.20.10.31:9092,10.20.10.32:9092,10.20.10.33:9092`

---

## 2. Redis — the 4 DEDICATED Sentinel clusters

Each cluster runs on its **own 3 VMs** (master + 2 replicas + 3 sentinels), standard
ports 6379 / 26379, master name `mymaster`. Master = node-1 of each cluster.

| Cluster | VMs (master = node-1) | Direct (master) | Sentinels | Used by |
|---|---|---|---|---|
| **shared** | `redis-shared-1/2/3` = `10.20.10.21/22/23` | `10.20.10.21:6379` | `10.20.10.21/22/23:26379` | chatapi, websocket, ai-agent-service, receipt-updater, notificationscore (cache) |
| **analytics** | `redis-analytics-1/2/3` = `10.20.10.24/25/26` | `10.20.10.24:6379` | `10.20.10.24/25/26:26379` | analytics |
| **prometrics** | `redis-prometrics-1/2/3` = `10.20.10.27/28/29` | `10.20.10.27:6379` | `10.20.10.27/28/29:26379` | pro-metrics |
| **bullmq** | `redis-bullmq-1/2/3` = `10.20.10.61/62/63` | `10.20.10.61:6379` | `10.20.10.61/62/63:26379` | notificationscore (BullMQ), notifications-delay-worker |

> Apps that use a single `REDIS_HOST` → point at the cluster's **master** (`.21:<port>`).
> Apps that support Sentinel (e.g. `*_REDIS_SENTINELS`) → point at all 3 **sentinel** endpoints.

---

## 3. Staging → GCP rewrite map (apply when building the k8s secrets)

| Datastore | Staging value (in Vault env) | → GCP value |
|---|---|---|
| Mongo | `@10.0.0.14:27017` | `@10.20.10.11:27017,10.20.10.12:27017,10.20.10.13:27017` |
| Kafka | `10.0.0.5/7/9:9092` | `10.20.10.31/32/33:9092` |
| TiDB (`DB_HOST`, `RECEIPTS_MYSQL_HOST`) | `10.0.0.11` | `10.20.10.51` |
| MySQL (`DB_HOST`) | `10.0.0.12` | `10.20.10.41` |
| Redis shared (chatapi/ws/ai-agent `REDIS_HOST`=`.8`) | `10.0.0.8` | `10.20.10.21:6379` (sentinels `…21/22/23:26379`) |
| Redis shared cache (`REDIS_HOST`=`.6`) | `10.0.0.6` | `10.20.10.21:6379` |
| Redis bullmq sentinels | `10.0.0.6/8/10:26379` | `10.20.10.61/62/63:26379` |
| Redis analytics (dedicated) | — | `10.20.10.24:6379` (sentinels `…24/25/26:26379`) |
| Redis prometrics (dedicated) | — | `10.20.10.27:6379` (sentinels `…27/28/29:26379`) |
| OpenSearch | `opensearch.cometchat-aniket.svc...:9200` | `opensearch.cometchat.svc.cluster.local:9200` |
| Qdrant | `qdrant.cometchat-aniket.svc...:6333` | `qdrant.cometchat.svc.cluster.local:6333` |
| Ollama | `ollama.cometchat-aniket.svc...:11434` | `ollama.cometchat.svc.cluster.local:11434` |

> Credentials (mongo user/pass, mysql/tidb root pass, redis pass) are set on the GCP
> datastores to **match staging**, so only the host/IP portion above changes. If you'd
> rather rotate creds, we update both the DB and the env key — note it here.

---

## 4. Per-service datastore usage (quick reference)

| Service | Mongo | Kafka | TiDB/MySQL | Redis cluster | Other |
|---|---|---|---|---|---|
> **Corrected 2026-07-02 from the live app `.env`s** (the 2026-06-21 version had the Mongo column wrong
> for extensions/globalwebhooks/analytics/pro-metrics). **Authoritative matrix:**
> [INTERNAL-CONNECTIONS.md](INTERNAL-CONNECTIONS.md). **IPs below use the default `10.20.x` scheme — this
> cluster's `customer.conf` uses `10.23.x`;** only the last octets are meaningful (mongo `.11-.13`, kafka
> `.31-.33`, tidb `.51`, mysql `.41`, redis shared `.21-.23`).

| Service | Mongo | Kafka | TiDB/MySQL | Redis cluster | Other |
|---|---|---|---|---|---|
| chatapi | — | ✅ | TiDB `.51` | **shared** | media-onprem |
| mgmtapi | — | — | MySQL `.41` | — | mailpit |
| websocket | — | ✅ | — | **shared** | |
| notificationscore | ✅ | ✅ | — | **shared** (cache) + **bullmq** | |
| notifications-delay-worker | — | ✅ | — | **bullmq** | |
| moderationservice | ✅ | ✅ | — | — | ollama, clamav |
| globalwebhooks | ✅ | ✅ | — | — | Mongo `events` DB (webhookuser) |
| receipt-updater | — | ✅ | TiDB `.51` | **shared** | |
| sql-consumer | — | ✅ | TiDB `.51` | — | |
| service-search | — | ✅ | — | — | opensearch |
| ai-agent-service | ✅ | ✅ | — | **shared** | ollama |
| extensions | ✅ | ✅ | — | — | media (assets) |
| analytics | — | — | MySQL `.41` (`analytics_logs`) | **analytics** | |
| pro-metrics | — | ✅ | MySQL `.41` (`metrics`) | **prometrics** | |
| visual-chat-builder | ✅ | — | — | — | |
| clamav | — | — | — | — | (standalone) |
| _calls-relay_ | _✅_ | _✅_ | — | — | _DISABLED — not deployed_ |

**MongoDB is used by exactly 6 services:** ai-agent-service, extensions, globalwebhooks, moderationservice,
notificationscore, visual-chat-builder. **chatapi is NOT one of them** — chat messages/conversations live in
**TiDB** (`DB_HOST=…51`), not Mongo. Mongo holds flexible-shape config/rules/templates only.

_Last updated: 2026-07-02 · IPs become live after `terraform apply`._
