# Services — the 16 CometChat apps

> Per-service: image port, health path (verified through the live edge), facing/internal, the on-prem
> host(s), the HAProxy NodePort (facing only), and where its manifest lives. TLS terminates at each pod's
> nginx sidecar unless marked HTTP-by-design. Routing: [HAPROXY-EDGE](HAPROXY-EDGE.md) ·
> [NETWORKING](NETWORKING.md) · call graph: [INTERNAL-CONNECTIONS](INTERNAL-CONNECTIONS.md).

## Facing services (public via HAProxy SNI → NodePort)

| Service | Health path | App port | Host(s) | NodePort | Sidecar TLS | Manifest |
|---|---|---|---|---|---|---|
| **chatapi** | `/health-check` | 8000 | `*.api-onprem`, `*.apiclient-onprem` | 30443 | yes | `k8s/chatapi.yaml` |
| **mgmtapi** | `/health-check` | 9000 (php-fpm) | `apimgmt` | 30446 | yes (FastCGI) | `k8s/mgmtapi.yaml` |
| **websocket** | `/` (also `/v1/health-check`) | 8080 | `*.websocket-onprem`, `ws-onprem` | 30444 | yes (WS) | `deploy-node-apps.py` |
| **analytics-api** | `/` | 8080 | `metrics-onprem` | 30447 | yes | `k8s/apps/no-ref-apps.yaml` |
| **extensions** | `/v1/health-check` | 5000 | `extensions-onprem`, `*.extensions-onprem`, stickers/polls/link-preview/thumbnail/document/whiteboard-onprem | 30448 (default) | yes | `k8s/apps/no-ref-apps.yaml` |
| **dashboard** | `/` | 80/443 (nginx) | `app` | 30445 | yes (own nginx) | `k8s/dashboard.yaml` |
| **notificationscore** | `/health-check` | 3100 | `notifications-onprem` | 30452 | yes | `k8s/apps/notificationscore.yaml` |
| **whiteboard** | `/` | 9000 | `whiteboard-embed-onprem` | 30451 | yes (WS) | `k8s/apps/doc-whiteboard.yaml` |
| **document-embed** | `/` | 9001 (Etherpad) | `document-embed-onprem` | 30450 | yes (WS) | `k8s/apps/doc-whiteboard.yaml` |
| **seaweedfs (S3)** | `/nginx-health` | 8333 (filer) | `media/data/files-onprem` | 30449 | yes (edge) | `k8s/seaweedfs/45-edge-tls.yaml` |

## Internal services (east-west only — no public DNS, no NodePort)

| Service | Health path | App port | East-west host | Sidecar TLS | Manifest |
|---|---|---|---|---|---|
| **metrics-pro** | `/health-check` | 3003 | `metrics-pro-onprem` | yes | `k8s/apps/no-ref-apps.yaml` |
| **service-search** | `/health-check` | 3000 | `internal-search-onprem` | yes | `k8s/apps/service-search.yaml` |
| **moderationservice** | `/health` | 3000 | `rule-onprem` | yes | `deploy-node-apps.py` |
| **visual-chat-builder** | `/v1/health-check` | 3000 | `internal-vcb-onprem`, `internal-apivcb-onprem` | yes | `deploy-node-apps.py` |
| **globalwebhooks** | `/v1/webhooks/health-check` | 3006 | `webhooks-onprem` | yes | `k8s/apps/globalwebhooks.yaml` |
| **ai-agent-service** | `/agents/health-check` | 4002 | `*.ai-agent-service` | **HTTP** (by design) | `deploy-node-apps.py` |

## Workers (no Service — background consumers)

| Worker | Role | Manifest |
|---|---|---|
| **receipt-updater** | delivery/read-receipt updater (TiDB + Kafka) | `deploy-node-apps.py` (WORKERS) |
| **notifications-delay-worker** | BullMQ delayed-notification worker | `deploy-node-apps.py` (WORKERS) |
| **sql-consumer** | Kafka → TiDB consumer | `k8s/apps/sql-consumer.yaml` |
| **metrics-pro-timer** | periodic monthly user-count job | `k8s/apps/metrics-pro-timer.yaml` |

## Support services (in-cluster backends)

| Service | Port | Role | Manifest |
|---|---|---|---|
| OpenSearch (+ ES8 proxy) | 9200 | service-search backend | `k8s/support-services.yaml`, `k8s/opensearch-es8proxy.yaml` |
| Ollama | 11434 | moderation vision / ai-agent LLM | `k8s/support-services.yaml` |
| clamav (+ antivirus API) | 3310 / 80 | moderation AV | `k8s/apps/clamav.yaml` (HTTP) |
| mailpit | 1025 / 8025 | dev SMTP catcher | `k8s/support-services.yaml` |
| cometchatfs | 3300 | S3 admin console (internal; port-forward) | `k8s/seaweedfs/40-cometchatfs.yaml` |

## Notes

- **`EXPECTED_WORKLOADS`** in `deploy/deploy.sh` is the authoritative "must-be-Ready after `all`" list;
  `./deploy.sh verify` checks every entry.
- **HTTP-by-design (no sidecar):** `ai-agent-service` (builds `http://` URLs) and `clamav` (test endpoint)
  stay plaintext on the pod network — never exposed via HAProxy.
- **Images** run unmodified, pinned by digest (no app patching). App images come from the
  `on-prem-docker-images` ECR; SeaweedFS/cometchatFS from the `cometchat-enterprise` ECR ([SEAWEEDFS](SEAWEEDFS.md)).
