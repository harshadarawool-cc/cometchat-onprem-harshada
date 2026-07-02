# Network Flow — CometChat On-Prem on GCP RKE2

Plain-English map of how traffic moves in this build, and how to clone it for a new cluster.
Everything here is verified against the Terraform in `terraform/`.

---

## The one-paragraph version

One private VPC with **three subnets** (datastores, RKE2 nodes, edge). **No VM has a public IP.**
The **only** way in from the internet is a single GCP load balancer → ingress-nginx on the worker
nodes. Apps talk to each other *inside* the cluster (CoreDNS rewrites their public-looking
hostnames back to in-cluster services), so **data never leaves the network**. Apps reach the
databases over private IPs in the data subnet. Outbound internet is NAT now, locked to a
deny-by-default allowlist after bootstrap.

---

## The picture

```
                          INTERNET
                             │
                  (clients: SDK, dashboard, webhooks)
                             │  443 / 80
                             ▼
                 ┌───────────────────────┐
                 │   GCP Edge LB (TCP)    │   ← ONLY public IP  (8.231.119.155)
                 │   forwards 80 + 443    │
                 └───────────┬───────────┘
                             │
        ╔════════════════════▼═════════════════════════════════════════╗
        ║  VPC: cometchat-onprem-vpc   (all private, no public IPs)     ║
        ║                                                               ║
        ║  ┌─────────────── edge subnet  10.20.30.0/24 ──────────────┐  ║
        ║  │  bastion (.10)  — SSH jump box, IAP only                │  ║
        ║  └─────────────────────────────────────────────────────────┘  ║
        ║                                                               ║
        ║  ┌─────────────── cluster subnet  10.20.20.0/24 ───────────┐  ║
        ║  │  RKE2 masters (.11+)    RKE2 workers (.21+)              │  ║
        ║  │                         └─ ingress-nginx (hostPort 80/443)│ ║
        ║  │                         └─ all app pods (ClusterIP)      │  ║
        ║  │  CoreDNS: rewrites *-us.cometchat-cluster-2.in → ingress/svc    │  ║
        ║  └──────────────────────────┬──────────────────────────────┘  ║
        ║                             │ private IP, east-west            ║
        ║  ┌──────────────────────────▼──────────────────────────────┐  ║
        ║  │  data subnet  10.20.10.0/24                              │  ║
        ║  │  mongo .11-.13   redis (4 clusters) .21-.29 + .61-.63    │  ║
        ║  │  kafka .31-.33   mysql .41   tidb .51                    │  ║
        ║  └─────────────────────────────────────────────────────────┘  ║
        ║                                                               ║
        ║  Cloud NAT ──► controlled outbound (image pulls, etc.)        ║
        ╚═══════════════════════════════════════════════════════════════╝
                             ▲
                             │  SSH 22, via Google IAP only (35.235.240.0/20)
                          Admins / Ansible
```

---

## The three subnets

| Subnet | CIDR | What lives here | Public IP? |
|---|---|---|---|
| `*-data` | `10.20.10.0/24` | Mongo, Redis, Kafka, TiDB, MySQL | No |
| `*-cluster` | `10.20.20.0/24` | RKE2 masters + workers, all app pods | No |
| `*-edge` | `10.20.30.0/24` | Bastion (jump box) | No |

VPC is custom-mode (no auto subnets), regional routing. All subnets have Private Google Access on.
*File: `terraform/network.tf`*

## Who gets which IP (auto-computed)

IPs come from `cidrhost()`, so a new CIDR keeps the same layout automatically.

```
data subnet  .11/.12/.13  mongo
             .21–.23  redis-shared     .24–.26  redis-analytics
             .27–.29  redis-prometrics .61–.63  redis-bullmq
             .31/.32/.33  kafka   .41  mysql   .51  tidb
cluster      .11+  k8s masters    .21+  k8s workers
edge         .10   bastion
```
*Files: `terraform/datastores.tf`, `terraform/rke2.tf`*

---

## Firewall — what's allowed IN (everything else is denied)

GCP denies all ingress by default. We open exactly four things:

| # | Rule | From | To | Ports |
|---|---|---|---|---|
| 1 | **Internal east-west** | the 3 subnet CIDRs | any VM in VPC | all tcp/udp/icmp |
| 2 | **SSH** | Google IAP `35.235.240.0/20` | any VM | 22 |
| 3 | **LB health checks** | `35.191.0.0/16`, `130.211.0.0/22` | worker nodes | 80, 443 |
| 4 | **Public edge** | `edge_allowed_cidrs` *(default open — tighten!)* | worker nodes | 80, 443 |

Rule 1 is broad on purpose: it's a single-tenant private cluster, so all DB ports and all RKE2
node-to-node ports are covered without listing them. *File: `terraform/firewall.tf`*

## Firewall — what's allowed OUT

- **Now (bootstrap):** Cloud NAT gives private VMs outbound so they can pull images (ECR), OS
  packages, and `get.rke2.io`. Egress is GCP default (allow-all) for now.
- **After bootstrap (data-residency lockdown):** flip to **deny-all egress** + an allowlist
  (internal subnets always; ECR ranges; only the external hosts the customer actually tests).
  The locked-down rules are written and commented at the bottom of `terraform/firewall.tf` —
  uncomment to enable. *Files: `terraform/network.tf` (NAT), `terraform/firewall.tf` (egress)*

---

## How traffic actually flows

**1. Client → app (the one public path)**
Internet client → Edge LB (`8.231.119.155`, ports 80/443) → ingress-nginx on a worker node →
app pod. The LB is a regional TCP passthrough LB; ingress-nginx holds the wildcard TLS cert and
terminates HTTPS. *File: `terraform/lb.tf`*

**2. App → app (stays inside — this is the whole point)**
Apps hardcode public-looking names like `rule-us.cometchat-cluster-2.in`. **CoreDNS split-horizon**
rewrites those to the in-cluster service (or the shared ingress) *before* DNS ever leaves the
cluster → traffic goes pod-to-pod over ClusterIP and **never touches the internet**.
- Only **chatapi** and **mgmtapi** (PHP-FPM) keep a per-pod nginx sidecar (FastCGI gateway).
- Every Node/Python app serves plain HTTP internally — no sidecar.
*(Config is an RKE2 `HelmChartConfig` for CoreDNS — applied via Ansible/Helm, not Terraform.)*

**3. App → database**
App pod → private IP of the DB VM in the data subset (e.g. `10.20.10.11:27017` for Mongo).
Secrets point `DB_HOST` / `REDIS_HOST` / `KAFKA_BROKER` / `MONGO_URI` at these GCP VMs.

**4. Admin → VMs**
SSH only through Google IAP tunnel to the bastion / nodes. No public SSH exists.

---

## Two rules for the secrets (so connectivity stays correct)

1. **Datastore endpoints → DO rewrite** to the GCP DB VM IPs.
2. **Service URLs → NEVER change** (keep host + http/https exactly as-is). Staging/external
   hostnames are handled by CoreDNS or the egress allowlist, *not* by editing app envs.

---

## Clone this for a NEW cluster (same networking, zero redesign)

Copy `terraform/` to a new folder with **its own state**, and change only these in
`terraform.tfvars`. Everything else (firewall logic, LB, NAT, IP layout) reproduces itself.

```hcl
project_id  = "<project>"             # same or new project
name_prefix = "cometchat-onprem2"     # MUST change — avoids name clashes
vpc_name    = "cometchat-onprem2-vpc" # MUST change

# Non-overlapping CIDRs so the two clusters can coexist / peer:
subnet_data_cidr    = "10.30.10.0/24"
subnet_cluster_cidr = "10.30.20.0/24"
subnet_edge_cidr    = "10.30.30.0/24"

edge_allowed_cidrs  = ["<your client / VPN CIDRs>"]   # don't leave 0.0.0.0/0 in prod
```

Then:
```bash
cd <new-folder>/terraform
terraform init      # fresh, separate state — do NOT reuse the existing state
terraform apply
```

Post-`apply` steps (CoreDNS split-horizon, ingress-nginx, egress lockdown) are infra-agnostic
Ansible/Helm — they apply to the new cluster identically.

---

## Source-of-truth files

| Concern | File |
|---|---|
| VPC + subnets + NAT | `terraform/network.tf` |
| Firewall (in + out) | `terraform/firewall.tf` |
| Edge load balancer | `terraform/lb.tf` |
| Datastore VMs + IPs | `terraform/datastores.tf` |
| RKE2 nodes + IPs | `terraform/rke2.tf` |
| Bastion | `terraform/bastion.tf` |
| All tunables (CIDRs, sizes) | `terraform/variables.tf` |
| Per-cluster values | `terraform/terraform.tfvars` |
| Datastore endpoint map | `DATASTORE-ENDPOINTS.md` |
| External deps / egress audit | `EXTERNAL-DEPENDENCIES.md` |
