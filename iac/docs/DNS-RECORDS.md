# DNS records — Route53 (`cometchat-cluster-2.in`)

> Public DNS points the base hosts at **both HAProxy IPs** (round-robin); everything else is a CNAME onto a
> base host. Internal-only hosts get **no public DNS**. Applied by `dns-point.sh`. See
> [NETWORKING §5](NETWORKING.md), [HAPROXY-EDGE](HAPROXY-EDGE.md).

## Base hosts — A records (→ both HAProxy IPs, round-robin)

One A record per facing base host, each carrying **both** HAProxy public IPs (active-active). On rebuild the
IPs change → re-run `dns-point.sh` to re-assert them; CNAMEs follow automatically.

```
api-onprem                 A   <haproxy-ip-1>
api-onprem                 A   <haproxy-ip-2>
websocket-onprem           A   <haproxy-ip-1> / <haproxy-ip-2>
app                        A   <haproxy-ips>     # dashboard
apimgmt                    A   <haproxy-ips>     # mgmtapi
metrics-onprem             A   <haproxy-ips>     # analytics
extensions-onprem          A   <haproxy-ips>
media-onprem               A   <haproxy-ips>     # seaweedfs S3
document-embed-onprem      A   <haproxy-ips>
whiteboard-embed-onprem    A   <haproxy-ips>
notifications-onprem       A   <haproxy-ips>
```

## Transitive CNAMEs (→ a base host)

```
apiclient-onprem                CNAME  api-onprem
*.api-onprem                    CNAME  api-onprem          # per-app appId hosts
*.apiclient-onprem              CNAME  apiclient-onprem
*.websocket-onprem              CNAME  websocket-onprem
*.extensions-onprem             CNAME  extensions-onprem
*.media-onprem                  CNAME  media-onprem
data-onprem / files-onprem      CNAME  media-onprem
document-onprem                 CNAME  extensions-onprem   # /v1/create API → extensions
whiteboard-onprem               CNAME  extensions-onprem
stickers-onprem / polls-onprem / link-preview-onprem / thumbnail-generator-onprem   CNAME  extensions-onprem
```

## Internal-only — NO public DNS (resolved by CoreDNS inside the cluster only)

Publishing these would expose internal services; they have **no A/CNAME** in Route53:

```
ws-onprem            (chatapi CHAT_HOST — internal use)
storage-onprem       (cometchatFS console — port-forward only)
webhooks-onprem      (globalwebhooks)
rule-onprem          (moderationservice)
metrics-pro-onprem   (metrics-pro)
internal-search-onprem, internal-vcb-onprem, internal-apivcb-onprem
ai-agent-service     (per-app; HTTP-only pod)
*-internal           (the east-west -internal twins)
```

## `dns-point.sh`

Reads `DOMAIN` / `R53_ZONE_ID` / `AWS_PROFILE` from `deploy/customer.conf` and the HAProxy IPs from
`iac/.haproxy_ips` (written by `deploy.sh phase_inventory`, falls back to `gcloud compute addresses list`).
It **re-asserts every A record in the zone** to the full HAProxy IP set (order-insensitive; a record already
correct is skipped). CNAMEs are untouched (they follow). Internal hosts have no A record, so they're never
pointed outward.

```bash
cd iac && ./dns-point.sh
# → "upserted N of M A-record(s) → round-robin [ ip1 ip2 ]"
dig +short app.cometchat-cluster-2.in      # should list BOTH HAProxy IPs
```

> ⚠️ On every teardown+rebuild the HAProxy public IPs re-allocate (unless you keep the reserved addresses).
> Re-run `./dns-point.sh`. This is the #1 cause of "it worked yesterday, now every facing host is broken."
