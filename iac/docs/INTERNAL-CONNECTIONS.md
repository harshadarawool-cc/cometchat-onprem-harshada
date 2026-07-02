# Internal connections — how the services talk to each other

> The east-west call graph and the datastore matrix: **who connects to whom, over which FQDN/port, and
> why.** Every inter-service hop below is resolved by CoreDNS split-horizon ([NETWORKING §3](NETWORKING.md))
> and terminates at the destination pod's `:443` nginx sidecar (except the two HTTP-by-design pods).

## 1. Service → service call graph (east-west)

All hostnames are `*.cometchat-cluster-2.in`. "via" = the on-prem FQDN the caller uses; CoreDNS rewrites it
to the in-cluster Service. `HTTP` marks the two plaintext (no-sidecar) targets.

```
                         ┌─────────────┐
  browser / SDK ───────▶ │   chatapi   │ (api-onprem, apiclient-onprem)   core REST API
                         └──────┬──────┘
        ┌───────────────┬───────┼───────────────┬──────────────────┬─────────────────┐
        ▼               ▼       ▼               ▼                  ▼                 ▼
   ws-onprem       rule-onprem  notifications-  media-onprem   webhooks-onprem   internal-search-onprem
   websocket    moderationservice notificationscore seaweedfs-edge globalwebhooks  service-search
   (realtime)   (moderate msg)  (push/email/sms) (S3 media R/W)  (event webhooks) (ES index/query)

  mgmtapi (apimgmt) ──▶ chatapi (api-onprem)        provision apps / server-side admin
  dashboard (app)   ──▶ mgmtapi (apimgmt)           admin UI → mgmt API (browser-side)
  ai-agent-service  ──▶ chatapi (api-onprem-internal, HTTP), Ollama, OpenAI(egress)
  moderationservice ──▶ clamav (test.antivirus, HTTP), Ollama (vision), Kafka
  extensions        ──▶ chatapi, seaweedfs-edge (assets), MySQL(etherpad) for document/whiteboard create
  metrics-pro       ──▶ Kafka (consume), MySQL(metrics), Redis(prometrics)     (metrics-pro-onprem, internal)
  analytics         ──▶ MySQL(analytics_logs), Redis(analytics)                (metrics-onprem, facing)
  receipt-updater   ──▶ TiDB, Kafka, Redis(shared)                             (worker, no Service)
  notifications-delay-worker ─▶ Redis(bullmq), Kafka                           (worker, no Service)
  sql-consumer      ──▶ TiDB, Kafka                                            (worker)
```

> **Verified against the real config.** Every row below is the actual host in the app's `.env`/secret
> (`secrets/apps/<app>/.env`), e.g. chatapi's `CHAT_HOST=websocket-onprem…`, `RULES_BASE_URL=https://rule-onprem…`,
> `SEARCH_MESSAGES_BASE_URL=https://internal-search-onprem…`, `WEBHOOKS_BASE_URL=https://webhooks-onprem…`,
> `EXTENSION_BASE_URL=https://notifications-onprem…`, `AI_AGENT_BASE_URL=http://{{appId}}.ai-agent-service…`,
> `SECURED_AWS_ENDPOINT=https://media-onprem…` — not inferred.

### Caller → callee table (the load-bearing hops)

| Caller | Callee | Via (FQDN) | Purpose |
|---|---|---|---|
| SDK/browser | chatapi | `<appId>.api-onprem`, `apiclient-onprem` | all REST |
| SDK/browser | websocket | `<appId>.websocket-onprem`, `ws-onprem` | realtime; `ws-onprem` = chatapi `CHAT_HOST` |
| chatapi | websocket | `ws-onprem` | push realtime events |
| chatapi | moderationservice | `rule-onprem` | pre-publish moderation |
| chatapi | notificationscore | `notifications-onprem` | fan-out push/email/sms |
| chatapi | globalwebhooks | `webhooks-onprem` | outbound event webhooks |
| chatapi | service-search | `internal-search-onprem` | index/query messages |
| chatapi | seaweedfs-edge | `media-onprem` (S3) | media upload (server-side PUT) + presign |
| mgmtapi | chatapi | `api-onprem` (`ADMIN_API_HOST`) | app provisioning / admin ops |
| mgmtapi | moderationservice | `rule-onprem` (`RULES_BASE_URL`) | rule config |
| mgmtapi | visual-chat-builder | `internal-vcb-onprem` (`VCB_BASE_URL`) | VCB admin |
| mgmtapi | metrics-pro | `metrics-pro-<region>` (`METRICS_BASE_URL`) | metrics admin |
| mgmtapi | extensions | `extensions-<region>` (`ONPREM_EXTENSIONS_BASE_URL`) | extension config |
| mgmtapi | mailpit | `mailpit.cometchat.svc` (`MAIL_HOST`) | outbound mail (dev catcher) |
| dashboard | mgmtapi | `apimgmt` | admin UI backend (browser-side) |
| ai-agent-service | chatapi | `<appId>.api-onprem-internal` (**HTTP**) | bot user creation (needs the `-internal` twin) |
| moderationservice | clamav | `test.antivirus` (**HTTP**) | AV scan |
| moderationservice | ollama | `ollama.cometchat.svc:11434` | vision moderation |
| extensions | seaweedfs-edge | `media-onprem` / `assets` | extension assets |
| visual-chat-builder | seaweedfs-edge | `media-onprem` (`visual-chat-builder-app` bucket) | builder zips |

> **Two `-internal` traps** baked into `coredns-direct.yaml`: `api-onprem-internal` and
> `apiclient-onprem-internal` (ai-agent's `createBot` uses them). Missing twin ⇒ NXDOMAIN ⇒ 500.

## 2. Datastore matrix (app → datastore)

Datastore VMs live on the **data subnet** (`10.23.10.0/24`), no public IPs, reached over the private VPC.
Canonical endpoints (rebuild via `ansible/group_vars/all/main.yml` + `secrets-*`):

| Datastore | Endpoint(s) | Port | Used by |
|---|---|---|---|
| **MongoDB** rs0 (×3) | `10.23.10.11-13` | 27017 | globalwebhooks (`events`), moderationservice, visual-chat-builder, notificationscore, extensions |
| **Kafka** KRaft (×3) | `10.23.10.31-33` | 9092 | chatapi, websocket, notificationscore, ai-agent, moderationservice, service-search, extensions, metrics-pro, sql-consumer, receipt-updater, notifications-delay-worker |
| **TiDB** (PD+TiKV+TiDB+TiProxy) | `10.23.10.51` | 3306 (wire) / 4000 | chatapi, receipt-updater, sql-consumer |
| **MySQL 8** | `10.23.10.41` | 3306 | mgmtapi (`pulsecustomerdb`), metrics-pro (`metrics`), analytics (`analytics_logs`), document-embed (etherpad) |
| **Redis — shared** (×3 Sentinel) | `10.23.10.21-23` | 6379 / 26379 | chatapi, websocket, ai-agent, receipt-updater, notificationscore (cache) |
| **Redis — analytics** | `10.23.10.24-26` | 6379 / 26379 | analytics |
| **Redis — prometrics** | `10.23.10.27-29` | 6379 / 26379 | metrics-pro |
| **Redis — bullmq** | `10.23.10.61-63` | 6379 / 26379 | notificationscore (BullMQ), notifications-delay-worker |
| **SeaweedFS S3** (in-cluster) | `seaweedfs.cometchat:8333` (internal HTTP driver) · `media-onprem` (TLS edge) | 8333 / 443 | chatapi, extensions, visual-chat-builder |
| **OpenSearch** (in-cluster) | `opensearch.cometchat.svc` (via ES8 proxy) | 9200 | service-search |
| **Ollama** (in-cluster) | `ollama.cometchat.svc` | 11434 | moderationservice, ai-agent |
| **Mailpit** (in-cluster) | `mailpit.cometchat.svc` | 1025/8025 | mgmtapi (dev SMTP catcher) |

> No in-cluster vector DB (Qdrant) is deployed in this repo — ai-agent uses Ollama in-cluster + any
> configured external LLM (egress). Add one only if a future ai-agent build requires it.

**4 independent Redis Sentinel clusters** (not one) so the `mymaster` name never collides and each workload
is isolated; `bullmq` is offset to `.61` to never overlap the `.21–.29` block. See
`terraform/variables.tf:redis_clusters`.

## 3. Object-store data paths (SeaweedFS)

- **Server-side (chatapi PUT):** `SECURED_AWS_ENDPOINT=https://media-onprem…` → CoreDNS → `seaweedfs-edge`
  (:443 TLS) → filer `:8333`. Host preserved so SigV4 validates. Object lands in `uploads/<appId>/…`.
- **Browser render (presigned/plain GET):** `https://media-onprem…` → HAProxy SNI → nodePort 30449 →
  `seaweedfs-edge` → filer. Same host resolves publicly and in-cluster (split-horizon), which is why the
  presigned URL works from both sides. (This is the fix for the old "broken thumbnail / internal-host-leak".)
- **Generic HTTP driver:** chatapi also uses `http://seaweedfs.cometchat:8333` (the `seaweedfs` alias
  Service) for non-presigned server-side ops. Details: [SEAWEEDFS](SEAWEEDFS.md).

## 4. Egress (leaves the VPC — data-residency review points)

These are the only paths that leave the VPC (via Cloud NAT), and are what the egress-lockdown step gates
([SECURITY](SECURITY.md)): OpenAI (ai-agent, moderation), Route53 (cert-manager DNS-01), ECR + OS repos
(image/package pulls, bootstrap only), and any third-party the customer enables (Akamai recordings, RTC,
Composio, external webhook targets). Everything else stays inside the VPC by design.
