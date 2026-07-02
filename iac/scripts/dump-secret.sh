#!/bin/sh
# Decode one or more k8s secrets in ns cometchat to plaintext key=value / file dumps.
# Handles both shapes: individual keys (envFrom) and single file keys (.env/.json).
# KUBECONFIG: env wins, else iac/kubeconfig-6444 resolved relative to this script (portable).
_IAC="$(cd "$(dirname "$0")/.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-$_IAC/kubeconfig-6444}"
NS="${NS:-cometchat}"
for s in "$@"; do
  echo "===== SECRET: $s ====="
  kubectl -n "$NS" get secret "$s" -o json 2>/dev/null | python3 -c '
import sys,json,base64
o=json.load(sys.stdin)
data=o.get("data") or {}
if not data:
    print("<<missing or empty secret>>"); sys.exit(0)
for k,v in sorted(data.items()):
    try: dec=base64.b64decode(v).decode()
    except Exception: dec="<binary>"
    if ("\n" in dec) or k.endswith(".json") or k.endswith(".env") or k==".env.staging" or k=="env.staging.json":
        print("----- key [%s] (file content) -----"%k); print(dec); print("----- end [%s] -----"%k)
    else:
        print("%s=%s"%(k,dec))
'
done
