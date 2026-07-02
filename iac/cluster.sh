#!/bin/bash
# One-stop access to the on-prem RKE2 cluster.
#   ./cluster.sh            -> ensure IAP tunnel, then open k9s on the cometchat namespace
#   ./cluster.sh tunnel     -> just bring up (and keep) the tunnel
#   ./cluster.sh kubectl ...-> run kubectl against the cluster (e.g. ./cluster.sh kubectl get pods -n cometchat)
#
# The cluster's API server has no public IP; we reach it through a GCP IAP tunnel
# (master VM :6443 -> local 127.0.0.1:6444) and talk to it with kubeconfig-6444.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export KUBECONFIG="$DIR/kubeconfig-6444"

PORT=6444
MASTER=cometchat-onprem-k8s-master-1
ZONE=asia-south1-a
PROJECT=onprem-499712
LOG=/tmp/iap-tunnel-${PORT}.log

tunnel_up() { lsof -iTCP:$PORT -sTCP:LISTEN -n -P >/dev/null 2>&1; }

ensure_tunnel() {
  if tunnel_up; then
    echo "✓ tunnel already up on 127.0.0.1:$PORT"
    return
  fi
  echo "→ starting IAP tunnel (master :6443 -> 127.0.0.1:$PORT) ..."
  nohup gcloud compute start-iap-tunnel "$MASTER" 6443 \
    --local-host-port=127.0.0.1:$PORT --zone="$ZONE" --project="$PROJECT" \
    >"$LOG" 2>&1 &
  for _ in $(seq 1 30); do tunnel_up && break; sleep 1; done
  if tunnel_up; then echo "✓ tunnel up"; else echo "✗ tunnel failed — see $LOG"; exit 1; fi
}

case "${1:-k9s}" in
  tunnel)
    # foreground tunnel that you keep running in its own terminal
    exec gcloud compute start-iap-tunnel "$MASTER" 6443 \
      --local-host-port=127.0.0.1:$PORT --zone="$ZONE" --project="$PROJECT"
    ;;
  kubectl)
    ensure_tunnel; shift; exec kubectl "$@"
    ;;
  k9s|"")
    ensure_tunnel
    kubectl version --request-timeout=5s >/dev/null 2>&1 && echo "✓ cluster reachable" || { echo "✗ cluster not reachable"; exit 1; }
    exec k9s -n cometchat
    ;;
  *)
    ensure_tunnel; exec kubectl "$@"
    ;;
esac
