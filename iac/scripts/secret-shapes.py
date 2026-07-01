#!/usr/bin/env python3
"""Build secrets in the SHAPE each app actually consumes (per swarm_to_k8s_GCP reference):
  - envFrom apps  -> Secret with INDIVIDUAL key=value entries (stringData), datastore-rewritten.
  - file apps     -> Secret with a single file key (.env / .env.staging / config.json / env.staging.json).
All data still lives in k8s Secrets; only the delivery shape differs. Reuses secret-sync.rewrite()
so datastore endpoints are rewritten identically (two-axis rule preserved).
"""
import json, os, subprocess, importlib.util, sys

SRC = os.environ.get("VAULT_ENVS_DIR", "/tmp/cc-vault-envs-v2")   # legacy one-time Vault dump
NS = os.environ.get("NS", "cometchat")
_IAC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # .../iac
KC = os.environ.get("KUBECONFIG", os.path.join(_IAC, "kubeconfig-6444"))

# import rewrite() from secret-sync.py (hyphenated filename)
spec = importlib.util.spec_from_file_location("secretsync", os.path.join(_IAC, "scripts", "secret-sync.py"))
ss = importlib.util.module_from_spec(spec); spec.loader.exec_module(ss)

# apps consumed via envFrom -> individual keys
ENVFROM = {
    "globalwebhooks": "globalwebhooks",
    "service-search": "service-search",
    "calls-relay": "calls-relay",
    "notificationscore": "notificationscore",
    "metrics-pro": "metrics-pro",          # PM2 app, no dotenv -> needs real env vars
}

# .env-FILE apps that need empty non-datastore values filled to pass the image's config validator
# (make-valid only: observability creds the app refuses to start without; staging Vault left empty).
FILL_EMPTY = {
    "ai-agent-service": {
        "LOKI_HOST": "http://localhost:3100",  # must be a valid URL (app builds <host>/loki/api/v1/push); no Loki on-prem
        "METRICS_USERNAME": "metrics",
        "METRICS_PASSWORD": "metrics",
    },
}

# Per-app keys whose Kafka broker list must be COMMA-separated host:port (the app comma-splits,
# it does NOT JSON.parse) — normalize JSON-array values to comma strings. Datastore-endpoint axis.
COMMA_BROKERS = {
    "globalwebhooks": ["BROKERS", "KAFKA_BROKER_PRODUCER"],
}
# config delivered as a single JSON file (vault key 'config_json' -> file)
CONFIGFILE = {
    "sql-consumer": ("sql-consumer-config", "config.json"),
    "extensions":   ("extensions-config", "env.staging.json"),
}

def kapply_secret(name, string_data):
    """Create/replace a generic secret from a stringData dict via apply."""
    manifest = {
        "apiVersion": "v1", "kind": "Secret", "type": "Opaque",
        "metadata": {"name": name, "namespace": NS},
        "stringData": string_data,
    }
    p = subprocess.run(
        f"kubectl --kubeconfig {KC} apply -f -",
        input=json.dumps(manifest), shell=True, capture_output=True, text=True)
    return "ok" if p.returncode == 0 else f"FAIL: {p.stderr.strip()[:140]}"

def rewritten_items(vault_name):
    d = json.load(open(os.path.join(SRC, vault_name + ".json")))
    out = {}
    comma_keys = COMMA_BROKERS.get(vault_name, [])
    for k, v in d.items():
        nv = ss.rewrite(vault_name, k, v)
        if k in comma_keys and isinstance(nv, str) and nv.strip().startswith("["):
            try: nv = ",".join(json.loads(nv))   # JSON array -> comma string
            except Exception: pass
        out[k] = nv
    return out

def main():
    print("== envFrom secrets (individual keys) ==")
    for vault, secret in ENVFROM.items():
        f = os.path.join(SRC, vault + ".json")
        if not os.path.exists(f):
            print(f"  {secret}-env: NO VAULT ENV"); continue
        items = rewritten_items(vault)
        print(f"  {secret}-env: {len(items)} keys -> {kapply_secret(secret + '-env', items)}")

    print("== calls-relay-envfile (.env.staging file) ==")
    items = rewritten_items("calls-relay")
    envfile = "\n".join(f"{k}={v}" for k, v in items.items()) + "\n"
    print(f"  calls-relay-envfile: -> {kapply_secret('calls-relay-envfile', {'.env.staging': envfile})}")

    print("== config-file secrets (config_json -> JSON file) ==")
    for vault, (secret, filekey) in CONFIGFILE.items():
        f = os.path.join(SRC, vault + ".json")
        if not os.path.exists(f):
            print(f"  {secret}: NO VAULT ENV"); continue
        d = json.load(open(f))
        raw = d.get("config_json")
        if raw is None:
            print(f"  {secret}: no config_json key (keys={list(d)[:5]})"); continue
        val = ss.rewrite(vault, "config_json", raw)   # apply datastore rewrites to the JSON blob
        # validate it parses as JSON
        try: json.loads(val); ok = "valid-json"
        except Exception as e: ok = f"WARN not-json: {e}"
        print(f"  {secret} [{filekey}] ({ok}): -> {kapply_secret(secret, {filekey: val})}")

    print("== .env-file apps: fill empty non-datastore values the validator requires ==")
    for vault, fills in FILL_EMPTY.items():
        d = json.load(open(os.path.join(SRC, vault + ".json")))
        lines, filled = [], []
        for k, v in d.items():
            nv = ss.rewrite(vault, k, v)
            if k in fills and (nv == "" or nv == "''"):
                nv = fills[k]; filled.append(k)
            lines.append(f"{k}={nv}")
        envfile = "\n".join(lines) + "\n"
        print(f"  {vault}-env (filled={filled}): -> {kapply_secret(vault + '-env', {'.env': envfile})}")

    print("== websocket-env: fix empty SENTRY -> {} (zod requires object) ==")
    d = json.load(open(os.path.join(SRC, "websocket.json")))
    lines = []
    fixed = False
    for k, v in d.items():
        nv = ss.rewrite("websocket", k, v)
        if k == "SENTRY" and (nv == "" or nv == "''"):
            nv = "{}"; fixed = True
        lines.append(f"{k}={nv}")
    envfile = "\n".join(lines) + "\n"
    print(f"  websocket-env (SENTRY fixed={fixed}): -> {kapply_secret('websocket-env', {'.env': envfile})}")

if __name__ == "__main__":
    main()
