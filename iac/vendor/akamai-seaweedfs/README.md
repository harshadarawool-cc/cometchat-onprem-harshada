# CometChat Storage Box

Self-contained, client-deployable object storage: **SeaweedFS** (distributed, replicated,
encrypted) + the **cometchatFS** S3 web console. Deploys on any Kubernetes cluster.

## 👉 Start here
**[`seaweedfs/README.md`](./seaweedfs/README.md)** → then the runbook **[`seaweedfs/DEPLOY.md`](./seaweedfs/DEPLOY.md)**.

```
seaweedfs/    distributed SeaweedFS manifests + runbook (DEPLOY.md)
cometchatfs/  the S3 console — k8s manifests, deploy script, ECR access
```

> This is a **deployment package** — the container images (SeaweedFS, edge nginx, console, seeder)
> are pre-built and digest-pinned in ECR; you only apply manifests. Application source lives in the
> cometchatFS source repo, not here.

> Images are digest-pinned (SeaweedFS **4.37**; obfuscated cometchatFS). Verified on a
> from-scratch deploy (SigV4, presigned, native public/private toggle, SSE-S3 encryption). The only
> owner-provided item is image pull access — see `cometchatfs/ECR-ACCESS.md`.
