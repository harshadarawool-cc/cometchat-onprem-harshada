# Granting the client access to the cometchatFS image

Image: `894996064311.dkr.ecr.us-east-2.amazonaws.com/cometchat-enterprise:cometchatfs-obf`
(pinned digest is in `k8s/deployment.yaml`).

Pick ONE delivery method.

## A. Cross-account pull (client pulls directly from our ECR) — recommended
Needs the **client's AWS account ID**. Add a repository policy that lets them pull:

```bash
CLIENT_ACCOUNT_ID=<their-account-id>
cat > ecr-policy.json <<EOF
{
  "Version": "2008-10-17",
  "Statement": [{
    "Sid": "AllowClientPull",
    "Effect": "Allow",
    "Principal": { "AWS": "arn:aws:iam::${CLIENT_ACCOUNT_ID}:root" },
    "Action": [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability"
    ]
  }]
}
EOF
aws ecr set-repository-policy --region us-east-2 \
  --repository-name cometchat-enterprise \
  --policy-text file://ecr-policy.json
```

On the client cluster, create the pull secret (their nodes' IAM or a token):
```bash
kubectl -n <ns> create secret docker-registry ecr-pull-secret \
  --docker-server=894996064311.dkr.ecr.us-east-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region us-east-2)"
# NOTE: ECR tokens expire in 12h — automate refresh (CronJob) or use IRSA/node IAM.
```

## B. Dedicated read-only IAM user (if no cross-account trust)
Create an IAM user for the client with an ECR read-only policy scoped to this repo, hand them the access keys, and they use those to `get-login-password`.
Policy actions: `ecr:GetAuthorizationToken` (resource `*`) + the three pull actions above on
`arn:aws:ecr:us-east-2:894996064311:repository/cometchat-enterprise`.

## C. Air-gapped (no registry access)
```bash
docker pull 894996064311.dkr.ecr.us-east-2.amazonaws.com/cometchat-enterprise:cometchatfs-obf
docker save 894996064311.dkr.ecr.us-east-2.amazonaws.com/cometchat-enterprise:cometchatfs-obf \
  | gzip > cometchatfs-obf.tar.gz
# client: gunzip -c cometchatfs-obf.tar.gz | docker load  ; then push to THEIR registry
# and update k8s/deployment.yaml image: to their registry path.
```
> Air-gapped is the most client-deliverable option (no dependency on our AWS).
```
