# CometChat on-prem (GCP RKE2) — One-Click Deployment

This directory automates the **entire** build, zero → 100%. Destroy the infra and a
single command brings it back, in the right order, with every fix we learned baked in.

> **Read first:** [`../PROBLEMS-AND-FIXES.md`](../PROBLEMS-AND-FIXES.md) — the "why" behind every
> step. The orchestrator is the executable form of that document.

---

## Edit one file, then pick a strategy

**Everything is driven by a single file: [`customer.conf`](customer.conf).** Edit your GCP
project, region, SSH public key and node sizes there — `deploy.sh` reads it and also generates
`terraform/terraform.tfvars` from it, so Terraform stays in sync. You never edit `.tf` files.

```bash
cd iac/deploy
cp customer.conf customer.conf.bak     # (optional) keep a copy
vi customer.conf                       # set PROJECT, SSH_PUBLIC_KEY, region, node sizes
```

Then choose how to deploy:

### Strategy A — One-click INFRA  *(recommended starting point)*
```bash
./deploy.sh                # preflight → terraform → datastores(+kafka topics) → rke2 → seed
```
From an empty project to: VPC + NAT + 25 VMs + edge LB, all datastores healthy, Kafka **with
topics already created**, a running RKE2 cluster, and seeded databases. Idempotent — re-run any time.

### Strategy B — One-click FULL (infra **+** apps)
```bash
./deploy.sh all            # everything A does, then secrets → support → apps → node-apps
                           #   → coredns(split-horizon) → ingress → verify
```
This deploys **every** service — including the node-only ones (websocket, moderationservice,
visual-chat-builder, ai-agent-service, receipt-updater, notifications-delay-worker, dashboard)
and the split-horizon DNS — and finishes with a readiness gate. There is **no** separate
`node-apps` step to remember anymore. Needs the app-phase inputs (licence, ECR access,
`secrets-rendered/` — see Prerequisites).

### Strategy C — Pure Terraform  *(drive the IaC yourself)*
```bash
./deploy.sh config         # generate terraform/terraform.tfvars from customer.conf
cd ../terraform
terraform init && terraform plan && terraform apply     # just the VMs / network / LB
```
For customers who want Terraform to own the infra. Configure the cluster afterwards with the
Ansible/app phases (`../deploy/deploy.sh datastores rke2 …`) or their own tooling.

### Strategy D — Phased / surgical
```bash
./deploy.sh <phase>        # one phase at a time (see the table below)
./deploy.sh status         # LB IP + node + pod status
```

### Teardown
```bash
./destroy.sh               # guarded: destroys ONLY ${PREFIX}-* ; asks you to type the project id
./destroy.sh --yes         # non-interactive (CI)
```
Then `./deploy.sh` rebuilds from scratch.

---

## What it does, in order

| Phase | Command | What happens | Key fixes encoded |
|------:|---------|--------------|-------------------|
| 0 | `preflight` | check gcloud auth/project, toolchain, vault pass, SSH key, **quota headroom** | A1, A2 |
| 1 | `infra` | `terraform apply`: VPC, **Cloud NAT**, 25 VMs (**pd-standard**), edge **TCP LB**, firewall, bastion | A1, B1, B2 |
| 2 | `inventory` | read **dynamic** `edge_lb_ip` from terraform output → write into group_vars (never hardcode) | B3 |
| 3 | `datastores-wait` | wait until all VMs accept SSH **over IAP** | B1 |
| 4 | `datastores` | Ansible: Mongo rs0, 4 Redis Sentinel clusters, **Kafka + 31 topics**, TiDB, MySQL → health check | C*, D*, **E1**, F* |
| 5 | `rke2` | Ansible: control plane + agents; fetch + **regenerate localhost kubeconfigs** from fresh CA | H1, H2, B4 |
| 6 | `seed` | restore MySQL/Mongo dumps **(optional, skip-if-absent)** + provision Mongo **app users** (admin/extadmin/webhookuser). Tables are created by the apps' own `php artisan migrate` on boot. | C4, F2 |
| 7 | `secrets` | namespace + **both ECR pull secrets** + licence + JWT keypair + wildcard TLS + SeaweedFS; then `secret-sync`/`secret-shapes` | I1, I2, G1, G2 |
| 8 | `support` | OpenSearch/Ollama/Mailpit/SeaweedFS + **ES8 proxy** (+ repoint `opensearch` Service) | I3 |
| 9 | `apps` | chatapi/mgmtapi (PHP+nginx) + curated `k8s/apps/*` manifests | I4–I12 |
| 10 | `node-apps` | node-only services w/ no curated manifest: websocket, moderationservice, visual-chat-builder, ai-agent-service, receipt-updater, notifications-delay-worker, dashboard | audit-2026-06-24 |
| 11 | `coredns` | split-horizon: `*.<DOMAIN>` resolves **in-cluster** → data residency + lets mgmtapi reach chatapi for app provisioning | NETWORK-FLOW |
| 12 | `ingress` | edge ingress; print the LB IP to point DNS at | B3 |
| 13 | `verify` | datastore health + **all workloads Ready** + split-horizon DNS check + PASS/FAIL summary | — |

Run the whole thing end-to-end with `./deploy.sh all`, or any single phase by name. `node-apps`
and `coredns` are now folded into `app-all`/`all` — you no longer run them separately.

---

## Prerequisites

**Always:**
- `gcloud` authenticated, with **`roles/iap.tunnelResourceAccessor`** (SSH and the kube-API both tunnel through IAP — no VM has a public IP).
- `terraform`, `ansible`, `kubectl`, `jq`, `openssl`, `python3` on PATH.
- `iac/ansible/.vault_pass` and `iac/ansible/ssh/cometchat_rke2` present (already in the repo).
- `INSTANCES` quota ≥ 26 and disk quota headroom (preflight warns if not — see A1/A2).

**App phase only (`secrets`/`app-all`):** set these in `customer.conf`:
- `AWS_PROFILE` — an `aws` CLI profile that can pull the ECR images (token for both pull secrets).
- `LICENCE_FILE` — absolute path to your CometChat `license.txt`.
- `VAULT_ENVS_DIR` — a directory of per-service env JSON files (`<service>.json`) holding your app
  secrets. This is the only piece the script can't reproduce on its own — produce it from your secret
  store, then run `./deploy.sh secrets`. Without it the deterministic secrets are still created but
  `secret-sync`/`secret-shapes` are **skipped** (loudly).

All values live in **`customer.conf`** (a single sourced file). You can still override any one of them
for a single run by exporting it first, e.g. `PREFIX=acme ./deploy.sh status`.

---

## The one thing that was missing before: Kafka topics

Previously the 31 topics only existed in a **k8s Job** that runs in the app phase — so Kafka came up
*empty* and apps that produced/consumed on boot raced ahead of topic creation. Now the topics are
defined in [`../ansible/group_vars/kafka.yml`](../ansible/group_vars/kafka.yml) and the `kafka` role's
existing idempotent task creates them **the moment the broker quorum is up**, inside the `datastores` phase.
The k8s Job is kept only as an in-cluster fallback. (See **E1** in PROBLEMS-AND-FIXES.)

---

## Idempotency & safety

- Every phase converges rather than duplicating: terraform is declarative; Ansible tasks are guarded;
  `kubectl` secrets/manifests use `apply` (server-side reconcile); topic creation is `--if-not-exists`;
  the RKE2 token and JWT keypair are generated **once** and reused.
- `destroy.sh` refuses to run if the terraform state contains anything **not** named `cometchat-onprem-*`,
  so it can never touch the old kept infra. It asks you to type the project id to confirm.
- Generated secret material (JWT keypair, wildcard TLS, SeaweedFS creds) is persisted under
  `iac/.secrets/` so re-runs reuse stable keys. Keep that directory private; do not commit it.

---

## Now automated (previously manual) — folded into one-click on 2026-06-24

- **Node-only services** (websocket, moderationservice, visual-chat-builder, ai-agent-service,
  receipt-updater, notifications-delay-worker, dashboard) deploy in the `node-apps` phase, which is
  now part of `app-all`/`all`. `scripts/deploy-node-apps.py` was **trimmed to only these** — it no
  longer re-deploys the curated `k8s/apps/*` services (notificationscore, globalwebhooks,
  service-search, analytics, metrics-pro, extensions, sql-consumer), so the two paths can no longer
  clobber each other.
- **CoreDNS split-horizon** is now a real, reconcile-safe manifest (`k8s/coredns-split-horizon.yaml`:
  a `coredns-custom` zone + a pinned internal-ingress ClusterIP) applied in the `coredns` phase. The
  `verify` phase confirms `*.<DOMAIN>` resolves in-cluster.
- **chatapi/mgmtapi TiDB schema** is created by the images themselves — chatapi's container runs a
  TiDB-aware self-healing `php artisan migrate` loop (fakes the one `TRIGGER` migration TiDB can't
  run, so the rest apply); mgmtapi runs `php artisan migrate --force`. **No SQL dump is needed for
  schema** — the optional dumps in `seed` are *data* only and skip cleanly if absent.

## Still manual / by design (not yet one-click)

- **Egress lockdown (data residency).** The default-deny + allowlist firewall rules are written but
  commented in `terraform/firewall.tf` (left open during bootstrap for ECR/OS/`get.rke2.io` pulls).
  Switch them on **after** the cluster is healthy via `./deploy.sh lockdown` (gated). Likewise tighten
  `edge_allowed_cidrs` from `0.0.0.0/0`.
- **Real TLS (cert-manager + Let's Encrypt).** The deploy ships a self-signed wildcard that works for
  the internal/split-horizon path. For browser-trusted edge certs, install cert-manager and apply
  `k8s/cert-manager-issuer.yaml` (needs `route53-credentials` + public DNS). Optional; not in `all`.
