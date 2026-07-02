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
├── terraform/             infra: VPC, subnets, firewall, 25 VMs (mongo/redis/kafka/mysql/tidb/rke2), edge LB
├── ansible/               datastore provisioning + data seeding
│   ├── datastores.yml     mongo rs0 / redis sentinel / kafka(+topics) / tidb / mysql  (roles/)
│   ├── restore-*.yml      DB dumps + mongo seeds + region-hash sync (from ../dumps)
│   └── fix-mongo-app-users.yml   creates the per-app mongo users (admin/extadmin/webhookuser)
├── k8s/                   every k8s manifest (chatapi, mgmtapi, apps/, node apps, ingress, coredns HCC,
│   │                      cert-manager, seaweedfs/, dashboard, jobs, sidecar TLS)
│   └── seaweedfs/         the object store (masters/volumes/filer/S3 + cometchatFS console)
├── scripts/               gen-cluster-creds.sh, sync-app-db-creds.py, secrets-from-rendered.py,
│   │                      deploy-node-apps.py, apply-region.py, … (archive/ = one-time/superseded)
├── secrets/               ALL credentials (gitignored) — see secrets/README.md
├── docs/                  architecture + problem/fix journal (archive/ = old planning docs)
└── kubeconfig-6444        kube-API via the IAP tunnel (deploy.sh opens it)
```

## Phases (`./deploy.sh <phase>`)
`preflight · infra · inventory · datastores-wait · credgen · datastores · rke2 · seed ·`
`secrets · support · storage · editors · apps · node-apps · coredns · ingress · certs · verify · status`

**Order matters** (encoded in `all`): VMs → datastores(+kafka topics) → **credgen** (fresh DB passwords) →
datastores provision with them → seed (dumps + mongo/vcb/moderation) → **then** apps → node-apps →
coredns (split-horizon, per-FQDN east-west) → ingress → certs (Let's Encrypt) → verify.

## Credentials (fresh per cluster, auto-synced)
`credgen` generates `secrets/infra/cluster-creds.yml` (6 datastore passwords). deploy.sh passes it to
ansible (`apb -e`) **and** to `sync-app-db-creds.py` (stamps them into the app secrets) — so the datastores
and the application secrets get **identical, brand-new** passwords. Ansible **fails loudly** if they're
missing. To rotate: delete `cluster-creds.yml`, re-run `datastores` + `secrets`. See `secrets/README.md`.

## Networking (data-residency)
Per-pod nginx TLS sidecars terminate the wildcard cert on `:443`; CoreDNS split-horizon rewrites every
on-prem FQDN to its in-cluster Service, so east-west traffic is verified HTTPS that never leaves the VPC.
Storage hosts (`media/data/files-onprem`) fall to the internal ingress. See `docs/`.
