# CometChat — Fresh GCP RKE2 Cluster Rebuild

Clean rebuild of the CometChat backend on a **fresh** GCP RKE2 cluster, using a colleague (Aryan)'s
**working** cluster as the blueprint. This folder replaces the accumulated one-off patches in
`~/GCP_RKE2/iac/` (the current/broken cluster) with a correct-from-the-start setup.

> **Status: PLANNING.** Nothing in here is applied yet, and the current cluster has NOT been touched.
> Each subfolder is populated only **after** its phase plan is reviewed and approved.

## Guiding rule — no app patching
Every application runs from its published image **as-is**, pinned by digest. If an image won't come up
healthy, the fix belongs in **networking / config / secrets / DB-seeding — never** the app.

## Layout (to be populated per approved plan)
| Folder | Holds |
|---|---|
| `terraform/` | VPC, subnets, firewall (inbound-closed / outbound-open), edge LB, RKE2 nodes, datastore VMs |
| `k8s/` | ingress, CoreDNS split-horizon, cert-manager, app manifests / Helm values |
| `deploy/` | phased deploy scripts + `customer.conf` |
| `dumps/sql`, `dumps/mongo` | the 7 DB dumps to restore (4 MySQL `.sql` + 3 Mongo `.json`) |
| `docs/` | `CLUSTER-GAP-ANALYSIS.md` + per-phase plans |

## Canonical reference material
- `~/Downloads/Aryan-clster-working setup/` — `K8S-NETWORKING-GUIDE (1).md`, `DUMPS-AND-SEEDING.md`, `cometchat-db-dumps 2/`
- `~/Downloads/cc-handoffs/` — 6 service handoffs (chatapi, extensions, metrics, moderation, seaweedfs, vcb)
- `~/Downloads/cometchat-envs-aryan/` — Aryan's live per-app envs + datastore secrets (⚠ live secrets)

## Locked decisions
- Domain **`cometchat-cluster-2.in`**, region **`onprem`**.
- Firewall: **inbound CLOSED** at cluster level (default-deny ingress; allow only minimal edge HTTPS +
  GCP health-check ranges + Google IAP 22/6443). **Outbound OPEN** for now (testing) — egress not yet locked.
- No app patching. Pin by digest. 3 pinned: chatapi `sha256:e35cfbec…d89558`, mgmt `sha256:1712df2f…6ea5c4`,
  notification `sha256:2dc5eb05…337ce9`; every other app = latest-from-ECR resolved to a digest.

## Reference: current cluster IaC being replaced
`~/GCP_RKE2/iac/` — terraform/{network,firewall,lb,rke2,datastores,bastion,variables}.tf ;
k8s/{ingress,coredns-split-horizon,cert-manager-issuer}.yaml ; docs/{R53-RECORDS,NETWORK-AND-SECURITY,NETWORK-FLOW}.md ;
deploy/{customer.conf,README.md}
