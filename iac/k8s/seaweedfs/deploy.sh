#!/usr/bin/env bash
###############################################################################
# Deploy the HA SeaweedFS + cometchatFS console (akamai-projects-seaweedfs package)
# into the COMMON namespace `cometchat` — the single, consolidated object store.
# Idempotent — safe to re-run; it converges.
#
#   ./deploy.sh            # full: secrets + manifests + buckets + cutover + status
#   ./deploy.sh secrets    # (re)create just the secrets (also refreshes the ECR token)
#   ./deploy.sh manifests  # apply just the manifests (assumes secrets exist)
#   ./deploy.sh buckets    # ensure the uploads/assets buckets exist
#   ./deploy.sh cutover    # repoint the `seaweedfs` Service name at the HA filer
#   ./deploy.sh status     # pods / svc / ingress + console URL & password
#   ./deploy.sh destroy    # remove ONLY the seaweedfs/cometchatfs objects (NOT the ns)
#
# Requires: kubectl (via the IAP tunnel kubeconfig), aws (profile `staging`) for the
# ECR pull token, openssl, node (for the scrypt password hash).
###############################################################################
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IAC="$(cd "$HERE/../.." && pwd)"

# ---- config -----------------------------------------------------------------
NS="cometchat"                                  # the ONE common namespace
KUBECONFIG_FILE="${KUBECONFIG:-$IAC/kubeconfig-6444}"
ECR_REGISTRY="894996064311.dkr.ecr.us-east-2.amazonaws.com"
ECR_REGION="us-east-2"
AWS_PROFILE="${AWS_PROFILE:-staging}"
S3_HOST="s3-onprem.cometchat-cluster-2.in"
CONSOLE_HOST="storage.cometchat-cluster-2.in"
SECRETS_DIR="$IAC/.secrets/seaweedfs-ha"        # persisted key material (stable across reruns)
PKG="/Users/harshada/Downloads/akamai-projects-seaweedfs"   # for hash-password.mjs
MASTER="seaweedfs-master-0.seaweedfs-master:9333"

export KUBECONFIG="$KUBECONFIG_FILE"
kc() { kubectl "$@"; }
log()  { printf "• %s\n" "$*"; }
ok()   { printf "✓ %s\n" "$*"; }
warn() { printf "! %s\n" "$*" >&2; }
die()  { printf "✗ %s\n" "$*" >&2; exit 1; }

ensure_tunnel() {
  if ! (exec 3<>/dev/tcp/127.0.0.1/6444) 2>/dev/null; then
    warn "IAP tunnel not up on :6444 — start it with:  $IAC/cluster.sh tunnel   (then re-run)"
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

  # --- ECR pull secret (for the cometchatfs-obf image; token ~12h) ---
  if command -v aws >/dev/null 2>&1; then
    local token; token="$(aws ecr get-login-password --region "$ECR_REGION" --profile "$AWS_PROFILE" 2>/dev/null || true)"
    if [ -n "$token" ]; then
      apply_secret secret docker-registry ecr-pull-secret \
        --docker-server="$ECR_REGISTRY" --docker-username=AWS --docker-password="$token"
      ok "ecr-pull-secret (ECR token ~12h — re-run 'secrets' to refresh)"
    else warn "could not get ECR token (profile $AWS_PROFILE) — cometchatfs will ImagePullBackOff"; fi
  else warn "aws CLI missing — skipping ecr-pull-secret"; fi

  # --- SeaweedFS S3 identities ---
  # PRIMARY identity = exactly what chatapi's SECURED driver presents (secrets-rendered/chatapi.env),
  # so a from-scratch rebuild always matches the apps. Persist it for the console/reruns.
  if [ ! -f "$SECRETS_DIR/access-key" ]; then
    local CENV="$IAC/secrets-rendered/chatapi.env"
    if [ -f "$CENV" ]; then
      grep -E '^SECURED_AWS_ACCESS_KEY_ID=' "$CENV" | head -1 | cut -d= -f2- | tr -d '\r\n' > "$SECRETS_DIR/access-key"
      grep -E '^SECURED_AWS_SECRET_ACCESS_KEY=' "$CENV" | head -1 | cut -d= -f2- | tr -d '\r\n' > "$SECRETS_DIR/secret-key"
      log "primary S3 identity derived from secrets-rendered/chatapi.env (matches the apps)"
    else
      printf '%s' "cometchat$(openssl rand -hex 8)" > "$SECRETS_DIR/access-key"
      openssl rand -hex 32 | tr -d '\n' > "$SECRETS_DIR/secret-key"
      warn "chatapi.env not found — generated a NEW S3 identity; update chatapi.env SECURED_AWS_* to match"
    fi
  fi
  local AK SK AK2 SK2
  AK="$(cat "$SECRETS_DIR/access-key")"; SK="$(cat "$SECRETS_DIR/secret-key")"
  # Secondary identity = whatever chatapi's *default* S3 driver injects (secret seaweedfs-s3-creds),
  # so BOTH chatapi drivers + every other app authenticate regardless of which key they present.
  AK2="$(kc -n "$NS" get secret seaweedfs-s3-creds -o jsonpath='{.data.access-key}' 2>/dev/null | base64 -d || true)"
  SK2="$(kc -n "$NS" get secret seaweedfs-s3-creds -o jsonpath='{.data.secret-key}' 2>/dev/null | base64 -d || true)"
  {
    printf '{ "identities": [\n'
    printf '  { "name": "cometchat", "credentials": [ { "accessKey": "%s", "secretKey": "%s" } ], "actions": ["Admin","Read","Write","List","Tagging"] }' "$AK" "$SK"
    if [ -n "$AK2" ] && [ "$AK2" != "$AK" ]; then
      printf ',\n  { "name": "cometchat-default", "credentials": [ { "accessKey": "%s", "secretKey": "%s" } ], "actions": ["Admin","Read","Write","List","Tagging"] }' "$AK2" "$SK2"
    fi
    # anonymous read so the browser can display media via the public host (no auth on <img> GETs).
    # assets+stickers = extension assets/sticker PNGs (always public). uploads = chat media; OUR chatapi
    # emits PLAIN URLs (not presigned) so uploads must be anonymous-readable too. (Colleague keeps uploads
    # private+presigned — switching to that is a hardening option; would need a chatapi presigned config.)
    printf ',\n  { "name": "anonymous", "actions": ["Read:uploads","Read:assets","Read:stickers","Read:visual-chat-builder-app","List:uploads","List:assets","List:stickers","List:visual-chat-builder-app"] }\n] }\n'
  } > "$SECRETS_DIR/s3config.json"
  apply_secret secret generic seaweedfs-s3-config --from-file=s3config.json="$SECRETS_DIR/s3config.json"
  ok "seaweedfs-s3-config ($( [ -n "$AK2" ] && echo 'dual identity' || echo 'single identity') + anonymous read)"

  # --- cometchatFS console env (JWT + admin password hash + S3 creds) ---
  if [ ! -f "$SECRETS_DIR/jwt-secret" ]; then openssl rand -hex 32 | tr -d '\n' > "$SECRETS_DIR/jwt-secret"; fi
  if [ ! -f "$SECRETS_DIR/admin-password" ]; then openssl rand -base64 18 | tr -d '\n/+=' | cut -c1-20 > "$SECRETS_DIR/admin-password"; fi
  local JWT ADMINPW HASH
  JWT="$(cat "$SECRETS_DIR/jwt-secret")"; ADMINPW="$(cat "$SECRETS_DIR/admin-password")"
  HASH="$(node "$PKG/cometchatfs/scripts/hash-password.mjs" "$ADMINPW")"
  apply_secret secret generic cometchatfs-env \
    --from-literal=S3_ENDPOINT="http://seaweedfs-filer.${NS}.svc:8333" \
    --from-literal=S3_PUBLIC_ENDPOINT="https://${S3_HOST}" \
    --from-literal=S3_REGION="us-east-1" \
    --from-literal=S3_ACCESS_KEY="$AK" \
    --from-literal=S3_SECRET_KEY="$SK" \
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
  kc apply -f "$HERE/30-filer-s3.yaml"
  kc -n "$NS" rollout status sts/seaweedfs-volume --timeout=180s || warn "volumes not all ready yet"
  kc -n "$NS" rollout status sts/seaweedfs-filer  --timeout=180s || warn "filer not ready yet"
  kc apply -f "$HERE/40-cometchatfs.yaml"
  kc -n "$NS" rollout status deploy/cometchatfs --timeout=180s || warn "cometchatfs not ready yet"
  kc apply -f "$HERE/50-ingress.yaml"           # applied AFTER services exist
  ok "manifests applied"
}

phase_buckets() {  # ensure the app buckets exist (idempotent). Created via `weed shell`, NOT aws-cli.
  ensure_tunnel
  # uploads = chat media · assets = extension assets · stickers = default sticker PNGs (public read)
  kc -n "$NS" exec seaweedfs-filer-0 -- sh -c "printf 's3.bucket.create -name uploads\ns3.bucket.create -name assets\ns3.bucket.create -name stickers\ns3.bucket.create -name visual-chat-builder-app\ns3.bucket.list\n' | weed shell -master=$MASTER" 2>/dev/null \
    | sed 's/^/    /' || warn "bucket create reported an error (may already exist)"
  ok "buckets ensured: uploads, assets, stickers, visual-chat-builder-app"
  # ⚠️ MANUAL UPLOADS (e.g. seeding sticker PNGs) MUST disable aws-cli's default CRC32 checksum, or
  #   SeaweedFS 3.80 stores the raw aws-chunked stream and files render corrupt:
  #     export AWS_REQUEST_CHECKSUM_CALCULATION=when_required AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
  #   (or use `mc`). chatapi's own (PHP SDK) uploads are NOT affected — this is an aws-cli >=2.23 issue.
}

phase_seed_assets() {  # one-time upload of the seed assets into the public buckets (idempotent aws s3 sync)
  # Aryan's upload-seed-assets.sh equivalent. Seed dirs live in ./seed/ (committed in the repo). Bucket map
  # (seaweedfs handoff SEAWEEDFS-HANDOFF.md):
  #   seed/sampleapp/       -> assets/sampleapp/                  (sample-app demo avatars; the UIKit <img> URLs)
  #   seed/ai-agent-icons/  -> assets/ai-agents/                 (BYO-agent integration icons)
  #   seed/vcb-zips/        -> visual-chat-builder-app/downloads/ (VCB platform export zips)
  ensure_tunnel
  local SEED="$HERE/seed"
  [ -d "$SEED" ] || { warn "no seed assets at $SEED — skipping"; return 0; }
  [ -s "$SECRETS_DIR/access-key" ] || { warn "no s3 creds ($SECRETS_DIR) — run './deploy.sh secrets' first; skipping"; return 0; }
  # temp port-forward to the in-cluster S3 (no public-DNS dependency; creds from the local secret, not a cmdline)
  kc -n "$NS" port-forward svc/seaweedfs 18333:8333 >/tmp/cc-sw-seed-pf.log 2>&1 &
  local pf=$!; local i
  for i in $(seq 1 10); do (exec 3<>/dev/tcp/127.0.0.1/18333) 2>/dev/null && { exec 3>&- 3<&-; break; }; sleep 1; done
  # CRC32 MUST be disabled — aws-cli >=2.23 + SeaweedFS 3.80 otherwise store the raw aws-chunked stream -> corrupt files.
  export AWS_ACCESS_KEY_ID="$(cat "$SECRETS_DIR/access-key")" AWS_SECRET_ACCESS_KEY="$(cat "$SECRETS_DIR/secret-key")"
  export AWS_DEFAULT_REGION=us-east-1 AWS_REQUEST_CHECKSUM_CALCULATION=when_required AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
  local E="--endpoint-url http://localhost:18333 --no-progress"
  [ -d "$SEED/sampleapp" ]      && { aws s3 sync "$SEED/sampleapp/"      s3://assets/sampleapp/                  $E >/dev/null 2>&1 && ok "avatars -> assets/sampleapp/"                  || warn "avatar seed failed"; }
  [ -d "$SEED/ai-agent-icons" ] && { aws s3 sync "$SEED/ai-agent-icons/" s3://assets/ai-agents/                  $E >/dev/null 2>&1 && ok "ai-agent icons -> assets/ai-agents/"            || warn "ai-agent-icons seed failed"; }
  [ -d "$SEED/vcb-zips" ]       && { aws s3 sync "$SEED/vcb-zips/"        s3://visual-chat-builder-app/downloads/ $E >/dev/null 2>&1 && ok "vcb zips -> visual-chat-builder-app/downloads/" || warn "vcb-zips seed failed"; }
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
  kill "$pf" 2>/dev/null || true   # set -e guard: a port-forward that already exited must NOT abort the run
}

phase_cutover() {  # repoint the in-cluster name `seaweedfs` at the HA filer
  ensure_tunnel
  kc -n "$NS" rollout status sts/seaweedfs-filer --timeout=120s >/dev/null 2>&1 || warn "filer not Ready — cutover may have no endpoints yet"
  kc apply -f "$HERE/35-s3-service.yaml"          # repoints Service `seaweedfs` selector -> component=filer
  ok "Service seaweedfs -> HA filer (seaweedfs.$NS:8333). Old single-pod (if any) no longer receives traffic."
  warn "retire the old single-pod when ready:  kubectl -n $NS delete statefulset seaweedfs"
}

phase_status() {
  ensure_tunnel
  echo "── pods ──";    kc -n "$NS" get pods -o wide -l app=seaweedfs; kc -n "$NS" get pods -l app=cometchatfs
  echo "── svc ──";     kc -n "$NS" get svc seaweedfs seaweedfs-filer seaweedfs-master seaweedfs-volume cometchatfs 2>/dev/null
  echo "── endpoints of the seaweedfs alias ──"; kc -n "$NS" get endpoints seaweedfs 2>/dev/null
  [ -f "$SECRETS_DIR/admin-password" ] && echo "── console: https://$CONSOLE_HOST  (admin / $(cat "$SECRETS_DIR/admin-password")) ──"
  echo "── S3: in-cluster http://seaweedfs.$NS:8333 (path-style) · public https://$S3_HOST · media https://media-onprem.cometchat-cluster-2.in ──"
}

phase_destroy() {  # remove ONLY this stack's objects — never the shared namespace
  ensure_tunnel
  kc -n "$NS" delete -f "$HERE/50-ingress.yaml" -f "$HERE/40-cometchatfs.yaml" \
        -f "$HERE/30-filer-s3.yaml" -f "$HERE/20-volume.yaml" -f "$HERE/10-master.yaml" --ignore-not-found
  kc -n "$NS" delete pvc -l app=seaweedfs --ignore-not-found
  ok "seaweedfs/cometchatfs objects deleted from $NS (namespace + app secrets left intact)"
}

case "${1:-all}" in
  all)         phase_secrets; phase_manifests; phase_buckets; phase_seed_assets; phase_cutover; phase_status ;;
  secrets)     phase_secrets ;;
  manifests)   phase_manifests ;;
  buckets)     phase_buckets ;;
  seed-assets) phase_seed_assets ;;
  cutover)     phase_cutover ;;
  status)      phase_status ;;
  destroy)     phase_destroy ;;
  *) die "usage: $0 [all|secrets|manifests|buckets|seed-assets|cutover|status|destroy]" ;;
esac
