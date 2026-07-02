#!/usr/bin/env bash
###############################################################################
# gen-cluster-creds.sh — generate FRESH, per-cluster datastore credentials.
#
#   Single source of truth: iac/.secrets/cluster-creds.yml (gitignored, chmod 600).
#   Consumed by BOTH:
#     - ansible  (deploy.sh apb() passes `-e @.secrets/cluster-creds.yml`) -> provisions
#                MySQL/TiDB/Mongo with THESE passwords.
#     - scripts/sync-app-db-creds.py -> stamps the SAME passwords into secrets-rendered/*.env
#                (DB_PASSWORD + MONGO_URI) so the apps authenticate with what the DBs were created with.
#   Because both sides read this one file, the datastore creds and the app secrets can NEVER drift.
#
#   IDEMPOTENT: a fresh cluster (no file yet) gets brand-new random passwords; a re-run REUSES the
#   existing file (regenerating would desync the already-provisioned DBs from the app secrets).
#   To force a rotation: delete iac/.secrets/cluster-creds.yml and re-run the datastore + secrets phases.
###############################################################################
set -euo pipefail
IAC="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$IAC/secrets/infra/cluster-creds.yml"
mkdir -p "$IAC/secrets/infra"

if [ -f "$OUT" ]; then
  n="$(grep -cE '_password:' "$OUT" 2>/dev/null || echo 0)"
  echo "cluster-creds.yml already present ($n creds) — REUSING (idempotent; delete it to force rotation)"
  exit 0
fi

command -v openssl >/dev/null 2>&1 || { echo "openssl required" >&2; exit 1; }
gen() { openssl rand -hex 16; }   # 32 hex chars — alphanumeric, safe in URIs / MySQL / Mongo

cat > "$OUT" <<EOF
# AUTO-GENERATED per-cluster datastore credentials — DO NOT COMMIT (gitignored, chmod 600).
# Consumed by ansible (deploy.sh apb -e) + scripts/sync-app-db-creds.py. One source of truth so the
# datastores and the application secrets are provisioned with identical passwords (never drift).
# Regenerate = delete this file + re-run 'datastores' and 'secrets' phases.
vault_mysql_root_password: "$(gen)"          # MySQL root@'%' (mgmtapi + metrics/analytics apps connect as root)
vault_tidb_root_password: "$(gen)"           # TiDB  root@'%' (chatapi connects as root)
vault_mongo_admin_password: "$(gen)"         # Mongo superuser 'root' (ansible auths as this; created by mongo role)
vault_mongo_app_admin_password: "$(gen)"     # Mongo app user 'admin'      (most apps' MONGO_URI)
vault_mongo_extadmin_password: "$(gen)"      # Mongo app user 'extadmin'   (extensions)
vault_mongo_webhookuser_password: "$(gen)"   # Mongo app user 'webhookuser' (globalwebhooks)
EOF
chmod 600 "$OUT"

# fail loudly if any value came out empty (openssl missing / disk full)
miss="$(grep -E '_password:\s*""' "$OUT" 2>/dev/null || true)"
[ -z "$miss" ] || { echo "ERROR: some generated creds are empty:" >&2; echo "$miss" >&2; exit 1; }
echo "generated FRESH cluster-creds.yml ($(grep -cE '_password:' "$OUT") datastore creds) -> $OUT"
