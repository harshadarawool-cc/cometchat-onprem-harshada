# CometChat on-prem — GCP RKE2, **HAProxy edge** (one-click)

Reproducible, zero → fully-working CometChat backend on GCP + RKE2. One command rebuilds the entire
cluster (VMs, datastores, seed data, all 16 app services, the object store, TLS, DNS) from scratch.

**Edge model:** 2 standalone **HAProxy VMs** do L4 **SNI passthrough** → per-service NodePorts; TLS
terminates at a **per-pod nginx sidecar** (never at the edge). No cloud LB, no central ingress. Full
picture: **[iac/docs/ARCHITECTURE.md](iac/docs/ARCHITECTURE.md)**.

```
.
├── dumps/          DB seed data — 4 MySQL .sql + Mongo JSON (vcb / moderation / notification seeds)
└── iac/            all Infrastructure-as-Code — START HERE: iac/README.md
    ├── deploy/     deploy.sh (the orchestrator) + customer.conf (the one file you edit)
    ├── terraform/  VPC, firewall, 2 HAProxy edge VMs, 25 datastore/RKE2 VMs, encrypted disks (CMEK opt)
    ├── ansible/    datastore provisioning + data seeding + the HAProxy role
    ├── k8s/        every k8s manifest (apps, edge-nodeports, coredns-direct, cert-manager, seaweedfs, …)
    ├── scripts/    credgen, cred-sync, secret-render, node-app deploy, s3-identity collect, …
    ├── secrets/    ALL credentials (gitignored, per-app) — see iac/secrets/README.md
    ├── vendor/     akamai-seaweedfs @ 5232cca (upstream object-store package, for provenance)
    └── docs/       ★ ARCHITECTURE / NETWORKING / HAPROXY-EDGE / INTERNAL-CONNECTIONS / SEAWEEDFS / …
```

## Deploy
```bash
cd iac/deploy
# edit customer.conf (project / zone / domain / sizing / LICENCE_FILE / R53 zone / HAPROXY_COUNT / DISK_KMS_KEY)
./deploy.sh config && ./deploy.sh all        # ~60–90 min, idempotent
cd .. && ./dns-point.sh                       # Route53 *.<domain> → round-robin across the 2 HAProxy IPs
```
Full runbook + verification: **[iac/docs/DEPLOYMENT.md](iac/docs/DEPLOYMENT.md)** · design notes: **[iac/README.md](iac/README.md)**.

## Principles
- **No app patching.** Every image runs as-is, pinned by digest. Fixes live in networking / config /
  secrets / DB-seeding — never the app.
- **Fresh creds per cluster.** `credgen` generates new datastore passwords and syncs them into both the
  DBs and the app secrets, so no credentials are ever reused. See `iac/secrets/README.md`.
- **Data residency.** Per-pod TLS sidecars + split-horizon CoreDNS keep east-west traffic (and all object
  data) inside the VPC.

> Secrets are **gitignored** — a clone contains only redacted `*.env.example` templates. Provide real
> values (or let the deploy self-generate them) before running. See `iac/secrets/README.md`.
