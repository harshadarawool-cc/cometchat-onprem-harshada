#!/usr/bin/env bash
# tunnels.sh — ONE command to reach every datastore + in-cluster UI from your laptop.
#
# Everything rides the kube-API IAP tunnel (the only datastore route the firewall allows on
# these VMs). Two kinds of targets, both via `kubectl port-forward`:
#   kpf  in-cluster ClusterIP services (kafka-ui, mailpit, ...)   -> svc/<name>
#   dbx  datastore VMs (mongo/mysql/tidb/redis)  -> a socat bridge pod (k8s/db-proxy.yaml)
# The API-server tunnel (127.0.0.1:6444) and the db-proxy pod are auto-started on demand.
#
# Usage:
#   ./tunnels.sh up                 # default: kafka-ui + ALL DBs (mongo, mysql, tidb, redis x4)
#   ./tunnels.sh up all             # + mailpit/opensearch/ollama/seaweedfs/dashboard
#   ./tunnels.sh up mongo redis-bullmq   # just these
#   ./tunnels.sh status             # what's currently up
#   ./tunnels.sh list               # all targets + how to connect (URLs + creds)
#   ./tunnels.sh down [names|all]   # tear down (leaves API tunnel up)
#   ./tunnels.sh down-api           # also stop the API-server tunnel (breaks kubectl/k9s)
#
# Each tunnel runs in the background; logs + pidfiles live under $STATE (printed by `status`).

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export KUBECONFIG="$DIR/kubeconfig-6444"

ZONE=asia-south1-a
PROJECT=onprem-499712
MASTER=cometchat-onprem-k8s-master-1
APIPORT=6444
NS=cometchat
STATE="${TMPDIR:-/tmp}/cc-tunnels"
mkdir -p "$STATE"

# Registry:  name  kind  localPort  target  remotePort
#   kind=kpf -> target is a k8s service (svc/<name>) in namespace $NS
#   kind=dbx -> datastore reached via the db-proxy pod (pod/db-proxy); localPort matches the
#               proxy's listen port for that datastore (see k8s/db-proxy.yaml)
TARGETS="
kafka-ui          kpf  8080   svc/kafka-ui          8080
mailpit           kpf  8025   svc/mailpit           8025
opensearch        kpf  9200   svc/opensearch-real   9200
ollama            kpf  11434  svc/ollama            11434
seaweedfs         kpf  8888   svc/seaweedfs         8888
dashboard         kpf  8090   svc/dashboard         80
mongo             dbx  27017  pod/db-proxy          27017
mysql             dbx  3306   pod/db-proxy          3306
tidb              dbx  4000   pod/db-proxy          4000
redis-shared      dbx  6379   pod/db-proxy          6379
redis-analytics   dbx  6380   pod/db-proxy          6380
redis-bullmq      dbx  6381   pod/db-proxy          6381
redis-prometrics  dbx  6382   pod/db-proxy          6382
"

get_row()   { awk -v n="$1" '$1==n {print; exit}' <<<"$TARGETS"; }
all_names() { awk 'NF>=5 {print $1}' <<<"$TARGETS"; }
port_up()   { lsof -iTCP:"$1" -sTCP:LISTEN -nP >/dev/null 2>&1; }

hint() {
  case "$1" in
    kafka-ui)          echo "    → open  http://localhost:8080  (Kafka UI — browse topics/messages)" ;;
    mailpit)           echo "    → open  http://localhost:8025" ;;
    opensearch)        echo "    → curl  http://localhost:9200" ;;
    ollama)            echo "    → api   http://localhost:11434" ;;
    seaweedfs)         echo "    → open  http://localhost:8888  (filer)" ;;
    dashboard)         echo "    → open  http://localhost:8090" ;;
    mongo)             echo "    → Compass: mongodb://admin:Cometchat2026%2A@localhost:27017/?authSource=admin&directConnection=true" ;;
    mysql)             echo "    → mysql -h127.0.0.1 -P3306 -uroot -p   (mgmt 'pulsecustomerdb'; pass Cometchat2026*)" ;;
    tidb)              echo "    → mysql -h127.0.0.1 -P4000 -uroot -p   (TiDB; per-app chat DBs cod_*; pass Cometchat2026*)" ;;
    redis-shared)      echo "    → redis-cli -h127.0.0.1 -p6379   (no auth)" ;;
    redis-analytics)   echo "    → redis-cli -h127.0.0.1 -p6380   (no auth)" ;;
    redis-bullmq)      echo "    → redis-cli -h127.0.0.1 -p6381   (no auth)" ;;
    redis-prometrics)  echo "    → redis-cli -h127.0.0.1 -p6382   (no auth)" ;;
  esac
}

ensure_api_tunnel() {
  port_up "$APIPORT" && return 0
  echo "→ starting API IAP tunnel (master :6443 -> 127.0.0.1:$APIPORT) ..."
  nohup gcloud compute start-iap-tunnel "$MASTER" 6443 \
    --local-host-port="127.0.0.1:$APIPORT" --zone="$ZONE" --project="$PROJECT" \
    >"$STATE/_api.log" 2>&1 &
  echo $! >"$STATE/_api.pid"
  for _ in $(seq 1 30); do port_up "$APIPORT" && break; sleep 1; done
  port_up "$APIPORT" || { echo "  ✗ API tunnel failed — see $STATE/_api.log"; return 1; }
  echo "  ✓ API tunnel up"
}

# db-proxy: the in-cluster socat bridge that all datastore (dbx) targets port-forward to.
ensure_proxy() {
  if kubectl -n "$NS" get pod db-proxy >/dev/null 2>&1 \
     && kubectl -n "$NS" wait --for=condition=ready pod/db-proxy --timeout=60s >/dev/null 2>&1; then
    return 0
  fi
  echo "→ deploying db-proxy (socat bridge to datastore VMs) ..."
  kubectl apply -f "$DIR/k8s/db-proxy.yaml" >/dev/null 2>&1 || { echo "  ✗ db-proxy apply failed"; return 1; }
  kubectl -n "$NS" wait --for=condition=ready pod/db-proxy --timeout=90s >/dev/null 2>&1 \
    || { echo "  ✗ db-proxy not ready — see: kubectl -n $NS describe pod db-proxy"; return 1; }
  echo "  ✓ db-proxy ready"
}

start_target() {
  local name="$1" row kind lport tgt rport
  row="$(get_row "$name")"
  [ -z "$row" ] && { echo "✗ unknown target: $name (try '$0 list')"; return 1; }
  # shellcheck disable=SC2086
  set -- $row; name="$1"; kind="$2"; lport="$3"; tgt="$4"; rport="$5"

  if port_up "$lport"; then echo "✓ $name already up on 127.0.0.1:$lport"; hint "$name"; return 0; fi

  # both kpf (services) and dbx (datastores) use kubectl port-forward over the API tunnel;
  # dbx additionally needs the db-proxy bridge pod up first.
  ensure_api_tunnel || return 1
  [ "$kind" = dbx ] && { ensure_proxy || return 1; }
  echo "→ $name: kubectl port-forward $tgt $lport:$rport ..."
  nohup kubectl -n "$NS" port-forward "$tgt" "$lport:$rport" >"$STATE/$name.log" 2>&1 &
  echo $! >"$STATE/$name.pid"
  for _ in $(seq 1 25); do port_up "$lport" && break; sleep 1; done
  if port_up "$lport"; then echo "  ✓ up on 127.0.0.1:$lport"; hint "$name"
  else echo "  ✗ $name failed — see $STATE/$name.log"; fi
}

stop_target() {
  local name="$1" row lport pid p
  row="$(get_row "$name")"
  [ -z "$row" ] && { echo "✗ unknown target: $name"; return 1; }
  # shellcheck disable=SC2086
  set -- $row; lport="$3"
  if [ -f "$STATE/$name.pid" ]; then
    pid="$(cat "$STATE/$name.pid")"; kill "$pid" 2>/dev/null; rm -f "$STATE/$name.pid"
  fi
  # fallback: kill anything WE own (gcloud/kubectl/ssh) still holding the local port
  for p in $(lsof -tiTCP:"$lport" -sTCP:LISTEN 2>/dev/null); do
    case "$(ps -o comm= -p "$p" 2>/dev/null)" in
      *gcloud*|*kubectl*|*ython*|*ssh*) kill "$p" 2>/dev/null ;;
    esac
  done
  if port_up "$lport"; then echo "… $name still up on $lport (not ours?)"; else echo "✓ $name stopped"; fi
}

status() {
  printf "%-18s %-5s %-7s %s\n" NAME KIND PORT STATE
  while read -r name kind lport _tgt _rport; do
    [ -z "${name:-}" ] && continue
    port_up "$lport" && st=UP || st=-
    printf "%-18s %-5s %-7s %s\n" "$name" "$kind" "$lport" "$st"
  done < <(awk 'NF>=5' <<<"$TARGETS")
  port_up "$APIPORT" && st=UP || st=-
  printf "%-18s %-5s %-7s %s\n" "api-tunnel" "iap" "$APIPORT" "$st"
  echo
  echo "logs/pidfiles: $STATE"
}

list() {
  echo "Available targets ('$0 up <name> ...'):"
  while read -r name kind lport _tgt _rport; do
    [ -z "${name:-}" ] && continue
    printf "  %-18s %-4s local:%s\n" "$name" "[$kind]" "$lport"
    hint "$name"
  done < <(awk 'NF>=5' <<<"$TARGETS")
}

usage() { sed -n '2,20p' "$0"; }

cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in
  up)
    names="$*"; [ -z "$names" ] && names="kafka-ui mongo mysql tidb redis-shared redis-analytics redis-bullmq redis-prometrics"
    [ "$names" = all ] && names="$(all_names | tr '\n' ' ')"
    for n in $names; do start_target "$n"; done
    echo; echo "→ '$0 status' to list, '$0 down' to stop (API tunnel + db-proxy stay up)."
    ;;
  down)
    names="$*"; { [ -z "$names" ] || [ "$names" = all ]; } && names="$(all_names | tr '\n' ' ')"
    for n in $names; do stop_target "$n"; done
    echo "(API tunnel on $APIPORT left running — '$0 down-api' to stop it too)"
    ;;
  down-api)
    [ -f "$STATE/_api.pid" ] && { kill "$(cat "$STATE/_api.pid")" 2>/dev/null; rm -f "$STATE/_api.pid"; }
    for p in $(lsof -tiTCP:"$APIPORT" -sTCP:LISTEN 2>/dev/null); do
      case "$(ps -o comm= -p "$p" 2>/dev/null)" in *gcloud*|*ython*|*ssh*) kill "$p" 2>/dev/null ;; esac
    done
    port_up "$APIPORT" && echo "… API tunnel still up" || echo "✓ API tunnel stopped"
    ;;
  status) status ;;
  list)   list ;;
  *)      usage ;;
esac
