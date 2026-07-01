#!/usr/bin/env python3
"""Build per-service k8s env secrets from the staging Vault envs, rewriting ONLY
datastore endpoints to the GCP datastores (two-axis rule: datastore hosts change,
service URLs / http(s) schemes untouched). Then `kubectl create secret`.

Source: /tmp/cc-vault-envs-v2/<vault>.json   Target ns: cometchat
"""
import json, os, subprocess, sys

SRC = os.environ.get("VAULT_ENVS_DIR", "/tmp/cc-vault-envs-v2")   # legacy one-time Vault dump
NS = os.environ.get("NS", "cometchat")
_IAC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # .../iac
KUBECONFIG = os.environ.get("KUBECONFIG", os.path.join(_IAC, "kubeconfig-6444"))
OUT = os.path.join(_IAC, "secrets-rendered")  # local .env copies (sensitive)
os.makedirs(OUT, exist_ok=True)

# vault service name -> k8s secret base name (deploy name)
SERVICES = {
    "chatapi": "chatapi", "mgmtapi": "mgmtapi", "websocket": "websocket",
    "notificationscore": "notificationscore", "moderationservice": "moderationservice",
    "globalwebhooks": "globalwebhooks", "receipt-updater": "receipt-updater",
    "sql-consumer": "sql-consumer", "extensions": "extensions",
    "service-search": "service-search", "ai-agent-service": "ai-agent-service",
    "calls-relay": "calls-relay", "clamav": "clamav", "metrics-pro": "metrics-pro",
    "analytics-api": "analytics", "visual-chat-builder": "visual-chat-builder",
    "notifications-delay-worker": "notifications-delay-worker",
}

# Blanket single-mapping datastore host rewrites (mongo/kafka/tidb/mysql + named hosts + ns)
BLANKET = {
    "10.0.0.14": "10.20.10.11",                       # mongo rs0 seed
    "10.0.0.5": "10.20.10.31", "10.0.0.7": "10.20.10.32", "10.0.0.9": "10.20.10.33",  # kafka
    "10.0.0.11": "10.20.10.51",                       # tidb (chatapi + receipts)
    "10.0.0.12": "10.20.10.41",                       # mysql (mgmtapi)
    "us-pro-metrics-db.cometchat.io": "10.20.10.41",  # metrics RDS -> mysql VM
    "us-analytics-rds.cometchat.io": "10.20.10.41",   # analytics RDS -> mysql VM
    "cometchat_mysql-db": "10.20.10.41",
    "cometchat-aniket": "cometchat",                  # in-cluster namespace rename (opensearch/qdrant/ollama/mailpit)
}

# Redis: 4 dedicated clusters (nodes[0]=master)
RCLUSTER = {
    "shared":     ["10.20.10.21", "10.20.10.22", "10.20.10.23"],
    "analytics":  ["10.20.10.24", "10.20.10.25", "10.20.10.26"],
    "prometrics": ["10.20.10.27", "10.20.10.28", "10.20.10.29"],
    "bullmq":     ["10.20.10.61", "10.20.10.62", "10.20.10.63"],
}
SVC_REDIS = {  # default cluster per service (non-bullmq keys)
    "chatapi": "shared", "websocket": "shared", "ai-agent-service": "shared",
    "receipt-updater": "shared", "notificationscore": "shared",
    "analytics-api": "analytics", "metrics-pro": "prometrics",
    "notifications-delay-worker": "bullmq",
}
STAGING_REDIS = ["10.0.0.6", "10.0.0.8", "10.0.0.10"]


def rewrite(svc, key, val):
    if not isinstance(val, str):
        val = json.dumps(val)
    # --- redis (key/context-aware) ---
    if any(ip in val for ip in STAGING_REDIS):
        cluster = "bullmq" if "BULLMQ" in key.upper() else SVC_REDIS.get(svc, "shared")
        nodes = RCLUSTER[cluster]
        if "26379" in val or "SENTINEL" in key.upper():     # sentinel list -> 3 nodes
            val = val.replace("10.0.0.6", nodes[0]).replace("10.0.0.8", nodes[1]).replace("10.0.0.10", nodes[2])
        else:                                                 # single host -> master
            val = val.replace("10.0.0.8", nodes[0]).replace("10.0.0.6", nodes[0]).replace("10.0.0.10", nodes[0])
    # --- blanket datastore hosts ---
    for a, b in BLANKET.items():
        if a in val:
            val = val.replace(a, b)
    return val


def main():
    summary = []
    for vault_name, secret in SERVICES.items():
        f = os.path.join(SRC, vault_name + ".json")
        if not os.path.exists(f):
            summary.append(f"{secret}: NO VAULT ENV"); continue
        d = json.load(open(f))
        lines, changed = [], 0
        for k, v in d.items():
            nv = rewrite(vault_name, k, v)
            if isinstance(v, str) and nv != v:
                changed += 1
            lines.append(f"{k}={nv}")
        envfile = os.path.join(OUT, secret + ".env")
        open(envfile, "w").write("\n".join(lines) + "\n")
        # create/replace the k8s secret
        p = subprocess.run(
            f"kubectl --kubeconfig {KUBECONFIG} -n {NS} create secret generic {secret}-env "
            f"--from-file=.env={envfile} --dry-run=client -o yaml | kubectl --kubeconfig {KUBECONFIG} apply -f -",
            shell=True, capture_output=True, text=True)
        ok = "ok" if p.returncode == 0 else f"FAIL: {p.stderr.strip()[:120]}"
        summary.append(f"{secret}-env: {len(d)} keys, {changed} datastore rewrites -> {ok}")
    print("\n".join(summary))


if __name__ == "__main__":
    main()
