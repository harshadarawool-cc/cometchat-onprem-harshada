# Migration — GCP L4 Load Balancer → HAProxy edge

> What changed vs the `cometchat-cluster2-rebuild` baseline (a GCP L4 Network LB → ingress-nginx), and why.
> This repo (`cometchat-cluster-haproxy`) is that baseline re-architected to the colleague's HAProxy model.

## Before vs after

| Concern | Before (LB model) | After (HAProxy model) |
|---|---|---|
| Public edge | 1 GCP regional TCP Network LB (`lb.tf`) + instance group | **2 HAProxy VMs** (`haproxy.tf`), 2 public IPs |
| Edge→cluster | LB forwarding-rule :443 → agent hostPort 443 → ingress-nginx | HAProxy **SNI passthrough** → per-service **NodePort** (30443–30452) |
| TLS termination | central, at **ingress-nginx** | per-pod **nginx sidecar** (`:443`) — never at the edge |
| North-south routing | Host-based at ingress-nginx | **SNI-based** at HAProxy (L4) |
| East-west DNS | CoreDNS catch-all → internal-ingress ClusterIP | CoreDNS **direct-to-Service** (`coredns-direct.yaml`), no catch-all |
| Facing Service type | ClusterIP (ingress fronts them) | ClusterIP **+ NodePort overlay** (`edge-nodeports.yaml`) |
| Public DNS | single LB IP | **round-robin A** across 2 HAProxy IPs |
| ingress-nginx | required (the edge) | **not used** (dropped for facing + internal) |
| Encryption at rest | PD default only | PD (+**CMEK** option) + **RKE2 secrets-encryption** + **SeaweedFS SSE enforced** |
| SeaweedFS media host | via ingress → filer | `seaweedfs-edge` (pod TLS :443) via HAProxy SNI + CoreDNS |

## Files changed

- **Deleted:** `terraform/lb.tf`.
- **Added:** `terraform/haproxy.tf`, `ansible/roles/haproxy/*`, `ansible/group_vars/haproxy.yml`,
  `ansible/haproxy.yml`, `k8s/edge-nodeports.yaml`, `k8s/seaweedfs/45-edge-tls.yaml`.
- **Edited:** `terraform/{firewall,variables,rke2,datastores,bastion}.tf` (HAProxy firewall + CMEK);
  `ansible/roles/rke2_server` (`secrets-encryption`, tls-san from `edge_public_ips`);
  `ansible/inventory/hosts.yml` (+`haproxy` group); `k8s/{dashboard,dashboard-nginx}.yaml` +
  `k8s/apps/doc-whiteboard.yaml` (add pod-TLS to the 3 facing pods that lacked it);
  `k8s/coredns-direct.yaml` (media → seaweedfs-edge); `k8s/seaweedfs/deploy.sh`;
  `deploy/deploy.sh` (phase_inventory/coredns/edge/haproxy, sequences); `dns-point.sh` (round-robin);
  `deploy/customer.conf` (HAPROXY_*, DISK_KMS_KEY).

## Why the change

- **Per-pod TLS** (the colleague's data-residency model): TLS terminates inside the pod, so decrypted
  traffic never exists at a shared edge. An L4 SNI-passthrough edge is the natural fit; a cloud L7 LB or
  ingress-nginx would terminate TLS centrally.
- **No cloud-controller on RKE2:** `type: LoadBalancer` never gets an IP, so the edge must be provisioned
  outside Kubernetes anyway — HAProxy VMs are a clean, portable choice (works on any cloud / bare metal).
- **Parity with the proven cluster** documented in `K8S-NETWORKING-GUIDE.md` (§3 sidecar, §4A HAProxy).

## Rollback

The LB model is recoverable from git history (`terraform/lb.tf` + the ingress-based `phase_ingress`). To
revert: restore `lb.tf`, point `phase_edge` back to `ingress.yaml`, switch `phase_coredns` to the
catch-all HCC, and re-point DNS to the single LB IP. Not recommended — the HAProxy model is the target.

## Suggested next hardening (flagged, not silently enabled)

- **Egress lockdown** — `terraform/firewall.tf` ships default-deny + allowlist rules commented (open during
  bootstrap for ECR/OS/ACME pulls). Turn on post-bootstrap. See [SECURITY](SECURITY.md).
- **Tighten `edge_allowed_cidrs`** from `0.0.0.0/0` to the customer's real client/VPN ranges.
- **HAProxy VIP (keepalived)** if a single stable edge IP is preferred over DNS round-robin.
- **NetworkPolicies + PodSecurity `restricted`.**
