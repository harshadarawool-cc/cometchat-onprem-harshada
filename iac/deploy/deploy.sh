#!/usr/bin/env bash
###############################################################################
# CometChat on-prem (GCP RKE2) — one-click deployment orchestrator
#
#   Zero -> 100% rebuild. If the infra is destroyed, this brings it back with the
#   exact ordering + fixes we learned the hard way (see ../PROBLEMS-AND-FIXES.md).
#   Every step is IDEMPOTENT — safe to re-run; it converges, it does not duplicate.
#
#   USAGE
#     ./deploy.sh                 # INFRA rebuild: preflight -> terraform -> datastores
#                                 #   (+ kafka topics) -> rke2 -> data seed   [the one-click]
#     ./deploy.sh app-all         # APP phase: secrets -> support -> storage -> editors ->
#                                 #   apps -> node-apps -> coredns(split-horizon) -> ingress ->
#                                 #   certs(Let's Encrypt) -> verify (gated)
#     ./deploy.sh all             # infra + apps end-to-end — EVERYTHING, all services
#                                 #   ORDER: VMs -> datastores(+kafka topics) -> seed(ALL dumps
#                                 #   + mongo/vcb/moderation seeds) -> THEN apps -> ingress -> certs
#     ./deploy.sh <phase>         # run ONE phase (see PHASES below)
#     ./deploy.sh status          # show LB IP, nodes, datastore health
#     ./deploy.sh --help
#
#   PHASES (run individually):
#     preflight datastores-wait infra inventory datastores rke2 seed
#     secrets support storage apps node-apps coredns ingress verify status
#     storage   (consolidated HA SeaweedFS + cometchatFS console — the ONE object store,
#                ns cometchat; now part of app-all/all, between support and apps)
#
#   Requires (preflight checks these): gcloud (auth + project), terraform, ansible,
#   kubectl, jq, openssl, python3 — and for the app phase: aws (profile `staging`).
#   The caller needs IAM roles/iap.tunnelResourceAccessor (SSH + kube-API go via IAP).
###############################################################################
set -euo pipefail

# ----------------------------------------------------------------------------- customer config (THE one file to edit)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${CONF:-$HERE/customer.conf}"
if [ -f "$CONF" ]; then . "$CONF"; else echo "WARN: no $CONF — using built-in defaults" >&2; fi

# Required + defaults (customer.conf wins; exporting a var before the run also works)
PROJECT="${PROJECT:-}"
case "$PROJECT" in ""|CHANGE_ME*) echo "ERROR: set PROJECT in $CONF" >&2; exit 1 ;; esac
REGION="${REGION:-asia-south1}"
ZONE="${ZONE:-asia-south1-a}"
PREFIX="${PREFIX:-cometchat-onprem}"
NS="${NS:-cometchat}"
MASTER="${MASTER:-${PREFIX}-k8s-master-1}"
TUNNEL_PORT="${TUNNEL_PORT:-6444}"          # kube-API IAP tunnel (matches kubeconfig-6444 the py scripts use)
ECR_REGISTRY="${ECR_REGISTRY:-894996064311.dkr.ecr.us-east-2.amazonaws.com}"
ECR_REGION="${ECR_REGION:-us-east-2}"
AWS_PROFILE="${AWS_PROFILE:-staging}"
LICENCE_FILE="${LICENCE_FILE:-}"
VAULT_ENVS_DIR="${VAULT_ENVS_DIR:-}"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-}"
DOMAIN="${DOMAIN:-cometchat-cluster-2.in}"               # public-looking app domain (split-horizon + ingress)
INGRESS_INTERNAL_IP="${INGRESS_INTERNAL_IP:-10.43.200.10}" # pinned ClusterIP fronting ingress-nginx (in svc CIDR)
MGMT_DUMP_SRC="${MGMT_DUMP_SRC:-}"     # OPTIONAL pulsecustomerdb.sql (blank => skip; image self-migrates)
MONGO_DUMP_SRC="${MONGO_DUMP_SRC:-}"   # OPTIONAL mongo-dump dir   (blank => skip; apps create collections)
EDGE_ALLOWED_CIDRS="${EDGE_ALLOWED_CIDRS:-[\"0.0.0.0/0\"]}"
RKE2_SERVER_COUNT="${RKE2_SERVER_COUNT:-1}"; RKE2_SERVER_TYPE="${RKE2_SERVER_TYPE:-e2-standard-4}"
RKE2_AGENT_COUNT="${RKE2_AGENT_COUNT:-3}";   RKE2_AGENT_TYPE="${RKE2_AGENT_TYPE:-e2-standard-8}"
DISK_TYPE="${DISK_TYPE:-pd-standard}"
EXPECTED_VM_COUNT="${EXPECTED_VM_COUNT:-25}"  # 3 mongo +12 redis +3 kafka +1 mysql +1 tidb +4 rke2 +1 bastion

# ----------------------------------------------------------------------------- paths
IAC="$(cd "$HERE/.." && pwd)"
TF="$IAC/terraform"
ANS="$IAC/ansible"
SCRIPTS="$IAC/scripts"
K8S="$IAC/k8s"
SECRETS_DIR="$IAC/secrets"                   # the clean, self-documenting secrets tree (gitignored)
SEC_APPS="$SECRETS_DIR/apps"                 #   apps/<app>/ : .env (+ .env.example, config.json, pems, license.txt)
SEC_SHARED="$SECRETS_DIR/shared"            #   shared/tls  : wildcard-tls (mounted by ~everything)
SEC_INFRA="$SECRETS_DIR/infra"              #   infra/      : seaweedfs, etherpad, cluster-creds.yml, region_secret, ca
KUBECONFIG_FILE="$IAC/kubeconfig-6444"

# ----------------------------------------------------------------------------- logging
if [ -t 1 ]; then C_B='\033[1m'; C_G='\033[32m'; C_Y='\033[33m'; C_R='\033[31m'; C_C='\033[36m'; C_0='\033[0m'; else C_B=''; C_G=''; C_Y=''; C_R=''; C_C=''; C_0=''; fi
log()  { printf "%b\n" "${C_C}•${C_0} $*"; }
ok()   { printf "%b\n" "${C_G}✓${C_0} $*"; }
warn() { printf "%b\n" "${C_Y}!${C_0} $*" >&2; }
err()  { printf "%b\n" "${C_R}✗ $*${C_0}" >&2; }
die()  { err "$*"; exit 1; }
step() { printf "\n%b\n" "${C_B}══ $* ══${C_0}"; }
run()  { printf "%b\n" "${C_C}\$ $*${C_0}"; "$@"; }

# ----------------------------------------------------------------------------- helpers
need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }
port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && { exec 3>&- 3<&-; return 0; } || return 1; }

TUNNEL_PID=""
open_tunnel() {
  port_open "$TUNNEL_PORT" && { log "IAP tunnel already up on :$TUNNEL_PORT"; return 0; }
  log "opening IAP tunnel  $MASTER:6443 -> 127.0.0.1:$TUNNEL_PORT"
  gcloud compute start-iap-tunnel "$MASTER" 6443 \
    --local-host-port="127.0.0.1:$TUNNEL_PORT" --zone="$ZONE" --project="$PROJECT" \
    >/tmp/cc-iap-tunnel.log 2>&1 &
  TUNNEL_PID=$!
  local i; for i in $(seq 1 30); do port_open "$TUNNEL_PORT" && { ok "tunnel up"; return 0; }; sleep 1; done
  cat /tmp/cc-iap-tunnel.log >&2 || true
  die "IAP tunnel to $MASTER:6443 did not come up (need roles/iap.tunnelResourceAccessor?)"
}
close_tunnel() { [ -n "$TUNNEL_PID" ] && kill "$TUNNEL_PID" 2>/dev/null || true; }
trap close_tunnel EXIT

kc() { KUBECONFIG="$KUBECONFIG_FILE" kubectl "$@"; }

apply_secret() {  # apply_secret <kubectl create secret ...args...>  (idempotent via dry-run|apply)
  KUBECONFIG="$KUBECONFIG_FILE" kubectl -n "$NS" create "$@" --dry-run=client -o yaml \
    | KUBECONFIG="$KUBECONFIG_FILE" kubectl apply -f - >/dev/null
}

tf()  { ( cd "$TF"  && "$@" ); }
# apb: run an ansible-playbook. If the per-cluster fresh datastore creds exist (secrets/infra/cluster-creds.yml,
# from phase_credgen), pass them as extra-vars so ansible provisions MySQL/TiDB/Mongo with the SAME passwords the
# app secrets get synced to (sync-app-db-creds.py). Extra-vars outrank the encrypted vault -> fresh creds win.
apb() {
  local ev=""; [ -f "$SEC_INFRA/cluster-creds.yml" ] && ev="-e @$SEC_INFRA/cluster-creds.yml"
  ( cd "$ANS" && ansible-playbook $ev "$@" )       # ansible.cfg lives in $ANS
}

# =============================================================================
# PHASE: preflight  — fail fast, before we touch anything
# =============================================================================
phase_preflight() {
  step "preflight"
  for t in gcloud terraform ansible-playbook kubectl jq openssl python3; do need "$t"; done
  ok "core toolchain present"

  local acct; acct="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1)"
  [ -n "$acct" ] || die "no active gcloud auth — run: gcloud auth login"
  ok "gcloud account: $acct"

  local cur; cur="$(gcloud config get-value project 2>/dev/null)"
  if [ "$cur" != "$PROJECT" ]; then
    warn "gcloud project is '$cur', expected '$PROJECT' — using --project=$PROJECT on every call (not switching your default)"
  else ok "gcloud project: $PROJECT"; fi

  [ -f "$ANS/.vault_pass" ]            || die "missing ansible vault pass: $ANS/.vault_pass"
  [ -f "$ANS/ssh/cometchat_rke2" ]     || die "missing SSH key: $ANS/ssh/cometchat_rke2"
  chmod 600 "$ANS/ssh/cometchat_rke2" 2>/dev/null || true
  ok "ansible vault pass + SSH key present"

  # Quota guard (PROBLEMS A1/A2) — warn, don't hard-fail (quotas already raised).
  local q; q="$(gcloud compute regions describe "$REGION" --project "$PROJECT" --format=json 2>/dev/null | jq -c '.quotas[]? | select(.metric=="INSTANCES" or .metric=="SSD_TOTAL_GB" or .metric=="DISKS_TOTAL_GB")' 2>/dev/null || true)"
  if [ -n "$q" ]; then
    echo "$q" | while read -r line; do
      local m u l; m=$(echo "$line"|jq -r .metric); u=$(echo "$line"|jq -r .usage); l=$(echo "$line"|jq -r .limit)
      printf "    quota %-16s usage=%s limit=%s\n" "$m" "$u" "$l"
      if [ "$m" = "INSTANCES" ] && [ "$(printf '%.0f' "$l")" -lt $((EXPECTED_VM_COUNT+1)) ]; then
        warn "INSTANCES limit ($l) < needed (~$EXPECTED_VM_COUNT) — raise it or apply will fail mid-way (A2)"
      fi
    done
  fi
  ok "preflight passed"
}

# =============================================================================
# PHASE: infra  — terraform apply (VPC, NAT, VMs, disks, edge LB, firewall, bastion)
# =============================================================================
gen_tfvars() {
  # Single source of truth: write terraform.tfvars from customer.conf so editing
  # one file keeps Terraform in sync. (Edit terraform.tfvars directly only if you
  # bypass deploy.sh and run terraform yourself.)
  [ -n "$SSH_PUBLIC_KEY" ] || die "SSH_PUBLIC_KEY is empty in $CONF (paste ansible/ssh/cometchat_rke2.pub)"
  cat > "$TF/terraform.tfvars" <<EOF
# AUTO-GENERATED from deploy/customer.conf by deploy.sh — edit customer.conf, not this file.
project_id  = "$PROJECT"
region      = "$REGION"
zone        = "$ZONE"
name_prefix = "$PREFIX"
vpc_name    = "${PREFIX}-vpc"
ssh_public_key     = "$SSH_PUBLIC_KEY"
disk_type          = "$DISK_TYPE"
edge_allowed_cidrs = $EDGE_ALLOWED_CIDRS
rke2_server = { count = $RKE2_SERVER_COUNT, machine_type = "$RKE2_SERVER_TYPE" }
rke2_agent  = { count = $RKE2_AGENT_COUNT, machine_type = "$RKE2_AGENT_TYPE" }
subnet_data_cidr    = "$SUBNET_DATA_CIDR"
subnet_cluster_cidr = "$SUBNET_CLUSTER_CIDR"
subnet_edge_cidr    = "$SUBNET_EDGE_CIDR"
mongo = { count = $MONGO_COUNT, machine_type = "$MONGO_TYPE", data_disk_gb = $MONGO_DISK }
redis = { count = $REDIS_COUNT, machine_type = "$REDIS_TYPE" }
kafka = { count = $KAFKA_COUNT, machine_type = "$KAFKA_TYPE", data_disk_gb = $KAFKA_DISK }
tidb  = { count = $TIDB_COUNT, machine_type = "$TIDB_TYPE", data_disk_gb = $TIDB_DISK }
mysql = { count = $MYSQL_COUNT, machine_type = "$MYSQL_TYPE", data_disk_gb = $MYSQL_DISK }
EOF
  ok "generated $TF/terraform.tfvars from $CONF"
}

phase_infra() {
  step "infra — terraform apply"
  gen_tfvars
  tf terraform init -input=false >/dev/null
  log "planning..."
  tf terraform plan -input=false -out=/tmp/cc.tfplan
  log "applying (pd-standard disks — A1; NAT for egress — B1)..."
  tf terraform apply -input=false -auto-approve /tmp/cc.tfplan
  ok "terraform apply complete"
}

# =============================================================================
# PHASE: inventory  — propagate the DYNAMIC edge LB IP (PROBLEMS B3) into group_vars
# =============================================================================
phase_inventory() {
  step "inventory — propagate edge LB IP"
  local ip; ip="$(tf terraform output -raw edge_lb_ip 2>/dev/null || true)"
  [ -n "$ip" ] || { warn "edge_lb_ip output empty (infra not applied yet?) — skipping"; return 0; }
  ok "edge LB IP = $ip"
  # rewrite group_vars (used by RKE2 tls-san) — never hardcode this again (B3)
  local gv="$ANS/group_vars/all/main.yml"
  if grep -q '^edge_lb_ip:' "$gv"; then
    sed -i.bak -E "s|^edge_lb_ip:.*|edge_lb_ip: \"$ip\"|" "$gv" && rm -f "$gv.bak"
    ok "updated edge_lb_ip in group_vars/all/main.yml"
  fi
  printf '%s\n' "$ip" > "$IAC/.edge_lb_ip"
}

# wait until the datastore VMs answer SSH over IAP (post-boot, B1)
phase_datastores_wait() {
  step "waiting for VMs to accept SSH over IAP"
  local i
  for i in $(seq 1 40); do
    if ( cd "$ANS" && ansible datastores -m ping -o ) >/tmp/cc-ping.log 2>&1; then
      ok "all datastore VMs reachable"; return 0
    fi
    log "not all reachable yet ($i/40)…"; sleep 15
  done
  cat /tmp/cc-ping.log >&2 || true
  die "datastore VMs never became reachable over IAP"
}

# =============================================================================
# PHASE: credgen  — generate FRESH, per-cluster datastore credentials (runs BEFORE datastores).
#   One source of truth (secrets/infra/cluster-creds.yml, gitignored): ansible (apb -e) provisions the DBs
#   with these, and sync-app-db-creds.py (phase_secrets) stamps the SAME values into the app secrets — so a
#   fresh cluster gets brand-new, self-consistent creds (the leaked ones die). Idempotent: reuses the file if
#   present (regenerating would desync already-provisioned DBs). Delete the file to force a rotation.
# =============================================================================
phase_credgen() {
  step "credgen — fresh per-cluster datastore credentials"
  run bash "$SCRIPTS/gen-cluster-creds.sh"
  local f="$SEC_INFRA/cluster-creds.yml"
  [ -f "$f" ] || die "credgen failed: $f not created"
  # every datastore cred must be present + non-empty (else ansible would provision a placeholder pw)
  local n; n="$(grep -cE '_password: *"[a-zA-Z0-9]{8,}"' "$f" 2>/dev/null || echo 0)"
  [ "$n" -ge 6 ] || die "credgen: expected 6 datastore creds in $f, found $n — refusing to continue"
  ok "fresh datastore creds ready ($n) — ansible + app secrets will both use secrets/infra/cluster-creds.yml"
}

# =============================================================================
# PHASE: datastores  — Mongo rs0 / 4 Redis Sentinel clusters / Kafka(+TOPICS) / TiDB / MySQL
# =============================================================================
phase_datastores() {
  step "datastores — ansible (mongo, redis, kafka+topics, tidb, mysql)"
  log "kafka topics are created the moment the broker quorum is up (PROBLEMS E1)"
  apb datastores.yml
  ok "datastores configured"
  log "health check…"
  apb verify-datastores.yml || warn "verify reported issues — inspect output above"
}

# =============================================================================
# PHASE: rke2  — control plane + agents; fetch + regenerate kubeconfigs (B4)
# =============================================================================
phase_rke2() {
  step "rke2 — control plane + agents"
  apb rke2.yml
  ok "RKE2 up; kubeconfig fetched to ansible/kubeconfig"
  # Regenerate the localhost kubeconfigs from the FRESH cluster CA (B4) — avoids stale certs after a rebuild.
  local src="$ANS/kubeconfig"
  [ -f "$src" ] || { warn "ansible/kubeconfig not found — skip kubeconfig regen"; return 0; }
  sed -E "s|server: https://[^ ]+|server: https://127.0.0.1:$TUNNEL_PORT|" "$src" > "$IAC/kubeconfig-6444"
  sed -E "s|server: https://[^ ]+|server: https://127.0.0.1:6443|"          "$src" > "$IAC/kubeconfig-local"
  ok "regenerated kubeconfig-6444 (:$TUNNEL_PORT) and kubeconfig-local (:6443)"
}

# =============================================================================
# PHASE: seed  — restore DB dumps + provision the Mongo app users the envs expect (C4)
# =============================================================================
phase_seed() {
  step "seed — restore dumps (optional) + mongo app users"
  # Dump paths are OPTIONAL overrides; blank => the playbooks use their built-in defaults and
  # skip any dump that isn't present. The mgmt (pulsecustomerdb) + mongo dumps are pre-seeded
  # DATA only — mgmtapi/chatapi create their own TABLES via `php artisan migrate` on boot.
  local ev_mysql="" ev_mongo=""
  [ -n "${MGMT_DUMP_SRC:-}" ]  && ev_mysql="-e mgmt_dump_src=$MGMT_DUMP_SRC"
  [ -n "${MONGO_DUMP_SRC:-}" ] && ev_mongo="-e mongo_dump_src=$MONGO_DUMP_SRC"
  # shellcheck disable=SC2086  # intentional word-split: $ev_* is empty or "-e key=val"
  # 1) MySQL dumps: pulsecustomerdb + onprem-features overlay + metrics + analytics (in-repo dumps/).
  apb restore-mysql-dumps.yml $ev_mysql || warn "mysql restore: inspect output (restore-mysql-dumps.yml)"
  # shellcheck disable=SC2086
  # 2) Mongo mongodump restore (optional external dump; skips if absent).
  apb restore-mongo.yml        $ev_mongo || warn "mongo restore: inspect output (restore-mongo.yml)"
  # 3) Mongo in-repo JSON seeds: events.triggers, notifications push-settings, vcb.templates,
  #    moderation configs/rules/profanity (idempotent, guarded on countDocuments, skip-if-absent).
  apb restore-mongo-seeds.yml || warn "mongo seeds: inspect output (restore-mongo-seeds.yml)"
  apb fix-mongo-app-users.yml
  ok "seed complete (mysql dumps + onprem-features + mongo seeds + admin/extadmin/webhookuser)"
  log "DB schemas: mgmtapi + chatapi create their own tables via 'php artisan migrate' on boot"
  log "  (this IS the akamai 'create tables in TiDB' automation) — the dumps above are optional data."
}

# =============================================================================
# PHASE: secrets  — namespace + the secrets the manifests mount (deterministic) + app env secrets
# =============================================================================
phase_secrets() {
  step "secrets — namespace + infra secrets + app env secrets"
  open_tunnel
  KUBECONFIG="$KUBECONFIG_FILE" kubectl get ns "$NS" >/dev/null 2>&1 \
    || kc create namespace "$NS"
  kc label ns "$NS" pod-security.kubernetes.io/enforce=privileged --overwrite >/dev/null 2>&1 || true
  ok "namespace $NS ready"

  mkdir -p "$SEC_APPS/chatapi" "$SEC_SHARED/tls" "$SEC_INFRA/seaweedfs"

  # --- ECR pull secrets: BOTH names (PROBLEMS I1) ---
  if command -v aws >/dev/null 2>&1; then
    local token; token="$(aws ecr get-login-password --region "$ECR_REGION" --profile "$AWS_PROFILE" 2>/dev/null || true)"
    if [ -n "$token" ]; then
      local n; for n in ecr-pull ecr-pull-secret; do
        apply_secret secret docker-registry "$n" --docker-server="$ECR_REGISTRY" --docker-username=AWS --docker-password="$token"
      done
      ok "ECR pull secrets: ecr-pull + ecr-pull-secret"
    else warn "could not get ECR token (aws profile '$AWS_PROFILE') — pods will ImagePullBackOff until secrets exist"; fi
  else warn "aws CLI missing — skipping ECR pull secrets"; fi

  # --- license: prefer the per-app copy (secrets/apps/chatapi/license.txt), else the external LICENCE_FILE ---
  local licfile="$SEC_APPS/chatapi/license.txt"; [ -f "$licfile" ] || licfile="${LICENCE_FILE:-}"
  if [ -n "$licfile" ] && [ -f "$licfile" ]; then
    apply_secret secret generic cc-license --from-file=license.txt="$licfile"
    ok "cc-license (license.txt <- ${licfile#$IAC/})"
  else warn "licence not found (secrets/apps/chatapi/license.txt or \$LICENCE_FILE) — chatapi/mgmtapi will fail license verify"; fi

  # --- JWT RSA keypair: generate ONCE (canonical: apps/chatapi), then MIRROR into every app that mounts it ---
  mkdir -p "$SEC_APPS/chatapi"
  if [ ! -f "$SEC_APPS/chatapi/private.pem" ]; then
    openssl genrsa -out "$SEC_APPS/chatapi/private.pem" 2048 >/dev/null 2>&1
    openssl rsa -in "$SEC_APPS/chatapi/private.pem" -pubout -out "$SEC_APPS/chatapi/public.pem" >/dev/null 2>&1
    log "generated new JWT keypair (canonical: secrets/apps/chatapi)"
  fi
  # mirror the keypair (+ public key) into the apps that mount jwt-keys / jwt-public — keeps each app folder
  # self-documenting; all resolve to the SAME k8s secret (created below from the chatapi canonical copy).
  mkdir -p "$SEC_APPS/mgmtapi"
  cp -f "$SEC_APPS/chatapi/private.pem" "$SEC_APPS/mgmtapi/private.pem"
  cp -f "$SEC_APPS/chatapi/public.pem"  "$SEC_APPS/mgmtapi/public.pem"
  for a in websocket moderationservice visual-chat-builder analytics metrics-pro extensions; do
    [ -d "$SEC_APPS/$a" ] && cp -f "$SEC_APPS/chatapi/public.pem" "$SEC_APPS/$a/jwtrsakey.pem"
  done
  apply_secret secret generic jwt-keys  --from-file=private.pem="$SEC_APPS/chatapi/private.pem" --from-file=public.pem="$SEC_APPS/chatapi/public.pem"
  apply_secret secret generic jwt-public --from-file=jwtrsakey.pem="$SEC_APPS/chatapi/public.pem"
  ok "jwt-keys (sign: chatapi/mgmtapi) + jwt-public (verify: websocket/analytics)"

  # --- wildcard TLS for the ingress (self-signed *.cometchat-cluster-2.in) ---
  if [ ! -f "$SEC_SHARED/tls/tls.crt" ]; then
    openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
      -keyout "$SEC_SHARED/tls/tls.key" -out "$SEC_SHARED/tls/tls.crt" \
      -subj "/CN=*.cometchat-cluster-2.in" \
      -addext "subjectAltName=DNS:*.cometchat-cluster-2.in,DNS:*.api-us.cometchat-cluster-2.in,DNS:*.websocket-us.cometchat-cluster-2.in" >/dev/null 2>&1
    log "generated self-signed wildcard TLS (persisted under secrets/shared/tls)"
  fi
  apply_secret secret tls wildcard-tls --cert="$SEC_SHARED/tls/tls.crt" --key="$SEC_SHARED/tls/tls.key"
  ok "wildcard-tls"

  # --- SeaweedFS S3 (create only if absent; don't clobber tuned creds) ---
  if ! KUBECONFIG="$KUBECONFIG_FILE" kubectl -n "$NS" get secret seaweedfs-s3-creds >/dev/null 2>&1; then
    local ak sk
    ak="cometchat$(openssl rand -hex 6)"; sk="$(openssl rand -hex 20)"
    printf '%s' "$ak" > "$SEC_INFRA/seaweedfs/access-key"
    printf '%s' "$sk" > "$SEC_INFRA/seaweedfs/secret-key"
    cat > "$SEC_INFRA/seaweedfs/s3.json" <<JSON
{ "identities": [ { "name": "cometchat",
  "credentials": [ { "accessKey": "$ak", "secretKey": "$sk" } ],
  "actions": ["Admin","Read","Write","List","Tagging"] } ] }
JSON
    apply_secret secret generic seaweedfs-s3       --from-file=s3.json="$SEC_INFRA/seaweedfs/s3.json"
    apply_secret secret generic seaweedfs-s3-creds --from-file=access-key="$SEC_INFRA/seaweedfs/access-key" --from-file=secret-key="$SEC_INFRA/seaweedfs/secret-key"
    ok "seaweedfs-s3 + seaweedfs-s3-creds (access-key/secret-key match the s3.json identity)"
  else ok "seaweedfs secrets already exist — left as-is"; fi

  # --- per-service secrets: authoritative source is secrets/apps/<app>/ (one folder per app) ---
  # 1) sync-app-db-creds.py stamps the freshly-generated datastore passwords (secrets/infra/cluster-creds.yml)
  #    into each app's .env/config.json FIRST, so apps authenticate with EXACTLY what ansible provisioned.
  # 2) secrets-from-rendered.py then creates every <svc>-env (+ *-config / calls-relay-envfile) k8s secret in
  #    the exact shape each app consumes.
  if [ -d "$SEC_APPS" ] && ls "$SEC_APPS"/*/.env >/dev/null 2>&1; then
    if [ -f "$SEC_INFRA/cluster-creds.yml" ]; then
      log "sync-app-db-creds.py (fresh datastore creds → app secrets)…"
      run python3 "$SCRIPTS/sync-app-db-creds.py" || die "cred sync FAILED — app secrets would not match the datastores; aborting"
    else warn "no secrets/infra/cluster-creds.yml — app secrets use their baked-in datastore creds (run ./deploy.sh credgen to rotate)"; fi
    log "secrets-from-rendered.py (secrets/apps/<app> → live secrets, correct shapes)…"
    run python3 "$SCRIPTS/secrets-from-rendered.py" --apply
    ok "per-service secrets created from secrets/apps/"
  else
    warn "no secrets/apps/<app>/.env baseline — cannot create app secrets."
    warn "  restore secrets/apps/ (per-app .env), then re-run: ./deploy.sh secrets"
  fi
}

# =============================================================================
# PHASE: support  — opensearch / ollama / mailpit / seaweedfs + ES8 proxy (+ repoint, I3)
# =============================================================================
phase_support() {
  step "support services + opensearch ES8 proxy"
  open_tunnel
  kc apply -f "$K8S/support-services.yaml"   # mailpit/opensearch/ollama (SeaweedFS is now its own phase)
  log "waiting for opensearch…"
  kc -n "$NS" rollout status deploy/opensearch --timeout=180s || warn "opensearch not ready yet"
  kc apply -f "$K8S/opensearch-es8proxy.yaml"
  # Repoint the 'opensearch' Service at the ES8 proxy pods (I3).
  kc -n "$NS" patch service opensearch --type merge \
    -p '{"spec":{"selector":{"app":"opensearch-es8proxy"}}}' >/dev/null 2>&1 \
    && ok "repointed opensearch Service -> ES8 proxy" || warn "could not repoint opensearch Service (patch manually per opensearch-es8proxy.yaml header)"
  # ES indexes (Aryan's es-indexes.sh equivalent): create app/search/reaction/prefix-search-index from the
  # service-search image schemas (extracted to k8s/es-schemas/*.json). service-search does NOT auto-create
  # them — without this, search queries hit index_not_found and return nothing. Idempotent (skips existing).
  kc -n "$NS" create configmap es-schemas --from-file="$K8S/es-schemas/" --dry-run=client -o yaml | kc apply -f - >/dev/null 2>&1 \
    && ok "es-schemas ConfigMap applied" || warn "es-schemas ConfigMap failed"
  kc -n "$NS" delete job es-indexes --ignore-not-found >/dev/null 2>&1
  kc apply -f "$K8S/es-indexes.job.yaml" >/dev/null
  kc -n "$NS" wait --for=condition=complete job/es-indexes --timeout=120s >/dev/null 2>&1 \
    && ok "ES indexes created (app/search/reaction/prefix-search-index)" || warn "es-indexes not complete (kc -n $NS logs job/es-indexes)"
}

# =============================================================================
# PHASE: editors  — Etherpad DB prep + secrets for document-embed/whiteboard (the
#   k8s/apps/doc-whiteboard.yaml Deployments are applied by phase_apps). Runs BEFORE apps
#   so the etherpad DB + the settings secret exist before Etherpad starts.
# =============================================================================
phase_editors() {
  step "editors — etherpad DB + secrets (document-embed/whiteboard manifests apply in 'apps')"
  open_tunnel
  mkdir -p "$SEC_INFRA/etherpad"
  [ -f "$SEC_INFRA/etherpad/db-password" ] || openssl rand -hex 16 | tr -d '\n' > "$SEC_INFRA/etherpad/db-password"
  apply_secret secret generic etherpad-db --from-file=password="$SEC_INFRA/etherpad/db-password"
  # render Etherpad settings.json (dbType mysql -> mgmt MySQL) from the persisted password
  python3 - "$SEC_INFRA/etherpad/db-password" "$SEC_INFRA/etherpad/settings.json" <<'PY'
import json,sys
pw=open(sys.argv[1]).read().strip()
json.dump({"title":"CometChat Document","favicon":"favicon.ico","skinName":"colibris",
  "ip":"0.0.0.0","port":9001,"dbType":"mysql",
  "dbSettings":{"user":"etherpaduser","host":"10.23.10.41","port":3306,"password":pw,
                "database":"etherpad","charset":"utf8mb4"},
  "defaultPadText":"","requireSession":False,"requireAuthentication":False,
  "requireAuthorization":False,"trustProxy":True,"editOnly":False,
  "socketTransportProtocols":["websocket","polling"],"loglevel":"INFO"},
  open(sys.argv[2],"w"),indent=2)
PY
  apply_secret secret generic document-embed-settings --from-file=settings.json="$SEC_INFRA/etherpad/settings.json"
  # create the etherpad DB + user (mysql_native_password) + force store-table utf8mb4 (one-shot Job)
  kc -n "$NS" delete job etherpad-db-init --ignore-not-found >/dev/null 2>&1
  kc apply -f "$K8S/etherpad-db-init.job.yaml" >/dev/null
  kc -n "$NS" wait --for=condition=complete job/etherpad-db-init --timeout=120s >/dev/null 2>&1 \
    && ok "etherpad DB + user ready (utf8mb4)" || warn "etherpad-db-init not complete (check: kc -n $NS logs job/etherpad-db-init)"
}

# =============================================================================
# PHASE: apps  — chatapi/mgmtapi (PHP+nginx) + the curated Node/worker manifests
# =============================================================================
phase_apps() {
  step "apps — chatapi/mgmtapi + curated node apps"
  open_tunnel
  # link-preview consumer patch (after_message) — the extensions deploy mounts this ConfigMap over the
  # image's buggy controller. Must exist BEFORE the extensions pod starts.
  [ -f "$K8S/patches/LinkPreviewController.js" ] && \
    kc -n "$NS" create configmap linkpreview-patch --from-file=LinkPreviewController.js="$K8S/patches/LinkPreviewController.js" \
      --dry-run=client -o yaml | kc apply -f - >/dev/null 2>&1 && ok "linkpreview-patch configmap"
  kc apply -f "$K8S/chatapi.yaml" -f "$K8S/mgmtapi.yaml"
  local f
  for f in "$K8S"/apps/*.yaml; do kc apply -f "$f"; done
  ok "applied chatapi, mgmtapi, and k8s/apps/* (digest-pinned, ecr-pull-secret)"
  # De-stage the mgmt-image-seeded extension URLs (cometchat-staging.com -> cometchat-cluster-2.in).
  # The mgmt onprem_setup migration bakes the staging domain into pulsecustomerdb.microservices + per-app
  # cod_* DBs; this idempotent REPLACE corrects them so the dashboard/SDK reach our on-prem extensions.
  kc -n "$NS" delete job ext-url-destage --ignore-not-found >/dev/null 2>&1
  kc apply -f "$K8S/ext-url-destage.job.yaml" >/dev/null 2>&1
  kc -n "$NS" wait --for=condition=complete job/ext-url-destage --timeout=120s >/dev/null 2>&1 \
    && ok "extension URLs de-staged (staging -> cometchat-cluster-2.in)" || warn "ext-url-destage not complete (kc -n $NS logs job/ext-url-destage)"
  log "node-only services (websocket, moderationservice, visual-chat-builder, ai-agent-service,"
  log "  receipt-updater, notifications-delay-worker, dashboard) deploy next in the 'node-apps' phase."
}

# =============================================================================
# PHASE: node-apps  — the node-only services that have NO curated k8s/apps manifest.
#   deploy-node-apps.py was trimmed to ONLY these (audit 2026-06-24): it no longer
#   re-deploys notificationscore/globalwebhooks/service-search/analytics/metrics-pro/
#   extensions/sql-consumer (those are owned by the `apps` phase). Safe to run after apps.
# =============================================================================
phase_node_apps() {
  step "node-apps — websocket / moderationservice / visual-chat-builder / ai-agent-service / workers / dashboard"
  open_tunnel
  run env KUBECONFIG="$KUBECONFIG_FILE" NS="$NS" python3 "$SCRIPTS/deploy-node-apps.py"
  # Dashboard (SINGLE SOURCE OF TRUTH): dashboard-nginx (nginx cm) + dashboard.yaml (build-copy + the
  # dashboard-config config.json overlay that points REACT_APP_CUSTOMER_DOMAIN at apimgmt.$DOMAIN). Without
  # this config.json overlay the SPA falls back to its baked-in cometchat-staging.com default -> CORS.
  # deploy-node-apps.py intentionally does NOT render the dashboard (its template lacked the overlay).
  kc apply -f "$K8S/dashboard-nginx.yaml" -f "$K8S/dashboard.yaml" >/dev/null 2>&1 \
    && ok "dashboard applied (config.json overlay -> apimgmt.$DOMAIN; no staging fallback)" \
    || warn "dashboard apply failed (check dashboard.yaml + dashboard-nginx.yaml)"
  kc -n "$NS" rollout status deploy/dashboard --timeout=120s >/dev/null 2>&1 || warn "dashboard not ready yet"
  # complete the default push-settings (poll/reminder/mention templates the auto-created doc omits).
  # Self-waits for notificationscore to create the base doc; idempotent.
  kc -n "$NS" delete job notifications-push-settings-seed --ignore-not-found >/dev/null 2>&1
  kc apply -f "$K8S/notifications-push-settings-seed.job.yaml" >/dev/null 2>&1
  kc -n "$NS" wait --for=condition=complete job/notifications-push-settings-seed --timeout=180s >/dev/null 2>&1 \
    && ok "push-settings templates seeded" || warn "push-settings seed not complete (kc -n $NS logs job/notifications-push-settings-seed)"
}

# =============================================================================
# PHASE: coredns  — split-horizon so *.<DOMAIN> resolves IN-CLUSTER (data residency +
#   lets mgmtapi reach chatapi for app provisioning instead of leaking to public staging).
#   Reconcile-safe (coredns-custom ConfigMap). See k8s/coredns-split-horizon.yaml.
# =============================================================================
phase_coredns() {
  step "coredns split-horizon (POD-TLS) — on-prem FQDNs -> in-cluster Service :443, catch-all -> ingress ($INGRESS_INTERNAL_IP)"
  open_tunnel
  local dom_re="${DOMAIN//./\\.}"                  # escape dots for the CoreDNS regex
  # 1) catch-all backing Service: rke2 ingress-nginx is a hostNetwork DaemonSet with NO ClusterIP, so the
  #    pinned INGRESS_INTERNAL_IP the catch-all points at is a blackhole without this. Gives it the ingress
  #    pods as endpoints so un-rewritten *.$DOMAIN storage hosts (media/data/files-onprem) route in-cluster.
  kc apply -f "$K8S/ingress-internal-svc.yaml" >/dev/null 2>&1 \
    && ok "ingress-internal Service ($INGRESS_INTERNAL_IP) backs the catch-all (media/data/files-onprem in-cluster)" \
    || warn "ingress-internal-svc apply failed — media/stickers may 000"
  # 2) POD-TLS split-horizon HCC: build the per-FQDN `rewrite stop` block from the SERVICE_MAP (single source
  #    of truth), inject it into the HCC template, apply. Each on-prem FQDN -> its Service (nginx sidecar
  #    terminates wildcard-tls on :443). Durable: the helm-controller re-renders the Corefile from this HCC.
  DOMAIN="$DOMAIN" DOMAIN_RE="$dom_re" INGRESS_IP="$INGRESS_INTERNAL_IP" NS="$NS" HCC="$K8S/coredns-splithorizon-hcc.yaml" \
    python3 - > /tmp/cc-coredns-hcc.yaml <<'PY'
import os
d=os.environ['DOMAIN']; dre=os.environ['DOMAIN_RE']; ip=os.environ['INGRESS_IP']; ns=os.environ['NS']
# region-prefixed hosts (us.<host>.<domain>) need the regex variant too (answer auto preserves the {appId}/region label)
WILDCARD={"api-onprem","apiclient-onprem","websocket-onprem"}
# SINGLE SOURCE OF TRUTH: on-prem subdomain label -> in-cluster Service name (ns = $NS). Add a row to expose a host.
SERVICE_MAP=[
  ("api-onprem","chatapi"),("apiclient-onprem","chatapi"),("websocket-onprem","websocket"),("ws-onprem","websocket"),
  ("rule-onprem","moderationservice"),("webhooks-onprem","globalwebhooks"),("notifications-onprem","notificationscore"),
  ("metrics-onprem","analytics"),("metrics-pro-onprem","metrics-pro"),("internal-search-onprem","service-search"),
  ("internal-vcb-onprem","visual-chat-builder"),("internal-apivcb-onprem","visual-chat-builder"),
  ("extensions-onprem","extensions"),("stickers-onprem","extensions"),("thumbnail-generator-onprem","extensions"),
  ("link-preview-onprem","extensions"),("polls-onprem","extensions"),("document-onprem","extensions"),
  ("whiteboard-onprem","extensions"),("document-embed-onprem","document-embed"),("whiteboard-embed-onprem","whiteboard"),
  ("apimgmt","mgmtapi"),("app","dashboard"),("test.antivirus","clamav"),
]
IND="          "  # 10 spaces: the plugin list-item indent inside servers[0].plugins
L=[]
for label,svc in SERVICE_MAP:
    tgt=f"{svc}.{ns}.svc.cluster.local"; lre=label.replace('.','\\.')
    if label in WILDCARD:
        L+=[f"{IND}- name: rewrite", f"{IND}  parameters: stop", f"{IND}  configBlock: |-",
            f"{IND}    name regex (.*)\\.{lre}\\.{dre} {tgt}", f"{IND}    answer auto"]
    L.append(f"{IND}- name: rewrite")
    L.append(f"{IND}  parameters: stop name exact {label}.{d} {tgt}")
# SaaS data-plane fallbacks the SDK/dashboard may hardcode -> keep IN-CLUSTER (defense-in-depth data residency)
for h in ["api.cometchat.com","apiclient-onprem.cometchat.com"]:
    L+=[f"{IND}- name: rewrite", f"{IND}  parameters: stop name exact {h} chatapi.{ns}.svc.cluster.local"]
block="\n".join(L)
tpl=open(os.environ['HCC']).read()
out=tpl.replace(f"{IND}# __REWRITES__", block).replace("__DOMAIN_RE__",dre).replace("__INGRESS_IP__",ip)
import sys; sys.stdout.write(out)
PY
  if ! grep -q 'rewrite stop name exact api-onprem' /tmp/cc-coredns-hcc.yaml 2>/dev/null; then
    warn "coredns HCC render produced no rewrites — aborting coredns (check SERVICE_MAP / template)"; return 1
  fi
  kc apply -f /tmp/cc-coredns-hcc.yaml >/dev/null \
    && ok "applied POD-TLS split-horizon HCC (per-FQDN rewrites -> Service:443, catch-all -> $INGRESS_INTERNAL_IP)" \
    || { warn "coredns HCC apply failed"; return 1; }
  # 3) helm-controller re-renders the Corefile from the HCC (~30-90s); wait for it to carry a rewrite.
  local i ok_rw=""
  for i in $(seq 1 30); do
    kc -n kube-system get cm rke2-coredns-rke2-coredns -o jsonpath='{.data.Corefile}' 2>/dev/null \
      | grep -q "rewrite stop name exact api-onprem.$DOMAIN" && { ok_rw=1; break; }; sleep 5
  done
  [ -n "$ok_rw" ] && ok "Corefile carries the pod-TLS rewrites" \
    || warn "Corefile did NOT pick up rewrites (helm-controller slow? verify: kc -n kube-system get cm rke2-coredns-rke2-coredns -o jsonpath='{.data.Corefile}')"
  # 4) confirm CoreDNS is healthy after the reload (a bad Corefile CrashLoops it -> DNS outage; check + warn loudly).
  kc -n kube-system rollout status deploy/rke2-coredns --timeout=120s >/dev/null 2>&1 \
    && ok "CoreDNS healthy after pod-TLS split-horizon reload" \
    || err "CoreDNS NOT healthy after reload — check 'kc -n kube-system get pods -l k8s-app=kube-dns' and logs; roll back the HCC if CrashLooping"
}

# =============================================================================
# PHASE: storage-ha (OPTIONAL) — parallel HA SeaweedFS + cometchatFS console
#   Standalone stack in ns `cometchat-storage` (3 masters + 3 volumes + filer/S3 + web
#   console), separate from the single-pod `seaweedfs` the apps currently use. NOT in
#   app-all — run on demand. Cutover steps: k8s/seaweedfs-ha/README.md.
# =============================================================================
phase_storage() {
  step "storage — consolidated HA SeaweedFS + cometchatFS console (the ONE object store, ns cometchat)"
  open_tunnel
  # secrets + masters + volumes + filer + console + uploads/assets buckets + `seaweedfs` Service cutover
  KUBECONFIG="$KUBECONFIG_FILE" AWS_PROFILE="$AWS_PROFILE" "$K8S/seaweedfs/deploy.sh" all
  # seed the 202 default sticker PNGs into the stickers bucket (from the extensions image; idempotent).
  # Without this a fresh rebuild leaves the bucket empty and the chat sticker picker shows broken images.
  kc -n "$NS" delete job sticker-seed --ignore-not-found >/dev/null 2>&1
  kc apply -f "$K8S/sticker-seed.job.yaml" >/dev/null 2>&1
  kc -n "$NS" wait --for=condition=complete job/sticker-seed --timeout=180s >/dev/null 2>&1 \
    && ok "default stickers seeded" || warn "sticker-seed not complete (kc -n $NS logs job/sticker-seed)"
}
phase_storage_ha() { phase_storage; }   # back-compat alias for the old phase name

# =============================================================================
# PHASE: ingress  — edge ingress (front with the LB IP from terraform output, B3)
# =============================================================================
phase_ingress() {
  step "ingress"
  open_tunnel
  kc apply -f "$K8S/ingress.yaml"
  # sample-app avatar host: assets.$DOMAIN -> seaweedfs (own Ingress; per-resource rewrite /(.*) -> /assets/$1)
  [ -f "$K8S/assets-ingress.yaml" ] && kc apply -f "$K8S/assets-ingress.yaml" >/dev/null 2>&1 && ok "assets ingress applied (assets.$DOMAIN)"
  local ip; ip="$(cat "$IAC/.edge_lb_ip" 2>/dev/null || tf terraform output -raw edge_lb_ip 2>/dev/null || echo '?')"
  ok "ingress applied — point public DNS for *.$DOMAIN at the edge LB: $ip"
}

# =============================================================================
# PHASE: certs  — cert-manager + Let's Encrypt (Route53 DNS-01) wildcard cert -> wildcard-tls.
#   The ingress (phase_ingress) references secret `wildcard-tls`; cert-manager issues a real, trusted
#   LE cert into it (browsers see a valid padlock; the same cert is system-trusted so apps need zero
#   custom-CA envs). DNS-01 works for internal hosts too (no public A record needed). Needs the AWS
#   `staging` profile (Route53) + outbound to Let's Encrypt/quay. Idempotent.
# =============================================================================
phase_certs() {
  step "certs — cert-manager + Let's Encrypt (Route53 DNS-01) wildcard -> wildcard-tls"
  open_tunnel
  local CM_VER="v1.20.2"
  # 1) install cert-manager (cluster-wide CRDs + webhooks; idempotent)
  kc apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CM_VER}/cert-manager.yaml" >/dev/null 2>&1 \
    && ok "cert-manager ${CM_VER} applied" || warn "cert-manager apply failed (check outbound to github/quay)"
  kc -n cert-manager rollout status deploy/cert-manager-webhook --timeout=180s >/dev/null 2>&1 || warn "cert-manager-webhook not ready yet"
  # 2) Route53 creds secret for the DNS-01 solver (AWS secret key from the profile; piped, never echoed/filed)
  if command -v aws >/dev/null 2>&1 && [ -n "$(aws configure get aws_secret_access_key --profile "$AWS_PROFILE" 2>/dev/null || true)" ]; then
    aws configure get aws_secret_access_key --profile "$AWS_PROFILE" | tr -d '\n' \
      | kc -n cert-manager create secret generic route53-credentials --from-file=secret-access-key=/dev/stdin --dry-run=client -o yaml | kc apply -f - >/dev/null \
      && ok "route53-credentials secret created" || warn "route53-credentials secret failed"
  else warn "no aws_secret_access_key (profile $AWS_PROFILE) — cert-manager Route53 DNS-01 will fail"; fi
  # 3) DNS-01 self-check must use PUBLIC resolvers (our split-horizon CoreDNS intercepts $DOMAIN)
  kc -n cert-manager patch deploy cert-manager --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--dns01-recursive-nameservers-only"},{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--dns01-recursive-nameservers=8.8.8.8:53,1.1.1.1:53"}]' >/dev/null 2>&1
  kc -n cert-manager rollout status deploy/cert-manager --timeout=120s >/dev/null 2>&1 || true
  # 4) ClusterIssuer (letsencrypt-route53) + ONE domain-wide wildcard Certificate -> wildcard-tls.
  #    cert-manager-issuer.yaml ships the ClusterIssuer + a per-host Certificate; we drop that per-host
  #    Certificate and use the domain-wide wildcard-cert-full.yaml so only ONE Certificate owns wildcard-tls.
  # render the AWS access key ID into the issuer (kept OUT of git; secret key stays in route53-credentials)
  local akid; akid="$(aws configure get aws_access_key_id --profile "$AWS_PROFILE" 2>/dev/null || true)"
  if [ -n "$akid" ]; then
    sed "s|__AWS_ACCESS_KEY_ID__|$akid|g" "$K8S/cert-manager-issuer.yaml" | kc apply -f - >/dev/null 2>&1
  else
    warn "no aws_access_key_id (profile $AWS_PROFILE) — cert-manager Route53 issuer will fail; set the profile then re-run: ./deploy.sh certs"
    kc apply -f "$K8S/cert-manager-issuer.yaml" >/dev/null 2>&1
  fi
  kc -n "$NS" delete certificate cometchat-wildcard --ignore-not-found >/dev/null 2>&1
  kc apply -f "$K8S/wildcard-cert-full.yaml" >/dev/null 2>&1
  ok "ClusterIssuer + domain-wide wildcard Certificate applied (DNS-01 challenge ~2-5 min)"
  kc -n "$NS" wait --for=condition=Ready certificate/cometchat-wildcard-full --timeout=360s >/dev/null 2>&1 \
    && ok "Let's Encrypt wildcard issued -> wildcard-tls (edge serves a valid cert)" \
    || warn "cert not Ready yet (kc -n $NS describe certificate cometchat-wildcard-full; check the DNS-01 challenge)"
}

# =============================================================================
# PHASE: verify / status
# =============================================================================
# Every workload that MUST be Ready after `all` (Deployments + StatefulSets, by metadata.name).
# Pure-Service entries (seaweedfs / seaweedfs-s3-external / rke2-ingress-nginx-internal) are not
# workloads. Storage is the consolidated HA stack (k8s/seaweedfs): master/volume/filer + cometchatfs.
EXPECTED_WORKLOADS="chatapi mgmtapi opensearch ollama mailpit \
seaweedfs-master seaweedfs-volume seaweedfs-filer cometchatfs \
clamav globalwebhooks metrics-pro-timer analytics metrics-pro extensions notificationscore service-search sql-consumer \
websocket moderationservice visual-chat-builder ai-agent-service receipt-updater notifications-delay-worker dashboard"

phase_verify() {
  step "verify — datastores, all workloads Ready, split-horizon DNS"
  apb verify-datastores.yml || true
  open_tunnel
  kc get nodes -o wide || true

  step "workload readiness (namespace $NS)"
  local w r ok_n=0 bad_n=0 missing=""
  for w in $EXPECTED_WORKLOADS; do
    # readyReplicas works for both Deployment and StatefulSet; empty/0 => not ready/absent
    r="$(kc -n "$NS" get deploy,statefulset "$w" -o jsonpath='{.items[*].status.readyReplicas}' 2>/dev/null || true)"
    if [ -n "$r" ] && [ "$r" != "0" ]; then ok "$w ready ($r)"; ok_n=$((ok_n+1))
    else err "$w NOT ready"; bad_n=$((bad_n+1)); missing="$missing $w"; fi
  done
  echo
  log "workloads ready: $ok_n / $((ok_n+bad_n))"
  [ "$bad_n" -ne 0 ] && warn "not ready:$missing"

  # Non-ready / non-running pods (quick triage view)
  local notrun; notrun="$(kc -n "$NS" get pods --no-headers 2>/dev/null | awk '$3!="Running" && $3!="Completed"{print "    "$1"  "$3}' || true)"
  [ -n "$notrun" ] && { warn "pods not Running:"; printf '%s\n' "$notrun" >&2; }

  # Split-horizon DNS check: api-onprem.<domain> must resolve IN-CLUSTER to the internal ingress IP.
  step "split-horizon DNS ( *.$DOMAIN -> $INGRESS_INTERNAL_IP )"
  local probe="cc-dns-$$"
  if kc -n "$NS" run "$probe" --rm -i --restart=Never --image=busybox:1.36 --timeout=70s -- \
        nslookup "api-onprem.$DOMAIN" 2>/dev/null | grep -q "$INGRESS_INTERNAL_IP"; then
    ok "in-cluster DNS resolves api-onprem.$DOMAIN -> $INGRESS_INTERNAL_IP (data stays in-cluster)"
  else
    warn "split-horizon DNS did NOT resolve to $INGRESS_INTERNAL_IP — inter-service calls may leak public."
    warn "  re-run: ./deploy.sh coredns   (and confirm INGRESS_INTERNAL_IP matches your service CIDR)"
  fi

  step "summary"
  if [ "$bad_n" -eq 0 ]; then ok "ALL $ok_n workloads Ready — one-click deploy looks healthy."
  else err "$bad_n workload(s) not ready — see above (kc -n $NS get pods, kc -n $NS logs <pod>)"; fi
}
phase_status() {
  step "status"
  local ip; ip="$(tf terraform output -raw edge_lb_ip 2>/dev/null || echo '(infra not applied)')"
  echo "  project   : $PROJECT  region: $REGION  zone: $ZONE"
  echo "  edge LB IP: $ip"
  open_tunnel
  kc get nodes 2>/dev/null || warn "cluster unreachable"
  kc -n "$NS" get pods 2>/dev/null || true
}

# =============================================================================
# dispatcher
# =============================================================================
usage() { awk 'NR==1{next} /^#####/{c++; if(c>=2) exit; next} {sub(/^# ?/,""); print}' "$0"; }

main() {
  local target="${1:-infra-all}"
  case "$target" in
    -h|--help|help) usage; exit 0 ;;
    config)           gen_tfvars ;;       # generate terraform.tfvars from customer.conf (Terraform-only strategy)
    preflight)        phase_preflight ;;
    infra)            phase_infra ;;
    inventory)        phase_inventory ;;
    datastores-wait)  phase_datastores_wait ;;
    credgen)          phase_credgen ;;      # generate fresh per-cluster datastore creds (secrets/infra/cluster-creds.yml)
    datastores)       phase_datastores ;;
    rke2)             phase_rke2 ;;
    seed)             phase_seed ;;
    secrets)          phase_secrets ;;
    support)          phase_support ;;
    storage)          phase_storage ;;      # consolidated HA SeaweedFS + console (the ONE object store)
    storage-ha)       phase_storage ;;      # back-compat alias
    editors)          phase_editors ;;      # etherpad DB + secrets for document-embed/whiteboard
    apps)             phase_apps ;;
    node-apps)        phase_node_apps ;;
    coredns)          phase_coredns ;;
    ingress)          phase_ingress ;;
    certs)            phase_certs ;;        # cert-manager + Let's Encrypt (Route53 DNS-01) wildcard -> wildcard-tls
    verify)           phase_verify ;;
    status)           phase_status ;;

    infra-all)        # the one-click INFRA rebuild
      phase_preflight; phase_infra; phase_inventory; phase_datastores_wait
      phase_credgen
      phase_datastores; phase_rke2; phase_seed
      step "DONE — infra is up"
      ok "Datastores + Kafka topics + RKE2 + seed complete."
      ok "Next (when ECR + licence + secrets/apps are ready):  ./deploy.sh app-all"
      ;;
    app-all)          # the gated APP phase — EVERYTHING app-side, in order
      phase_secrets; phase_support; phase_storage; phase_editors; phase_apps; phase_node_apps; phase_coredns; phase_ingress; phase_certs
      step "DONE — app phase applied"; phase_verify ;;
    all)              # the true one-click: zero -> fully-working, all services
      phase_preflight; phase_infra; phase_inventory; phase_datastores_wait
      phase_credgen
      phase_datastores; phase_rke2; phase_seed
      phase_secrets; phase_support; phase_storage; phase_editors; phase_apps; phase_node_apps; phase_coredns; phase_ingress; phase_certs; phase_verify ;;
    *) err "unknown target: $target"; usage; exit 2 ;;
  esac
}
main "$@"
