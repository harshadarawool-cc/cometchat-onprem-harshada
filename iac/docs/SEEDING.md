# Database seeding — what gets pre-loaded, where, and how it's connected

> Plain-language answer to: *"what seeding does the database need, and how are the seedings connected?"*
> Seeding = the minimum data each datastore must contain (or each app must create) so the platform actually
> works on a fresh cluster. There are **three kinds**, run in a **specific order**, and they're **chained**
> to the credential + datastore phases. Source of truth: `deploy.sh` phases `seed / support / editors /
> apps / node-apps / storage-seed`.

## The big picture: schema vs data

- **Schema (the tables/collections)** is mostly **created by the apps themselves** on first boot —
  `mgmtapi` and `chatapi` run `php artisan migrate`, which creates their tables in **MySQL** and **TiDB**.
  *This is the "create tables" automation — you don't load a schema dump.*
- **Data (the rows/documents the apps need to function)** is what we **pre-load** — regions, moderation
  rules, notification templates, VCB templates, search indexes, seed assets. That's "seeding".

So: **apps make their own tables; we seed the starting data.**

## Kind 1 — DB dumps & seeds (the `seed` phase → into the datastore VMs, via Ansible)

### MySQL (→ the MySQL VM, `10.23.10.41`) — `restore-mysql-dumps.yml`, files in `dumps/sql/`
| Dump | Loads into | Feeds which app | Why it's needed |
|---|---|---|---|
| `pulsecustomerdb.sql` | `pulsecustomerdb` | **mgmtapi** | regions, parameters, plans (baseline). *Optional — mgmtapi self-provisions this on first boot; the dump is a fallback/pre-baked data.* |
| `onprem-features.sql` | `pulsecustomerdb` (appended) | mgmtapi | turns on microservices / hooks / regionmeta → **enables webhooks, VCB, extensions**. Applied **after** pulsecustomerdb. |
| `metrics.sql` | `metrics` | **metrics-pro** | metrics baseline |
| `analytics.sql` | `analytics_logs` | **analytics-api** (+ metrics-pro) | analytics baseline |

### MongoDB (→ Mongo rs0 `10.23.10.11-13`) — `restore-mongo-seeds.yml`, files in `dumps/mongo/`
| Seed | Collection | Feeds which app | Why |
|---|---|---|---|
| `events.triggers.json` | `events.triggers` | **globalwebhooks** | the event/trigger catalog |
| `notifications-core-db.notifications-core-push-settings.json` | `…push-settings` | **notificationscore** | default push config (`_id=cometchat_default`) |
| `vcb.templates.json` | `vcb.templates` | **visual-chat-builder** | the default builder template (`_id=default`) |
| `moderation.configurations.json` | moderation configs | **moderationservice** | moderation setup |
| `moderation.rules.json` | moderation rules | moderationservice | the rule set |
| `moderation.profanewordkeywords.json` | profanity list | moderationservice | word filter |

All Mongo seeds are **idempotent** — guarded on `countDocuments()`, so a re-run never duplicates.

### Mongo app users — `fix-mongo-app-users.yml`
Creates the three Mongo login users the apps authenticate as — **`admin` / `extadmin` / `webhookuser`** —
**using the fresh passwords from credgen** (see below). Without this, the apps can't log in to Mongo.

## Kind 2 — App self-provisioning (no dump; happens on first boot)

| App | Creates | Trigger |
|---|---|---|
| **mgmtapi** | `pulsecustomerdb` schema (+ regions/params) | `php artisan migrate` on boot |
| **chatapi** | its **chat/message tables in TiDB** | `php artisan migrate` on boot |
| **ai-agent-service** | its own schema | migrate step on install |

This is why the MySQL/Mongo dumps are "data, optional" — the **structure** is self-built.

## Kind 3 — In-cluster seed Jobs (Kubernetes Jobs, during the app phases)

| Job | Phase | Seeds | Feeds |
|---|---|---|---|
| `es-indexes.job` | **support** | OpenSearch indexes `app/search/reaction/prefix-search-index` (from `k8s/es-schemas/*.json`) | **service-search** |
| `etherpad-db-init.job` | **editors** | the `etherpad` MySQL DB + `etherpaduser` (utf8mb4) | **document-embed** |
| `ext-url-destage.job` | **apps** | rewrites leftover staging URLs → `cometchat-cluster-2.in` in extension data | **extensions** |
| `notifications-push-settings-seed.job` | **node-apps** | push-notification templates | **notificationscore** |
| SeaweedFS seed (`60-seed-job`) | **storage-seed** (LATE) | uploads **stickers, vcb-zips, ai-agent-icons, sample avatars** to the object-store buckets | chat media / assets |

## How the seedings are connected (the ordering chain)

Order matters — each step depends on the one before. Encoded in `deploy.sh`:

```
credgen ──▶ datastores ──▶ seed ──────────────▶ apps start ──▶ (in-cluster seed jobs) ──▶ certs ──▶ storage-seed
   │            │            │                                                                          │
   │            │            ├─ MySQL dumps (pulsecustomerdb → onprem-features overlay → metrics/analytics)
   │            │            ├─ Mongo JSON seeds (webhooks/notifications/vcb/moderation)
   │            │            └─ Mongo app users (admin/extadmin/webhookuser)
   │            └─ DBs created WITH the fresh credgen passwords
   └─ fresh passwords minted (see CREDENTIALS-FLOW.md)
```

The dependencies, in words:

1. **credgen → seed:** the Mongo app users (`fix-mongo-app-users`) are created with the **fresh passwords
   from credgen**, and the apps' `MONGO_URI` (stamped by `sync-app-db-creds.py`) use the same ones — so the
   seed step and the credential step are linked ([CREDENTIALS-FLOW.md](CREDENTIALS-FLOW.md)).
2. **datastores → seed:** the DBs must exist before you can load data into them.
3. **seed → apps:** apps need their data present at boot — moderationservice needs its rules, globalwebhooks
   needs `onprem-features` enabled, notificationscore needs push-settings, VCB needs its template.
4. **pulsecustomerdb before onprem-features:** the second is an *overlay* appended to the first.
5. **OpenSearch up → es-indexes → service-search:** search only works once the indexes exist.
6. **MySQL up → etherpad-db-init → document-embed:** the editor needs its DB created first.
7. **DNS + cert live → SeaweedFS seed (LATE):** the seed Job signs S3 uploads against the public
   `media-onprem` host, so it must run *after* certs — hence it's the last step, not part of early seeding.

## Run / re-run

Seeding is idempotent — safe to re-run any piece:
```bash
./deploy.sh seed            # MySQL dumps + Mongo seeds + Mongo app users
./deploy.sh support         # (re)creates the OpenSearch indexes
./deploy.sh editors         # (re)creates the etherpad DB
./deploy.sh storage-seed    # LATE: (re)upload stickers/vcb/ai-agent assets (needs DNS+cert live)
```

## TL;DR

- **You don't seed schemas** — mgmtapi/chatapi build their own tables via migrate (incl. the chat tables in
  TiDB). **You seed data:** MySQL (`pulsecustomerdb`+`onprem-features`, `metrics`, `analytics`) and Mongo
  (webhooks/notifications/vcb/moderation), plus the OpenSearch indexes, the etherpad DB, and the SeaweedFS
  assets. They're chained: **credgen → datastores → seed → apps → search/editor/push jobs → certs →
  object-store assets.** Datastore endpoints: [INTERNAL-CONNECTIONS.md](INTERNAL-CONNECTIONS.md).
