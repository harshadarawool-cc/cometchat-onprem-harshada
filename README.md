# CometChat on-prem — GCP RKE2 (one-click)

Reproducible, zero → fully-working CometChat backend on GCP + RKE2. One command rebuilds the entire
cluster (VMs, datastores, seed data, all app services, ingress, TLS) from scratch.

```
.
├── dumps/          DB seed data — 4 MySQL .sql (pulsecustomerdb, onprem-features, metrics, analytics)
│                   + Mongo JSON (vcb template, moderation rules, notification templates)
└── iac/            all Infrastructure-as-Code — START HERE: iac/README.md
    ├── deploy/     deploy.sh (the orchestrator) + customer.conf (the one file you edit)
    ├── terraform/  VPC, firewall, edge LB, 25 VMs (mongo/redis/kafka/mysql/tidb/rke2)
    ├── ansible/    datastore provisioning + data seeding
    ├── k8s/        every k8s manifest (apps, ingress, coredns, cert-manager, seaweedfs, …)
    ├── scripts/    credgen, cred-sync, secret-render, node-app deploy, …
    ├── secrets/    ALL credentials (gitignored, per-app) — see iac/secrets/README.md
    └── docs/       architecture + the problem→fix journal
```

## Deploy
```bash
cd iac/deploy
# edit customer.conf (project / zone / domain / sizing / LICENCE_FILE / R53 zone)
./deploy.sh config && ./deploy.sh all        # ~60–90 min, idempotent
cd .. && ./dns-point.sh                       # Route53 *.<domain> → new edge LB IP
```
Full runbook, phase list, and design notes: **[iac/README.md](iac/README.md)**.

## Principles
- **No app patching.** Every image runs as-is, pinned by digest. Fixes live in networking / config /
  secrets / DB-seeding — never the app.
- **Fresh creds per cluster.** `credgen` generates new datastore passwords and syncs them into both the
  DBs and the app secrets, so no credentials are ever reused. See `iac/secrets/README.md`.
- **Data residency.** Per-pod TLS sidecars + split-horizon CoreDNS keep east-west traffic (and all object
  data) inside the VPC.

> Secrets are **gitignored** — a clone contains only redacted `*.env.example` templates. Provide real
> values (or let the deploy self-generate them) before running. See `iac/secrets/README.md`.
