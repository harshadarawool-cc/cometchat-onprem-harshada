# Network hardening — moving to the Azure cluster-4 (production-grade) model

> Goal: make our GCP RKE2 networking match the **production posture of the Azure
> `cometchat-cluster-4` deployment** (the Route53 records the user shared), without the
> Azure-specific multi-IP cost. Decisions locked with the user 2026-06-24.
>
> **Realization:** keep the single GCP edge LB + ingress-nginx, but adopt cluster-4's three
> production traits: **(1) per-host public DNS (no domain-wide wildcard), (2) explicit-SAN
> certs (no bare `*.cometchat-cluster-2.in`), (3) a tight public set.**

---

## 1. Locked public / internal split

| Public (internet-reachable) | Internal-only (app→app via CoreDNS) |
|---|---|
| chatapi — `api-onprem`, `apiclient-onprem` (+ `*.api-onprem`, `*.apiclient-onprem`) | globalwebhooks — `webhooks-onprem` (fires *outbound* only) |
| websocket — `websocket-onprem` (+ `*.websocket-onprem`) | notificationscore — `notifications-onprem` |
| dashboard — `app` | moderationservice — `rule-onprem` |
| mgmtapi — `apimgmt` | service-search — `internal-search-onprem` |
| extensions — `extensions-onprem` (+ `*.extensions-onprem`) | visual-chat-builder — `internal-vcb-onprem` |
| seaweedfs media — `media-onprem`, `files-onprem` | metrics-pro — `metrics-pro-onprem` |
| analytics — `metrics-onprem` | mailpit — `mail` |
| calls-relay — `rtc-onprem`, `calls-relay-onprem` | (datastores already internal) |

This matches cluster-4's published set exactly (it also keeps webhooks/notifications/moderation/search/vcb/metrics-pro/mailpit off public DNS).

---

## 2. Why this is safe — the key mechanism

`app→app` calls (e.g. chatapi → `https://rule-onprem.cometchat-cluster-2.in`) do **not** use public DNS. The in-cluster CoreDNS Corefile answers **every** `cometchat-cluster-2.in` name with the internal ingress ClusterIP:

```
cometchat-cluster-2.in:53 {
    template IN A { answer "{{ .Name }} 30 IN A 10.43.230.223" }   # rke2-ingress-nginx-internal
}
```

So an app's request goes: app → CoreDNS → `10.43.230.223` (internal ingress) → ingress rule → backend service. **Public Route53 is only consulted by external clients.** Therefore we can remove an internal service's *public* DNS and it keeps working internally. This is the whole reason the migration is low-risk.

---

## 3. Current state (the 3 gaps vs cluster-4)

| Gap | Now | cluster-4 (target) |
|---|---|---|
| DNS | one `*.cometchat-cluster-2.in` **wildcard** → LB (everything resolves, incl. internal) | **per-host A records**; only public hosts published |
| Cert | one **bare `*.cometchat-cluster-2.in`** LE wildcard | **explicit per-host SANs** + only scoped per-app wildcards |
| Public surface | 15 services on one shared ingress | **8** public; rest internal-only |

---

## 4. Target — exact records & config

### 4a. Route53 (public DNS) — replace the wildcard with per-host records
Zone `Z04640112BJ8TJHK3I2RI` (`cometchat-cluster-2.in`), all → edge LB `35.200.134.182`.

**CREATE (A → 35.200.134.182):** `app`, `apimgmt`, `api-onprem`, `apiclient-onprem`, `websocket-onprem`, `extensions-onprem`, `media-onprem`, `files-onprem`, `metrics-onprem`, `rtc-onprem`, `calls-relay-onprem`
**CREATE (scoped wildcard CNAME → its base):** `*.api-onprem`, `*.apiclient-onprem`, `*.websocket-onprem`, `*.extensions-onprem`
**DELETE:** the domain-wide `*.cometchat-cluster-2.in` wildcard A
**DO NOT create:** `webhooks-onprem`, `notifications-onprem`, `rule-onprem`, `internal-search-onprem`, `internal-vcb-onprem`, `metrics-pro-onprem`, `mail`

> Note: the per-host `_acme-challenge.<host>` TXT records are created/managed automatically by cert-manager — don't hand-create them. (cluster-4's TXT records are exactly these.)

### 4b. Certificate — explicit SANs, no bare wildcard
Edit `k8s/cert-manager-issuer.yaml` `Certificate.dnsNames`. Replace:
```
- cometchat-cluster-2.in
- "*.cometchat-cluster-2.in"          # ← DROP the bare wildcard
```
with the **explicit list** (public + internal named hosts, so the internal ingress also has a real, trusted cert; only the per-app levels stay wildcard):
```
# public
- app.cometchat-cluster-2.in
- apimgmt.cometchat-cluster-2.in
- api-onprem.cometchat-cluster-2.in
- apiclient-onprem.cometchat-cluster-2.in
- websocket-onprem.cometchat-cluster-2.in
- extensions-onprem.cometchat-cluster-2.in
- media-onprem.cometchat-cluster-2.in
- files-onprem.cometchat-cluster-2.in
- metrics-onprem.cometchat-cluster-2.in
- rtc-onprem.cometchat-cluster-2.in
- calls-relay-onprem.cometchat-cluster-2.in
# internal (no public A record, but app→app still needs a trusted cert)
- webhooks-onprem.cometchat-cluster-2.in
- notifications-onprem.cometchat-cluster-2.in
- rule-onprem.cometchat-cluster-2.in
- internal-search-onprem.cometchat-cluster-2.in
- internal-vcb-onprem.cometchat-cluster-2.in
- metrics-pro-onprem.cometchat-cluster-2.in
- mail.cometchat-cluster-2.in
# scoped per-app wildcards (unavoidable for {appId}. SDK pattern — these match cluster-4)
- "*.api-onprem.cometchat-cluster-2.in"
- "*.apiclient-onprem.cometchat-cluster-2.in"
- "*.websocket-onprem.cometchat-cluster-2.in"
- "*.extensions-onprem.cometchat-cluster-2.in"
```
This keeps one secret (`wildcard-tls`) that apps already trust (public LE CA — **no app CA-mount changes**), but it is **explicit per-host**, not a bare domain wildcard. ~22 SANs (LE allows 100). The internal hosts get a real cert via DNS-01 (`_acme-challenge.<host>` TXT) **without** a public A record, so they're certificate-valid for app→app yet unreachable from the internet.

### 4c. Ingress — split public vs internal, lock internal to in-cluster sources
Split the single `cometchat-edge` Ingress into two (same controller, same `wildcard-tls`):
- **`cometchat-edge` (public):** rules for the 8 public services only.
- **`cometchat-internal` (internal):** rules for the 7 internal services, annotated:
  ```
  nginx.ingress.kubernetes.io/whitelist-source-range: "10.42.0.0/16,10.43.0.0/16,10.20.0.0/16"
  ```
  (pods `10.42`, services `10.43`, VM subnets `10.20`). Internal source IPs allowed → app→app works; external client IP (preserved by the L4 LB) → **403**. Belt-and-suspenders on top of "no public DNS."

---

## 5. Migration order (each phase verifies before the next; all reversible)

**Phase 1 — DNS (biggest win, lowest risk).** Apply 4a. Internal services become undiscoverable from the internet; app→app unaffected (CoreDNS). *Verify:* `dig +short rule-onprem.… @8.8.8.8` → NXDOMAIN; public hosts still resolve; in-cluster app→app calls still 200. *Rollback:* re-add the wildcard A.

**Phase 2 — Cert (drop bare wildcard).** Apply 4b; wait for cert-manager to reissue `wildcard-tls`. *Verify:* `kubectl describe certificate cometchat-wildcard` Ready=True; `openssl s_client -servername api-onprem.… -connect 35.200.134.182:443` shows the explicit-SAN cert; app→app https still 200 (apps trust LE CA). *Rollback:* restore the previous dnsNames.

**Phase 3 — Ingress split + whitelist.** Apply 4c. *Verify:* external `curl -H 'Host: rule-onprem.…' https://35.200.134.182` → **403**; in-cluster `curl https://rule-onprem.…` from a pod → 200; public hosts unchanged. *Rollback:* re-merge into one Ingress.

**Phase 4 — later, when client model known.** Lock `edge_allowed_cidrs` (if clients are a known network), pair with the egress deny-all lockdown and secrets-encryption (the P0 items in NETWORK-AND-SECURITY.md §6).

---

## 6. Open items to confirm at execution

- **`cometchat.com` data-plane hosts** (`api.cometchat.com`, `apiclient-onprem.cometchat.com`, `*.api-onprem.cometchat.com`): we can't get an LE cert for `cometchat.com` (not our Route53 zone). The dashboard nginx `sub_filter` already rewrites `api.cometchat.com → api-onprem`, so these ingress rules may be legacy. **Verify** the dashboard rewrite covers all client paths; if some SDK path truly needs `cometchat.com`, keep those rules on a small self-signed cert. Otherwise drop them.
- **How Route53 is edited:** cert-manager already writes to zone `Z04640112BJ8TJHK3I2RI` with the `staging` AWS keys. Phase 1 record changes can use `aws route53 change-resource-record-sets` with the same profile, or be added to Terraform if/when DNS is moved under IaC.
- **Per-app wildcard certs via DNS-01** already work today (the current cert has `*.api-onprem` etc.), so Phase 2 doesn't add new challenge types.

---

*This plan changes DNS, certs, and ingress — all production-affecting and (DNS) outward-facing.
Execute phase by phase with the verification gates above; do not batch them.*
