# Step 3 — Service Deployment + Image Digests

Status: **PLAN for review. Nothing applied.** From the 6 service handoffs + overall-orchestration read
(7-agent workflow) and live ECR resolution (420 images). Constraint: **no app patching** — every fix is
manifest/config/secret/CoreDNS, never the image.

> **Guiding correction (your steer):** the **latest images all work in Aryan's cluster** — what broke ours was
> the **environment** (the networking + seeding + config gaps in Steps 1–2), not the image versions. So the image
> policy is simple: **latest ECR digest for every app** (your 3 explicit pins fixed), and we fix the environment.

---

## 0. How the reference deploys (and where we diverge)
- **Image delivery — the big one.** Aryan mirrors **ECR → an in-cluster Harbor** (`crane copy` at deploy); pods pull
  from **Harbor** (static pull secret, zero runtime external dep). **We pull straight from ECR** with `ecr-pull-secret`
  whose token **expires ~12h** → the recurring `ImagePullBackOff 403`. → **Decision in §3.**
- **Manifests.** Reference = generic Helm `charts/app` + values. Ours = **raw `k8s/*.yaml`** via `deploy.sh`; our
  `helm/cometchat/` chart is a **red herring** (unused). Map reference chart *values* → our raw manifests.
- **Secrets/env.** Reference: `secrets.yml` → `materialize-secrets.py` → `.env`. Ours: `secrets-rendered/*.env` →
  per-svc k8s secrets + `ecr-pull` + `jwt-public`. Same idea.
- **Deploy order (both):** datastores up + **Kafka topics** → **DB seeds** (pulsecustomerdb before create-app) →
  apps → CoreDNS → ingress → seed assets.

## 1. The environment fixes we missed (config-only, no app patch)
These are the "few things" — none require touching an image.
| Service | What we missed | Fix |
|---|---|---|
| **extensions** | a local `LinkPreviewController.js` **lp-patch** mount (our workaround) | **DELETE the lp-patch** configMap + mount; run the latest image. On-send works on the latest image with the correct extensions **config** (as in Aryan's cluster) — if not, fix the config, not the image |
| **whiteboard** | embed `accessToken` not blanked | set `accessToken:""` in the whiteboard-config ConfigMap |
| **analytics** | `[::1]` TCP-forwarder sidecar hack + broken secret seam (`analytics-env` created, `analytics-config` mounted) | use the reference's clean env (`NODE_OPTIONS=--dns-result-order=ipv4first`); fix renderer to emit `analytics-config` (config.json) |
| **metrics-pro** | start cmd `pm2-runtime … --only` **exits 127** on the current image | align start to the image (`node --max-old-space-size=4096 loader.js`) |
| **moderationservice** | reads `moderation.*` Mongo collections **never seeded**; `.env` mount vs envFrom | seed the moderation collections (Step 2); switch to `envFrom`; create Kafka's 3 moderation topics first |
| **visual-chat-builder** | `BASIC_AUTH_PASSWORD=cc@123#ins` **unquoted → truncated at `#` → 401**; no `vcb.templates` default → 400; no `internal-apivcb-onprem` route/SAN | **quote the password**; seed `vcb.templates _id:default`; add the `internal-apivcb-onprem` ingress rule + cert SAN + `-internal` twin |
| **seaweedfs** | **seed-asset upload missing** | add `weed filer.copy` upload of stickers / VCB-zips / ai-agent-icons / avatars + buckets (not aws-cli — chunked corruption) |
| **chatapi** | command-override + **TiDB-trigger-faking migrate loop**; replicas 1 | keep TiDB-on-VM (locked); replicas 1→4; verify the latest image + correct env makes the migrate-loop unnecessary (§4) |

## 2. Image → digest table — LATEST digest per app (snapshot; your 3 pins fixed)

**Pinned by you (verified pullable in ECR):**
| App | Digest |
|---|---|
| chatapi | `sha256:e35cfbec…d89558` |
| mgmtapi | `sha256:1712df2f…6ea5c4` |
| notificationscore | `sha256:2dc5eb05…337ce9` |

**Latest ECR digest (resolved 2026-07-01):**
| App | Tag | Digest |
|---|---|---|
| websocket | `websocket-ubi-a314dbb` | `sha256:57c6d000f704f5c0f4cab6f46ca6f6ef982ab46eb3d79dc48265c58e8c2e3972` |
| moderationservice | `moderationservice-ubi-dab8164` | `sha256:b6dcb064715215059bc7b3db4c001e912bdf0b629defc59504e5ae70b61f0f5d` |
| visual-chat-builder | `visual-chat-builder-ubi-c00c0f6` | `sha256:58f9279b775c9ffdbef65576046506a97ea85f6b711de8d0fdf80913e2c6e204` |
| ai-agent-service | `ai-agent-service-ubi-3` | `sha256:5adf6f3fec9768699eb4df8dd9ef1962a2a4d72eed621a062e79dc0ebe7207df` |
| dashboard | `customer-dashboard` | `sha256:fd2d877b093c4f7d26cfe4462bd76a34cbdd2e12a0089a2f47f857903bbb70aa` |
| receipt-updater | `receipts-updater-ubi-2b50b6d` | `sha256:070b74b4a41bb7281714a866cd0b9066826e37076c384277cb67cbc0b153b41e` |
| notifications-delay-worker | `notifications-delay-worker-ubi-2056c7b` | `sha256:cf49d977d26e8e64f2dfc79a400bf434cea940a78e35efee08d24b5e5584807a` |
| globalwebhooks | `globalwebhooks-ubi-83d96b2` | `sha256:96a7e73b36760fa86974bdfac7ab42b78e8d51b5250dee4e2d0c3a61e0afbd45` |
| service-search | `service-search-ubi-7c824b0` | `sha256:c05ddc1fe10715655f1807cdaf1d2067323ad48afee4d36aff1d3ab4ab2a2609` |
| analytics | `service-analytics-ubi-d62a5b3` | `sha256:8ae95a99701474485d08196938bf39dd5f99aec493d2f714ddba725fa1b94433` |
| metrics-pro | `pro-metrics` | `sha256:3a127b3334712094c1401f7c8380b83e97ef829b358175b799cae596ed0ec12d` |
| extensions | `extensions-ubi-4a853bb` | `sha256:dca93de50fa1766c496fd228f669f1c98bd7c7242eff18dd383814d8cd9a5664` |
| sql-consumer | `sql-consumer-ubi-7a5fefc` | `sha256:94a5add99fff2c3230fcffa3efa63321a2e1e9c39b946edb65c87338f45c23e8` |
| clamav | `clamav-daemon` | `sha256:16a41224f9918fa731111b504e4a58b5018710f0c6414504142f2cc366ab68bb` |
| cometchatfs | `cometchatfs-obf` | `sha256:122cbf6d95244ad043896f283b9b17fe526b25534580601cb72dafcc79ee495b` |
| document-embed | `document-embed` | `sha256:06aa1266fa1275b7f58908fa30c320ba8326aaaa85aff2143578018592223148` |
| whiteboard | `whiteboard` | `sha256:e149acaaa9c922aff0bb5528412c31cb699d9f67fcce334d50b7d34eb70fc041` |
| seaweedfs (public) | `chrislusf/seaweedfs:3.80` | `@sha256:1055999e08eed1789b0ae45d235126e4495e23d3fb9d6396293fd42539b1ae6a` — **never 4.x** (breaks sigv4) |

**Public infra (keep pinned):** nginx:1.27-alpine · opensearch 2.17.1 · mongo:7 · mysql:8.0 · ollama 0.5.7 ·
mailpit v1.20 · kafka 3.8.0 · busybox 1.36.
**NOT deployed (confirm skip):** campaigns, umc, secure-files, http-runner, internal-ai-service,
ai-agent-rag-service, onboarding-flow, timer-task.

> **Re-resolve right before the rebuild.** chatapi ionCube expires ~36h and the ECR token ~12h, so the chatapi/mgmt
> pins and the `-ubi` line get **re-pinned to the freshest digest at deploy time** — the table above is today's snapshot.
> (I'll re-run the one-line ECR resolver at rebuild.)

## 3. Decision — image delivery
- **A) Direct-ECR + digest pin (simpler)** — add a **CronJob/timer refreshing the ECR token every ~12h** so a fresh
  cluster doesn't `ImagePullBackOff` after 12h. No new infra.
- **B) ECR→Harbor mirror (reference)** — in-cluster Harbor + `crane copy`; pods pull from Harbor (static secret).
  Kills the 12h-token outage class **and** keeps images in-cluster (residency). More infra.

*Recommendation: **A** for the first rebuild, **B** as a fast follow. Your call.*

## 4. Verify-during-build / open escalations
- **chatapi ionCube EVAL ~36h expiry** — re-pin the freshest licensed chatapi/mgmt digest right before rebuild;
  Create App needs the licensed non-expiring build (dev-owned).
- **chatapi TiDB migrate-loop** — verify the latest image + correct env removes the need for the trigger-faking shim;
  if truly required, escalate (not a keep-forever patch).
- **Prove after seeding:** Create App, moderation loads, VCB template opens, search returns, link-preview on-send.

---
Steps 1–3 are all drafted. Nothing applied. Next: **Step 0.5 — teardown + backup + rebuild plan** (what's
destroyed, what's preserved, backups first), which needs your explicit go before anything is touched.
