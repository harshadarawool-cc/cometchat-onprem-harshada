# Route53 records — what to point (one-LB model)

> Zone: `cometchat-cluster-2.in` (`Z04640112BJ8TJHK3I2RI`). Edge LB IP: **35.200.134.182**
> (always re-check: `gcloud compute forwarding-rules list --filter="name~cometchat-onprem-edge" --format='value(IPAddress)'`).

## The key point about "one LB + multiple certs"

**The number of certs does NOT change DNS.** With a single edge LB, **every public hostname's A
record points to the same one LB IP** (`35.200.134.182`). ingress-nginx then serves the correct
cert per-host via **SNI** — so 1 cert or 10 certs, the DNS is identical. (Your colleague has many
*IPs* only because Azure gives each `type: LoadBalancer` service its own IP — that's the multi-LB
model we are deliberately not using.)

## PUBLIC records — CREATE these (8 services)

All `A` records resolve to the single edge LB.

| Record | Type | Value | Service |
|---|---|---|---|
| `app.cometchat-cluster-2.in` | A | 35.200.134.182 | dashboard |
| `apimgmt.cometchat-cluster-2.in` | A | 35.200.134.182 | mgmtapi |
| `api-onprem.cometchat-cluster-2.in` | A | 35.200.134.182 | chatapi |
| `apiclient-onprem.cometchat-cluster-2.in` | A | 35.200.134.182 | chatapi |
| `websocket-onprem.cometchat-cluster-2.in` | A | 35.200.134.182 | websocket |
| `extensions-onprem.cometchat-cluster-2.in` | A | 35.200.134.182 | extensions |
| `media-onprem.cometchat-cluster-2.in` | A | 35.200.134.182 | seaweedfs (⏸ deploy pending) |
| `files-onprem.cometchat-cluster-2.in` | A | 35.200.134.182 | seaweedfs (⏸ deploy pending) |
| `metrics-onprem.cometchat-cluster-2.in` | A | 35.200.134.182 | analytics |
| `rtc-onprem.cometchat-cluster-2.in` | A | 35.200.134.182 | calls-relay |
| `calls-relay-onprem.cometchat-cluster-2.in` | A | 35.200.134.182 | calls-relay |

### Scoped per-app wildcards (the `{appId}.` SDK pattern) — CNAME to their base

| Record | Type | Value |
|---|---|---|
| `*.api-onprem.cometchat-cluster-2.in` | CNAME | api-onprem.cometchat-cluster-2.in |
| `*.apiclient-onprem.cometchat-cluster-2.in` | CNAME | apiclient-onprem.cometchat-cluster-2.in |
| `*.websocket-onprem.cometchat-cluster-2.in` | CNAME | websocket-onprem.cometchat-cluster-2.in |
| `*.extensions-onprem.cometchat-cluster-2.in` | CNAME | extensions-onprem.cometchat-cluster-2.in |

This matches your colleague's cluster-4 exactly (he uses the same `*.api-onprem`, `*.apiclient-onprem`, `*.websocket-onprem` CNAMEs to base).

## DELETE this record

| Record | Why |
|---|---|
| `*.cometchat-cluster-2.in` (wildcard A) | the domain-wide wildcard makes *every* name (incl. internal services) resolve → over-exposure. Remove it; publish per-host instead. |

## DO NOT create (internal-only — reached app→app via CoreDNS, never the internet)

`webhooks-onprem`, `notifications-onprem`, `rule-onprem`, `internal-search-onprem`,
`internal-vcb-onprem`, `metrics-pro-onprem`, `mail`

These resolve **inside the cluster** via CoreDNS (`*.cometchat-cluster-2.in → 10.43.230.223`,
the internal ingress) and never need a public record. No public DNS = not discoverable/reachable
from the internet.

## Managed automatically — do NOT hand-create

`_acme-challenge.<host>` TXT records: created/cleaned up automatically by **certbot --dns-route53**
(or cert-manager) during DNS-01 issuance. See [CERTIFICATES.md](CERTIFICATES.md).

## Apply (AWS CLI, `staging` profile)

Example for one record — repeat per host (or use a JSON batch in one `change-resource-record-sets`):
```bash
aws route53 change-resource-record-sets --hosted-zone-id Z04640112BJ8TJHK3I2RI \
  --profile staging --change-batch '{
    "Changes":[{"Action":"UPSERT","ResourceRecordSet":{
      "Name":"api-onprem.cometchat-cluster-2.in","Type":"A","TTL":60,
      "ResourceRecords":[{"Value":"35.200.134.182"}]}}]}'
```
Delete the wildcard with `"Action":"DELETE"` and its current value.
