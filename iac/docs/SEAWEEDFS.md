# SeaweedFS — the object store (4.37 enterprise, encrypted at rest)

> Deployed from the **akamai-projects** package (`vendor/akamai-seaweedfs/`, commit `5232cca`), adapted for
> this cluster in `k8s/seaweedfs/`. Encryption: [ENCRYPTION-AT-REST](ENCRYPTION-AT-REST.md). Media routing:
> [INTERNAL-CONNECTIONS §3](INTERNAL-CONNECTIONS.md).

## Topology

```
  3× seaweedfs-master  (Raft quorum, volume assignment)      StatefulSet, 5Gi PVC each
  3× seaweedfs-volume  (replication 001 = 2 copies/object)   StatefulSet, data PVC each, 1/node
  1× seaweedfs-filer   (leveldb2 index + S3 gateway :8333)   StatefulSet, SSE-encrypted at rest
  2× seaweedfs-edge    (nginx TLS :443 → filer:8333)         Deployment (this build; HAProxy edge)
  1× cometchatfs       (S3 admin console :3300, INTERNAL)    Deployment
```

Images from the consolidated **`cometchat-enterprise` ECR** (every pod needs `ecr-pull-secret`).

## How it's deployed

Orchestrated by `k8s/seaweedfs/deploy.sh` (called by `deploy.sh phase_storage` early, `phase_storage_seed`
late):

```bash
./deploy.sh            # EARLY: secrets (SSE-KEK, S3 identities, console) + manifests + buckets + status
./deploy.sh manifests  # 10-master → 20-volume → 30-filer → 40-cometchatfs → 35-s3-alias → 45-edge-tls
./deploy.sh buckets    # ensure the 5 buckets (weed shell; internal, no DNS)
./deploy.sh seed       # LATE: in-cluster seed Job (assets → public buckets + ACLs); needs DNS+cert live
./deploy.sh status     # pods / svc + console URL & password
```

**Order matters:** masters reach Raft quorum before volumes; the filer CrashLoops until `seaweedfs-sse-kek`
exists (by design). Buckets are created early so chatapi has `uploads` before it starts; the public-read
seed runs late (it signs against the external `media-onprem` host, so DNS + cert must be live).

## Manifests (`k8s/seaweedfs/`)

| File | What |
|---|---|
| `10-master.yaml` | 3 masters, Raft, `-defaultReplication=001` |
| `20-volume.yaml` | 3 volume servers, 1/node (anti-affinity), data PVC |
| `30-filer-s3.yaml` | filer + S3 `:8333`; **`WEED_S3_SSE_KEY` + startup guard = enforced encryption at rest**; `S3_EXTERNAL_URL=https://media-onprem…` |
| `35-s3-service.yaml` | `seaweedfs` **alias** Service → filer `:8333` (chatapi's generic in-cluster HTTP driver hardcodes this) |
| `40-cometchatfs.yaml` | admin console `:3300` (ClusterIP, internal) |
| `45-edge-tls.yaml` | **this build:** `seaweedfs-edge` nginx `:443` (wildcard-tls) → filer `:8333`; the `media-onprem` TLS front for HAProxy SNI (north-south) + CoreDNS (east-west) |
| `60-seed-job.yaml` | LATE seed Job — bundled assets → public buckets + public-read ACLs |

## S3 identities & buckets

`deploy.sh phase_secrets` builds `s3config.json` via `scripts/collect-app-s3-identities.py`, which
de-duplicates every distinct `(accessKey, secretKey)` the apps already present (chatapi `SECURED_AWS_*`,
extensions `AWS_*`, …) into least-privilege identities:

- **`console`** — Admin (console + seed only; key persisted, never shared with apps)
- **`apps`** (one per distinct key) — Read/Write/List/Tagging (no bucket-create)
- **`anonymous`** — Read/List on `uploads assets stickers visual-chat-builder-app` (our chatapi/extensions
  emit **plain, non-presigned** object URLs, so browser `<img>` GETs need anonymous read or they 403)

| Bucket | ACL | Contents |
|---|---|---|
| `uploads` | private (readable-by-URL via anonymous identity) | chat media `<appId>/…` |
| `assets` | public | ai-agent icons, sample avatars |
| `stickers` | public | default sticker sets |
| `visual-chat-builder-app` | public | VCB builder zips |
| `observability` | private (no anonymous) | OTel logs/metrics/traces |

## Encryption at rest

**Enforced** — the filer will not start without the SSE-S3 KEK. Full detail:
[ENCRYPTION-AT-REST §3](ENCRYPTION-AT-REST.md). Back up `secrets/infra/seaweedfs/sse-kek`.

## The `media-onprem` dual path (why `seaweedfs-edge` exists)

The filer S3 gateway is **plain HTTP `:8333`**. In the HAProxy SNI-passthrough model, `media-onprem` must be
**HTTPS at a pod**, so `seaweedfs-edge` (nginx `:443` → filer `:8333`, **Host preserved** for SigV4)
terminates the wildcard cert. It's reached both ways:
- north-south: HAProxy SNI → nodePort **30449** (`seaweedfs-edge-np`) → edge pod
- east-west: CoreDNS `media-onprem` → `seaweedfs-edge.cometchat.svc:443`

`chatapi` signs presigned/plain URLs against `https://media-onprem…` (`SECURED_AWS_ENDPOINT`), which resolves
**both** publicly and in-cluster — the fix for the old "internal host leaked into the browser URL" bug.

## SigV4 on 4.37 — validation & fallback

4.x historically broke S3 SigV4 unless IAM/STS was configured (see `vendor/akamai-seaweedfs/seaweedfs/…`
notes). This build ships the enterprise 4.37 build with the SSE KEK path; **validate end-to-end** after deploy:

```bash
# in-cluster (internal HTTP driver)
kubectl -n cometchat exec seaweedfs-filer-0 -- sh -c 'echo "s3.bucket.list" | weed shell -master=seaweedfs-master-0.seaweedfs-master:9333'
# through the TLS edge (external host, after DNS+cert live)
aws s3 ls s3://uploads --endpoint-url https://media-onprem.cometchat-cluster-2.in
aws s3 cp /tmp/x.png s3://uploads/_probe/x.png --endpoint-url https://media-onprem.cometchat-cluster-2.in
```

**Fallback if SigV4 fails on 4.37:** pin SeaweedFS **3.80** (verified SigV4) with `-encryptVolumeData` (still
encrypts at rest). The 3.80 manifests are preserved under `k8s/seaweedfs/.v380-backup/`; swap the image tags
in `10/20/30-*.yaml`, re-run `./deploy.sh manifests`. Trade-off: 3.80 lacks the bucket-policy console badge.

## Console (cometchatFS)

Internal-only (`storage-onprem` is **not** on public DNS). Reach it via port-forward:
```bash
kubectl -n cometchat port-forward svc/cometchatfs 3300:3300     # http://localhost:3300  (admin / see deploy.sh output)
```
