#!/usr/bin/env bash
# Connect to the v3 TEST cluster (cometchat-onprem-v3) from your laptop — opens every tunnel and
# prints kubectl + Mailpit + MongoDB + MySQL + TiDB + Redis + Kafka + OpenSearch + SeaweedFS details.
#
# Self-syncing: reads cluster identity + datastore /24 from deploy/customer.conf, so it always matches
# whatever ./deploy.sh built (no hand-edits when prefix/CIDR/port change).
#
# The VMs have NO public IP, so everything rides Google IAP:
#   - k8s API : IAP direct to master:6443            -> 127.0.0.1:$KPORT   (kubectl)
#   - DBs     : ONE SSH session through the BASTION (IAP only opens 22/6443 to the DB VMs; the bastion
#               can reach the datastore /24) -> Mongo/MySQL/TiDB/Redis/Kafka on localhost.
#   - UIs     : kubectl port-forward -> Mailpit/OpenSearch/SeaweedFS S3
# Re-run anytime — it skips tunnels already up.  Stop all: see footer.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# ---- load the SAME cluster identity deploy.sh uses (single source of truth) ----
. "$HERE/deploy/customer.conf"
NS="${NS:-cometchat}"
MASTER="${PREFIX}-k8s-master-1"; BASTION="${PREFIX}-bastion"; KPORT="${TUNNEL_PORT:-6444}"
# datastore /24 prefix from customer.conf subnet_data_cidr (e.g. 10.23.10.0/24 -> 10.23.10)
DATA3="$(echo "${SUBNET_DATA_CIDR:-10.23.10.0/24}" | sed -E 's/\.[0-9]+\/[0-9]+$//')"
# fixed host offsets from the terraform module (first node of each role)
MONGO_IP="$DATA3.11"; REDIS_IP="$DATA3.21"; REDIS_ANALYTICS_IP="$DATA3.24"
REDIS_PROMETRICS_IP="$DATA3.27"; REDIS_BULLMQ_IP="$DATA3.61"; KAFKA_IP="$DATA3.31"
MYSQL_IP="$DATA3.41"; TIDB_IP="$DATA3.51"
SR="$HERE/secrets-rendered"
export KUBECONFIG="$HERE/kubeconfig-$KPORT"
LB_IP="$(cat "$HERE/.edge_lb_ip" 2>/dev/null || echo '?')"

up(){ (exec 3<>/dev/tcp/127.0.0.1/"$1") 2>/dev/null && { exec 3>&- 3<&-; return 0; }; return 1; }

# 1) k8s API tunnel (kubectl)
if up "$KPORT"; then echo "k8s API tunnel already up on :$KPORT"
else echo "opening k8s API tunnel ($MASTER:6443 -> :$KPORT) ..."
  nohup gcloud compute start-iap-tunnel "$MASTER" 6443 --local-host-port=127.0.0.1:"$KPORT" --zone="$ZONE" --project="$PROJECT" >/tmp/v3-tunnel-k8s.log 2>&1 &
  for i in $(seq 1 30); do up "$KPORT" && break; sleep 1; done; fi

# 2) ALL datastores via ONE bastion SSH session (-L every port through it):
#    Mongo 27017 / MySQL 3306 / TiDB 4000 / Kafka 9092 / Redis 6379 shared .21 / 6380 analytics .24 / 6381 prometrics .27 / 6382 bullmq .61
if up 27017 && up 3306 && up 4000 && up 9092 && up 6379; then echo "datastore tunnels already up"
else echo "opening datastore tunnels via bastion ($BASTION -> $DATA3.x) ..."
  nohup gcloud compute ssh "$BASTION" --tunnel-through-iap --zone="$ZONE" --project="$PROJECT" -- -N \
     -L 27017:"$MONGO_IP":27017 -L 3306:"$MYSQL_IP":3306 -L 4000:"$TIDB_IP":4000 -L 9092:"$KAFKA_IP":9092 \
     -L 6379:"$REDIS_IP":6379 -L 6380:"$REDIS_ANALYTICS_IP":6379 -L 6381:"$REDIS_PROMETRICS_IP":6379 -L 6382:"$REDIS_BULLMQ_IP":6379 \
     >/tmp/v3-tunnel-db.log 2>&1 &
  for i in $(seq 1 40); do up 27017 && up 3306 && up 4000 && up 9092 && break; sleep 1; done; fi

# 3) In-cluster UIs via kubectl port-forward (only if the pod is deployed yet)
for entry in "mailpit:8025:8025" "opensearch:9200:9200" "seaweedfs:8333:8333"; do
  svc="${entry%%:*}"; rest="${entry#*:}"; lport="${rest%%:*}"; tport="${rest##*:}"
  if up "$lport"; then echo "$svc already up on :$lport"
  else
    if kubectl -n "$NS" get "svc/$svc" >/dev/null 2>&1; then
      echo "forwarding $svc -> :$lport ..."
      nohup kubectl -n "$NS" port-forward "svc/$svc" "$lport:$tport" >/tmp/v3-pf-$svc.log 2>&1 &
      for i in $(seq 1 20); do up "$lport" && break; sleep 1; done
    else echo "$svc not deployed yet — skipping (re-run connect.sh after it's up)"; fi
  fi
done

# ---- creds (from the rendered envs deploy.sh generated + the ansible vault) ----
TIDB_PW="$(grep -E '^DB_PASSWORD=' "$SR/chatapi.env" 2>/dev/null | cut -d= -f2-)"
MYSQL_PW="$(grep -E '^DB_PASSWORD=' "$SR/mgmtapi.env" 2>/dev/null | cut -d= -f2-)"
VV(){ ( cd "$HERE/ansible" && ansible-vault view group_vars/all/vault.yml 2>/dev/null ) | grep -E "^$1" | sed -E 's/^[^:]*:[[:space:]]*//; s/^"//; s/"$//; s/^'\''//; s/'\''$//'; }
MONGO_PW="$(VV vault_mongo_admin_password)"
REDIS_PW="$(VV redis_requirepass)"
S3_KEY="$(kubectl -n "$NS" get secret seaweedfs-s3-creds -o jsonpath='{.data.access-key}' 2>/dev/null | base64 --decode 2>/dev/null)"
S3_SECRET="$(kubectl -n "$NS" get secret seaweedfs-s3-creds -o jsonpath='{.data.secret-key}' 2>/dev/null | base64 --decode 2>/dev/null)"
DB_USER="root"

cat <<EOF

================================ CONNECT ($PREFIX) ================================
edge LB IP: $LB_IP        (point $DOMAIN A-records here)
DB admin user: $DB_USER   (current creds; rotating to fresh per-service later)

kubectl:    export KUBECONFIG=$HERE/kubeconfig-$KPORT
            kubectl get pods -n $NS

Dashboard:  https://app.$DOMAIN
Mailpit:    http://localhost:8025           (signup / OTP emails)

MongoDB (Compass) — paste this URI:
  mongodb://${DB_USER}:${MONGO_PW}@localhost:27017/?authSource=admin&directConnection=true

MySQL Workbench — shared MySQL (pulsecustomerdb, metrics, analytics_logs):
  Host 127.0.0.1   Port 3306   User ${DB_USER}   Password  ${MYSQL_PW}

MySQL Workbench — TiDB (per-app chat DBs cod_<appId>; MySQL protocol):
  Host 127.0.0.1   Port 4000   User ${DB_USER}   Password  ${TIDB_PW}

Redis ($([ -n "$REDIS_PW" ] && echo "AUTH pass: $REDIS_PW" || echo "no auth")):
  redis-cli -h 127.0.0.1 -p 6379 $([ -n "$REDIS_PW" ] && echo "-a $REDIS_PW")   # shared
  redis-cli -h 127.0.0.1 -p 6380 ...   # analytics (.24)
  redis-cli -h 127.0.0.1 -p 6381 ...   # prometrics (.27)
  redis-cli -h 127.0.0.1 -p 6382 ...   # bullmq (.61)

Kafka:        127.0.0.1:9092    # kafka-console-consumer --bootstrap-server 127.0.0.1:9092 --topic <t>
OpenSearch:   http://localhost:9200    # curl localhost:9200/_cat/indices
SeaweedFS S3: http://localhost:8333    access ${S3_KEY:-<in seaweedfs-s3-creds>}   secret ${S3_SECRET:-<in seaweedfs-s3-creds>}
==================================================================================
(tunnels run in the background; logs: /tmp/v3-tunnel-*.log + /tmp/v3-pf-*.log)
(stop all: pkill -f start-iap-tunnel; pkill -f 'ssh.*-L 27017'; pkill -f 'kubectl.*port-forward')
EOF
