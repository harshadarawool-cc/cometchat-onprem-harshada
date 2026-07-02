# Networking — FQDN model, split-horizon DNS, per-pod TLS, edge routing

> How traffic flows. Companions: [HAPROXY-EDGE](HAPROXY-EDGE.md), [INTERNAL-CONNECTIONS](INTERNAL-CONNECTIONS.md),
> [DNS-RECORDS](DNS-RECORDS.md), [SERVICES](SERVICES.md). Derived from the colleague's `K8S-NETWORKING-GUIDE.md`,
> adapted from the LB edge to the HAProxy edge.

## 1. Everything is an FQDN, and each FQDN answers twice

CometChat services address each other (and the SDK addresses the backend) by **hostname, never by
pod/ClusterIP** — e.g. `api-onprem.<domain>`, `ws-onprem.<domain>`, and the appId-scoped
`<appId>.api-onprem.<domain>` (the SDK literally builds URLs from the appId subdomain). The core trick is
**split-horizon DNS**: the same hostname resolves differently depending on who asks.

```
                 api-onprem.cometchat-cluster-2.in
                /                                  \
  OUTSIDE (browser / mobile SDK)          INSIDE the cluster (service → service)
  public DNS → HAProxy public IPs         CoreDNS rewrite → chatapi ClusterIP
  → TLS SNI → nodePort → pod sidecar      → destination pod sidecar :443
  (north-south)                           (east-west; never hairpins out)
```

## 2. North-south (outside → in) — HAProxy SNI passthrough

Public DNS points every **base host** at **both HAProxy IPs** (round-robin). HAProxy reads the TLS **SNI**
and forwards the raw stream to a **per-service NodePort** (30443–30452); kube-proxy lands it on the pod,
whose **nginx sidecar terminates the wildcard cert on :443**. Full SNI→NodePort table:
[HAPROXY-EDGE](HAPROXY-EDGE.md). TLS terminates **in the pod**, never at the edge.

## 3. East-west (in → in) — CoreDNS split-horizon, DIRECT to Service

`k8s/coredns-direct.yaml` (a `coredns-custom` ConfigMap RKE2 imports) rewrites each on-prem FQDN
**straight to its backing Service** `<svc>.cometchat.svc.cluster.local`, then re-resolves the cluster
name via CoreDNS's own kubernetes plugin (`forward . 127.0.0.1:53`). So an internal call to
`https://rule-onprem.<domain>` resolves to the moderationservice ClusterIP and terminates at **that pod's**
`:443` sidecar — verified HTTPS that never leaves the VPC.

**Four rule shapes** (rendered with the real domain by `deploy.sh phase_coredns`):

```
# 1) per-app WILDCARD + bare + -internal twin (many appIds → one Service). answer auto keeps the appId.
rewrite name regex (.*)\.api-onprem\.<domain_re> chatapi.cometchat.svc.cluster.local answer auto
rewrite name regex (.*)\.api-onprem-internal\.<domain_re> chatapi.cometchat.svc.cluster.local answer auto
rewrite name exact api-onprem.<domain> chatapi.cometchat.svc.cluster.local
rewrite name exact api-onprem-internal.<domain> chatapi.cometchat.svc.cluster.local

# 2) regional EXACT (extensions feature hosts, data-tier)
rewrite name exact rule-onprem.<domain>          moderationservice.cometchat.svc.cluster.local
rewrite name exact webhooks-onprem.<domain>      globalwebhooks.cometchat.svc.cluster.local
rewrite name exact notifications-onprem.<domain> notificationscore.cometchat.svc.cluster.local

# 3) per-app wildcard, NO region (AI agent — HTTP-only pod, no sidecar)
rewrite name regex (.*)\.ai-agent-service\.<domain_re> ai-agent-service.cometchat.svc.cluster.local answer auto

# 4) data tier → seaweedfs-edge (:443 TLS front, NOT the plain :8333 filer alias)
rewrite name exact media-onprem.<domain>  seaweedfs-edge.cometchat.svc.cluster.local
```

**Two things that bite (both handled):**
- **`answer auto`** on every wildcard rule — returns the reply under the *original* queried name, so the
  app's Host-based appId routing still works. Without it, `<appId>` host routing 500s.
- **`-internal` twins** — some east-west calls target `<appId>.api-onprem-internal.<domain>` (e.g. ai-agent
  `createBot`). A missing `-internal` rewrite → NXDOMAIN → the caller 500s. Every east-west base host has its
  `-internal` twin.

## 4. Per-pod nginx TLS sidecar

Every **facing** pod (and every east-west HTTPS target) runs an `nginx:alpine` sidecar that terminates the
wildcard cert (`wildcard-tls`) on `:443` and proxies to the app on `127.0.0.1:<port>`. Source of the
pattern: `k8s/nginx-tls-sidecar.snippet.yaml`. Load-bearing directives:

```nginx
server {
  listen 80; listen 443 ssl; server_name _;              # wildcard cert; {appId} stays in Host
  ssl_certificate /etc/nginx/ssl/tls.crt; ssl_certificate_key /etc/nginx/ssl/tls.key;
  underscores_in_headers on;      # CRITICAL — keep app_secret / api_key (nginx drops underscore headers by default)
  ignore_invalid_headers off;     # forward EVERY header verbatim
  location / {
    proxy_pass http://127.0.0.1:<APP_PORT>;
    proxy_set_header Host $host;             # preserve appId.api-onprem.domain for routing
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header Expect "";              # drop Expect:100-continue → avoids 417 on app-create
    # websocket / editors add: proxy_http_version 1.1; Upgrade/Connection; proxy_read_timeout 86400s;
  }
}
```

- **`underscores_in_headers on;`** — CometChat passes auth/appId headers with underscores; nginx silently
  drops them by default → the app sees missing auth → 401/500 → surfaces in the browser as a phantom "CORS"
  error. This one line fixes a large share of fake CORS.
- **`:80` does NOT 301→https** — a redirect makes HTTP clients drop `Authorization` (RFC 7231), silently
  breaking east-west auth. East-west HTTP rides the encrypted pod network.

Which pods have a sidecar: all facing apps (chatapi, mgmtapi, dashboard, analytics, extensions,
notificationscore, websocket, document-embed, whiteboard, seaweedfs-edge) **and** internal HTTPS targets
(metrics-pro, moderationservice, globalwebhooks, service-search, visual-chat-builder). **HTTP-by-design, no
sidecar:** `ai-agent-service` and `clamav` (the app builds `http://` URLs; kept plaintext on the pod network).

## 5. Public DNS (transitive)

Only **base hosts** get `A` records → **both** HAProxy IPs (round-robin). Everything else is a **CNAME** onto
a base host, so on rebuild you update ~10 A records and every CNAME follows. Internal-only hosts get **no
public DNS**. Full record set + `dns-point.sh` behaviour: [DNS-RECORDS](DNS-RECORDS.md).

## 6. `-onprem` (API) vs `-embed-onprem` (iframe) — the CORS trap

For document & whiteboard there are **two** hosts: `document-onprem`/`whiteboard-onprem` → **extensions**
(the `/v1/create` API, returns id + CORS headers) and `document-embed-onprem`/`whiteboard-embed-onprem` →
**document-embed / whiteboard** (the editor iframe). Hitting `/v1/create` on the *embed* host returns 404
with no CORS header → the browser blames CORS. Always match host ↔ backend.

## 7. CORS / 503 debugging checklist

A browser "CORS error" is almost always a masked 4xx/5xx (the backend errored *before* its CORS middleware,
or the request hit the wrong backend). **curl the endpoint directly and read the real status.**

| Symptom | Likely cause | Check / fix |
|---|---|---|
| "CORS error" | masked 500 (licence/boot) or wrong routing target | `curl -ik https://<host>/…`; read real status |
| 404 that looks like CORS | `-onprem` API vs `-embed-onprem` iframe mixed up | §6 — point each host at its backend |
| 503 (all upstreams down) | CoreDNS can't resolve the Service, or sidecar/pod not Ready | `kubectl -n cometchat get pods`; `nslookup` the FQDN from a pod; HAProxy `:8404/stats` |
| east-west 500 on `*-internal` | missing `-internal` CoreDNS rewrite | add the `-internal` twin (§3) |
| lost auth / 401 as CORS | `underscores_in_headers` off | ensure it's `on` on the sidecar (§4) |
| edge host unreachable | DNS A not pointing at HAProxy IPs, or backend DOWN | `dig +short <host>`; HAProxy `:8404/stats` |

## Summary

| Layer | This build (HAProxy edge) |
|---|---|
| Edge | 2 HAProxy VMs, L4 SNI passthrough → per-service NodePorts (30443–30452) |
| Public DNS | round-robin A across both HAProxy IPs + transitive CNAMEs |
| Internal DNS | CoreDNS split-horizon, **direct-to-Service** (`coredns-custom`) |
| Service type | facing = ClusterIP **+ NodePort overlay**; internal = ClusterIP only |
| TLS | per-pod nginx sidecar (wildcard cert); edge is passthrough (no TLS there) |
| Headers | `underscores_in_headers on`, `ignore_invalid_headers off`, `Host` preserved, `:80` no-redirect |
