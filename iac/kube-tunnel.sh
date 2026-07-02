#!/bin/bash
# Opens an IAP tunnel to the RKE2 API. Keep this running; use kubeconfig-local in another shell.
exec gcloud compute start-iap-tunnel cometchat-onprem-k8s-master-1 6443 \
  --local-host-port=127.0.0.1:6443 \
  --zone=asia-south1-a --project=onprem-499712
