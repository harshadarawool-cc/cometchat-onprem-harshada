# Architecture — CometChat on-prem (GCP + RKE2, HAProxy edge)

> The authoritative overview. Companion deep-dives: [NETWORKING](NETWORKING.md) ·
> [HAPROXY-EDGE](HAPROXY-EDGE.md) · [INTERNAL-CONNECTIONS](INTERNAL-CONNECTIONS.md) ·
> [SERVICES](SERVICES.md) · [SEAWEEDFS](SEAWEEDFS.md) · [ENCRYPTION-AT-REST](ENCRYPTION-AT-REST.md) ·
> [DNS-RECORDS](DNS-RECORDS.md) · [DEPLOYMENT](DEPLOYMENT.md) · [SECURITY](SECURITY.md) ·
> [MIGRATION-FROM-LB](MIGRATION-FROM-LB.md).

## What this is

A reproducible, one-command deployment of the **entire CometChat backend** on **Google Cloud + RKE2
(Kubernetes)**, self-hosted for **data residency**. Every datastore, app service, the object store, the
edge, TLS, DNS and seed data is built from Infrastructure-as-Code. One orchestrator (`deploy/deploy.sh`)
drives it; every phase is idempotent.

**This build's distinguishing choice: the public edge is 2 standalone HAProxy VMs doing L4 SNI
passthrough — NOT a cloud load balancer.** TLS terminates inside each pod (per-pod nginx sidecar), never
at the edge. This is the colleague's proven model (see `K8S-NETWORKING-GUIDE.md`).

## The four planes

```
                         INTERNET (clients / SDK / browser)
                                   │  HTTPS :443 (TLS SNI)
                     ┌─────────────┴──────────────┐   DNS round-robin (A → both IPs)
                     ▼                             ▼
           ┌──────────────────┐          ┌──────────────────┐     EDGE PLANE
           │  HAProxy VM #1    │          │  HAProxy VM #2    │     (edge subnet 10.23.30.0/24)
           │  L4 SNI passthru  │          │  L4 SNI passthru  │     no TLS termination here
           └────────┬─────────┘          └─────────┬────────┘
                    │  raw TLS → per-service NodePort (30443–30452)
                    └───────────────┬───────────────┘
                                    ▼
   ┌───────────────────────────────────────────────────────────────────┐
   │  RKE2 cluster (cluster subnet 10.23.20.0/24) — no public IPs        │  APP PLANE
   │                                                                     │
   │   NodePort → kube-proxy → facing pod's nginx TLS sidecar (:443)     │
   │              ┌─────────────────────────────────────────────┐       │
   │   pod:  [ nginx sidecar :443 (wildcard-tls) ] → [ app :N ]  │       │
   │              └─────────────────────────────────────────────┘       │
   │                                                                     │
   │   east-west: CoreDNS split-horizon rewrites <fqdn> → Service        │
   │              ClusterIP:443 (destination pod's sidecar) — verified   │
   │              HTTPS that never leaves the VPC.                       │
   └───────────────────────────────────────────────────────────────────┘
                                    │ (private, intra-VPC only)
                                    ▼
   ┌───────────────────────────────────────────────────────────────────┐
   │  Datastore VMs (data subnet 10.23.10.0/24) — no public IPs          │  DATA PLANE
   │  Mongo rs0 ×3 · Redis Sentinel ×4 clusters · Kafka KRaft ×3 ·       │
   │  TiDB (PD+TiKV+TiDB+TiProxy) · MySQL 8 · (all disks encrypted)      │
   │                                                                     │
   │  Object store IN-cluster: SeaweedFS 4.37 (3 master/3 volume/filer   │
   │  + S3 :8333, SSE-encrypted at rest) + cometchatFS console           │
   └───────────────────────────────────────────────────────────────────┘

   ADMIN PLANE: no public SSH. All admin (SSH, kube-API, HAProxy stats) via Google IAP tunnels only.
```

## Component inventory

| Layer | Components | Where |
|---|---|---|
| **Edge** | 2× HAProxy VM (SNI passthrough), 2 public IPs | `terraform/haproxy.tf`, `ansible/roles/haproxy` |
| **Kubernetes** | RKE2 — 1 server + 3 agents (worker/data nodes) | `terraform/rke2.tf`, `ansible/roles/rke2_*` |
| **Ingress model** | per-service NodePort overlay + per-pod nginx TLS sidecar | `k8s/edge-nodeports.yaml`, `k8s/nginx-tls-sidecar.snippet.yaml` |
| **East-west DNS** | CoreDNS split-horizon (direct-to-Service) | `k8s/coredns-direct.yaml` |
| **TLS** | Let's Encrypt wildcard (Route53 DNS-01) → `wildcard-tls` | `k8s/cert-manager-issuer.yaml`, `k8s/wildcard-cert-full.yaml` |
| **Apps** (16) | chatapi, mgmtapi, websocket, analytics, metrics-pro, service-search, moderationservice, ai-agent-service, visual-chat-builder, extensions, globalwebhooks, dashboard, receipt-updater, notificationscore, whiteboard, document-embed | `k8s/`, `k8s/apps/`, `scripts/deploy-node-apps.py` |
| **Object store** | SeaweedFS 4.37 (3+3+filer/S3) + cometchatFS console | `k8s/seaweedfs/`, `vendor/akamai-seaweedfs/` |
| **Datastores** | Mongo rs0 ×3, Redis ×4 Sentinel clusters, Kafka ×3 (KRaft), TiDB, MySQL 8 | `terraform/datastores.tf`, `ansible/roles/*` |
| **Search / AI** | OpenSearch (+ES8 proxy), Ollama | `k8s/support-services.yaml` |

## Request lifecycle (north-south, e.g. `api-onprem`)

1. Client resolves `api-onprem.cometchat-cluster-2.in` → public DNS returns **both** HAProxy IPs (round-robin).
2. TLS ClientHello hits a HAProxy VM `:443`. HAProxy reads the **SNI** (`api-onprem…`), matches the chatapi
   rule, and forwards the **raw TLS stream** to nodePort **30443** on an RKE2 agent (no decryption at edge).
3. kube-proxy routes the nodePort to a **chatapi pod**; its **nginx sidecar** terminates `wildcard-tls`
   on `:443` and proxies to the chatapi container on `127.0.0.1:8000`.
4. chatapi talks to datastores over the private VPC and to sibling services over **east-west** HTTPS
   (`https://rule-onprem…`, `https://media-onprem…`) — CoreDNS resolves those to in-cluster ClusterIPs, so
   they never leave the VPC. Full call graph: [INTERNAL-CONNECTIONS](INTERNAL-CONNECTIONS.md).

## Design principles

- **No app patching.** Images run as-is, pinned by digest. All fixes live in networking / config /
  secrets / DB-seeding (per-pod sidecars are separate containers, so they don't violate this).
- **Data residency.** No VM has a public IP except the 2 HAProxy VMs (which only SNI-forward `:443`).
  Per-pod TLS + split-horizon CoreDNS keep east-west traffic and all object data inside the VPC.
- **Encryption at rest everywhere.** Encrypted GCP PDs (optional CMEK), RKE2 etcd/secrets encryption,
  SeaweedFS SSE. See [ENCRYPTION-AT-REST](ENCRYPTION-AT-REST.md).
- **Fresh creds per cluster.** `credgen` mints new datastore passwords and syncs them into both the DBs
  and the app secrets — no reuse.
- **One command, idempotent.** `./deploy.sh all` builds zero → working; re-runs converge.
