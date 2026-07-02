# cometchatFS — Architecture & API Contract

A self-hosted **S3 console** (AWS-S3-style UI) for a SeaweedFS backend. Next.js 14 (App Router, TypeScript, Tailwind). Single container. The browser **never** sees the SeaweedFS creds — all S3 calls go through Next.js API routes (the proxy), which enforce auth + RBAC and mint presigned URLs.

## Stack
- Next.js 14 App Router + TypeScript + Tailwind
- `@aws-sdk/client-s3` + `@aws-sdk/s3-request-presigner` (talks to SeaweedFS S3, path-style)
- `jose` for JWT (HS256), httpOnly cookie session
- Config-driven users/roles (env JSON)

## Roles (RBAC)
- `admin` — everything (incl. create/delete buckets)
- `readwrite` — list/browse/upload/delete objects on allowed buckets
- `readonly` — list/browse/download only

`can(role, action, bucket)` in `lib/rbac.ts`. Actions: `bucket:list|create|delete`, `object:list|get|put|delete`.

## Shared libs (already written — build on these)
- `lib/config.ts` — env config (S3 endpoint/creds/region/forcePathStyle), JWT secret, users list
- `lib/s3.ts` — `s3Client()`, helpers: `listBuckets`, `createBucket`, `deleteBucket`, `listObjects(bucket,prefix)`, `presignGet`, `presignPut`, `deleteObject`
- `lib/auth.ts` — `signSession(user)`, `getSession(req)` (reads cookie), `COOKIE`
- `lib/rbac.ts` — `can(role, action, bucket?)`
- `lib/types.ts` — shared TS types

## API routes (Next.js — `app/api/**/route.ts`)
All return JSON. All except `/auth/login` require a valid session cookie; enforce RBAC.

| Method + path | Body / query | Returns | RBAC |
|---|---|---|---|
| `POST /api/auth/login` | `{username,password}` | sets cookie, `{role,username}` | public |
| `POST /api/auth/logout` | — | clears cookie | any |
| `GET /api/auth/me` | — | `{username,role}` | any |
| `GET /api/buckets` | — | `{buckets:[{name,createdAt}]}` | bucket:list |
| `POST /api/buckets` | `{name}` | `{ok}` | bucket:create (admin) |
| `DELETE /api/buckets?name=` | — | `{ok}` | bucket:delete (admin) |
| `GET /api/objects?bucket=&prefix=` | — | `{prefixes:[string],objects:[{key,size,lastModified}]}` | object:list |
| `POST /api/objects/presign-get` | `{bucket,key}` | `{url}` (5 min) | object:get |
| `POST /api/objects/presign-put` | `{bucket,key,contentType}` | `{url}` (5 min) | object:put |
| `DELETE /api/objects?bucket=&key=` | — | `{ok}` | object:delete |

`listObjects` uses delimiter `/` → returns common prefixes (folders) + objects at that level.

## Frontend (`app/login`, `app/console`, `components/`)
- `app/login/page.tsx` — login form → POST /api/auth/login → redirect to /console
- `app/console/page.tsx` — main console: bucket sidebar + object table + breadcrumbs (prefix nav) + upload (drag-drop, presigned PUT) + download/preview (presigned GET) + delete + create/delete bucket (admin). Hide actions the role can't do.
- `components/` — `BucketSidebar`, `ObjectTable`, `Breadcrumbs`, `UploadModal`, `PreviewModal`, `Toolbar`
- Upload: get presigned PUT from API → PUT file directly to SeaweedFS from browser (multipart via XHR for progress).
- AWS-console look: left bucket list, main pane object table (name/size/modified), top breadcrumbs, action toolbar.

## Env (`.env.example`)
```
S3_ENDPOINT=http://seaweedfs.cometchat-aniket.svc:8333
S3_PUBLIC_ENDPOINT=https://media-onprem.cc-cluster-1.io   # for presigned URLs the browser uses
S3_REGION=us-east-1
S3_ACCESS_KEY=...
S3_SECRET_KEY=...
S3_FORCE_PATH_STYLE=true
JWT_SECRET=<random>
# users: JSON array [{username,password,role,buckets?}] buckets omitted = all
APP_USERS=[{"username":"admin","password":"admin123","role":"admin"}]
```
> Presigned URLs must be signed against `S3_PUBLIC_ENDPOINT` (browser-reachable), while server-side list/create/delete use the internal `S3_ENDPOINT`.

## Deploy (`k8s/`)
- Ships as a **pre-built, digest-pinned image** in ECR (`cometchatfs-obf`) — no local build needed.
- Kubernetes Deployment + Service (`k8s/`), fronted by the shared edge nginx (TLS + host routing).
- Config via a Secret (S3 creds, JWT, APP_USERS); the backend talks to the SeaweedFS S3 endpoint.
- **Full deployment runbook: [`../seaweedfs/DEPLOY.md`](../seaweedfs/DEPLOY.md).**
