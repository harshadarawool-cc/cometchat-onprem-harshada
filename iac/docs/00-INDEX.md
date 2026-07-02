# CometChat on GCP RKE2 — Documentation Index

All project docs live in this folder. Start with **PROJECT-JOURNEY** for the whole story.

## Story & history
- [PROJECT-JOURNEY.md](PROJECT-JOURNEY.md) — the full project narrative, start→now: what we built, every blocker + fix, new tooling, pipeline tweaks, workarounds.
- [PROBLEMS-AND-FIXES.md](PROBLEMS-AND-FIXES.md) — the detailed build journal (every infra issue → root cause → fix → where it's baked in).

## Networking & security
- [NETWORK-AND-SECURITY.md](NETWORK-AND-SECURITY.md) — traffic flow, firewall rules, certs, security assessment (P0/P1/P2).
- [NETWORK-FLOW.md](NETWORK-FLOW.md) — plain-English traffic map + how to clone the network for a new cluster.
- [NETWORK-PRODUCTION-MIGRATION.md](NETWORK-PRODUCTION-MIGRATION.md) — the plan to move to the production-grade (Azure cluster-4-style) model: per-host DNS, scoped certs, tight public set.
- [R53-RECORDS.md](R53-RECORDS.md) — exact Route53 records to publish (the one-LB model).
- [CERTIFICATES.md](CERTIFICATES.md) — every TLS cert we use + certbot (Let's Encrypt DNS-01) commands.

## Data & dependencies
- [DATASTORE-ENDPOINTS.md](DATASTORE-ENDPOINTS.md) — datastore endpoint rewrite map.
- [EXTERNAL-DEPENDENCIES.md](EXTERNAL-DEPENDENCIES.md) — external-call / egress audit.
- [ENV-VALUE-MAPPING.md](ENV-VALUE-MAPPING.md) — how to take the colleague's cluster-4 envs and substitute OUR values (datastores, domain, secrets).

## Capacity
- [HA-AND-SIZING-PLAN.md](HA-AND-SIZING-PLAN.md) — the deferred HA / right-sizing pass.

## Runbook
- [../deploy/README.md](../deploy/README.md) — how to run `deploy.sh` (kept next to the scripts).
