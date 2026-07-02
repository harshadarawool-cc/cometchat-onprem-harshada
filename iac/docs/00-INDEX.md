# CometChat on GCP RKE2 (HAProxy edge) — Documentation Index

This build re-architects the edge from a GCP L4 Load Balancer to **2 HAProxy VMs (L4 SNI passthrough) with
per-pod TLS**. The docs below marked **★** are the authoritative set for THIS architecture; the rest are
carried-over deep-dives (still valid where noted).

## ★ Start here (this architecture)
- [ARCHITECTURE.md](ARCHITECTURE.md) — system overview, the four planes, request lifecycle. **Read first.**
- [DEPLOYMENT.md](DEPLOYMENT.md) — the one-click runbook + phase order + end-to-end verification.
- [NETWORKING.md](NETWORKING.md) — FQDN model, split-horizon DNS, per-pod TLS, edge routing, CORS/503 triage.
- [HAPROXY-EDGE.md](HAPROXY-EDGE.md) — HAProxy config, SNI→NodePort map, stats, HA.
- [INTERNAL-CONNECTIONS.md](INTERNAL-CONNECTIONS.md) — **how the services connect internally** (east-west call graph + datastore matrix).
- [SERVICES.md](SERVICES.md) — the 16 apps: ports, health paths, hosts, NodePorts, manifests.
- [IMAGES.md](IMAGES.md) — every container image, pinned by digest, and where it's referenced.
- [SEAWEEDFS.md](SEAWEEDFS.md) — the object store (4.37, encrypted, SigV4 validation + 3.80 fallback).
- [ENCRYPTION-AT-REST.md](ENCRYPTION-AT-REST.md) — disk (CMEK) + etcd/secrets + SeaweedFS SSE.
- [DNS-RECORDS.md](DNS-RECORDS.md) — Route53 records (round-robin A across both HAProxy IPs).
- [SECURITY.md](SECURITY.md) — posture: enforced vs. gated next steps.
- [MIGRATION-FROM-LB.md](MIGRATION-FROM-LB.md) — what changed vs the LB baseline, and why.

## Carried-over deep-dives (still valid)
- [PROBLEMS-AND-FIXES.md](PROBLEMS-AND-FIXES.md) — the build journal (every infra issue → root cause → fix). See its HAProxy addendum.
- [DATASTORE-ENDPOINTS.md](DATASTORE-ENDPOINTS.md) — datastore endpoint rewrite map (unchanged by the edge swap).
- [ENV-VALUE-MAPPING.md](ENV-VALUE-MAPPING.md) — substituting our values into the app envs (unchanged).
- [CERTIFICATES.md](CERTIFICATES.md) — TLS cert issuance (Let's Encrypt DNS-01); the wildcard cert now feeds the pod sidecars.
- [HA-AND-SIZING-PLAN.md](HA-AND-SIZING-PLAN.md) — the deferred HA / right-sizing pass.
- [EXTERNAL-DEPENDENCIES.md](EXTERNAL-DEPENDENCIES.md) — external-call / egress audit.
- [PROJECT-JOURNEY.md](PROJECT-JOURNEY.md) — the original project narrative (LB era).

## Superseded by the ★ docs (LB-era; kept for history)
- [NETWORK-FLOW.md](NETWORK-FLOW.md), [NETWORK-AND-SECURITY.md](NETWORK-AND-SECURITY.md),
  [NETWORK-PRODUCTION-MIGRATION.md](NETWORK-PRODUCTION-MIGRATION.md), [R53-RECORDS.md](R53-RECORDS.md)
  → replaced by NETWORKING / SECURITY / HAPROXY-EDGE / DNS-RECORDS. The old ones describe the single-LB +
  ingress-nginx edge, not the HAProxy edge.

## Runbook
- [../deploy/README.md](../deploy/README.md) — `deploy.sh` reference (kept next to the scripts).
