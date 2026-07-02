#!/usr/bin/env bash
# Substitute __PLACEHOLDER__ tokens from environment variables into rendered/.
# Usage: export NAMESPACE=... S3_HOST=... CONSOLE_HOST=... STORAGE_CLASS=... \
#               VOLUME_SIZE=... TLS_SECRET=... [ASSETS_HOST=...]  ; ./render.sh
set -euo pipefail
cd "$(dirname "$0")"

REQUIRED=(NAMESPACE S3_HOST CONSOLE_HOST STORAGE_CLASS VOLUME_SIZE TLS_SECRET)
for v in "${REQUIRED[@]}"; do
  if [ -z "${!v:-}" ]; then echo "Missing env var: $v" >&2; exit 1; fi
done

# OPTIONAL: vanity domain for the public `assets` bucket (https://assets.<domain>/… -> /assets/…).
# Leave unset to disable — it renders a dormant host that never matches real traffic. To enable,
# set e.g. ASSETS_HOST=assets.<client-domain> (also add its DNS record + cover it in the TLS cert).
ASSETS_HOST="${ASSETS_HOST:-assets.unset.invalid}"

mkdir -p rendered
for f in 10-master.yaml 20-volume.yaml 30-filer-s3.yaml 50-ingress-nginx.yaml 60-seed-job.yaml 40-s3-secret.example.yaml; do
  sed \
    -e "s|__NAMESPACE__|${NAMESPACE}|g" \
    -e "s|__S3_HOST__|${S3_HOST}|g" \
    -e "s|__CONSOLE_HOST__|${CONSOLE_HOST}|g" \
    -e "s|__ASSETS_HOST__|${ASSETS_HOST}|g" \
    -e "s|__STORAGE_CLASS__|${STORAGE_CLASS}|g" \
    -e "s|__VOLUME_SIZE__|${VOLUME_SIZE}|g" \
    -e "s|__TLS_SECRET__|${TLS_SECRET}|g" \
    "$f" > "rendered/${f/.example/}"
done
echo "Rendered to rendered/ . Fill in real keys in rendered/40-s3-secret.yaml before applying."
