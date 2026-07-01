# Step 1 — Networking Plan (REVISED: internal HTTPS end-to-end, like Aryan)

Status: **PLAN for review. Nothing applied.** Reflects your decisions: single-zone/1-master now,
**managed GCP LB** edge (not HAProxy), **internal traffic on HTTPS like Aryan**, `notifications-onprem`
public. Domain `cometchat-cluster-2.in`, region `onprem`, firewall **inbound-closed / outbound-open**,
**no app patching** (a sidecar is a separate container — allowed; app images run as-is). Built from Aryan's
guide + coredns role and two analyze→adversarially-verify passes (27 verified risks total).

---

## 0. The model you asked for
**Every hop terminates TLS at the destination pod's nginx sidecar — internal *and* external.** No plaintext
inside the cluster except a few HTTP-by-design services. This is Aryan's per-pod-TLS model, realized on our
single managed GCP LB.

- **East-west (internal):** caller → `https://<host>.cometchat-cluster-2.in` → **CoreDNS rewrites the name
  straight to the backing Service** → that pod's **nginx TLS sidecar :443** → app. No shared-ingress detour.
- **North-south (public):** client → **single GCP managed L4 LB** (reserved IP) → pod TLS sidecar → app.
  (Edge sub-choice in §5 — one small decision left.)

This is a real change from today: our cluster currently terminates all TLS at the shared ingress and speaks
**plaintext** pod-to-pod. That's the accumulated shortcut we're replacing.

---

## 1. Per-pod TLS sidecar rollout (the bulk of the work — all config, no app patches)

Add an `nginx:alpine` sidecar (Aryan's block: `listen 80; listen 443 ssl; server_name _;`
`ssl_certificate /etc/nginx/ssl/tls.crt`; `underscores_in_headers on; ignore_invalid_headers off;`
`proxy_set_header Host $host; X-Forwarded-Proto https; Expect "";` `client_max_body_size 50M`;
`location = /nginx-health`) mounting secret **`wildcard-tls`**, proxying to the app on `127.0.0.1:<port>`.
Add `{name: https, port: 443, targetPort: 443}` to each Service. **The app container is untouched.**

| Pod | App port | Sidecar today | Action | Notes |
|---|---|---|---|---|
| chatapi | 8000 (octane) | :80 only | **add :443 block** to existing ConfigMap | REST, no ws |
| mgmtapi | 9000 (fastcgi) | :80 only | **add :443 block** (keep fastcgi) | PHP-FPM |
| dashboard | nginx SPA | :80 only | **add :443 block** in same nginx, keep `sub_filter` data-host rewrite | do NOT add 2nd container |
| websocket | 8080 | none | **new sidecar** + Upgrade/Connection + `proxy_read_timeout 86400s` | realtime |
| moderationservice | 3000 | none | new sidecar | |
| globalwebhooks | 3006 | none | new sidecar | |
| notificationscore | 3100 | none | new sidecar | public + east-west |
| service-search | 3000 | none | new sidecar | |
| analytics | 8080 | none | new sidecar | Service name is **`analytics`** (not `analytics-api`) |
| metrics-pro | 3003 | none | new sidecar | |
| extensions | 5000 | none | new sidecar | |
| visual-chat-builder | 3000 | none | new sidecar | |
| document-embed | 9001 | none | new sidecar + ws-upgrade | editor iframe |
| whiteboard | 9000 | none | new sidecar + ws-upgrade | editor iframe |
| seaweedfs | 8333 (S3) | none | new sidecar **or** keep `media/data/files-onprem` at ingress | `SECURED_AWS_ENDPOINT=https://media-onprem` |

**Deploy-layer reality (verified):** `deploy.sh` applies **raw** `k8s/*.yaml` (+ `deploy-node-apps.py` for the
node services) — the Helm `_app.tpl` is dead code. So the sidecar goes into the **raw manifests + the node-app
generator + one shared sidecar snippet**, not the Helm chart.

### HTTP-by-design — stay plaintext, get NO TLS sidecar / no cert SAN
- `chatapi → http://{appId}.ai-agent-service.<domain>` (ai-agent, app builds an `http://` URL — forcing HTTPS
  would require patching the app) → CoreDNS rewrites the name, target pod stays `:80` (port 4002).
- `moderationservice → http://test.antivirus.<domain>` (clamav) → `:80`.
- Raw in-cluster names (not customer FQDNs, never hit the sidecar/CoreDNS-domain path): `http://seaweedfs.cometchat:8333`
  (server-side S3 PUT), `http://opensearch-real...:9200`, `http://ollama...:11434`, mailpit, datastores.

---

## 2. CoreDNS — direct-to-Service split-horizon (done properly)

Replace the current single-`template`→one-ingress-IP with Aryan's `rewrite ... answer auto` map, retargeted to
**our** namespace `cometchat` and **our** Service names. Reconcile-safe RKE2 HelmChartConfig/Corefile.

```
# per-app WILDCARD: regex + answer auto (keeps appId in Host) + bare exact + -internal twin
*.api-onprem / api-onprem / *.api-onprem-internal / api-onprem-internal   → chatapi.cometchat.svc.cluster.local
*.apiclient-onprem (+bare +-internal twin)                                → chatapi
*.websocket-onprem (+bare +-internal twin)  ·  ws-onprem                   → websocket
# flat/regional exact
rule-onprem→moderationservice · webhooks-onprem→globalwebhooks · notifications-onprem→notificationscore
internal-search-onprem→service-search · internal-vcb-onprem→visual-chat-builder · metrics-pro-onprem→metrics-pro
metrics-onprem→analytics · app→dashboard · apimgmt→mgmtapi
extensions-onprem/*.extensions-onprem/stickers/polls/link-preview/thumbnail-generator/document/whiteboard-onprem→extensions
document-embed-onprem→document-embed · whiteboard-embed-onprem→whiteboard
# data tier (ns cometchat, Service seaweedfs:8333 — NOT seaweedfs-edge)
media-onprem/*.media-onprem/data-onprem/files-onprem→seaweedfs
# HTTP-only (answer auto, but target stays :80, no TLS)
*.ai-agent-service / ai-agent-service → ai-agent-service   ·   test.antivirus → clamav
```

Three things that must be right (verified as the exact traps): **`answer auto`** on every wildcard (or appId
Host-routing 500s) · **`-internal` twins present** (images build them; missing = NXDOMAIN → 500) · **our real
names** — `cometchat` ns, `seaweedfs:8333`, `analytics` (copying Aryan's `cometchat-app`/`seaweedfs-edge`/
`analytics-api` = NXDOMAIN).

---

## 3. Certificate — switch to a domain-wide wildcard

Keep the cert-manager **Route53 DNS-01** issuer (inbound-closed-safe). But because every pod now presents the
cert for whatever host is asked (`server_name _`), the cert must cover **all** internal hosts. Ship:

```
cometchat-cluster-2.in                       # apex / CN
*.cometchat-cluster-2.in                      # ALL single-label hosts (rule-onprem, webhooks-onprem, ws-onprem, app, apimgmt, media-onprem, metrics-*, internal-*, …)
*.api-onprem.cometchat-cluster-2.in           # 2-label appId hosts — a domain wildcard does NOT cover these
*.apiclient-onprem.cometchat-cluster-2.in
*.websocket-onprem.cometchat-cluster-2.in
*.extensions-onprem.cometchat-cluster-2.in
*.media-onprem.cometchat-cluster-2.in
# (+ *.api-onprem-internal etc. only if we wire the -internal twins)
```

- **CA trust:** it's a public Let's Encrypt cert → every image's system trust store already trusts it → **no
  `NODE_EXTRA_CA_CERTS`/`CURL_CA_BUNDLE` needed** (Aryan runs zero CA envs). Add per-service *only* if a caller
  throws a verify error.
- **cert-manager must actually be installed + given the DNS-01 recursive-nameserver flags** on the controller
  (`--dns01-recursive-nameservers=8.8.8.8:53,1.1.1.1:53` + `--dns01-recursive-nameservers-only`) and the
  `route53-credentials` secret — today `deploy.sh` only ships a self-signed cert and the flag is a wrong-syntax
  comment. Add a deploy gate so the rebuild can't "complete" on a self-signed cert.
- **Edge IP re-point:** reserve a **persistent static IP** (survives teardown) so public A records never need
  re-pointing — kills Aryan's #1 rebuild breakage. (You chose this.)

---

## 4. Firewall (inbound-closed / outbound-open) — unchanged from the confirmed design
GCP default-deny; keep only: **(1)** VPC-internal east-west (10.20.10/20/30.0/24), **(2)** IAP→22 all VMs,
**(3)** IAP→6443 masters, **(4)** GCP health-check ranges→agents **443**, **(5)** public→agents **443 only**.
Drop tcp **80** at the edge + LB (DNS-01 ⇒ no public :80). Egress stays open (Cloud NAT); the commented
deny-egress block is **not** a safe one-line flip (missing 10.42/10.43 + ECR allowlist) — I'll fix that template
now so a future lockdown is safe.

---

## 5. One decision left — the north-south edge
East-west is settled (per-pod TLS + direct CoreDNS). For **north-south** on the single managed LB, pick how
facing TLS terminates:

- **Option A — full end-to-end (max Aryan parity):** ingress-nginx in **SSL-passthrough** → TLS terminates at
  the pod for external too. One LB, one IP, TLS never terminates off-pod. *Cost:* ingress becomes a pure **SNI
  router** (per-host Ingress rules become SNI rules; appId still routes because each SNI base maps 1:1 to one
  Service and the appId rides the encrypted Host header), and it **loses L7 annotations** (`whitelist-source-range`,
  body-size) — we lean on the firewall + no-public-DNS instead. Single-controller, so a passthrough misconfig can
  black-hole all north-south → careful rollout.
- **Option B — hybrid (recommended, lower risk):** ingress-nginx keeps **terminating** north-south TLS (Host-routing
  + annotations intact, plus the `enable-underscores-in-headers` fix) and forwards to the pod sidecar's `:80`; **east-west
  still terminates at the pod `:443`.** Internal traffic is HTTPS end-to-end (what you asked for); external terminates
  at the ingress exactly as a managed-LB setup normally does. Least blast radius; the pod sidecar's dual `:80/:443`
  block (Aryan's) serves both paths.

**✅ DECIDED (2026-07-01): Option B (hybrid).** ingress-nginx terminates north-south TLS (Host-routing + L7
annotations + `enable-underscores-in-headers` fix intact) and forwards to the pod sidecar `:80`; east-west
terminates HTTPS at the pod `:443`. The pod sidecar's dual `:80/:443` block serves both. Can move to A later.

### Also flag (can't be solved config-only)
The dashboard's data-plane redirect hosts `api.cometchat.com` / `*.api-onprem.cometchat.com` are in a zone we
**don't** control, so Let's Encrypt can't issue a cert for them — they must keep terminating at the shared ingress
(with `wildcard-tls`) or you supply a `cometchat.com` cert out-of-band. Not a blocker; just noting it.

---

## 6. Rollout order (so nothing black-holes)
1. Ship the **domain-wide wildcard cert** (cert-manager installed + DNS-01 flags + route53 secret).
2. Add **:443 sidecars + Service :443** to every east-west pod (build only — no traffic change yet; keep :80 up).
3. Flip **CoreDNS** to direct-to-Service (`answer auto` + `-internal` twins); verify in-pod `curl -k` each host.
4. **(Option A only)** convert the edge to ssl-passthrough; verify north-south; keep a revert bundle.
5. Firewall to 443-only edge; verify IAP + health-checks + an external HTTPS probe before re-pointing DNS.

Every item is config/infra/cert/CoreDNS/sidecar — **no app image changes**. After you okay this (and pick the
§5 edge option), I move to **Step 2 (DB seeding)** — still planning, no cluster changes.
