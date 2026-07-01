#!/usr/bin/env python3
"""Global domain rename: cc-cluster-1.io -> cometchat-cluster-2.in across
  - repo files (k8s manifests, secrets/apps baseline, scripts, docs, deploy/)
  - live k8s secrets (decode -> replace -> re-apply, preserving every key & shape)
The CoreDNS split-horizon configmap and Route53/cert steps are handled separately.
Default dry-run; pass --apply to write.
"""
import os, sys, json, base64, subprocess, glob

OLD = "cc-cluster-1.io"
NEW = "cometchat-cluster-2.in"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # .../iac
KC = os.environ.get("KUBECONFIG", os.path.join(ROOT, "kubeconfig-6444"))
NS = os.environ.get("NS", "cometchat")
APPLY = "--apply" in sys.argv

FILE_GLOBS = ["k8s/*.yaml", "secrets/apps/*/.env", "scripts/*.py", "*.md",
              "deploy/*.sh", "deploy/*.conf", "deploy/*.example", "deploy/*.md"]

print("===== FILES =====")
file_occ = 0
for g in FILE_GLOBS:
    for f in sorted(glob.glob(os.path.join(ROOT, g))):
        if os.path.abspath(f) == os.path.abspath(__file__):
            continue
        s = open(f).read()
        n = s.count(OLD)
        if n:
            print(f"  {os.path.relpath(f, ROOT)}: {n}")
            file_occ += n
            if APPLY:
                open(f, "w").write(s.replace(OLD, NEW))

SECRETS = ["chatapi-env","mgmtapi-env","websocket-env","notificationscore-env",
  "moderationservice-env","globalwebhooks-env","receipt-updater-env","sql-consumer-env",
  "sql-consumer-config","extensions-env","extensions-config","service-search-env",
  "ai-agent-service-env","calls-relay-env","calls-relay-envfile","clamav-env",
  "metrics-pro-env","analytics-env","visual-chat-builder-env","notifications-delay-worker-env"]

def kget(s):
    p = subprocess.run(f"kubectl --kubeconfig {KC} -n {NS} get secret {s} -o json",
                       shell=True, capture_output=True, text=True)
    return json.loads(p.stdout) if p.returncode == 0 else None

def kapply(name, sdata):
    man = {"apiVersion":"v1","kind":"Secret","type":"Opaque",
           "metadata":{"name":name,"namespace":NS},"stringData":sdata}
    p = subprocess.run(f"kubectl --kubeconfig {KC} apply -f -", input=json.dumps(man),
                       shell=True, capture_output=True, text=True)
    return "ok" if p.returncode == 0 else "FAIL: " + p.stderr.strip()[:140]

print("===== LIVE SECRETS =====")
sec_occ = 0
for s in SECRETS:
    obj = kget(s)
    if not obj:
        print(f"  {s}: <missing>"); continue
    data = obj.get("data", {})
    sdata, total = {}, 0
    for k, b in data.items():
        v = base64.b64decode(b).decode()
        total += v.count(OLD)
        sdata[k] = v.replace(OLD, NEW)   # include ALL keys so re-apply is intact
    if total:
        print(f"  {s}: {total}")
        sec_occ += total
        if APPLY:
            print("    ->", kapply(s, sdata))

print(f"\nfiles={file_occ}  secrets={sec_occ}  | {'=== APPLIED ===' if APPLY else '=== DRY-RUN (use --apply) ==='}")
