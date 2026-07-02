# Image inventory — every container image, pinned

> The exact images this deploy runs, all **pinned by digest** (no floating `latest` in the app plane), and
> where each is referenced. **No app patching** — images run as-is. Registries + pull secrets at the bottom.

## App plane — `on-prem-docker-images` ECR (pinned by digest)

Registry: `894996064311.dkr.ecr.us-east-2.amazonaws.com/on-prem-docker-images` · pull secret `ecr-pull` / `ecr-pull-secret`.

| Service | Tag (intent) | Digest (sha256) | Referenced in |
|---|---|---|---|
| chatapi | `:chatapi-ioncube-test` | `f195b85a…9651` | `k8s/chatapi.yaml` |
| mgmtapi | `:mgmt` | `1712df2f…a5c4` | `k8s/mgmtapi.yaml` |
| dashboard | `:customer-dashboard` | `28078c3b…3457` | `k8s/dashboard.yaml` |
| analytics-api | `:analytics` | `8ae95a99…9433` | `k8s/apps/no-ref-apps.yaml` |
| metrics-pro (+ metrics-pro-timer) | `:pro-metrics` | `3a127b33…c12d` | `k8s/apps/no-ref-apps.yaml`, `k8s/apps/metrics-pro-timer.yaml` |
| extensions | `:extensions` (node22-fix, pinned) | `c826c46e…35e72` | `k8s/apps/no-ref-apps.yaml` |
| globalwebhooks | (webhooks) | `96a7e73b…bd45` | `k8s/apps/globalwebhooks.yaml` |
| notificationscore | `:notifications-core` | `2d23ab53…78a61` | `k8s/apps/notificationscore.yaml` |
| service-search | (search) | `c05ddc1f…2609` | `k8s/apps/service-search.yaml` |
| document-embed | `:document-embed` (Etherpad) | `8681d4e6…b226` | `k8s/apps/doc-whiteboard.yaml` |
| whiteboard | `:whiteboard` | `91cf6c69…d7e4` | `k8s/apps/doc-whiteboard.yaml` |
| sql-consumer | (kafka→TiDB) | `94a5add9…c23e8` | `k8s/apps/sql-consumer.yaml` |
| clamav (daemon) | `:clamav-daemon` | `16a41224…b68b` | `k8s/apps/clamav.yaml` |
| antivirus API | `:antimalware-antivirus-service` *(tag, not digest)* | — | `k8s/apps/clamav.yaml` |

### Node-only apps + workers — same ECR, digests in `scripts/deploy-node-apps.py`

| Service | Digest (sha256) | TLS sidecar? |
|---|---|---|
| websocket | `57c6d000…3972` | yes (WS) |
| moderationservice | `b6dcb064…f0f5d` | yes |
| visual-chat-builder | `8c0f173b…15a168` | yes |
| ai-agent-service | `5adf6f3f…7207df` | no (HTTP by design) |
| receipt-updater (worker) | `070b74b4…3b41e` | n/a |
| notifications-delay-worker (worker) | `cf49d977…84807a` | n/a |

> `apps/disabled/calls-relay.yaml` (`2a644be6…`) is **not deployed** (disabled). rtc/`rtc-onprem`
> referenced by chatapi's `WEBRTC_HOST` is likewise not part of this deployed set.

## Object store — `cometchat-enterprise` ECR (pinned by digest)

Registry: `894996064311.dkr.ecr.us-east-2.amazonaws.com/cometchat-enterprise` · pull secret `ecr-pull-secret`.

| Component | Tag | Digest (sha256) | Referenced in |
|---|---|---|---|
| SeaweedFS master/volume/filer | `seaweedfs-4.37` | `f898c91e…8b03d` | `k8s/seaweedfs/10/20/30-*.yaml` |
| cometchatFS console | `cometchatfs-obf` | `122cbf6d…495b` | `k8s/seaweedfs/40-cometchatfs.yaml` |
| cometchatFS seed Job | `cometchatfs-seed` | `aacf9de8…77a4` | `k8s/seaweedfs/60-seed-job.yaml` |

> **Fallback:** `chrislusf/seaweedfs:3.80@sha256:1055999e…` is kept in `k8s/seaweedfs/.v380-backup/` for the
> SigV4 fallback path ([SEAWEEDFS](SEAWEEDFS.md)) — **not deployed** by default.

## Infra / support / utility images (public registries, pinned tags)

| Image | Role |
|---|---|
| `nginx:1.27-alpine` (also `nginx:alpine`) | per-pod TLS sidecars, dashboard nginx, seaweedfs-edge, ES8 proxy |
| `opensearchproject/opensearch:2.17.1` | search backend (service-search) |
| `ollama/ollama:0.5.7` | moderation vision / ai-agent LLM |
| `axllent/mailpit:v1.20` | dev SMTP catcher |
| `ghcr.io/kafbat/kafka-ui:latest` | Kafka admin UI (port-forward only) |
| `rancher/local-path-provisioner:v0.0.30` | local-path storage class |
| `apache/kafka:3.8.0` | **Job** — `k8s/kafka-topics-job.yaml` (topic creation fallback) |
| `public.ecr.aws/docker/library/mongo:7` | **Job** — `notifications-push-settings-seed.job.yaml` (mongoimport) |
| `public.ecr.aws/docker/library/mysql:8.0` | **Job** — `etherpad-db-init.job.yaml` |
| `public.ecr.aws/aws-cli/aws-cli:latest`, `curlimages/curl:8.10.1`, `busybox(:1.36)`, `alpine/socat` | jobs / probes / utilities |

> Note: Mongo/Redis/Kafka/TiDB/MySQL **datastores run on VMs** (provisioned by Ansible), not as pods — the
> `mongo:7` / `mysql:8.0` / `apache/kafka` images above are only short-lived **seed/init Jobs**.

## Registries & pull secrets

- **ECR** `…/on-prem-docker-images` (app plane) and `…/cometchat-enterprise` (object store), region `us-east-2`.
- Pull secrets created by the deploy from an AWS ECR token (~12 h TTL; re-run the relevant phase to refresh):
  `ecr-pull` (chatapi + node-apps) and `ecr-pull-secret` (everything else + SeaweedFS) — **both** exist.
- Public images pull directly (egress via Cloud NAT during bootstrap; gate later — [SECURITY](SECURITY.md)).

To repin an app image, update its digest in the manifest / `deploy-node-apps.py` — never switch to a
floating tag (reproducibility + the pinned fixes like `extensions` node22-fix depend on the digest).
