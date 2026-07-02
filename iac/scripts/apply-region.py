#!/usr/bin/env python3
"""Apply the on-prem region change to the LIVE k8s secrets, in one atomic prep step:
  1. region secret -> all consumers + mgmt-api (one value from iac/secrets/infra/region_secret)
  2. region id  us -> onprem   (ONPREM_REGION / REGION / *_REGION fields whose value is exactly 'us')
  3. host rename  *-us.cometchat-cluster-2.in -> *-onprem.cometchat-cluster-2.in   (region in service URLs)
Operates on the live secret VALUES (so all prior fixes are preserved) and re-applies in the
same shape. Run with --apply to write; default is a dry-run preview.
"""
import json, os, subprocess, sys, base64

_IAC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # .../iac
KC = os.environ.get("KUBECONFIG", os.path.join(_IAC, "kubeconfig-6444"))
NS = os.environ.get("NS", "cometchat")
APPLY = "--apply" in sys.argv
# NOTE: largely obsolete — the new mgmt image self-applies the region (regions.hash from
# ONPREM_REGION_SECRET) and secrets-rendered/ already ships -onprem hosts + REGION=onprem.
# Kept for ad-hoc use; reads the region secret from secrets/infra/region_secret if present.
SECRET = open(os.path.join(_IAC, "secrets", "infra", "region_secret")).read().strip()

# secret-name -> the plain env KEY that must equal the region secret
REGION_VAR = {
    "mgmtapi-env": "ONPREM_REGION_SECRET",
    "chatapi-env": "REGION_SECRET",
    "ai-agent-service-env": "COMETCHAT_REGION_SECRET",
    "moderationservice-env": "SECRET_ACCESS_KEY",
    "globalwebhooks-env": "CHAT_API_UNIVERSAL_KEY",
    "notificationscore-env": "CHAT_API_REGION_SECRET",
    "calls-relay-env": "UNIVERSAL_API_KEY",
}
# every secret to process (host-rename applies to all; region-secret only where mapped)
SECRETS = list(REGION_VAR) + [
    "websocket-env", "calls-relay-envfile", "sql-consumer-config", "extensions-config",
    "service-search-env", "metrics-pro-env", "analytics-env", "receipt-updater-env",
    "notifications-delay-worker-env", "visual-chat-builder-env",
]
REGION_ID_FIELDS = {"ONPREM_REGION", "REGION", "CHAT_API_REGION", "MICROSERVICE_REGION", "MICROSERVICE_CC_REGION"}

def kget(s):
    p = subprocess.run(f"kubectl --kubeconfig {KC} -n {NS} get secret {s} -o json", shell=True, capture_output=True, text=True)
    if p.returncode != 0: return None
    return json.load(open("/dev/stdin")) if False else json.loads(p.stdout)

def host_rename(v):
    return v.replace("-us.cometchat-cluster-2.in", "-onprem.cometchat-cluster-2.in") if isinstance(v, str) else v

def patch_envfile(content, regionvar):
    out, seen, n_host, n_region, n_sec = [], False, 0, 0, 0
    for ln in content.split("\n"):
        if "=" in ln and not ln.lstrip().startswith("#"):
            k, _, v = ln.partition("=")
            nv = host_rename(v)
            if nv != v: n_host += 1
            if k in REGION_ID_FIELDS and nv.strip() == "us": nv = "onprem"; n_region += 1
            if k == "SETTINGS_API":
                try:
                    j = json.loads(nv); j["apiKey"] = SECRET; nv = json.dumps(j); n_sec += 1
                except Exception: pass
            if regionvar and k == regionvar: nv = SECRET; seen = True; n_sec += 1
            out.append(f"{k}={nv}")
        else:
            out.append(ln)
    if regionvar and not seen:
        out.append(f"{regionvar}={SECRET}"); n_sec += 1
    return "\n".join(out), n_host, n_region, n_sec

def apply_stringdata(name, sdata):
    man = {"apiVersion": "v1", "kind": "Secret", "type": "Opaque",
           "metadata": {"name": name, "namespace": NS}, "stringData": sdata}
    p = subprocess.run(f"kubectl --kubeconfig {KC} apply -f -", input=json.dumps(man),
                       shell=True, capture_output=True, text=True)
    return "ok" if p.returncode == 0 else "FAIL: " + p.stderr.strip()[:120]

for s in SECRETS:
    obj = kget(s)
    if not obj:
        print(f"  {s}: <missing, skip>"); continue
    data = obj.get("data", {})
    keys = set(data.keys())
    regionvar = REGION_VAR.get(s)
    sdata, summ = {}, ""
    if keys == {".env"} or keys == {".env.staging"}:
        key = list(keys)[0]
        content = base64.b64decode(data[key]).decode()
        new, nh, nr, nsx = patch_envfile(content, regionvar)
        sdata[key] = new
        summ = f"envfile[{key}] host={nh} region-id={nr} secret-set={nsx}"
    elif keys == {"config.json"}:           # sql-consumer
        cfg = json.loads(base64.b64decode(data["config.json"]).decode())
        cfg.setdefault("API_CONFIG", {})["API_KEY"] = SECRET
        new = host_rename(json.dumps(cfg))
        sdata["config.json"] = new
        summ = f"config.json API_CONFIG.API_KEY=secret + host-rename"
    elif keys == {"env.staging.json"}:      # extensions
        new = host_rename(base64.b64decode(data["env.staging.json"]).decode())
        sdata["env.staging.json"] = new
        summ = "env.staging.json host-rename"
    else:                                    # individual-key (envFrom)
        nh = nr = nsx = 0
        for k, b64 in data.items():
            v = base64.b64decode(b64).decode()
            nv = host_rename(v)
            if nv != v: nh += 1
            if k in REGION_ID_FIELDS and nv.strip() == "us": nv = "onprem"; nr += 1
            if regionvar and k == regionvar: nv = SECRET; nsx += 1
            sdata[k] = nv
        if regionvar and regionvar not in data:
            sdata[regionvar] = SECRET; nsx += 1
        summ = f"envFrom({len(data)}k) host={nh} region-id={nr} secret-set={nsx}"
    status = apply_stringdata(s, sdata) if APPLY else "DRY-RUN"
    print(f"  {s}: {summ} -> {status}")

print(f"\n{'APPLIED' if APPLY else 'PREVIEW (use --apply to write)'} | region secret len={len(SECRET)}")
