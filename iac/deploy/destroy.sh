#!/usr/bin/env bash
###############################################################################
# CometChat on-prem (GCP RKE2) — teardown
#
#   Destroys ONLY the new `cometchat-onprem-*` infra managed by ../terraform.
#   The OLD kept infra (cometchat-ds-* / cometchat-gke / cometchat-vpc) is in a
#   DIFFERENT terraform state (or unmanaged) and is NOT touched here.
#
#   USAGE
#     ./destroy.sh            # prints the plan + the VM names, then asks to confirm
#     ./destroy.sh --yes      # non-interactive (CI)
#
#   After destroy, rebuild with:  ./deploy.sh
###############################################################################
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF="$(cd "$HERE/.." && pwd)/terraform"
CONF="${CONF:-$HERE/customer.conf}"
[ -f "$CONF" ] && . "$CONF"
PREFIX="${PREFIX:-cometchat-onprem}"
PROJECT="${PROJECT:-}"
ASSUME_YES=0; [ "${1:-}" = "--yes" ] && ASSUME_YES=1

if [ -t 1 ]; then R='\033[31m'; Y='\033[33m'; B='\033[1m'; Z='\033[0m'; else R=''; Y=''; B=''; Z=''; fi

cd "$TF"
terraform init -input=false >/dev/null

printf "%b\n" "${B}Resources Terraform will DESTROY (must all be '${PREFIX}-*'):${Z}"
terraform state list 2>/dev/null | sed 's/^/  /' || true

# Safety guard: refuse if any managed resource name does NOT start with the new prefix.
bad="$(terraform show -json 2>/dev/null \
  | jq -r '.values.root_module.resources[]?.values.name // empty' \
  | grep -v "^${PREFIX}" || true)"
if [ -n "$bad" ]; then
  printf "%b\n" "${R}ABORT: state contains resources NOT named ${PREFIX}-* :${Z}"
  printf '%s\n' "$bad" | sed 's/^/  /'
  printf "%b\n" "${R}This state may include the OLD infra — refusing to destroy.${Z}"
  exit 1
fi

printf "%b\n" "${Y}This permanently deletes ALL ${PREFIX}-* VMs, disks, VPC, LB and bastion above.${Z}"
if [ "$ASSUME_YES" -ne 1 ]; then
  printf "Type the project id (%s) to confirm: " "$PROJECT"
  read -r ans
  [ "$ans" = "$PROJECT" ] || { echo "confirmation mismatch — aborted"; exit 1; }
fi

terraform destroy -auto-approve
printf "%b\n" "${B}Destroyed. Rebuild with: ./deploy.sh${Z}"
