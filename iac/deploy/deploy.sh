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
#                                 #   apps -> node-apps -> coredns(split-horizon) -> edge(NodePorts)
#                                 #   -> haproxy(SNI edge) -> certs(Let's Encrypt) -> verify (gated)
#     ./deploy.sh all             # infra + apps end-to-end — EVERYTHING, all services
#                                 #   ORDER: VMs(+HAProxy) -> datastores(+kafka topics) -> seed(ALL
#                                 #   dumps + seeds) -> apps -> edge NodePorts -> HAProxy -> certs
#     ./deploy.sh <phase>         # run ONE phase (see PHASES below)
#     ./deploy.sh status          # show HAProxy edge IPs, nodes, datastore health
#     ./deploy.sh --help
#
#   EDGE MODEL: 2 HAProxy VMs do L4 SNI passthrough -> per-service NodePorts (30443-30452) ->
#     pod nginx TLS sidecar (:443). TLS terminates IN THE POD, never at the edge. East-west uses
#     CoreDNS direct-to-Service split-horizon. NO cloud LB, NO central ingress. See docs/HAPROXY-EDGE.md.
#
#   PHASES (run individually):
#     preflight datastores-wait infra inventory datastores rke2 seed
#     secrets support storage apps node-apps coredns edge haproxy certs verify status
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
haproxy     = { count = ${HAPROXY_COUNT:-2}, machine_type = "${HAPROXY_TYPE:-e2-small}" }
disk_kms_key       = "${DISK_KMS_KEY:-}"
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
  step "inventory — propagate the 2 HAProxy edge public IPs"
  # HAProxy replaces the GCP LB: 2 VMs, 2 public IPs, DNS round-robins facing hosts across both.
  local ips_json; ips_json="$(tf terraform output -json haproxy_ips 2>/dev/null || true)"
  [ -n "$ips_json" ] && [ "$ips_json" != "null" ] || { warn "haproxy_ips output empty (infra not applied yet?) — skipping"; return 0; }
  # flatten to a space-separated list for logging + a YAML flow list for group_vars
  local ips; ips="$(printf '%s' "$ips_json" | python3 -c 'import json,sys; print(" ".join(json.load(sys.stdin)))')"
  ok "HAProxy edge IPs = $ips"
  # edge_public_ips feeds the RKE2 API tls-san (extra SANs) — never hardcode these (B3).
  local gv="$ANS/group_vars/all/main.yml" flow
  flow="$(printf '%s' "$ips_json" | python3 -c 'import json,sys; print("[" + ", ".join("\"%s\""%x for x in json.load(sys.stdin)) + "]")')"
  if grep -q '^edge_public_ips:' "$gv"; then
    sed -i.bak -E "s|^edge_public_ips:.*|edge_public_ips: $flow|" "$gv" && rm -f "$gv.bak"
    ok "updated edge_public_ips in group_vars/all/main.yml -> $flow"
  fi
  printf '%s\n' "$ips" > "$IAC/.haproxy_ips"
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
  # base StorageClass: RKE2 ships NONE, so without this EVERY PVC (opensearch/ollama/seaweedfs/etherpad)
  # hangs Pending ("unbound immediate PersistentVolumeClaims"). Install the local-path provisioner + the
  # `local-path` default SC now — cluster is up + kubeconfig ready, and this MUST precede any PVC phase.
  open_tunnel
  kc apply -f "$K8S/local-path-storage.yaml" >/dev/null 2>&1 \
    && kc -n local-path-storage rollout status deploy/local-path-provisioner --timeout=120s >/dev/null 2>&1 \
    && ok "local-path StorageClass (default) + provisioner ready" \
    || warn "local-path provisioner not confirmed — PVCs will hang until it's up (check: kc get sc)"
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

  # --- SeaweedFS S3 secrets are owned by the SeaweedFS 4.37 stack (k8s/seaweedfs/deploy.sh phase_secrets):
  #     seaweedfs-sse-kek (encryption KEK), seaweedfs-s3-config (console=Admin + apps=RW), cometchatfs-env.
  #     The old 3.80 seaweedfs-s3 / seaweedfs-s3-creds are RETIRED (4.37 uses seaweedfs-s3-config). ---

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
  step "coredns split-horizon (per-pod TLS, DIRECT-to-Service) — every on-prem FQDN -> its Service"
  open_tunnel
  local dom_re="${DOMAIN//./\\.}"                  # escape dots for the CoreDNS regex
  # HAProxy edge model: NO central ingress. North-south is HAProxy SNI -> per-service NodePort ->
  # pod nginx sidecar :443. East-west is CoreDNS rewriting each customer FQDN STRAIGHT to its backing
  # Service (chatapi.cometchat.svc, …) with `answer auto` (keeps {appId} in Host); the rewritten
  # cluster.local query is resolved by re-forwarding to CoreDNS's own kubernetes plugin. Data-tier hosts
  # (media/data/files-onprem) go to seaweedfs-edge (:443 TLS). So NO ingress-internal-svc / catch-all.
  # Substitute __DOMAIN_RE__ FIRST (it contains __DOMAIN__ as a substring), then __DOMAIN__.
  sed -e "s|__DOMAIN_RE__|$dom_re|g" -e "s|__DOMAIN__|$DOMAIN|g" "$K8S/coredns-direct.yaml" > /tmp/cc-coredns-direct.yaml
  if ! grep -q "rewrite name exact api-onprem.$DOMAIN" /tmp/cc-coredns-direct.yaml 2>/dev/null; then
    warn "coredns-direct render produced no rewrites — aborting coredns (check k8s/coredns-direct.yaml)"; return 1
  fi
  kc apply -f /tmp/cc-coredns-direct.yaml >/dev/null \
    && ok "applied coredns-custom (per-FQDN DIRECT-to-Service split-horizon; data-tier -> seaweedfs-edge:443)" \
    || { warn "coredns-custom apply failed"; return 1; }
  # coredns-custom is imported by rke2-coredns on reload; bounce it to pick up promptly + confirm healthy.
  kc -n kube-system rollout restart deploy/rke2-coredns >/dev/null 2>&1 || true
  kc -n kube-system rollout status deploy/rke2-coredns --timeout=120s >/dev/null 2>&1 \
    && ok "CoreDNS healthy after direct split-horizon reload" \
    || err "CoreDNS NOT healthy after reload — check 'kc -n kube-system get pods -l k8s-app=kube-dns' + logs; a malformed coredns-custom .server CrashLoops it"
}

# =============================================================================
# PHASE: storage — HA SeaweedFS 4.37 + cometchatFS console (the ONE object store, ns cometchat)
#   EARLY part (this phase): SSE-KEK + S3 identities + masters/volumes/filer/console + `seaweedfs`
#   alias Service + our Ingress + the 5 buckets (uploads/observability private, assets/stickers/vcb
#   public). The LATE seed (public-bucket assets + ACLs) is phase_storage_seed — it signs against the
#   external host so it MUST run after DNS+cert are live (after phase_certs).
# =============================================================================
phase_storage() {
  step "storage — HA SeaweedFS 4.37 + cometchatFS console (the ONE object store, ns cometchat)"
  open_tunnel
  # secrets (SSE-KEK, console+apps identities, console env) + manifests + buckets + status
  KUBECONFIG="$KUBECONFIG_FILE" AWS_PROFILE="$AWS_PROFILE" "$K8S/seaweedfs/deploy.sh" all
}
phase_storage_ha() { phase_storage; }   # back-compat alias for the old phase name

# LATE seed — bundled assets into assets/stickers/visual-chat-builder-app + native public-read ACLs.
# Runs AFTER phase_certs because the seed Job signs S3 requests against https://media-onprem… (needs a
# resolvable host + valid cert). The in-cluster seed Job replaces the old aws-cli sticker-seed.job.yaml.
phase_storage_seed() {
  step "storage-seed — seed public buckets + set ACLs (SeaweedFS 4.37 in-cluster Job)"
  open_tunnel
  KUBECONFIG="$KUBECONFIG_FILE" AWS_PROFILE="$AWS_PROFILE" "$K8S/seaweedfs/deploy.sh" seed
}

# =============================================================================
# PHASE: edge  — NodePort overlay (the north-south entry points for the HAProxy edge)
#   Replaces the old ingress phase. Applies the fixed-NodePort <svc>-edge Services
#   (:443 -> pod nginx sidecar). HAProxy (phase_haproxy) SNI-routes to these NodePorts.
# =============================================================================
phase_edge() {
  step "edge — NodePort overlay (facing services :443 -> fixed NodePorts for HAProxy SNI)"
  open_tunnel
  kc apply -f "$K8S/edge-nodeports.yaml" \
    && ok "edge NodePorts applied (chatapi 30443 … notificationscore 30452 — see k8s/edge-nodeports.yaml)" \
    || warn "edge-nodeports apply failed"
  local ips; ips="$(cat "$IAC/.haproxy_ips" 2>/dev/null || tr '\n' ' ' < /dev/null)"
  ok "point public DNS (round-robin A) for the facing hosts at the HAProxy IPs: ${ips:-<run phase_inventory>}"
}

# =============================================================================
# PHASE: haproxy  — configure the 2 HAProxy edge VMs (L4 SNI passthrough -> NodePorts).
#   Runs AFTER the NodePort Services exist (phase_edge) and the RKE2 agents are up
#   (the config templates backends from the rke2_agents inventory group). Idempotent;
#   the config is validated (`haproxy -c`) before it replaces the running one.
# =============================================================================
phase_haproxy() {
  step "haproxy — configure the edge VMs (SNI passthrough -> per-service NodePorts)"
  apb haproxy.yml && ok "HAProxy edge configured (SNI -> NodePorts; stats on :8404 via IAP)" \
    || warn "haproxy playbook failed — check ansible reachability to the haproxy group"
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

  # Split-horizon DNS check (direct-to-Service model): api-onprem.<domain> must resolve IN-CLUSTER to
  # the chatapi Service ClusterIP (NOT a public/HAProxy IP) — proving east-west stays in the cluster.
  local cip; cip="$(kc -n "$NS" get svc chatapi -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)"
  step "split-horizon DNS ( api-onprem.$DOMAIN -> chatapi ClusterIP ${cip:-?} )"
  local probe="cc-dns-$$"
  if [ -n "$cip" ] && kc -n "$NS" run "$probe" --rm -i --restart=Never --image=busybox:1.36 --timeout=70s -- \
        nslookup "api-onprem.$DOMAIN" 2>/dev/null | grep -q "$cip"; then
    ok "in-cluster DNS resolves api-onprem.$DOMAIN -> $cip (chatapi ClusterIP; data stays in-cluster)"
  else
    warn "split-horizon DNS did NOT resolve api-onprem.$DOMAIN to chatapi's ClusterIP — east-west may leak public."
    warn "  re-run: ./deploy.sh coredns   (and check 'kc -n kube-system get cm coredns-custom -o yaml')"
  fi

  step "summary"
  if [ "$bad_n" -eq 0 ]; then ok "ALL $ok_n workloads Ready — one-click deploy looks healthy."
  else err "$bad_n workload(s) not ready — see above (kc -n $NS get pods, kc -n $NS logs <pod>)"; fi
}
phase_status() {
  step "status"
  local ips; ips="$(tf terraform output -json haproxy_ips 2>/dev/null | python3 -c 'import json,sys;print(" ".join(json.load(sys.stdin)))' 2>/dev/null || echo '(infra not applied)')"
  echo "  project     : $PROJECT  region: $REGION  zone: $ZONE"
  echo "  HAProxy IPs : $ips   (DNS round-robins facing hosts across these)"
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
    storage-seed)     phase_storage_seed ;; # LATE seed (public buckets + ACLs) — run after certs
    editors)          phase_editors ;;      # etherpad DB + secrets for document-embed/whiteboard
    apps)             phase_apps ;;
    node-apps)        phase_node_apps ;;
    coredns)          phase_coredns ;;
    edge)             phase_edge ;;         # NodePort overlay (facing :443 -> fixed NodePorts)
    ingress)          phase_edge ;;         # back-compat alias -> edge (no central ingress in the HAProxy model)
    haproxy)          phase_haproxy ;;      # (re)configure the 2 HAProxy edge VMs (SNI -> NodePorts)
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
      phase_secrets; phase_support; phase_storage; phase_editors; phase_apps; phase_node_apps; phase_coredns; phase_edge; phase_haproxy; phase_certs; phase_storage_seed
      step "DONE — app phase applied"; phase_verify ;;
    all)              # the true one-click: zero -> fully-working, all services
      phase_preflight; phase_infra; phase_inventory; phase_datastores_wait
      phase_credgen
      phase_datastores; phase_rke2; phase_seed
      phase_secrets; phase_support; phase_storage; phase_editors; phase_apps; phase_node_apps; phase_coredns; phase_edge; phase_haproxy; phase_certs; phase_storage_seed; phase_verify ;;
    *) err "unknown target: $target"; usage; exit 2 ;;
  esac
}
main "$@"
