# CometChat Storage Box — Deployment Runbook

Deploys, on **your** Kubernetes cluster, a self-contained object-storage stack —
**SeaweedFS** (distributed, replicated, encrypted-at-rest) + the **cometchatFS** S3 console —
behind **your** domain. No dependency on the vendor cluster.

```
            ┌──────── edge nginx (LoadBalancer, TLS, x2 replicas) ────────┐
 users ────▶│  <S3_HOST>      → SeaweedFS S3 gateway (:8333)               │
            │  <CONSOLE_HOST> → cometchatFS console (:3300)                │
            └─────────────────────────────────────────────────────────────┘
   SeaweedFS: 3 masters (Raft quorum) · 3 volume servers (replication 001) · filer+S3 (encrypt-at-rest)
```

This runbook was re-verified end-to-end on a from-scratch clean-room deploy
(masters→volumes→filer→console→edge→seed), followed by a full functional pass: TLS + login/RBAC, the
seed Job, live public/private bucket toggle, object CRUD (upload / download / copy / bulk-delete /
delete-prefix), the details drawer (head + tags + metadata on public *and* private), large-file
**multipart** round-trip, the **least-privilege apps key** (Read/Write/List/Tagging — bucket
create/delete denied), edge caching, and **encryption-at-rest** (plaintext absent from volume disks).

---

## 0. Prerequisites (have these ready before you start)

- [ ] Kubernetes cluster + `kubectl` admin access, and a **namespace** (e.g. `cometchat-on-prem`)
- [ ] An **encrypted** block `StorageClass` (cloud-provider encrypted volumes); `allowVolumeExpansion: true` recommended
- [ ] **Two DNS hostnames** you control: `<S3_HOST>` (object endpoint) and `<CONSOLE_HOST>` (the UI)
- [ ] A **TLS secret** in the namespace covering **both** hosts (wildcard or SAN cert)
- [ ] **Image pull access** to `894996064311.dkr.ecr.us-east-2.amazonaws.com/cometchat-enterprise`
      (`cometchatfs-obf` + `cometchatfs-seed`) — see [`../cometchatfs/ECR-ACCESS.md`](../cometchatfs/ECR-ACCESS.md)
      (cross-account pull, read-only IAM, or air-gapped tarball)
- [ ] `node` (for the password hash) + `openssl` on the operator machine

### Pinned images — **all four pull from our ECR** (`894996064311.dkr.ecr.us-east-2.amazonaws.com/cometchat-enterprise`), digest-pinned
| Component | ECR tag |
|---|---|
| SeaweedFS (master/volume/filer) | `:seaweedfs-4.37` (mirror of `chrislusf/seaweedfs:4.37`) |
| edge nginx | `:edge-nginx-1.27-alpine` (mirror of `nginx:1.27-alpine`) |
| cometchatFS console | `:cometchatfs-obf` (obfuscated) |
| Seeder | `:cometchatfs-seed` |

> One registry, one access grant, all digest-pinned — air-gap friendly. **Every** pod (not just the
> console) needs `ecr-pull-secret`; the manifests reference it and step 2.3 creates it.

---

## 1. Parameters

| Var | Meaning | Example |
|---|---|---|
| `NAMESPACE` | target namespace | `cometchat-on-prem` |
| `S3_HOST` | S3 endpoint host | `media.client.example.com` |
| `CONSOLE_HOST` | console host | `storage.client.example.com` |
| `STORAGE_CLASS` | encrypted storage class | `<your-encrypted-sc>` |
| `VOLUME_SIZE` | disk per volume server | `100Gi` |
| `TLS_SECRET` | kube TLS secret name (covers both hosts) | `client-tls` |
| `ASSETS_HOST` | **OPTIONAL** vanity host for public `assets` (see §2.11) | `assets.client.example.com` |

> Leave `ASSETS_HOST` **unset** to disable the vanity domain — `render.sh` fills it with a dormant
> host that never matches. Set it only if the client wants pretty asset URLs (`https://assets.…/x`).

---

## 2. Deploy

```bash
export NAMESPACE=cometchat-on-prem S3_HOST=media.client.example.com \
       CONSOLE_HOST=storage.client.example.com STORAGE_CLASS=<your-encrypted-sc> \
       VOLUME_SIZE=100Gi TLS_SECRET=client-tls

# 2.1 namespace
kubectl create ns $NAMESPACE

# 2.2 TLS secret covering BOTH hosts (skip if it already exists in the namespace)
kubectl -n $NAMESPACE create secret tls $TLS_SECRET --cert=fullchain.pem --key=privkey.pem

# 2.3 image pull secret (skip if using node IAM / an air-gapped local registry)
kubectl -n $NAMESPACE create secret docker-registry ecr-pull-secret \
  --docker-server=894996064311.dkr.ecr.us-east-2.amazonaws.com \
  --docker-username=AWS --docker-password="$(aws ecr get-login-password --region us-east-2)"
#   ⚠️ ECR tokens expire in 12h — see ../cometchatfs/ECR-ACCESS.md for refresh/IRSA/air-gapped.

# 2.4 generate TWO S3 key pairs (LEAST PRIVILEGE):
#   console = Admin (console ONLY) ; apps = Read/Write/List/Tagging (your apps' SHARED key)
export CONSOLE_ACCESS_KEY=$(openssl rand -hex 16); export CONSOLE_SECRET_KEY=$(openssl rand -hex 32)
export APP_ACCESS_KEY=$(openssl rand -hex 16);     export APP_SECRET_KEY=$(openssl rand -hex 32)

# 2.5 ENCRYPTION-AT-REST key (SSE-S3 KEK) — REQUIRED. The filer encrypts ALL S3 uploads on the
#     volume servers with this key, and REFUSES to start without it. Generate once, keep it SAFE
#     and BACKED UP — losing it makes encrypted data unrecoverable.
export SSE_KEK=$(openssl rand -hex 32)
kubectl -n $NAMESPACE create secret generic seaweedfs-sse-kek --from-literal=kek="$SSE_KEK"

# 2.6 render SeaweedFS manifests + fill the S3-config secret (console + apps identities)
cd seaweedfs && ./render.sh && cd ..
sed -e "s|__NAMESPACE__|$NAMESPACE|g" \
    -e "s|__CONSOLE_ACCESS_KEY__|$CONSOLE_ACCESS_KEY|g" -e "s|__CONSOLE_SECRET_KEY__|$CONSOLE_SECRET_KEY|g" \
    -e "s|__APP_ACCESS_KEY__|$APP_ACCESS_KEY|g"         -e "s|__APP_SECRET_KEY__|$APP_SECRET_KEY|g" \
    seaweedfs/40-s3-secret.example.yaml > seaweedfs/rendered/40-s3-secret.yaml
#   → SAVE the APP key ($APP_ACCESS_KEY / $APP_SECRET_KEY) — you hand it to the app teams (see §5).

# 2.7 deploy SeaweedFS — ORDER MATTERS
kubectl apply -f seaweedfs/rendered/40-s3-secret.yaml
kubectl apply -f seaweedfs/rendered/10-master.yaml
kubectl -n $NAMESPACE rollout status sts/seaweedfs-master   # wait for Raft quorum (3/3)
kubectl apply -f seaweedfs/rendered/20-volume.yaml
kubectl apply -f seaweedfs/rendered/30-filer-s3.yaml        # needs the seaweedfs-sse-kek secret (2.5)
kubectl -n $NAMESPACE rollout status sts/seaweedfs-filer    # filer REFUSES to start w/o the KEK (by design)

# 2.7 cometchatFS console  (MUST be before the edge nginx — nginx resolves upstreams at startup
#     and crash-loops if the cometchatfs Service doesn't exist yet)
node cometchatfs/scripts/hash-password.mjs 'a-strong-admin-password'   # -> scrypt:...:...
cp cometchatfs/k8s/secret.example.yaml cometchatfs/k8s/secret.yaml
#   edit cometchatfs/k8s/secret.yaml:
#     S3_ENDPOINT/S3_PUBLIC_ENDPOINT = https://$S3_HOST
#     S3_ACCESS_KEY/S3_SECRET_KEY    = the CONSOLE key ($CONSOLE_ACCESS_KEY/$CONSOLE_SECRET_KEY) — Admin, console only
#     JWT_SECRET                     = $(openssl rand -hex 32)
#     APP_USERS                      = [{"username":"admin","password":"<scrypt hash>","role":"admin"}]
#     (PUBLIC_BUCKETS is OPTIONAL on 4.37 — the console reads real bucket ACLs; leave it unset)
kubectl -n $NAMESPACE apply -f cometchatfs/k8s/secret.yaml
kubectl -n $NAMESPACE apply -f cometchatfs/k8s/deployment.yaml -f cometchatfs/k8s/service.yaml
kubectl -n $NAMESPACE rollout status deploy/cometchatfs

# 2.8 edge nginx (TLS + host routing) — applied AFTER cometchatfs + filer Services exist
kubectl apply -f seaweedfs/rendered/50-ingress-nginx.yaml

# 2.9 DNS: point BOTH hosts at the edge LoadBalancer's external IP
kubectl -n $NAMESPACE get svc seaweedfs-edge -o wide
#   -> create A records:  S3_HOST  -> <EXTERNAL-IP>   and   CONSOLE_HOST -> <EXTERNAL-IP>
#   (one IP, both hosts — the edge routes by Host header). Wait for DNS to propagate.

# 2.10 SEED the buckets (recommended) — pre-fills the 4 buckets with the bundled public assets
#      (AI-agent icons, sample-app avatars+groups+messages+sampledata, default stickers, VCB zips)
#      and creates the empty private `uploads`. Run LAST — it signs against $S3_HOST, so DNS (2.9)
#      must resolve first. Idempotent (re-running skips prefixes that already have objects).
#      ⚠️ The seed talks S3 — it MUST use the external host (https://$S3_HOST, via the edge).
#      Do NOT repoint S3_ENDPOINT at the internal `seaweedfs-filer` Service: port 8888 is the filer's
#      NATIVE API (uploads fail with "invalid XML" + a {"name":..,"size":..} body) and the raw
#      :8333 fails SigV4 (SignatureDoesNotMatch). Only the edge host works. See §7.
kubectl apply -f seaweedfs/rendered/60-seed-job.yaml
kubectl -n $NAMESPACE wait --for=condition=complete job/cometchatfs-seed --timeout=300s
kubectl -n $NAMESPACE logs job/cometchatfs-seed | tail -12
#   (if bringing up before a public cert is live, set S3_INSECURE="true" in 60-seed-job.yaml)
```

### 2.11 OPTIONAL — vanity domain for public assets (`https://assets.<domain>/…`)

Skip this unless the client wants pretty, bucket-less URLs for public assets (e.g.
`https://assets.client.example.com/logo.png` instead of `…/media…/assets/logo.png`). The edge
already has a ready server block gated on `ASSETS_HOST`; to enable it:

1. **Render with the host:** add `ASSETS_HOST=assets.<client-domain>` to the `export` in step 2, then
   re-run `./render.sh` and re-apply `seaweedfs/rendered/50-ingress-nginx.yaml`.
2. **DNS:** add an A record `assets.<client-domain>` → the **same edge LB IP** as the other hosts.
3. **TLS:** the `TLS_SECRET` cert must **cover** `assets.<client-domain>` — a wildcard `*.<client-domain>`
   cert is easiest (covers this and any future vanity host).

**Public/anonymous reads ONLY.** Never presign or send authenticated requests to the vanity host —
the signature is tied to host+path and the internal rewrite would break it. Private/presigned traffic
stays on `S3_HOST`. (Copy the block for `stickers`/`visual-chat-builder-app` if you want those too.)

---

## 3. The 4 buckets / public vs private

| Bucket | Access | Contents |
|---|---|---|
| `uploads` | **PRIVATE** (presigned URLs only) | chat media at runtime — written by chat-api + extensions |
| `assets` | **PUBLIC** (anonymous read) | AI-agent icons, sample-app avatars/groups/messages, `sampledata.json` |
| `stickers` | **PUBLIC** | default sticker sets |
| `visual-chat-builder-app` | **PUBLIC** | VCB export zips |

Public/private is a **native per-bucket S3 ACL** on 4.37. The seed Job sets the 3 public buckets to
`public-read`; `uploads` stays private. In the console, each bucket shows a real **Public/Private
badge**, and an admin can **flip it live from the bucket menu** ("Make public" / "Make private") —
instant, no restart. To make any new bucket public, just toggle it in the console. (No `anonymous`
identity, no config edits, no `PUBLIC_BUCKETS` needed — that env is an optional badge fallback only.)

---

## 4. Verify

```bash
# storage healthy (3 masters, 3 volumes, free slots)
kubectl -n $NAMESPACE exec seaweedfs-filer-0 -- sh -c 'echo "volume.list" | weed shell' | head

# console + TLS
curl -I https://$CONSOLE_HOST/login                 # 200
open  https://$CONSOLE_HOST                          # log in (admin + your password)

# public asset loads with NO credentials (browser-loadable)
curl -s -o /dev/null -w '%{http_code}\n' https://$S3_HOST/assets/ai-agents/openai-integration.png   # 200
# private bucket is denied to anonymous
curl -s -o /dev/null -w '%{http_code}\n' "https://$S3_HOST/uploads?list-type=2"                      # 403
```
In the console: you should see the 4 seeded buckets → open one → create a bucket → upload + download a file.

---

## 5. Hand to your application teams

Give the app teams (chat-api, extensions, …) these — they need **only** the apps key, never the console/Admin key:

```
S3 endpoint   : https://<S3_HOST>
Access key    : <APP_ACCESS_KEY>      # the "apps" key from step 2.4 — Read/Write/List/Tagging, NO admin
Secret key    : <APP_SECRET_KEY>
Force path style: true
Private bucket: uploads               # chat media (chat-api SECURED_AWS_BUCKET, extensions S3_BUCKET)
Public base   : https://<S3_HOST>/assets/  ·  /stickers/  ·  /visual-chat-builder-app/
```
The apps key **cannot** create/delete buckets (least privilege) — buckets are pre-created by the seed
Job / console. If an app needs a new bucket, create it in the console first.

> **Using the AWS CLI / SDK against this endpoint** — always target the **external** endpoint
> (`https://<S3_HOST>`), never the in-cluster `seaweedfs-filer:8333` directly: SeaweedFS 4.37 rejects
> SigV4 on the raw filer host (`SignatureDoesNotMatch`). Use **path-style** addressing, and with
> **aws-cli v2.17+** export `AWS_REQUEST_CHECKSUM_CALCULATION=when_required` — its default forced
> CRC32 checksum otherwise breaks SeaweedFS signing. (The console SDK and the seed Job already do this.)

---

## 6. Day-2

- **Encryption at rest** — app-layer is **enforced**: every S3 upload is AES-encrypted on the volume
  servers with the **SSE-S3 KEK** (`seaweedfs-sse-kek` secret, from step 2.5). The filer wrapper refuses
  to start (CrashLoopBackOff + FATAL) if that KEK is missing. Keep `STORAGE_CLASS` an *encrypted* class
  for the disk layer too. **BACK UP the `seaweedfs-sse-kek` secret — losing the KEK makes all encrypted
  data unrecoverable.** (Rotating it requires re-encrypting existing objects.)
- **Grow capacity** — raise volume `-max` and/or `VOLUME_SIZE`; or add volume-server replicas.
- **Filer HA** (optional) — point the filer store at a shared DB (Postgres/Redis via `filer.toml`) and raise
  `seaweedfs-filer` replicas. Data durability already survives a node loss via masters + replication `001`.
- **Backups** — snapshot the volume-server PVCs + the filer PVC **together**.

---

## 7. Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| filer `CrashLoopBackOff: FATAL …KEK… refusing to start` | The `seaweedfs-sse-kek` secret (step 2.5) is missing/empty. Encryption-at-rest is enforced — create the secret. |
| Edge nginx `CrashLoopBackOff: host not found in upstream "cometchatfs"` | Edge was applied **before** the cometchatfs Service existed. Apply cometchatFS first, then the edge. |
| `ImagePullBackOff` after ~12h | ECR token expired. Re-run the `ecr-pull-secret` create (or automate per ECR-ACCESS.md). |
| Presigned URLs give `SignatureDoesNotMatch` | `S3_PUBLIC_ENDPOINT` / `S3_HOST` must match the filer's `S3_EXTERNAL_URL` (all `https://$S3_HOST`). |
| Storage 502s after a filer/node reschedule | Edge nginx cached the old filer pod IP. Re-`rollout restart deploy/seaweedfs-edge`. |
| Seed Job fails with a TLS error during bring-up | Cert not live yet — set `S3_INSECURE="true"` in `60-seed-job.yaml`, or run after the real cert is serving. |
| Uploaded data readable as plaintext on a volume's `/data` | You're on an old bare `-encryptVolumeData` build — 4.x needs the **SSE-S3 KEK** (step 2.5). The pinned 4.37 manifests use it. |
| An app's `aws`/SDK calls fail `SignatureDoesNotMatch` | Either it's hitting `seaweedfs-filer:8333` **directly** (bypassing the edge — 4.37 rejects SigV4 on the raw filer host) or it's aws-cli v2.17+ forcing a CRC32. Point the app at the **external** `https://<S3_HOST>`, use **path-style**, and set `AWS_REQUEST_CHECKSUM_CALCULATION=when_required`. |
| Seed/app upload fails `invalid XML received` / `not well-formed`, body `{"name":..,"size":..}` | You're uploading to the filer's **native port 8888**, not the **S3 gateway 8333**. The `seaweedfs-filer` Service exposes both. Point `S3_ENDPOINT` at the **external** `https://<S3_HOST>` (the edge → 8333) — not `seaweedfs-filer:8888` (native) and not `:8333` (fails SigV4 on the raw host). Then re-run the seed. Files that "uploaded" to 8888 landed in the filer root, not the bucket — re-seeding via the edge writes them to the right place. |
| `rollout status` on volumes/filer hangs for minutes | Normal on first deploy — the block-storage PVCs provision + attach before pods go Ready. Wait it out (each StatefulSet member binds its own volume). |
```
