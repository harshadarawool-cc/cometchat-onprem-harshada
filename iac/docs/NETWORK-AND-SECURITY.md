# CometChat On‑Prem (GCP RKE2) — Network & Security Guide

> One place that answers four questions in plain language:
> 1. **How does traffic flow** through this cluster (in, sideways, out)?
> 2. **What certificates / keys do we need** and what is each for?
> 3. **What do our firewall rules mean** — what traffic do we actually expect?
> 4. **Is this correct, and what should we improve** on networking & security?
>
> Scope: the new `cometchat-onprem-*` infra in GCP project `onprem-499712`, region `asia-south1`.
> Source of truth: `terraform/`, `k8s/`, `ansible/`. This doc is a readable summary — the `.tf`/`.yaml` files win if they ever disagree.

---

## 0. TL;DR (read this first)

**The design is sound. The hardening is half‑applied.**

The shape of the network is genuinely good for an on‑prem, data‑residency deployment:
- No VM has a public IP. The **only** way in is one GCP load balancer.
- Admin access (SSH, kubectl) is through **Google IAP**, not the open internet.
- Databases sit on their own private subnet, reachable only from inside the VPC.

But three controls that the design *intends* are **not switched on yet**, and they are exactly the ones that back up the "customer data must not leave the network" promise:

| # | Gap | Why it matters | Effort |
|---|-----|----------------|--------|
| **P0** | **Egress is still allow‑all** | The whole point of the project is data residency. Right now any pod can talk to any internet host. | Low — uncomment ready rules |
| **P0** | **Secrets are unencrypted in etcd** | DB passwords, AWS keys, JWT private key are base64 (not encrypted) at rest. | Low — one RKE2 flag |
| **P1** | **No Kubernetes NetworkPolicies** | Flat pod network: any pod can reach any other pod/DB. One compromised pod = lateral movement. | Medium |

Everything else (LB, certs, IAP, firewall ingress) is in good shape. Details and the full improvement list are in [§6](#6-security-assessment--whats-right-what-to-improve).

---

## 1. The big picture

**25 VMs, one private VPC, three subnets, zero public IPs, one front door.**

```
                                 INTERNET
                          (SDK clients, dashboard,
                           inbound webhooks)
                                    │  HTTPS 443 / HTTP 80
                                    ▼
                   ┌──────────────────────────────────┐
                   │   GCP Edge Load Balancer (L4 TCP) │  ◄── the ONLY public IP
                   │   reserved static IP, fwd 80+443  │      (terraform output edge_lb_ip)
                   └────────────────┬─────────────────┘
   ╔════════════════════════════════│════════════════════════════════════════════╗
   ║  VPC: cometchat-vpc            │           (every VM is private, no public IP) ║
   ║                                ▼                                              ║
   ║  edge subnet 10.20.30.0/24                                                    ║
   ║     └─ bastion .10  ── jump host, reachable by IAP SSH only                   ║
   ║                                                                               ║
   ║  cluster subnet 10.20.20.0/24                                                 ║
   ║     ├─ RKE2 masters .11+      (control plane / API 6443)                      ║
   ║     └─ RKE2 workers .21+      ◄── LB sends 80/443 here                        ║
   ║            └─ ingress‑nginx (hostPort 80/443)  ──►  app pods (ClusterIP)      ║
   ║                                    │ east‑west over private IPs               ║
   ║  data subnet 10.20.10.0/24         ▼                                          ║
   ║     mongo .11‑.13   kafka .31‑.33   mysql .41   tidb .51                      ║
   ║     redis  shared .21‑23 · analytics .24‑26 · prometrics .27‑29 · bullmq .61‑63║
   ║                                                                               ║
   ║  Cloud NAT ──────────────────────────────────────────►  controlled outbound  ║
   ╚═══════════════════════════════════════════════════════════════════════════════╝
                                    ▲
                                    │  SSH 22 + kubectl 6443, via Google IAP only
                                    │  (source 35.235.240.0/20)
                              Admins / Ansible
```

### The three subnets

| Subnet | CIDR | What lives here | Public IP? |
|--------|------|-----------------|------------|
| `cometchat-edge` | `10.20.30.0/24` | Bastion (jump box) | No |
| `cometchat-cluster` | `10.20.20.0/24` | RKE2 masters + workers, **all app pods** | No |
| `cometchat-data` | `10.20.10.0/24` | Mongo, Kafka, MySQL, TiDB, 4× Redis | No |

VM count: 1 bastion + 1 master + 3 workers + 3 mongo + 3 kafka + 1 mysql + 1 tidb + 12 redis (4 clusters × 3) = **25**.
Defined in `terraform/network.tf`, `rke2.tf`, `datastores.tf`, `bastion.tf`.

> **Key property:** because no VM has an external IP, outbound traffic can only leave through **Cloud NAT**, and inbound can only arrive through the **edge LB** or **IAP**. That gives us exactly two choke points to secure.

---

## 2. How traffic flows

There are three directions of traffic. Understand each separately.

### 2a. Inbound — internet → application pod

This is the path of a real request, e.g. `https://api-onprem.cometchat-cluster-2.in/v1/users`:

```
client
  │ 1. DNS: api-onprem.cometchat-cluster-2.in  ──►  edge LB public IP
  ▼
GCP Edge LB  :443
  │ 2. L4 TCP passthrough — NO TLS termination here.
  │    Picks a healthy worker (TCP health‑check on :443), forwards the raw stream.
  ▼
worker node  :443  (hostPort)
  │ 3. kernel/iptables hands :443 to the ingress‑nginx pod on that node
  ▼
ingress‑nginx  :443
  │ 4. TLS TERMINATES HERE. Uses the `wildcard-tls` secret (Let's Encrypt cert).
  │    Reads the Host header, matches the Ingress rule, picks the backend Service.
  ▼
Service (ClusterIP)  :80
  │ 5. kube‑proxy load‑balances to a pod behind the Service
  ▼
app pod
  │ 6a. PHP apps (chatapi, mgmtapi): nginx sidecar :80 → app :8000/:9000 (localhost)
  │ 6b. Node/Python apps: serve HTTP natively on :80 → app port (:3000/:3006/…)
  ▼
business logic runs, response returns the same way back out
```

**Why this design is good:** the LB is "dumb" (L4 TCP). All TLS, routing, and host rules live *inside* the cluster at ingress‑nginx, so we manage every certificate in Kubernetes and the LB never needs to know about them. TLS is encrypted end‑to‑end up to ingress‑nginx (the LB just forwards bytes).

**Host → Service routing** (from `k8s/ingress.yaml`, all backends are ClusterIP `:80` unless noted):

| Public hostname | Service | Purpose |
|-----------------|---------|---------|
| `app.cometchat-cluster-2.in` | dashboard | Customer web dashboard |
| `apimgmt.cometchat-cluster-2.in` | mgmtapi | Management / provisioning API |
| `api-onprem…` / `apiclient-onprem…` / `*.api-onprem…` | chatapi | Chat data API (per‑app via wildcard) |
| `websocket-onprem…` | websocket | Realtime WebSocket |
| `webhooks-onprem…` | globalwebhooks | Outbound event webhooks |
| `rule-onprem…` | moderationservice | Content moderation |
| `rtc-onprem…` / `calls-relay-onprem…` | calls-relay | Voice/video relay |
| `notifications-onprem…` | notificationscore | Push notifications |
| `metrics-pro-onprem…` | metrics-pro | Pro metrics |
| `internal-vcb-onprem…` | visual-chat-builder | Visual chat builder |
| `internal-search-onprem…` | service-search | Search API |
| `media-onprem…` / `files-onprem…` | seaweedfs :8333 | S3‑compatible object storage |
| `mail.cometchat-cluster-2.in` | mailpit :8025 | Dev mail catcher |

### 2b. East‑west — app pod → datastore

Apps reach databases by **private IP** on the data subnet. No traffic leaves the VPC. This is allowed by the single `internal` firewall rule (see [§3](#3-firewall-rules--what-we-allow-and-why)).

| Datastore | Address(es) | Port | Auth |
|-----------|-------------|------|------|
| MongoDB (rs0) | `10.20.10.11‑13` | 27017 | user/pass |
| Kafka (KRaft) | `10.20.10.31‑33` | 9092 | **none** (VPC‑private) |
| TiDB | `10.20.10.51` | 3306 | root |
| MySQL | `10.20.10.41` | 3306 | root |
| Redis — shared | `10.20.10.21‑23` | 6379 / sentinel 26379 | optional |
| Redis — analytics | `10.20.10.24‑26` | 6379 / 26379 | optional |
| Redis — prometrics | `10.20.10.27‑29` | 6379 / 26379 | optional |
| Redis — bullmq | `10.20.10.61‑63` | 6379 / 26379 | optional |
| OpenSearch / Qdrant / Ollama / Mailpit | in‑cluster `*.cometchat.svc` | 9200 / 6333 / 11434 / 1025 | varies |

> ⚠️ Note the auth column: Kafka has **no** auth and Redis auth is **optional**. Today their only protection is the network boundary. That's fine *if* the network boundary is tight — which is why NetworkPolicies ([§6](#6-security-assessment--whats-right-what-to-improve)) matter.

App‑to‑app calls (e.g. mgmtapi → chatapi) stay in‑cluster too, via Kubernetes Service DNS or split‑horizon DNS ([§5](#5-dns--split-horizon)). In‑cluster app‑to‑app traffic is **plain HTTP** (no mTLS) — acceptable on a private network, noted as a hardening option.

### 2c. Outbound — pod → internet (egress) and the data‑residency angle

All outbound traffic exits through **Cloud NAT** (`terraform/network.tf`). **Today egress is allow‑all** (GCP default), left open during build so nodes can pull container images (ECR), OS packages, and `get.rke2.io`.

This is the single biggest open item, because some app features genuinely call **external** services and that means **customer data leaves the network**:

| External endpoint | Used by | Data risk |
|-------------------|---------|-----------|
| `api.openai.com` | ai‑agent, moderationservice | **HIGH** — chat/content sent to OpenAI |
| `s3.us‑east‑2.amazonaws.com` (+ live AWS keys) | ai‑agent | **CRITICAL** — uploads to AWS |
| `sqs` / `lambda` `.us‑east‑2` | ai‑agent | HIGH |
| `api.firecrawl.dev`, `gateway.helicone.ai`, `api.notion.com` | ai‑agent | HIGH |
| `recordings-us…`, `rtcv5-us…` (Akamai) | calls‑relay, chatapi | HIGH — call media/recordings |
| `hooks.slack.com`, `hooks.zapier.com` | umc, mgmtapi | MEDIUM — customer‑defined webhooks |

**Required action for data residency:** flip egress to **deny‑all + allowlist**. The rules are already written (commented) in `terraform/firewall.tf` and gated behind `deploy/deploy.sh lockdown`. Any genuinely‑needed external host (e.g. ECR for image pulls) goes on the allowlist; AI/recording features that leak data must be **disabled or self‑hosted** unless the customer explicitly accepts them.

---

## 3. Firewall rules — what we allow and why

GCP denies all ingress by default. We deliberately open **exactly five** ingress rules. All live in `terraform/firewall.tf`. Here is what each one means in plain English and the traffic we *expect* through it:

| # | Rule | Direction | From (source) | To (target VMs) | Port(s) | What it's for / expected traffic |
|---|------|-----------|---------------|-----------------|---------|----------------------------------|
| 1 | `internal` | INGRESS | the 3 subnet CIDRs (`10.20.10/20/30.0/24`) | any VM in VPC | all tcp/udp/icmp | **East‑west.** Lets app pods reach databases and nodes talk to each other. This is what makes the cluster work internally. |
| 2 | `iap_ssh` | INGRESS | `35.235.240.0/20` (Google IAP) | any VM | tcp 22 | **Admin SSH** — only through Google IAP, never the open internet. Used by you + Ansible. |
| 3 | `iap_k8s_api` | INGRESS | `35.235.240.0/20` (Google IAP) | `rke2-server` (masters) | tcp 6443 | **kubectl** to the Kubernetes API, only through IAP. |
| 4 | `health_checks` | INGRESS | `35.191.0.0/16`, `130.211.0.0/22` (GCP) | `rke2-agent` (workers) | tcp 80,443 | **LB health probes** — GCP checking which workers are alive. |
| 5 | `edge_ingress` | INGRESS | `edge_allowed_cidrs` (**default `0.0.0.0/0`**) | `rke2-agent` (workers) | tcp 80,443 | **Public client traffic** — SDK clients, dashboard, inbound webhooks hitting the app. |

**Network tags → which VMs a rule hits** (`tags = [...]` on each instance):
- `rke2-server` = master/control‑plane VMs → rules 3
- `rke2-agent` = worker VMs (run ingress‑nginx) → rules 4, 5
- `bastion` = jump host; `datastore` + role (`mongo`/`redis`/`kafka`/`mysql`/`tidb`) on DB VMs (covered by rule 1 only)

**Reading the picture:** the internet can only ever reach **workers on 80/443** (rule 5). It can *never* reach a database, a master, or the bastion directly. Admins can only reach VMs via **IAP** (rules 2–3). Everything internal is rule 1.

### Egress rules — current vs. target

```
NOW (bootstrap):     pod ──► Cloud NAT ──► ANY internet host       (allow‑all)
TARGET (residency):  pod ──► [deny‑all egress]
                                ├─ allow → VPC subnets (always)
                                ├─ allow → ECR image ranges
                                └─ allow → explicit customer‑approved hosts only
```
The target rules are written and commented in `terraform/firewall.tf:93‑110`; enabling them is the `lockdown` step.

> One nuance on rule 5: `edge_allowed_cidrs` defaults to `0.0.0.0/0`. For a public chat SDK whose end‑users are everywhere, open ingress on 443 is *expected and usually necessary* — this is **not** the same problem as open egress. If this deployment instead serves a known set of client networks, tighten `edge_allowed_cidrs` to those ranges. Otherwise, defend it with rate‑limiting / WAF rather than CIDR (see [§6](#6-security-assessment--whats-right-what-to-improve)).

---

## 4. Certificates & keys — what we need and why

There are **four independent** crypto systems here. People conflate them; keep them separate:

| # | Name | Type | Issued by | Used by | Renewal |
|---|------|------|-----------|---------|---------|
| 1 | `wildcard-tls` | **Public TLS server cert** | Let's Encrypt (cert‑manager + Route53 DNS‑01) | ingress‑nginx (terminates HTTPS) | **Automatic** (cert‑manager, ~30d before expiry) |
| 2 | `wildcard-tls` mounted at mgmtapi | **Internal CA trust** (same cert, used to *verify*) | same as #1 | mgmtapi → validates HTTPS calls to chatapi | follows #1 |
| 3 | `jwt-keys` / `jwt-public` | **JWT signing keypair** (RSA‑2048, RS256) — *app auth, NOT TLS* | generated by `deploy.sh` (openssl) | chatapi/mgmtapi sign; websocket/analytics verify | static (regenerated only if deleted) |
| 4 | RKE2 control‑plane PKI | **Cluster TLS** (API server, etcd, kubelet) | RKE2 (self‑managed CA) | Kubernetes internals | **Automatic** (RKE2) |

### What you actually *need* (the public TLS chain)

This is the only cert that browsers/SDKs must trust:

```
Let's Encrypt (ACME prod)
   │  DNS‑01 challenge solved via AWS Route53 (zone Z04640112BJ8TJHK3I2RI, cometchat-cluster-2.in)
   ▼
cert‑manager  ClusterIssuer: letsencrypt-route53
   │  issues Certificate "cometchat-wildcard":
   │     CN cometchat-cluster-2.in + SANs *.cometchat-cluster-2.in,
   │     *.api-onprem…, *.apiclient-onprem…, *.websocket-onprem…, *.extensions-onprem…
   ▼
Kubernetes Secret  wildcard-tls   ◄── ingress‑nginx serves this on :443
```

Notes:
- A **self‑signed** wildcard (`openssl … -subj /CN=*.cometchat-cluster-2.in`, 825 days) is created by `deploy.sh` as a **bootstrap fallback** so HTTPS works before ACME completes. cert‑manager then **overwrites the same `wildcard-tls` secret** with the real Let's Encrypt cert. End state = trusted public cert. (Files: `k8s/cert-manager-issuer.yaml`, `deploy/deploy.sh`.)
- cert‑manager is patched with `--dns01-recursive-nameservers-only=8.8.8.8,1.1.1.1` so its self‑check bypasses the in‑cluster split‑horizon DNS that intercepts `cometchat-cluster-2.in`.
- **Prereqs that are NOT auto‑installed:** cert‑manager itself, and the `route53-credentials` secret (AWS key) in the `cert-manager` namespace. If those are missing, the cert stays self‑signed.

### JWT keys are not TLS

`jwt-keys` (private) signs API/auth tokens; `jwt-public` (`jwtrsakey.pem`) verifies them. RSA‑2048, RS256. This is **application authentication**, completely separate from the HTTPS certs. Don't mix them up when rotating.

### A legacy CA to clean up

`/.secrets/cc-cluster-1-ca.crt` (CN `cc-cluster-1.io`) is from the old domain and is **not mounted by anything**. Safe to remove once the new domain is confirmed stable.

---

## 5. DNS / split‑horizon

The data‑residency trick: apps keep their original public‑looking hostnames (e.g. `api-us.cometchat-cluster-2.in`, and legacy `api.cometchat.com`), but they must resolve to **in‑cluster services**, not to the public internet — so service‑to‑service traffic never leaves the VPC.

Two mechanisms are in play:
1. **Ingress + (intended) split‑horizon CoreDNS** — public hostnames map to ClusterIP services. The cert‑manager comment confirms CoreDNS is meant to intercept `cometchat-cluster-2.in` internally.
2. **nginx `sub_filter` rewrite** in the dashboard (`k8s/dashboard-nginx.yaml`) rewrites baked‑in hosts (`api.cometchat.com` → `api-onprem.cometchat-cluster-2.in`, and old `cc-cluster-1.io` → `cometchat-cluster-2.in`) in the served JS bundle.

> **Verify‑me:** the actual CoreDNS Corefile/HelmChartConfig override was **not found in the tracked `k8s/` tree** — it may be applied via Ansible at bootstrap or may not be committed. Confirm `kubectl -n kube-system get configmap rke2-coredns-rke2-coredns-custom -o yaml` shows the rewrite rules. If it's missing, in‑cluster calls to `*.cometchat-cluster-2.in` could resolve out to the public LB and hairpin (works, but not truly "internal"). This is worth nailing down for the residency guarantee.

External DNS for the public domain is real Route53 (`cometchat-cluster-2.in`), pointing the public hostnames at the edge LB IP.

---

## 6. Security assessment — what's right, what to improve

### ✅ What's already done well

- **No public IPs on any VM.** Only the LB is exposed. (`access_config` absent everywhere.)
- **Single, narrow front door.** L4 LB → workers on 80/443 only. TLS terminates in‑cluster.
- **Admin plane off the internet.** SSH (22) and kubectl (6443) only via Google IAP; needs `roles/iap.tunnelResourceAccessor` IAM.
- **GCP‑scoped health checks.** Only Google's documented ranges can probe workers.
- **Public TLS done properly.** Let's Encrypt wildcard via DNS‑01, auto‑renewing.
- **NAT logging on**, dynamic edge IP read from `terraform output` (no stale hardcoding).
- **Some pod hardening** already present on the newer Node apps (seccomp `RuntimeDefault`, `drop ALL` caps, `allowPrivilegeEscalation:false`, `runAsNonRoot`).

### ⚠️ What to improve (prioritised)

**P0 — do before handing over (directly tied to the data‑residency promise):**

1. **Lock down egress.** Flip to deny‑all + allowlist (`deploy/deploy.sh lockdown`; rules already in `terraform/firewall.tf`). Until this is on, the "data must not leave the network" guarantee is **not enforced**.
2. **Disable or self‑host the data‑leaking features.** OpenAI, AWS S3/SQS/Lambda, Firecrawl, Helicone, Notion, external recordings/RTC. Each is a hole in residency. Decide per‑feature with the customer; document what's accepted.
3. **Encrypt secrets at rest.** Today DB passwords, AWS keys, and the JWT private key sit base64 (not encrypted) in etcd. Enable RKE2 secrets encryption (`secrets-encryption: true` in the RKE2 server config / `EncryptionConfiguration`). One flag, big win.

**P1 — strongly recommended:**

4. **Add NetworkPolicies.** The pod network is currently flat — any pod can reach any pod and any database. Canal (the default CNI) enforces them. Start with a default‑deny in the `cometchat` namespace, then allow only the real edges (ingress‑nginx → app, app → its specific datastore). This contains a single compromised pod.
5. **Add real auth on datastores.** Kafka has none; Redis auth is optional; DBs reuse staging passwords. They rely entirely on the network today. Add SASL/ACLs (Kafka), `requirepass`/ACL (Redis), and rotate DB creds off the staging values.
6. **Even out pod security.** Several pods (dashboard, analytics, metrics‑pro, extensions, opensearch, ollama, mailpit, seaweedfs) have no securityContext; OpenSearch runs a `privileged` init container. Apply a namespace‑wide **Pod Security Standard** (`baseline`, aiming for `restricted`) and give every workload the same `drop ALL` / non‑root / no‑privilege‑escalation treatment the Node apps already have.

**P2 — defence in depth:**

7. **Confirm/commit the split‑horizon CoreDNS config** (see [§5](#5-dns--split-horizon)) so internal hostnames truly resolve in‑cluster.
8. **Protect the open ingress.** `edge_allowed_cidrs=0.0.0.0/0` is expected for a public SDK, but add rate‑limiting / a WAF (or ingress‑nginx `limit-rps`, ModSecurity) and consider Cloud Armor in front of the LB.
9. **Tighten the `internal` firewall rule.** It allows *all* protocols between *all* three subnets. Narrow it so only the cluster subnet reaches the data subnet, and only on the specific DB ports — datastores shouldn't accept traffic from the edge subnet at all.
10. **Single namespace** (`cometchat`) limits blast‑radius isolation; pairs with #4 and #6. Consider splitting tiers if effort allows.
11. **Clean up** the legacy `cc-cluster-1-ca.crt` and any leftover external test endpoints (`httpdump.app`, obsolete AWS Step Functions ARN).

### Verdict

> **Architecture: correct and well‑chosen** for an on‑prem, private, data‑residency deployment — private‑by‑default VMs, one auditable ingress, IAP admin plane, NAT‑only egress.
>
> **Posture: incomplete.** The build is in its "everything open so it can bootstrap" state. The three P0 items (egress lockdown, secrets encryption, disabling external‑data features) are what turn this from "works" into "meets the data‑residency requirement." None are large; they're switches the design already anticipates.

---

## 7. Quick reference (cheat sheet)

```
PUBLIC ENTRY     edge LB (static IP)  →  workers :80/:443  →  ingress‑nginx (TLS)  →  svc  →  pod
ADMIN ENTRY      IAP (35.235.240.0/20)  →  SSH :22 (all VMs) | kubectl :6443 (masters)
OUTBOUND         pod  →  Cloud NAT  →  internet   [TODO: deny‑all + allowlist]

SUBNETS          edge 10.20.30/24 (bastion) · cluster 10.20.20/24 (k8s) · data 10.20.10/24 (DBs)

FIREWALL (ingress, 5 rules)
  internal       3 subnets → any           all proto     east‑west
  iap_ssh        IAP       → any           tcp 22        admin SSH
  iap_k8s_api    IAP       → masters        tcp 6443      kubectl
  health_checks  GCP HC    → workers        tcp 80,443    LB probes
  edge_ingress   0.0.0.0/0 → workers        tcp 80,443    public clients

CERTS            wildcard-tls = Let's Encrypt (cert‑manager+Route53)  →  ingress  [public TLS]
                 jwt-keys/jwt-public = RSA app token signing          [NOT TLS]
                 RKE2 PKI = auto‑managed cluster certs

TOP 3 TODO       1) egress deny‑all+allowlist  2) secrets‑encryption on  3) NetworkPolicies
```

---

*Generated from `terraform/`, `k8s/`, `ansible/`, and the existing `NETWORK-FLOW.md` / `DATASTORE-ENDPOINTS.md` / `EXTERNAL-DEPENDENCIES.md` / `PROBLEMS-AND-FIXES.md`. Two items are flagged **verify‑me**: the committed location of the split‑horizon CoreDNS config (§5), and that cert‑manager + `route53-credentials` are installed so `wildcard-tls` is the Let's Encrypt cert and not the self‑signed fallback (§4).*
