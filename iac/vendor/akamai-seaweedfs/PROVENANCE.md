# Vendored: cometchat-team/akamai-projects @ seaweedfs

- Repo: https://github.com/cometchat-team/akamai-projects
- Branch: `seaweedfs`
- Commit: `5232cca9ab31e3773742c2dd2433a11f104e3e88`
  ("chore(ecr): migrate all image refs to the cometchat-enterprise ECR repo")
- Vendored on: 2026-07-02

This is the AUTHORITATIVE upstream object-store package (SeaweedFS 4.37 enterprise + cometchatFS).
The deployable, environment-adapted copy lives in `iac/k8s/seaweedfs/` (same manifests, wrapped by
`deploy.sh` with our RKE2 / CoreDNS split-horizon / S3-identity-collection flow). Re-sync from upstream
by re-cloning the branch and copying `seaweedfs/` + `cometchatfs/` here.
