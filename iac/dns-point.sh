#!/usr/bin/env bash
# Point this cluster's DNS at its CURRENT edge LB IP (Route53, AWS profile from customer.conf).
# Re-asserts every plain A record in the zone to the edge LB IP terraform built for THIS cluster —
# run after any rebuild that may have changed the LB IP. Idempotent: records already correct are skipped.
#
# Self-syncing: reads DOMAIN / AWS_PROFILE / PREFIX / REGION / PROJECT from deploy/customer.conf and the
# LB IP from .edge_lb_ip (falls back to the reserved GCP address). Zone id is discovered from DOMAIN
# unless R53_ZONE_ID is set in customer.conf.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/deploy/customer.conf"
PROF="${R53_AWS_PROFILE:-${AWS_PROFILE:-staging}}"

# ---- HAProxy edge IPs (2 -> round-robin): .haproxy_ips -> reserved GCP addresses ----
IPS="$(cat "$HERE/.haproxy_ips" 2>/dev/null || true)"
if [ -z "${IPS// /}" ]; then
  IPS="$(gcloud compute addresses list --project "$PROJECT" --filter="name~'${PREFIX}-haproxy-.*-ip'" --format='value(address)' 2>/dev/null | tr '\n' ' ' || true)"
fi
IPS="$(echo $IPS)"   # normalise whitespace to single spaces
[ -n "${IPS// /}" ] || { echo "✗ could not determine the HAProxy edge IPs (.haproxy_ips / gcloud both empty)" >&2; exit 1; }

# ---- hosted zone id: customer.conf override, else discover by DOMAIN ----
ZID="${R53_ZONE_ID:-}"
if [ -z "$ZID" ]; then
  ZID="$(aws route53 list-hosted-zones --profile "$PROF" --output json \
    | DOMAIN="$DOMAIN" python3 -c 'import json,sys,os
d=os.environ["DOMAIN"].rstrip(".")+"."
for h in json.load(sys.stdin)["HostedZones"]:
  if h["Name"]==d: print(h["Id"].split("/")[-1]); break')"
fi
[ -n "$ZID" ] || { echo "✗ no Route53 hosted zone found for $DOMAIN (profile $PROF)" >&2; exit 1; }
echo "Pointing *.$DOMAIN A-records -> round-robin [ $IPS ]   (zone $ZID, AWS profile $PROF)"

# Re-assert every A record in the zone to the FULL HAProxy IP set (multi-value round-robin, active-active).
# Idempotent: a record whose value set already equals the target (order-insensitive) is skipped. CNAMEs
# (all the non-base hosts) follow transitively. Internal-only hosts have no A record, so they are untouched.
CB="$(aws route53 list-resource-record-sets --hosted-zone-id "$ZID" --profile "$PROF" --output json \
  | IPS="$IPS" DOMAIN="$DOMAIN" python3 -c '
import json,sys,os
ips=os.environ["IPS"].split(); dom=os.environ["DOMAIN"].rstrip(".")
target=sorted(ips)
recs=json.load(sys.stdin)["ResourceRecordSets"]; ch=[]
for r in recs:
    if r.get("Type")!="A" or "AliasTarget" in r: continue
    if not r["Name"].rstrip(".").endswith(dom): continue
    if sorted(v.get("Value") for v in r.get("ResourceRecords",[]))==target: continue
    ch.append({"Action":"UPSERT","ResourceRecordSet":{"Name":r["Name"],"Type":"A","TTL":60,
               "ResourceRecords":[{"Value":ip} for ip in ips]}})
print(json.dumps({"Comment":"round-robin to HAProxy edge","Changes":ch}))')"

NCH="$(echo "$CB" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["Changes"]))')"
TOTAL="$(aws route53 list-resource-record-sets --hosted-zone-id "$ZID" --profile "$PROF" --query "length(ResourceRecordSets[?Type=='A'])" --output text 2>/dev/null)"
if [ "$NCH" -eq 0 ]; then echo "✓ all $TOTAL A-record(s) already round-robin [ $IPS ] — nothing to change"; exit 0; fi
echo "$CB" > /tmp/v3-r53-change.json
OUT="$(aws route53 change-resource-record-sets --hosted-zone-id "$ZID" --profile "$PROF" \
        --change-batch file:///tmp/v3-r53-change.json --query 'ChangeInfo.Status' --output text)"
echo "✓ upserted $NCH of $TOTAL A-record(s) -> round-robin [ $IPS ]   (change status: $OUT)"
echo "  propagation ~1 min; verify:  dig +short app.$DOMAIN   (should list all HAProxy IPs)"
