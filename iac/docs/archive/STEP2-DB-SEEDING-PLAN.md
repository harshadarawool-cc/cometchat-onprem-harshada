# Step 2 — Database Seeding Plan

Status: **PLAN for review. No restore/seed has run.** Verified against the reference seeding guide, the
handoff seed files, and our real `GCP_RKE2/iac` playbooks (grep-confirmed, not assumed). Engines match the
reference 1:1 — the gap is *which seeds we actually apply*, not *where*.

---

## 0. The clean reference model (what "seeded correctly" means)
- **7 pre-baked DB dumps** are the ONLY hand-loaded DB content: 4 MySQL `.sql` + 3 Mongo `.json`.
- **3 apps self-provision** (no dump): mgmt-api creates `pulsecustomerdb` on first HTTP hit; ai-agent-service
  runs its own migrations; service-search builds ES indexes from image-baked schemas.
- **Seed assets** (stickers / VCB zips / ai-agent icons) go to the **object store**, not the DB.
- **Moderation** ships 3 extra Mongo collections (config + rules + wordlist) in the moderation handoff.

---

## 1. Each database → what it needs → why (and our target datastore)

| Seed | Engine → our VM | Target DB/collection | Why it's needed | In our IaC today? |
|---|---|---|---|---|
| `pulsecustomerdb.sql` | MySQL `10.20.10.41` | `pulsecustomerdb` | mgmt baseline (regions, parameters, migrations) | **self-provisions** (dump optional) ✅ |
| `onprem-features.sql` | MySQL `10.20.10.41` | `pulsecustomerdb` (append) | microservices / hooks / interface_trigger / regionmeta → **enables webhooks, extensions, VCB, and the app-provisioning template** | **MISSING** ⚠️ |
| `metrics.sql` | MySQL `10.20.10.41` | `metrics` | metrics-pro `DB_DATABASE` | ✅ restored from repo |
| `analytics.sql` | MySQL `10.20.10.41` | `analytics_logs` | analytics-api / metrics-pro old DB | ✅ restored from repo |
| `events.triggers.json` | Mongo `10.20.10.11` | `events.triggers` | webhook/trigger event catalog | ⚠️ only via an external path that won't exist on rebuild |
| `notifications-core-push-settings.json` | Mongo | `notifications-core-push-settings` (`_id=cometchat_default`) | default push template groups | partial — a K8s Job fills gaps (image workaround) |
| `vcb.templates.json` | Mongo | `vcb.templates` (`_id=default`) | VCB default template — without it dashboard = `ERR_TEMPLATE_NOT_FOUND` | **MISSING** ⚠️ |
| `moderation.configurations.json` | Mongo | `moderation.configurations` | rules-engine config | **MISSING** ⚠️ |
| `moderation.rules.json` | Mongo | `moderation.rules` | default moderation rules | **MISSING** ⚠️ |
| `moderation.profanewordkeywords.json` | Mongo | `moderation.profanewordkeywords` | profanity wordlist | **MISSING** ⚠️ |
| **ES indexes** | OpenSearch (in-cluster) | `app` / `search` / `reaction` / `prefix-search-index` | message search | **MISSING** ⚠️ (no index-creation step; env names exist, indexes don't) |
| chatapi schema | TiDB `10.20.10.51` | `chatapi` + per-app `cod_<appid>` | core chat DB + per-app DBs | app self-provisions per app (see §4) |

Non-DB seeds that stay: **stickers** (our `sticker-seed` Job ✅), **kafka topics** (our `kafka-topics` Job ✅),
**Etherpad DB** (our `etherpad-db-init` Job ✅). Missing object-store assets: **VCB builder zips (5)**,
**ai-agent icons** — add if those features are used.

---

## 2. What our current cluster does wrong (verified against the files)
1. **Skips `onprem-features.sql` entirely** — so webhooks show no triggers and extensions/VCB provisioning is
   inert. This is the reference's mechanism for the app-provisioning template; **missing it is likely the root
   of the "Create App 417 / cod_ template" saga** we've been patching around.
2. **Mongo seeds + pulsecustomerdb pull from external absolute paths** (`/Users/harshada/prodction-kubenates/...`),
   not the repo → on a clean rebuild they **SKIP silently**. So `vcb.templates`, `events.triggers`, moderation
   never land. → the fresh folder must ship every dump **in-repo** and point the playbooks at it.
3. **No ES index seeding** — search indexes are never created in code (they were populated by hand once; not
   codified), so a fresh cluster has broken search.
4. **Workarounds instead of the clean seed** — e.g. `ext-url-destage.job.yaml` hand-rewrites a *specific*
   app's (`cod_66d26ff11c9`) TiDB URLs, and moderation was patched per-app. The reference gets this for free
   from `onprem-features.sql` (pulsecustomerdb microservices template) + the global moderation collections.
   **Fresh plan = seed it the reference way; drop the one-off patches.**

---

## 3. Dump inventory — where each source lives (to stage into `dumps/`)
All present; sources to copy into `cometchat-cluster2-rebuild/dumps/` (portable, no external paths):

| Dump | Source (canonical) |
|---|---|
| pulsecustomerdb.sql, onprem-features.sql, metrics.sql, analytics.sql | `Aryan-clster-working setup/cometchat-db-dumps 2/sql/` |
| events.triggers.json, notifications-core-push-settings.json, vcb.templates.json | `…/cometchat-db-dumps 2/mongo/` |
| moderation.{configurations,rules,profanewordkeywords}.json | `cc-handoffs/cometchat-moderation-handoff/config/secrets/seed/mongo/` |
| VCB builder zips (5), ai-agent icons | `cc-handoffs/cometchat-vcb-handoff/…/seed/vcb-zips/`, `cc-handoffs/cometchat-seaweedfs-handoff/seed/ai-agent-icons/` |
| ES index schemas | **baked into the service-search image** (`/app/src/collection_schema/*.json`) — PUT at deploy |

---

## 4. Restore order + method (adapted to our dedicated DB VMs)
Reference restores via `kubectl exec` into DB *pods*; **our datastores are VMs**, so we keep the ansible-against-VM
approach (`restore-mysql-dumps.yml` copies to the VM then `mysql <`; `restore-mongo.yml` uses `mongoimport`),
just made **portable + complete**. Order (idempotent, guarded on row/table/doc counts):

```
1. kafka-topics + db-users (Mongo app users, Etherpad DB)      ← our Jobs, already correct
2. deploy apps
3. warm mgmt-api (curl) → self-provisions pulsecustomerdb
4. MySQL:  metrics.sql · analytics.sql · onprem-features.sql (append, INSERT IGNORE, AFTER step 3)
5. Mongo:  events.triggers · notifications-core-push-settings · vcb.templates · moderation.{config,rules,words}
6. ES indexes: PUT the image-baked schemas → app/search/reaction/prefix-search-index
7. Assets → SeaweedFS: stickers ✅ (+ VCB zips, ai-agent icons if used)
```
Changes vs today: **add** onprem-features (step 4), the 4 Mongo seeds (step 5), ES indexes (step 6), and the
mgmt warm-up (step 3); **repoint** all dumps at the in-repo `dumps/` folder.

## 5. Verify-during-build (don't assume — prove)
- **Create App** end-to-end after `onprem-features.sql` — confirm it works *without* the custom
  `tidb-cod-template` / `ext-url-destage` patch. Keep a TiDB-level seed only if it still 417s.
- **Moderation** service loads rules from the global collections (not per-app patch).
- **VCB** dashboard opens a template (no `ERR_TEMPLATE_NOT_FOUND`); **search** returns results.

---
Nothing here runs until you approve. On approval I'll **stage the dumps into `dumps/`** (a file copy, not a DB
op) and wire the playbooks — then the actual restore happens only during the rebuild, after the Step 0.5 go-ahead.
Next: **Step 3 (service deployment + image digests)**.
