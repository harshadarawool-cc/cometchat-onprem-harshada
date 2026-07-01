#!/usr/bin/env bash
###############################################################################
# Stop the Link Preview "history-replay" storm that lags the UIKit browser.
#
# WHY THIS EXISTS
#   The EXTENSIONS_LINK_PREVIEW Kafka consumer (topic internal-events-restapi-messages)
#   defaults to auto.offset.reset=earliest. On a FRESH consumer group (first build, or a
#   Kafka/topic rebuild) it starts at offset 0 and reprocesses the ENTIRE message history.
#   Each reprocessed message -> PATCH /metadata/injected -> CometChat broadcasts a
#   "message edited" event over the WebSocket to EVERY connected client -> the UIKit browser
#   drowns in events and lags (worse with a 2nd user/tab; hits all machines, it's server-pushed).
#
# WHAT THIS DOES (Link Preview stays ENABLED the whole time)
#   1. pause the extensions consumers (scale->0) so Kafka allows an offset reset
#   2. reset EXTENSIONS_LINK_PREVIEW to LATEST  (skip the backlog; only new messages from now)
#   3. resume extensions (scale back)
#
# WHEN TO RUN
#   - once after a full infra rebuild (Kafka recreated), or
#   - any time the group's lag balloons again (kafka-ui -> Consumers -> EXTENSIONS_LINK_PREVIEW)
#
# Idempotent + safe. Trade-off: ~backlog of OLD messages won't get link-preview backfill (fine).
###############################################################################
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-$DIR/kubeconfig-6444}"
NS="${NS:-cometchat}"
GROUP="${GROUP:-EXTENSIONS_LINK_PREVIEW}"
BROKERS="${BROKERS:-10.20.10.31:9092,10.20.10.32:9092,10.20.10.33:9092}"
kc(){ kubectl -n "$NS" "$@"; }

echo "• current EXTENSIONS_LINK_PREVIEW lag (before):"
kubectl -n "$NS" run kafka-lag-$$ --rm -i --restart=Never --image=apache/kafka:3.8.0 --command -- \
  /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server "$BROKERS" --group "$GROUP" --describe 2>/dev/null \
  | awk 'NR==1||/internal-events/{print "   "$0}' || true

REPLICAS="$(kc get deploy extensions -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 1)"
echo "• pausing extensions consumers (was ${REPLICAS} replica(s); Link Preview stays enabled)…"
kc scale deploy/extensions --replicas=0 >/dev/null
kc wait --for=delete pod -l app.kubernetes.io/name=extensions --timeout=90s >/dev/null 2>&1 || true
echo "• waiting for consumer group to go inactive (Kafka session timeout)…"; sleep 45

echo "• resetting ${GROUP} -> latest…"
for attempt in 1 2 3; do
  if kubectl -n "$NS" run kafka-reset-$$-$attempt --rm -i --restart=Never --image=apache/kafka:3.8.0 --command -- \
      /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server "$BROKERS" \
      --group "$GROUP" --reset-offsets --to-latest --all-topics --execute 2>&1 \
      | tee /tmp/lp-reset.out | grep -qiE "NEW-OFFSET|reset"; then
    break
  fi
  echo "   group not empty yet (attempt $attempt) — waiting 20s…"; sleep 20
done
grep -iE "GROUP|internal-events|error|inactive" /tmp/lp-reset.out || true

echo "• resuming extensions…"
kc scale deploy/extensions --replicas="${REPLICAS:-1}" >/dev/null
kc rollout status deploy/extensions --timeout=120s
echo "✓ done — ${GROUP} at latest; Link Preview now processes only NEW messages."
