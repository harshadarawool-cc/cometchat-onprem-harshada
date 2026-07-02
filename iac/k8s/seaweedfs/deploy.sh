#!/usr/bin/env bash
###############################################################################
# Deploy HA SeaweedFS 4.37 + cometchatFS console — the ONE object store.
# Source package: akamai-projects-seaweedfs @ commit 5232cca (seaweedfs/ dir),
# ADAPTED to our RKE2 cluster (namespace `cometchat`, our Ingress instead of the
# package's LoadBalancer edge, local-path SC on Google-managed-encrypted GCP PDs).
# Idempotent — safe to re-run; it converges.
#
#   ./deploy.sh            # early: secrets + manifests + buckets + status  (run in phase_storage)
#   ./deploy.sh secrets    # (re)create secrets (SSE-KEK, S3 identities, console) + refresh ECR token
#   ./deploy.sh manifests  # apply masters -> volumes -> filer -> console -> alias Svc -> Ingress
#   ./deploy.sh buckets    # ensure the 5 buckets exist (weed shell; internal — no DNS needed)
#   ./deploy.sh seed       # LATE: run the in-cluster seed Job (needs external DNS+cert; after phase_certs)
#   ./deploy.sh status     # pods / svc / ingress + console URL & password
#   ./deploy.sh destroy    # remove ONLY the seaweedfs/cometchatfs objects (NOT the ns)
#
# WHAT CHANGED FROM 3.80:
#   - 4.37 images from the consolidated `cometchat-enterprise` ECR (every pod needs ecr-pull-secret)
#   - ENCRYPTION-AT-REST is enforced: the filer refuses to start without the `seaweedfs-sse-kek`
#     secret (SSE-S3 KEK). ⚠️ The KEK is generated ONCE and persisted in secrets/infra/seaweedfs/sse-kek
#     — BACK IT UP. Losing it makes every encrypted object unrecoverable.
#   - S3 identities: `console` (Admin, console+seed only) + one `apps` identity per DISTINCT app key
#     (Read/Write/List/Tagging, what chatapi/extensions present) + an `anonymous` READ identity on
#     uploads/assets/stickers/visual-chat-builder-app. The anonymous grant is REQUIRED: our chatapi/
#     extensions emit PLAIN (non-presigned) object URLs, so browser <img> GETs need anonymous read or
#     they 403 (proven cometchat-podtls model). observability has NO anonymous grant (truly private).
#   - Bucket ACLs (per the live console): assets/stickers/visual-chat-builder-app = PUBLIC, uploads/
#     observability = PRIVATE. `uploads` stays a PRIVATE bucket ACL (console shows Private) but is
#     readable-by-URL via the anonymous identity — that is how chat media renders. The seed Job also
#     sets public-read ACLs on the public buckets (belt-and-suspenders; the anonymous identity already
#     makes them readable immediately, so assets/stickers do NOT wait on the late seed).
#   - Seeding is the in-cluster Job `60-seed-job.yaml` (assets bundled in the image), which signs against
#     the EXTERNAL host https://media-onprem… — so it runs LATE (after DNS + cert are live).
#
# Requires: kubectl (via the IAP tunnel kubeconfig), aws (profile `staging`) for the ECR token,
#           openssl, node (for the scrypt console-password hash).
###############################################################################
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IAC="$(cd "$HERE/../.." && pwd)"

# ---- config -----------------------------------------------------------------
NS="cometchat"                                            # the ONE common namespace
KUBECONFIG_FILE="${KUBECONFIG:-$IAC/kubeconfig-6444}"
ECR_REGISTRY="894996064311.dkr.ecr.us-east-2.amazonaws.com"
ECR_REGION="us-east-2"
AWS_PROFILE="${AWS_PROFILE:-staging}"
# S3_HOST MUST equal the filer's S3_EXTERNAL_URL host (30-filer-s3.yaml) or SigV4/presigned break.
S3_HOST="media-onprem.cometchat-cluster-2.in"            # object endpoint (main Ingress -> seaweedfs alias -> filer)
CONSOLE_HOST="storage.cometchat-cluster-2.in"            # the web console (our 50-ingress.yaml)
SECRETS_DIR="$IAC/secrets/infra/seaweedfs"               # persisted key material (gitignored, stable across reruns)
HASH_SCRIPT="$HERE/hash-password.mjs"                     # scrypt hasher (copied into the workspace)
CHATAPI_ENV="$IAC/secrets/apps/chatapi/.env"             # source of the `apps` S3 identity (matches chatapi)
MASTER="seaweedfs-master-0.seaweedfs-master:9333"
# The 5 buckets and their ACL model (matches the live cometchatFS console):
PUBLIC_BUCKETS="assets stickers visual-chat-builder-app" # native public-read ACL (set by the seed Job)
PRIVATE_BUCKETS="uploads observability"                  # private bucket ACL (uploads=chat media, readable via the anonymous identity; observability=OTel, truly private)

export KUBECONFIG="$KUBECONFIG_FILE"
kc() { kubectl "$@"; }
log()  { printf "• %s\n" "$*"; }
ok()   { printf "✓ %s\n" "$*"; }
warn() { printf "! %s\n" "$*" >&2; }
die()  { printf "✗ %s\n" "$*" >&2; exit 1; }

ensure_tunnel() {
  if ! (exec 3<>/dev/tcp/127.0.0.1/6444) 2>/dev/null; then
    warn "IAP tunnel not up on :6444 — start it, then re-run"
    die "no cluster connectivity"
  fi
  exec 3>&- 3<&- 2>/dev/null || true
  kc version --request-timeout=5s >/dev/null 2>&1 || die "cluster unreachable via $KUBECONFIG_FILE"
}

apply_secret() {  # idempotent create|apply
  kc -n "$NS" create "$@" --dry-run=client -o yaml | kc apply -f - >/dev/null
}

phase_secrets() {
  ensure_tunnel
  kc get ns "$NS" >/dev/null 2>&1 || die "namespace $NS missing (it should already exist)"
  ok "namespace $NS (shared — not created/destroyed here)"
  mkdir -p "$SECRETS_DIR"

  # --- ECR pull secret (every 4.37 pod pulls from cometchat-enterprise; token ~12h) ---
  if command -v aws >/dev/null 2>&1; then
    local token; token="$(aws ecr get-login-password --region "$ECR_REGION" --profile "$AWS_PROFILE" 2>/dev/null || true)"
    if [ -n "$token" ]; then
      apply_secret secret docker-registry ecr-pull-secret \
        --docker-server="$ECR_REGISTRY" --docker-username=AWS --docker-password="$token"
      ok "ecr-pull-secret (ECR token ~12h — re-run 'secrets' to refresh)"
    else warn "could not get ECR token (profile $AWS_PROFILE) — 4.37 pods will ImagePullBackOff"; fi
  else warn "aws CLI missing — skipping ecr-pull-secret"; fi

  # --- SSE-S3 KEK (encryption-at-rest) — MANDATORY (filer refuses to start without it) ---
  # ⚠️ Generated ONCE, persisted, and BACKED UP. Losing it = all encrypted objects unrecoverable.
  if [ ! -s "$SECRETS_DIR/sse-kek" ]; then
    openssl rand -hex 32 | tr -d '\n' > "$SECRETS_DIR/sse-kek"
    warn "generated a NEW SSE-S3 KEK at $SECRETS_DIR/sse-kek — BACK THIS UP (losing it = unrecoverable data)"
  fi
  apply_secret secret generic seaweedfs-sse-kek --from-literal=kek="$(cat "$SECRETS_DIR/sse-kek")"
  ok "seaweedfs-sse-kek (encryption-at-rest KEK — object-layer AES on top of the encrypted GCP PDs)"

  # --- S3 identities: console (Admin) + ONE apps identity per DISTINCT app key. NO anonymous
  #     (public buckets = native 4.37 ACLs). Our apps do NOT all share one S3 key — chatapi presents
  #     its SECURED_* key, extensions ALSO presents a second plain AWS_* key — so we enumerate every
  #     distinct (accessKey,secretKey) pair from secrets/apps/*/{.env,config.json}. A single identity
  #     would 403 the others. Keys are what the apps ALREADY present, so nothing needs re-configuring. ---
  local APP_IDS
  APP_IDS="$(python3 "$IAC/scripts/collect-app-s3-identities.py" "$IAC/secrets/apps")" \
    || die "could not collect app S3 identities (secrets/apps/*/{.env,config.json})"
  # console (Admin) key — generated once + persisted; NEVER shared with the apps.
  [ -s "$SECRETS_DIR/console-access-key" ] || printf 'console%s' "$(openssl rand -hex 8)" > "$SECRETS_DIR/console-access-key"
  [ -s "$SECRETS_DIR/console-secret-key" ] || openssl rand -hex 32 | tr -d '\n'          > "$SECRETS_DIR/console-secret-key"
  local CON_AK CON_SK; CON_AK="$(cat "$SECRETS_DIR/console-access-key")"; CON_SK="$(cat "$SECRETS_DIR/console-secret-key")"
  # ANONYMOUS read identity — REQUIRED because our chatapi/extensions emit PLAIN (non-presigned) object
  # URLs (SECURED_S3_BASE_PATH is a bare path builder; there is no presign toggle). Without this, browser
  # <img> GETs on chat media + assets/stickers 403. This is the proven cometchat-podtls model. The BUCKET
  # ACLs stay private (console still shows `uploads` Private, matching the live console) — the anonymous
  # identity grants object read by URL, which is the capability chat media relies on. observability is NOT
  # anonymous (stays truly private). Public assets are readable IMMEDIATELY (not gated on the late seed ACL).
  local ANON_READ="uploads assets stickers visual-chat-builder-app"
  # merge: { identities: [ console(Admin), <app identities>, anonymous(Read/List on ANON_READ) ] }
  CONSOLE_ID="{\"name\":\"console\",\"credentials\":[{\"accessKey\":\"$CON_AK\",\"secretKey\":\"$CON_SK\"}],\"actions\":[\"Admin\"]}"
  python3 - "$CONSOLE_ID" "$APP_IDS" "$ANON_READ" > "$SECRETS_DIR/s3config.json" <<'PY'
import sys, json
console = json.loads(sys.argv[1]); apps = json.loads(sys.argv[2])
buckets = sys.argv[3].split()
anon_actions = [f"Read:{b}" for b in buckets] + [f"List:{b}" for b in buckets]
anon = {"name": "anonymous", "actions": anon_actions}   # no credentials => anonymous
json.dump({"identities": [console] + apps + [anon]}, open(1, "w", closefd=False), indent=2)
PY
  apply_secret secret generic seaweedfs-s3-config --from-file=s3config.json="$SECRETS_DIR/s3config.json"
  ok "seaweedfs-s3-config (console=Admin + $(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["identities"])-2)' "$SECRETS_DIR/s3config.json") app identities + anonymous read on: $ANON_READ)"

  # --- seaweedfs-s3-creds (chatapi's GENERIC S3 driver reads AWS_ACCESS_KEY_ID/SECRET from this secret;
  #     chatapi.yaml sources keys `access-key`/`secret-key`). Point it at chatapi's SECURED key, which the
  #     collector already registered as an `apps` identity (Read/Write/List/Tagging) — so the generic
  #     in-cluster driver (http://seaweedfs.cometchat:8333) authenticates. Without this secret every chatapi
  #     pod is stuck in CreateContainerConfigError. ---
  local CHAT_AK CHAT_SK
  CHAT_AK="$(grep -E '^SECURED_AWS_ACCESS_KEY_ID='     "$CHATAPI_ENV" | head -1 | cut -d= -f2- | tr -d '\r\n')"
  CHAT_SK="$(grep -E '^SECURED_AWS_SECRET_ACCESS_KEY=' "$CHATAPI_ENV" | head -1 | cut -d= -f2- | tr -d '\r\n')"
  [ -n "$CHAT_AK" ] && [ -n "$CHAT_SK" ] || die "chatapi SECURED_AWS_* missing — cannot build seaweedfs-s3-creds (chatapi would CrashLoop)"
  apply_secret secret generic seaweedfs-s3-creds --from-literal=access-key="$CHAT_AK" --from-literal=secret-key="$CHAT_SK"
  ok "seaweedfs-s3-creds (chatapi generic S3 driver — same key as the registered apps identity)"

  # --- cometchatFS console env (uses the CONSOLE/Admin key; presigns against the external host) ---
  [ -s "$SECRETS_DIR/jwt-secret" ]     || openssl rand -hex 32 | tr -d '\n'          > "$SECRETS_DIR/jwt-secret"
  [ -s "$SECRETS_DIR/admin-password" ] || openssl rand -base64 18 | tr -d '\n/+=' | cut -c1-20 > "$SECRETS_DIR/admin-password"
  local JWT ADMINPW HASH
  JWT="$(cat "$SECRETS_DIR/jwt-secret")"; ADMINPW="$(cat "$SECRETS_DIR/admin-password")"
  HASH="$(node "$HASH_SCRIPT" "$ADMINPW")"
  apply_secret secret generic cometchatfs-env \
    --from-literal=S3_ENDPOINT="http://seaweedfs-filer.${NS}.svc:8333" \
    --from-literal=S3_PUBLIC_ENDPOINT="https://${S3_HOST}" \
    --from-literal=S3_REGION="us-east-1" \
    --from-literal=S3_ACCESS_KEY="$CON_AK" \
    --from-literal=S3_SECRET_KEY="$CON_SK" \
    --from-literal=S3_FORCE_PATH_STYLE="true" \
    --from-literal=JWT_SECRET="$JWT" \
    --from-literal=APP_USERS="[{\"username\":\"admin\",\"password\":\"$HASH\",\"role\":\"admin\"}]"
  ok "cometchatfs-env  (console login: admin / $(cat "$SECRETS_DIR/admin-password"))"
}

phase_manifests() {
  ensure_tunnel
  kc apply -f "$HERE/10-master.yaml"
  log "waiting for master Raft quorum…"
  kc -n "$NS" rollout status sts/seaweedfs-master --timeout=180s || warn "masters not all ready yet"
  kc apply -f "$HERE/20-volume.yaml"
  kc apply -f "$HERE/30-filer-s3.yaml"          # CrashLoops without seaweedfs-sse-kek (by design)
  kc -n "$NS" rollout status sts/seaweedfs-volume --timeout=240s || warn "volumes not all ready yet"
  kc -n "$NS" rollout status sts/seaweedfs-filer  --timeout=240s || warn "filer not ready yet (check seaweedfs-sse-kek exists)"
  kc apply -f "$HERE/40-cometchatfs.yaml"       # console (needs cometchatfs-env)
  kc -n "$NS" rollout status deploy/cometchatfs --timeout=180s || warn "cometchatfs not ready yet"
  kc apply -f "$HERE/35-s3-service.yaml"        # the `seaweedfs` alias -> component=filer (apps hardcode it)
  kc apply -f "$HERE/50-ingress.yaml"           # OUR Ingress (console + s3-onprem); media/data via main ingress
  ok "manifests applied (masters/volumes/filer/console + seaweedfs alias + Ingress)"
}

phase_buckets() {  # ensure the 5 buckets exist (idempotent; via `weed shell` — internal, no DNS/cert needed).
  ensure_tunnel   # Created EARLY so chatapi has `uploads` before it starts. Public-read ACLs are set LATER by the seed.
  local mk=""; local b
  for b in $PRIVATE_BUCKETS $PUBLIC_BUCKETS; do mk="${mk}s3.bucket.create -name ${b}\n"; done
  kc -n "$NS" exec seaweedfs-filer-0 -- sh -c "printf '${mk}s3.bucket.list\n' | weed shell -master=$MASTER" 2>/dev/null \
    | sed 's/^/    /' || warn "bucket create reported an error (may already exist)"
  ok "buckets ensured: $PRIVATE_BUCKETS $PUBLIC_BUCKETS  (ACLs applied by the seed Job)"
}

phase_seed() {  # LATE: in-cluster seed Job. Bundled assets -> public buckets + sets public-read ACLs. Idempotent
  ensure_tunnel # (skips a prefix that already has objects). Signs against https://$S3_HOST -> needs DNS + cert LIVE.
  # Preflight: the external host must resolve + serve a valid cert (post phase_certs). If not, skip gracefully.
  kc -n "$NS" delete job cometchatfs-seed --ignore-not-found >/dev/null 2>&1
  kc apply -f "$HERE/60-seed-job.yaml"
  if kc -n "$NS" wait --for=condition=complete job/cometchatfs-seed --timeout=300s >/dev/null 2>&1; then
    ok "seed complete — public buckets populated + ACLs set"
    kc -n "$NS" logs job/cometchatfs-seed 2>/dev/null | tail -8 | sed 's/^/    /' || true
  else
    warn "seed did NOT complete in 300s — likely $S3_HOST DNS/cert not live yet (run AFTER phase_certs)."
    warn "inspect: kubectl -n $NS logs job/cometchatfs-seed ; then re-run: $0 seed"
  fi
}

phase_status() {
  ensure_tunnel
  echo "── pods ──";    kc -n "$NS" get pods -o wide -l app=seaweedfs 2>/dev/null; kc -n "$NS" get pods -l app=cometchatfs 2>/dev/null
  echo "── svc ──";     kc -n "$NS" get svc seaweedfs seaweedfs-filer seaweedfs-master seaweedfs-volume cometchatfs 2>/dev/null
  echo "── endpoints of the seaweedfs alias ──"; kc -n "$NS" get endpoints seaweedfs 2>/dev/null
  [ -f "$SECRETS_DIR/admin-password" ] && echo "── console: https://$CONSOLE_HOST  (admin / $(cat "$SECRETS_DIR/admin-password")) ──"
  echo "── S3: in-cluster http://seaweedfs.$NS:8333 (path-style) · external https://$S3_HOST ──"
}

phase_destroy() {  # remove ONLY this stack's objects — never the shared namespace
  ensure_tunnel
  kc -n "$NS" delete job cometchatfs-seed --ignore-not-found
  kc -n "$NS" delete -f "$HERE/50-ingress.yaml" -f "$HERE/40-cometchatfs.yaml" \
        -f "$HERE/30-filer-s3.yaml" -f "$HERE/20-volume.yaml" -f "$HERE/10-master.yaml" --ignore-not-found
  kc -n "$NS" delete pvc -l app=seaweedfs --ignore-not-found
  ok "seaweedfs/cometchatfs objects deleted from $NS (namespace + app secrets + SSE-KEK left intact)"
}

case "${1:-all}" in
  all)         phase_secrets; phase_manifests; phase_buckets; phase_status ;;   # EARLY (no seed — that's LATE)
  secrets)     phase_secrets ;;
  manifests)   phase_manifests ;;
  buckets)     phase_buckets ;;
  seed)        phase_seed ;;                                                     # LATE (after phase_certs)
  status)      phase_status ;;
  destroy)     phase_destroy ;;
  *) die "usage: $0 [all|secrets|manifests|buckets|seed|status|destroy]" ;;
esac
