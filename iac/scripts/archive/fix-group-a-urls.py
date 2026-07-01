#!/usr/bin/env python3
"""Group A: rewrite the unambiguous CometChat staging / wrong-cluster service URLs to the
on-prem cometchat-cluster-2.in hosts, in BOTH the live k8s secrets and the secrets-rendered baseline.
Only the clearly-mapped hosts are touched here (no Group B / Group C). Default dry-run; --apply writes.

Mapping (Group A only):
  ws-us.cometchat-staging.com           -> websocket-onprem.cometchat-cluster-2.in   (chatapi CHAT_HOST)
  rtcv5-us.cometchat-staging.com        -> rtc-onprem.cometchat-cluster-2.in         (chatapi WEBRTC_HOST)
  ALLOWED_API_DOMAINS                   -> cometchat-cluster-2.in                     (drop staging)
  metrics-pro-%s.cometchat-staging.com  -> metrics-pro-%s.cometchat-cluster-2.in     (mgmtapi METRICS_BASE_URL)
  media-us.cometchat-staging.com        -> media-onprem.cometchat-cluster-2.in       (moderation/clamav)
  files-* (URL_SPLIT...)                -> files-onprem.cometchat-cluster-2.in        (moderation/clamav)
  app-beta.cometchat-staging.com        -> app.cometchat-cluster-2.in                 (ai-agent COMPOSIO callback)
"""
import json, subprocess, sys, base64, os

_IAC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # .../iac
KC = os.environ.get("KUBECONFIG", os.path.join(_IAC, "kubeconfig-6444"))
NS = os.environ.get("NS", "cometchat")
RENDERED = os.path.join(_IAC, "secrets-rendered")
APPLY = "--apply" in sys.argv

# svc -> { KEY: ("substr", "replacement") } | { KEY: ("__SET__", "whole new value") }
GROUP_A = {
  "chatapi": {
    "CHAT_HOST":           ("ws-us.cometchat-staging.com",          "websocket-onprem.cometchat-cluster-2.in"),
    "WEBRTC_HOST":         ("rtcv5-us.cometchat-staging.com",       "rtc-onprem.cometchat-cluster-2.in"),
    "ALLOWED_API_DOMAINS": ("__SET__",                              "cometchat-cluster-2.in"),
  },
  "mgmtapi": {
    "METRICS_BASE_URL":    ("metrics-pro-%s.cometchat-staging.com", "metrics-pro-%s.cometchat-cluster-2.in"),
  },
  "moderationservice": {
    "BUCKET_NAME_SECRET_ACCESS_TOKEN_FILE": ("media-us.cometchat-staging.com", "media-onprem.cometchat-cluster-2.in"),
    "URL_SPLIT_SECRET_ACCESS_TOKEN":        ("__SET__",                        "files-onprem.cometchat-cluster-2.in"),
  },
  "clamav": {
    "BUCKET_NAME_SECRET_ACCESS_TOKEN_FILE": ("media-us.cometchat-staging.com", "media-onprem.cometchat-cluster-2.in"),
    "URL_SPLIT_SECRET_ACCESS_TOKEN":        ("__SET__",                        "files-onprem.cometchat-cluster-2.in"),
  },
  "ai-agent-service": {
    "COMPOSIO_OAUTH_CALLBACK_URL": ("app-beta.cometchat-staging.com", "app.cometchat-cluster-2.in"),
  },
}

def patch_env(content, spec):
    out, changed = [], []
    for ln in content.split("\n"):
        if "=" in ln and not ln.lstrip().startswith("#"):
            k, _, v = ln.partition("=")
            if k in spec:
                mode, val = spec[k]
                nv = val if mode == "__SET__" else v.replace(mode, val)
                if nv != v:
                    changed.append(f"{k}: {v}  ->  {nv}")
                    ln = f"{k}={nv}"
        out.append(ln)
    return "\n".join(out), changed

def kget(secret):
    p = subprocess.run(f"kubectl --kubeconfig {KC} -n {NS} get secret {secret} -o json",
                       shell=True, capture_output=True, text=True)
    return json.loads(p.stdout) if p.returncode == 0 else None

def kapply(secret, key, content):
    man = {"apiVersion":"v1","kind":"Secret","type":"Opaque",
           "metadata":{"name":secret,"namespace":NS},"stringData":{key:content}}
    p = subprocess.run(f"kubectl --kubeconfig {KC} apply -f -", input=json.dumps(man),
                       shell=True, capture_output=True, text=True)
    return "ok" if p.returncode==0 else "FAIL: "+p.stderr.strip()[:140]

for svc, spec in GROUP_A.items():
    secret = svc + "-env"
    print(f"\n==== {secret} ====")
    obj = kget(secret)
    if not obj:
        print("  <live secret missing>")
    else:
        data = obj.get("data", {})
        envkey, content = None, None
        for k, b in data.items():
            try: dec = base64.b64decode(b).decode()
            except Exception: continue
            if "=" in dec:
                envkey, content = k, dec; break
        if not envkey:
            print("  <no .env blob key>")
        else:
            new, changed = patch_env(content, spec)
            for c in changed: print("  LIVE", c)
            if not changed: print("  LIVE (already clean)")
            if APPLY and changed: print("  ->", kapply(secret, envkey, new))
    rf = os.path.join(RENDERED, svc + ".env")
    if os.path.exists(rf):
        new, changed = patch_env(open(rf).read(), spec)
        for c in changed: print("  REND", c)
        if not changed: print("  REND (already clean)")
        if APPLY and changed: open(rf,"w").write(new); print("  REND written")
    else:
        print("  <rendered missing>")

print("\n" + ("=== APPLIED ===" if APPLY else "=== DRY-RUN (pass --apply to write) ==="))
