# CometChat on-prem (cluster **v4**) — Session Handoff & Current State

_Snapshot: 2026-07-03. Purpose: hand full context to a fresh agent/session mid-flight._

## TL;DR
- Cluster **v4** is **LIVE**; **36/36 pods Ready**; **every originally-flagged feature works**.
- One item needs the **user**: the vercel-agent's OpenAI key (see §7).
- **Nothing is pushed to GitHub yet** — the standing rule is *test locally, push only on explicit approval at the very end*. All work below is committed-or-uncommitted **locally only**.

---

## 0. Hard constraints (DO NOT violate)
1. **No image patching.** Fixes are config / data / cluster-level only (env, command override, ConfigMap, manifest, DB seed). Never rebuild or edit an app image.
2. **Local only until the end.** Do **not** `git push` / open PRs until the user explicitly approves at the very end. Uncommitted local edits are expected.
3. **SeaweedFS stays on 4.37** (latest). Do **not** downgrade to 3.80 (a `.v380-backup/` fallback exists but is unused).
4. **Understand → explain → fix.** Verify against **our** live cluster, not blindly against the `cc-handoffs/` docs (they describe a *different* cluster; note the deltas).

---

## 1. Access & coordinates
| Thing | Value |
|---|---|
| Repo | `~/cometchat-cluster-haproxy` (git, branch `master`, HEAD `cfa3f53`; uncommitted = this session, see §6) |
| kubeconfig | `export KUBECONFIG=/Users/harshada/cometchat-cluster-haproxy/iac/kubeconfig-6444` |
| GCP | project `onprem-499712`, zone `asia-south1-a`, region `asia-south1`, prefix `cometchat-onprem-v4` |
| Domain | `cometchat-cluster-2.in` (Route53 zone `Z04640112BJ8TJHK3I2RI`) |
| Edge (public) | HAProxy IPs `35.200.198.194`, `8.231.87.107` (DNS round-robin) |
| Test app | appId `1bf6470b9a8`, region `us`; working REST apiKey `218cb3962bd447ab3f3366189dc2f149ff00e257` |
| CIDRs | data `10.24.10.0/24`, cluster `10.24.20.0/24`, edge `10.24.30.0/24` |

**Test through the edge:** `curl -sk --resolve <host>.cometchat-cluster-2.in:443:35.200.198.194 https://<host>.cometchat-cluster-2.in/<path>`

---

## 2. Datastores (private subnet `10.24.10.0/24`)
| Store | IP | Notes |
|---|---|---|
| **TiDB** (chat DB) | `10.24.10.51` | **SINGLE VM**, runs `pd0`/`tikv0`/`tidb`/`tiproxy` as **Docker containers** (not tiup/systemd; `sudo docker ps`). **`e2-standard-2` / 8 GB** (resized this session — see §5). chatapi hard-points `DB_HOST=10.24.10.51`; **no failover**. |
| **MySQL** (mgmt / etherpad / metrics) | `10.24.10.41` | metrics + analytics_logs + etherpad DBs live here (independent of TiDB). |
| Mongo rs0 | `10.24.10.11-13` | |
| Redis Sentinel | `10.24.10.21`, `.24`, … | |
| Kafka | `10.24.10.31`, … | |

**Recover a wedged TiDB VM (no SSH needed):** `gcloud compute instances stop … ` (force) → `set-machine-type e2-standard-2` → `start`. Signature: `ERROR 2013` (no MySQL handshake) = wedged; `ERROR 1045` = recovered.

---

## 3. Architecture (one paragraph)
DNS round-robins the 2 **HAProxy** VMs, which do **L4 SNI passthrough** (no TLS termination) → per-service **NodePort** (30443–30452) on the RKE2 agents → each facing pod's **nginx TLS sidecar** (`:443`, wildcard cert) → the app. East-west traffic uses **CoreDNS split-horizon** (direct-to-Service ClusterIP). SeaweedFS 4.37 S3 is reached at `media-onprem` in **path-style**. The **SNI→NodePort map is the source of truth** in `iac/ansible/group_vars/haproxy.yml` (mirror of `iac/k8s/edge-nodeports.yaml`). **Internal-only** services (no NodePort / no public DNS, east-west only): `metrics-pro`, `moderationservice`, `globalwebhooks`, `service-search`, `visual-chat-builder`, `ai-agent-service`, `vercel-agent`.

---

## 4. Service status — ALL working (36/36 pods Ready)
| Feature (originally flagged) | State | Verified by |
|---|---|---|
| chatapi (chat core) | ✅ | `/v3.0/users` → 200 with real TiDB rows |
| avatars (were 404) | ✅ | `assets.…/…/cometchat-uid-1.webp` → 200 through edge |
| metrics / analytics (were 500) | ✅ | analytics 3/3, metrics-pro 2/2; data in MySQL, not TiDB |
| BYO AI-agents (were 500) | ✅ | ai-agent-service 200; `vercel-agent` 1/1 (LLM key pending, §7) |
| moderation (empty rules) | ✅ | moderationservice 200 |
| VCB (was 401) | ✅ | visual-chat-builder `/v1/health-check` 200 |
| extensions / stickers | ✅ | extensions 200; stickers PNGs + metadata seeded |
| whiteboard | ✅ | `whiteboard-embed-onprem/` 200 |
| **document (Etherpad)** | ✅ **(fixed this session)** | `document-embed-onprem/` 200; see §5 / §O |
| mgmtapi · dashboard · websocket · notifications · search · webhooks | ✅ | edge + east-west health 200 |

---

## 5. What was fixed this session (durable detail in `PROBLEMS-AND-FIXES.md`)
- **§N — TiDB OOM outage (root of a full chat outage).** VM was `e2-medium` (4 GB); co-located TiDB+TiKV+PD OOM-thrashed it into an unreachable wedge (sshd + tidb both stopped handshaking). Fix: stop→resize `e2-standard-2` (8 GB)→start. IaC updated: `customer.conf` `TIDB_TYPE="e2-standard-2"` (+ rendered `terraform.tfvars`).
- **§O — document-embed (Etherpad 3.3.2 / TypeScript).** Image's `entrypoint.sh` hardcodes a 1.x `node …/server.js` that doesn't exist in the TS build → CrashLoop. Fix (config-only): override the container `command` to `node --require tsx/cjs node/server.ts` + set `DB_*` env → our `etherpad` DB (`DB_PASS` from `etherpad-db` secret). In `k8s/apps/doc-whiteboard.yaml`.
- **Earlier (this thread, pre-outage):** SeaweedFS 4.37 SigV4 host rule (chatapi `AWS_ENDPOINT`→edge + extensions `node -r` path-style preload); avatars (`45-edge-tls.yaml` `default_server`); metrics DBs + `sql_mode` (MySQL role); moderation; VCB `#`-password dotenv quoting; stickers PNGs + Mongo metadata seed; ai-agent forms/integrations migration + mem; vercel-agent deploy.

---

## 6. Local changes NOT yet pushed (the diff to eventually commit)
Modified (`M`):
- `iac/deploy/customer.conf` — `TIDB_TYPE="e2-standard-2"` (8 GB floor)
- `iac/deploy/deploy.sh` — extensions path-style patch + sticker seed wiring; metrics restore `die`
- `iac/k8s/apps/doc-whiteboard.yaml` — **document-embed command override + DB env** (the fix)
- `iac/k8s/chatapi.yaml` — `AWS_ENDPOINT` → edge (`media-onprem`), path-style
- `iac/k8s/seaweedfs/45-edge-tls.yaml` — `default_server` on the path-style block (avatars)
- `iac/ansible/group_vars/haproxy.yml` — seaweedfs SNI regex incl. `assets.`
- `iac/ansible/roles/mysql/{defaults,tasks}/main.yml` — `sql_mode` baked (metrics)
- `iac/docs/PROBLEMS-AND-FIXES.md` — incidents **§N**, **§O** + checklist 15–16
- `iac/docs/{SERVICES,IMAGES,UNDERSTANDING-YOUR-INFRA}.md`, `iac/ansible/restore-mongo-seeds.yml`, `iac/k8s/seaweedfs/{60-seed-job.yaml,deploy.sh}`, `iac/scripts/deploy-node-apps.py`, `iac/secrets/apps/visual-chat-builder/.env.example`

Deleted (`D`): `iac/k8s/apps/metrics-pro-timer.yaml` (→ `timer-task.yaml`)

New (`??`): `iac/k8s/apps/extensions-force-path-style.js` (S3 path-style preload) · `iac/k8s/apps/vercel-agent.yaml` (BYOA) · `iac/k8s/apps/timer-task.yaml` · `iac/k8s/ai-agent-forms-seed.job.yaml` · `iac/k8s/sticker-metadata-seed.job.yaml` · `iac/k8s/seaweedfs/seed/stickers/` + a group avatar · `iac/dumps/`

> Note: `iac/terraform/terraform.tfvars` (`tidb.machine_type`) was also edited live but is gitignored; `customer.conf` is the tracked source `deploy.sh` renders it from.

---

## 7. Pending / open items
> ⚠️ **MORNING RESUME (after you START the VMs):** a stop/start is effectively a datastore outage. Services that come up **before** TiDB/Kafka/Redis are ready can survive a startup `uncaughtException` and run **degraded** (esp. `websocket` → realtime dies + client freeze — see below). **First thing after all VMs are Ready: `kubectl -n cometchat rollout restart deploy/websocket` and verify `48 consumers joined / 0 uncaughtException`.** Consider also restarting `chatapi` if its workers crash-loop. Then test the UI Kit. (TiDB VM stays `e2-standard-2`/8 GB across stop/start — the resize persists.)

1. **UI-Kit realtime freeze — IN PROGRESS (resume here).** Symptom: UI Kit `cometchat-uikit-react-6/sample-app` freezes the whole Mac on connect; realtime only updates after refresh. **Root cause found:** the `websocket` service had run a **degraded process since the 18:01 TiDB-outage crash** (`restarts=0`, survived `uncaughtException`) → presence reconnect-storm. **Fixed by `rollout restart deploy/websocket`** (48 consumers, 0 errors, storm gone). My 2 diagnostic edits to that app's `index.tsx` are **reverted** (back to original). **Left off awaiting the user's confirm ("works"/"still freezes")** with the fresh websocket. Full detail: memory `websocket-realtime-freeze` + `docs/PROJECT-JOURNEY.md`. NOT transport/HAProxy/Redis/UI-Kit-version (all verified fine).
2. **vercel-agent LLM key (needs the user).** Local agent at `/Users/harshada/Downloads/vercel-agent/` (port **4000**). Its `OPENAI_API_KEY` is a `sk-proj-…` key whose **org is inaccessible** → OpenAI `401 invalid_organization`. Not a cluster issue. Fix = a valid OpenAI key in that `.env` (org with active billing), **or** point `OPENAI_BASE_URL` at an Ollama/OpenAI-compatible endpoint + set `OPENAI_MODEL`. (`OPENAI_MODEL` is currently `gpt-4o`.)
3. **GitHub push** — only after **explicit user approval**. Then `git add -A && commit` the §6 set + push.
4. **document create-flow e2e** — the editor serves 200; the extensions `/v1/create` → pad-URL → iframe round-trip hasn't been click-tested.
5. **link-preview** extension historically 401'd on `PATCH /messages/<id>/metadata/injected` (revisit if it recurs).

---

## 8. Verify quickly (copy-paste)
```sh
export KUBECONFIG=/Users/harshada/cometchat-cluster-haproxy/iac/kubeconfig-6444
# all pods ready?
kubectl -n cometchat get pods --no-headers | awk '{split($2,a,"/"); t++; if(a[1]==a[2]&&$3=="Running")r++} END{print r"/"t" ready"}'
# chat core (real TiDB read) — from a chatapi pod:
P=$(kubectl -n cometchat get po --no-headers | grep ^chatapi | awk 'NR==1{print $1}')
kubectl -n cometchat exec $P -c chatapi -- curl -sk -o /dev/null -w "%{http_code}\n" \
  -H "Host: api-us.cometchat-cluster-2.in" -H "appId: 1bf6470b9a8" \
  -H "apiKey: 218cb3962bd447ab3f3366189dc2f149ff00e257" "https://127.0.0.1/v3.0/users?perPage=1"
# edge health (public path): document-embed / whiteboard / extensions / chatapi …
for h in api-onprem apimgmt extensions-onprem whiteboard-embed-onprem document-embed-onprem; do
  curl -sk -m10 --resolve $h.cometchat-cluster-2.in:443:35.200.198.194 -o /dev/null \
    -w "  $h -> %{http_code}\n" https://$h.cometchat-cluster-2.in/ ; done
```

## 9. Key files
- Orchestrator: `iac/deploy/deploy.sh` (+ `customer.conf`). Run: `./deploy.sh all` then `./dns-point.sh`.
- Edge map: `iac/ansible/group_vars/haproxy.yml` ↔ `iac/k8s/edge-nodeports.yaml`.
- Problems log (read this first): `iac/docs/PROBLEMS-AND-FIXES.md`.
- Docs index: `iac/docs/00-INDEX.md`.
