# Env value-mapping — colleague's cluster-4 envs → OUR GCP cluster

> Source templates: `~/Downloads/cometchat-envs/apps/<svc>/.env` (his Azure cluster-4, working).
> Rule: **adopt his clean env STRUCTURE; substitute OUR values.** His datastores are in-cluster
> StatefulSets (`*.cometchat-data.svc.cluster.local`); ours are dedicated VMs (`10.20.10.x`).
>
> ⚠️ **Do NOT blind-copy his identity values** (region secret, universal key). Our cluster is
> internally consistent on OUR values and is working — copying his would break auth. See §3.

## 1. Domain
`cometchat-cluster-4.in` → **`cometchat-cluster-2.in`** (everywhere, keep the scheme byte-for-byte — two-axis rule).

## 2. Datastore endpoints (his in-cluster DNS → our VM IPs)

| His value | Our value |
|---|---|
| `mongodb.cometchat-data.svc.cluster.local:27017` | `10.20.10.11:27017` (rs0) |
| `kafka-0/1/2.kafka.cometchat-data.svc.cluster.local:9092` | `10.20.10.31:9092,10.20.10.32:9092,10.20.10.33:9092` |
| `tiproxy.cometchat-data.svc.cluster.local:3306` (TiDB) | `10.20.10.51:3306` |
| `mysql.cometchat-data.svc.cluster.local:3306` | `10.20.10.41:3306` |
| `redis.cometchat-data…` / `redis-0.redis…` (shared) | `10.20.10.21:6379` (sentinel `10.20.10.21/22/23:26379`) |
| `redis-analytics-0.redis-analytics…` | `10.20.10.24:6379` |
| `redis-pro-metrics-0.redis-pro-metrics…` | `10.20.10.27:6379` |
| `redis-bullmq-sentinel.cometchat-data…` | `10.20.10.61:6379` (sentinel `…61/62/63:26379`) |
| `opensearch.cometchat-data.svc.cluster.local:9200` | `opensearch.cometchat.svc.cluster.local:9200` (in-cluster, **ns `cometchat`** not `cometchat-data`) |
| `ollama.cometchat-data.svc.cluster.local:11434` | `ollama.cometchat.svc.cluster.local:11434` |
| `*.cometchat-data.svc` (any other in-cluster svc) | same name, **ns `cometchat`** |

> Note: his redis values are sentinel/DNS; ours are the 4 dedicated Sentinel clusters
> (`master = node-1`, sentinel `:26379`, `master_name = mymaster`). Map each service to its
> assigned cluster (shared / analytics / prometrics / bullmq) per `scripts/secret-sync.py` SVC_REDIS.

## 3. Identity values — KEEP OURS (do not copy his)

Our cluster is consistent on these and **proven working**; his are his cluster's:

| Field(s) | Use OUR value |
|---|---|
| `region_secret` / `CHAT_API_REGION_SECRET` / `CHAT_API_UNIVERSAL_KEY` / moderation `SECRET_ACCESS_KEY` / `ONPREM_REGION_SECRET` / `MICROSERVICE_REGION` | `iac/.secrets/region_secret` (our `218cb3…`, written to `regions.hash` by mgmtapi onprem_setup) |
| Datastore root password (Mongo `admin`, TiDB/MySQL `root`) | **`Cometchat2026*`** (our datastore root) — his are fresh randoms |
| JWT signing pair (`private.pem`/`public.pem`) + `license.txt` | OURS (generated fresh per-install; license `authorizedDomain=cometchat-cluster-2.in`) |
| Wildcard/host TLS | OURS (Let's Encrypt for cometchat-cluster-2.in) |

## 4. Source/blueprint secrets — SAME as his (already match ours)

These are tied to the restored dumps, identical across clusters — verify ours already equals his, keep as-is:

| Field | Value (source) |
|---|---|
| Mongo `webhookuser` pw | `zhyOR9TCNqlN8xRe` (db `events`) |
| Mongo `extadmin` pw | `Q16d1Pe0DUq` (db `extensions`) |
| `db_pass_salt` | `a0ade190a0a5547a5a7e15080aa122ea` |
| calls/analytics creds | `user_sdfkrt345gww` / `pass_geiwerlkw45w` |
| metrics creds | `user_AX345ustycykam` / `pass_hdfj347dfgdfkms` |
| webhooks basic-auth | `user_z5mlpsle73kp` / `pass_aoppolyomtfr` |
| extension creds | `user_m2HLeqEGGd2Xx443` / `Z1duU9K5DB8C1kNQ` |
| `chat_secret` | `9KVyW80W2HJLllXv` |

> ⚠️ If any of these differ from our current live env, **flag before changing** — a mismatch with
> restored DB data causes auth failures (his README §"app shared secrets" warns the same).

## 5. Structural forms his envs get RIGHT (keep them)
- `ACTIVE_TRIGGER` = bare comma-separated, **no quotes/brackets** (our hard-won webhook fix ✓).
- Kafka broker lists = comma-separated `host:port` (not JSON arrays).
- `WEBSOCKETS_*` / topic names, `WEBHOOK_API_*` collection names — take his canonical values.

## 6. Migration procedure (per app — careful, non-destructive)
For each **deployed** app:
1. Take his `apps/<svc>/.env` (or `config.json`/`config_json`/`.envfrom`).
2. Apply §1–§2 substitutions (domain + datastore endpoints) and §3 (our identity values).
3. Keep §4 source secrets (verify equal to ours).
4. **Diff the result against our current LIVE env** (`secret-pull.py` output / `secrets-rendered/<svc>.env`).
5. Review the diff: his structural improvements win; **our working identity/fix values win**. Anything ambiguous → flag, don't apply.
6. Write to `secrets-rendered/<svc>.env`, apply via `secrets-from-rendered.py`, roll the pod, verify healthy.

Skip: **seaweedfs** (deploy pending — ignore per instruction). Apps not deployed (e.g. clamav, and his http-runner/campaigns/umc/etc. that aren't in our 18) → not migrated.
