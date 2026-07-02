# HAProxy edge — L4 SNI passthrough

> The public entry point. Replaces the GCP L4 Network LB. See also [NETWORKING](NETWORKING.md),
> [MIGRATION-FROM-LB](MIGRATION-FROM-LB.md), [DNS-RECORDS](DNS-RECORDS.md).

## Model

Two standalone **HAProxy VMs** in the edge subnet, each with its own **reserved public IP**. Public DNS
**round-robins** every facing host across both IPs → **active-active**. HAProxy operates at **L4**: it
inspects the TLS **ClientHello SNI** and forwards the **raw, still-encrypted** TCP stream to a
**per-service NodePort** on the RKE2 agents. It **never terminates TLS** — the wildcard cert is terminated
by the destination pod's **nginx sidecar** on `:443`.

```
client ──TLS(SNI=api-onprem…)──▶ HAProxy :443 ──raw TLS──▶ agent:30443 ──kube-proxy──▶ chatapi pod
                                  (reads SNI only)                                     nginx sidecar :443
                                                                                       terminates wildcard-tls
```

Why not a cloud LB: RKE2 ships no cloud-controller (so `type: LoadBalancer` never gets an IP), and we
want TLS to terminate **inside the pod** (data residency), which a passthrough L4 edge gives us cleanly.

## Terraform (`terraform/haproxy.tf`)

- `google_compute_address.haproxy[*]` — one EXTERNAL static IP per VM (`var.haproxy.count`, default 2).
- `google_compute_instance.haproxy[*]` — edge-subnet VMs (`10.23.30.21`, `.22`), tag `haproxy`, shielded VM.
- Outputs: `haproxy_ips` (public, for DNS) and `haproxy_internal_ips`.
- Firewall (`terraform/firewall.tf`): `edge_allowed_cidrs → haproxy :443`, `IAP → haproxy :8404` (stats),
  `edge subnet → rke2-agent :30000-32767` (NodePorts).

## Config (`ansible/roles/haproxy` + `ansible/group_vars/haproxy.yml`)

`haproxy.cfg` is rendered from the **service map** in `group_vars/haproxy.yml` and validated
(`haproxy -c`) before it replaces the running config. Structure:

```haproxy
frontend ft_https
  bind *:443
  mode tcp
  tcp-request inspect-delay 5s
  tcp-request content accept if { req_ssl_hello_type 1 }   # wait for the full ClientHello (SNI)
  use_backend bk_chatapi   if { req.ssl_sni -m reg -i (^|.*\.)(api|apiclient)-onprem(-internal)?\.cometchat-cluster-2\.in$ }
  use_backend bk_websocket if { req.ssl_sni -m reg -i (^|.*\.)(ws|websocket)-onprem(-internal)?\.cometchat-cluster-2\.in$ }
  ... (exact-match rules for app/apimgmt/metrics/media/document-embed/whiteboard-embed/notifications) ...
  default_backend bk_extensions                            # extensions + feature hosts + document/whiteboard API

backend bk_chatapi
  mode tcp
  balance roundrobin
  server <agent-1> 10.23.20.21:30443 check                 # one server line per rke2_agent
  server <agent-2> 10.23.20.22:30443 check                 # (templated from the inventory group)
  server <agent-3> 10.23.20.23:30443 check
```

`stats` is served on `:8404` (HTTP, reachable only from IAP per the firewall).

## SNI → NodePort → Service map

The nodePorts here **must** match `k8s/edge-nodeports.yaml`. Source of truth: `group_vars/haproxy.yml`.

| Facing host(s) (SNI) | Backend | NodePort | k8s Service (`-edge`) | App port |
|---|---|---|---|---|
| `*.api-onprem`, `api-onprem`, `*.apiclient-onprem`, … (+`-internal`) | chatapi | **30443** | `chatapi-edge` | 8000 |
| `*.websocket-onprem`, `ws-onprem`, `websocket-onprem` (+`-internal`) | websocket | **30444** | `websocket-edge` | 8080 |
| `app` | dashboard | **30445** | `dashboard-edge` | 80/443 (nginx) |
| `apimgmt` | mgmtapi | **30446** | `mgmtapi-edge` | 9000 |
| `metrics-onprem` | analytics | **30447** | `analytics-edge` | 8080 |
| `media/data/files-onprem`, `*.media-onprem` | seaweedfs-edge | **30449** | `seaweedfs-edge-np` | filer 8333 |
| `document-embed-onprem` | document-embed | **30450** | `document-embed-edge` | 9001 |
| `whiteboard-embed-onprem` | whiteboard | **30451** | `whiteboard-edge` | 9000 |
| `notifications-onprem` | notificationscore | **30452** | `notificationscore-edge` | 3100 |
| **everything else** (extensions-onprem, `*.extensions-onprem`, stickers/polls/link-preview/thumbnail-generator/document/whiteboard-onprem) | extensions | **30448** | `extensions-edge` | 5000 |

**Internal-only** services (metrics-pro, moderationservice/`rule-onprem`, globalwebhooks/`webhooks-onprem`,
service-search, visual-chat-builder, ai-agent-service) have **no HAProxy backend and no public DNS** — they
are reached east-west via CoreDNS only.

## High availability

- **Active-active**: both VMs serve; DNS round-robins across both public IPs. Losing one VM drops ~half of
  new connections until DNS/clients retry the other IP; existing connections on the surviving VM are fine.
- Each backend `server` has an L4 `check` — a dead agent node is taken out of rotation automatically.
- **Future upgrade** (documented, not enabled): a single stable **VIP via keepalived** across the 2 VMs if
  you prefer one IP over DNS round-robin. Round-robin is simpler and needs no shared L2, so it's the default.

## Operate

```bash
./deploy.sh haproxy          # (re)render + apply haproxy.cfg on both VMs (idempotent, validated)
# stats (via an IAP tunnel to a haproxy VM):
gcloud compute start-iap-tunnel <prefix>-haproxy-1 8404 --local-host-port=localhost:8404 --zone <zone>
open http://localhost:8404/stats     # all bk_* backends should be UP
# prove SNI routing + that the pod (not the edge) serves the cert:
openssl s_client -servername api-onprem.cometchat-cluster-2.in -connect <haproxy-ip>:443 </dev/null | openssl x509 -noout -issuer -subject
```

## Gotchas

- **Add a facing service** = add a row to `group_vars/haproxy.yml` **and** a NodePort Service to
  `k8s/edge-nodeports.yaml` with the **same** nodePort, then `./deploy.sh edge haproxy`.
- **SNI is required.** Non-SNI TLS clients hit `default_backend` (extensions). All CometChat clients send SNI.
- **`answer auto` is a CoreDNS concern, not HAProxy** — HAProxy is L4 and never sees the HTTP Host; the
  appId in the Host header is preserved end-to-end because HAProxy doesn't touch the payload.
