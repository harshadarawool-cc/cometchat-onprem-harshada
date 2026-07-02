# `iac/` — CometChat on-prem, one-click Infrastructure-as-Code

Zero → fully-working CometChat cluster on GCP + RKE2, reproducibly. One orchestrator drives everything;
every phase is idempotent (safe to re-run).

## Quickstart
```bash
cd deploy
# 1) edit customer.conf (project, zone, domain, sizing, LICENCE_FILE, R53 zone)
./deploy.sh config        # render terraform.tfvars from customer.conf
./deploy.sh all           # infra → datastores → seed → apps → ingress → certs → verify  (~60–90 min)
# or staged:  ./deploy.sh          (infra only)   then   ./deploy.sh app-all
../dns-point.sh           # point Route53 *.<domain> at the new edge LB IP
./deploy.sh status
```
Prereqs: `gcloud` (authed), `terraform`, `ansible`, `kubectl`, `jq`, `openssl`, `python3`, `aws` (profile in
customer.conf); the ansible vault pass (`ansible/.vault_pass`) + SSH key (`ansible/ssh/cometchat_rke2`).

## Layout
```
iac/
├── deploy/
│   ├── deploy.sh          THE orchestrator (phases below). Start here.
│   └── customer.conf      the ONE file you edit per cluster (project/domain/sizing/licence/R53)
├── terraform/             infra: VPC, subnets, firewall, 25 datastore/RKE2 VMs + 2 HAProxy edge VMs, encrypted disks
├── ansible/               datastore provisioning + data seeding + the HAProxy edge role
│   ├── datastores.yml     mongo rs0 / redis sentinel / kafka(+topics) / tidb / mysql  (roles/)
│   ├── haproxy.yml        renders + validates haproxy.cfg (SNI → NodePorts) on the 2 edge VMs
│   ├── restore-*.yml      DB dumps + mongo seeds + region-hash sync (from ../dumps)
│   └── fix-mongo-app-users.yml   creates the per-app mongo users (admin/extadmin/webhookuser)
├── k8s/                   every k8s manifest (chatapi, mgmtapi, apps/, node apps, edge-nodeports,
│   │                      coredns-direct, cert-manager, seaweedfs/, dashboard, jobs, sidecar TLS)
│   └── seaweedfs/         the object store (masters/volumes/filer/S3 + cometchatFS console + pod-TLS edge)
├── scripts/               gen-cluster-creds.sh, sync-app-db-creds.py, secrets-from-rendered.py,
│   │                      deploy-node-apps.py, apply-region.py, … (archive/ = one-time/superseded)
├── secrets/               ALL credentials (gitignored) — see secrets/README.md
├── docs/                  architecture + problem/fix journal (archive/ = old planning docs)
└── kubeconfig-6444        kube-API via the IAP tunnel (deploy.sh opens it)
```

## Phases (`./deploy.sh <phase>`)
`preflight · infra · inventory · datastores-wait · credgen · datastores · rke2 · seed ·`
`secrets · certs · coredns · support · storage · editors · apps · node-apps · edge · haproxy · storage-seed · verify · status`

**Order matters — it's a dependency chain** (encoded in `all`): VMs (incl. 2 HAProxy) →
datastores(+kafka topics) → **credgen** (fresh DB passwords) → datastores provision with them → **seed**
(dumps + mongo/vcb/moderation + mongo users) → secrets → **certs** (real wildcard-tls) → **coredns**
(east-west DNS) → backends (support/storage/editors) → **then** apps → node-apps → **edge** (NodePort
overlay) → **haproxy** (SNI) → **storage-seed** (LATE object assets) → verify. Apps start only once their
prerequisites exist — real cert (sidecars load it at boot), east-west DNS, and seeded backends. See
[docs/SEEDING.md](docs/SEEDING.md) + [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).

## Credentials (fresh per cluster, auto-synced)
`credgen` generates `secrets/infra/cluster-creds.yml` (6 datastore passwords). deploy.sh passes it to
ansible (`apb -e`) **and** to `sync-app-db-creds.py` (stamps them into the app secrets) — so the datastores
and the application secrets get **identical, brand-new** passwords. Ansible **fails loudly** if they're
missing. To rotate: delete `cluster-creds.yml`, re-run `datastores` + `secrets`. See `secrets/README.md`.

## Networking (data-residency)
2 HAProxy VMs do L4 **SNI passthrough** → per-service NodePorts (north-south); per-pod nginx TLS sidecars
terminate the wildcard cert on `:443` (TLS never terminates at the edge); CoreDNS split-horizon rewrites
every on-prem FQDN **direct to its in-cluster Service**, so east-west traffic is verified HTTPS that never
leaves the VPC. Storage hosts (`media/data/files-onprem`) route to the `seaweedfs-edge` pod-TLS front. Full
detail: **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** + the ★ docs (**[docs/00-INDEX.md](docs/00-INDEX.md)**).
