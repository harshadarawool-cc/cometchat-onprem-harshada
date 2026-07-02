# CometChat Storage Box — deployment package

A self-contained, client-deployable object-storage stack: **SeaweedFS** (distributed,
replicated, encrypted-at-rest) + the **cometchatFS** S3 web console. Deploys on any
Kubernetes cluster, behind your own domain. Verified end-to-end on a from-scratch deploy.

## 👉 Deployment team: start here
**Follow [`DEPLOY.md`](./DEPLOY.md)** — the step-by-step runbook (prereqs → deploy → verify).
That's the only doc you need to run a deployment.

## What's in this package
```
seaweedfs/
├── DEPLOY.md            ← START HERE (the runbook)
├── render.sh            substitutes your hosts/namespace into the manifests
├── 10-master.yaml       SeaweedFS masters (3, Raft HA)
├── 20-volume.yaml       SeaweedFS volume servers (3, replication 001)
├── 30-filer-s3.yaml     filer + S3 gateway (encryption at rest)
├── 40-s3-secret.example.yaml   S3 credentials template
├── 50-ingress-nginx.yaml       edge nginx (TLS + host routing)
└── 60-seed-job.yaml    seeds the 4 buckets + sample data (pre-built image)
../cometchatfs/
├── k8s/                 the console: deployment + service + secret template
├── scripts/hash-password.mjs   generate APP_USERS password hashes
├── ARCHITECTURE.md      how the console + storage fit together
└── ECR-ACCESS.md        how to pull the console image
```

## Before you start — get these ready (prereqs)
- A namespace, and an **encrypted** block `StorageClass`
- **Two DNS hostnames** you control (S3 endpoint + console) and a **TLS secret** covering both
- **Pull access to the console image** — ask the package owner (see `../cometchatfs/ECR-ACCESS.md`)

## Image versions (already digest-pinned — do not change)
- SeaweedFS **`4.37`** — pinned by digest (validated end-to-end). **Do NOT use `latest`** — keep the pin.
- cometchatFS — the obfuscated `cometchatfs-obf` image, pinned by digest.

## Public/private + encryption
- **Public/private buckets**: native per-bucket S3 ACL — flip live from the console bucket menu.
- **Encryption at rest**: enforced via the SSE-S3 KEK (`seaweedfs-sse-kek` secret) — see DEPLOY.md §2.5/§6.

## Need help?
The runbook is self-contained. The only thing the package **owner** must provide is
**image pull access** (`../cometchatfs/ECR-ACCESS.md`) — everything else is self-service.
