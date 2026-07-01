#!/usr/bin/env bash
###############################################################################
# CometChat on-prem (GCP RKE2) — power control (cost saver)
#
#   Stop the VMs at night, start them in the morning. Disks persist, so all data,
#   RKE2 state and datastores survive a stop/start. After start, give the cluster
#   ~3-5 min to settle (systemd datastores + RKE2 + pods reconnect automatically).
#
#   USAGE
#     ./vms.sh stop      # stop all ${PREFIX}-* VMs
#     ./vms.sh start     # start them all
#     ./vms.sh status    # show each VM's state
###############################################################################
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${CONF:-$HERE/customer.conf}"; [ -f "$CONF" ] && . "$CONF"
PROJECT="${PROJECT:-}"; PREFIX="${PREFIX:-cometchat-onprem}"
[ -n "$PROJECT" ] || { echo "set PROJECT in $CONF"; exit 1; }
export CLOUDSDK_CORE_PROJECT="$PROJECT"
action="${1:-status}"

case "$action" in
  status)
    gcloud compute instances list --filter="name~^${PREFIX}-" --format="table(name,status,zone.basename())" ;;
  stop|start)
    filt="name~^${PREFIX}-"
    [ "$action" = stop ]  && filt="$filt AND status=RUNNING"
    [ "$action" = start ] && filt="$filt AND status=TERMINATED"
    gcloud compute instances list --filter="$filt" --format="value(name,zone)" \
    | while read -r vm zone; do
        [ -n "$vm" ] || continue
        gcloud compute instances "$action" "$vm" --zone="$zone" --async >/dev/null 2>&1 \
          && echo "$action issued: $vm" || echo "FAILED: $vm"
      done
    echo "--- '$action' issued for all (async). Check with: ./vms.sh status ---"
    [ "$action" = start ] && echo "Give the cluster ~3-5 min, then: ./deploy.sh status" ;;
  *) echo "usage: ./vms.sh stop|start|status"; exit 1 ;;
esac
