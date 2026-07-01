#!/usr/bin/env python3
"""Create every per-app k8s secret FROM secrets-rendered/ — the single authoritative baseline.

secrets-rendered/ holds one file per app (already datastore-rewritten / fixed, pulled from live
by secret-pull.py). This script is the deploy's secret step: it recreates each live secret in the
exact SHAPE its pod consumes, with NO Vault dump and NO re-rewriting needed.

Shapes (verified against the live cluster):
  file env   -> Secret { .env: <whole file> }                 (mounted as a file volume)
  envFrom    -> Secret { KEY: value, ... }                     (injected via envFrom)
  extra      -> Secret { <filekey>: <file> }                   (second artifact some apps need)

This REPLACES secret-sync.py + secret-shapes.py in the deploy (those remain only as the one-time
Vault bootstrap that originally produced secrets-rendered/).

  ./scripts/secrets-from-rendered.py            # dry-run: show the plan (shapes + key counts)
  ./scripts/secrets-from-rendered.py --apply    # create/replace the live secrets
  ./scripts/secrets-from-rendered.py --apply calls-relay globalwebhooks   # limit to named apps
"""
import json, os, subprocess, sys

NS = os.environ.get("NS", "cometchat")
_IAC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # .../iac
KC = os.environ.get("KUBECONFIG", os.path.join(_IAC, "kubeconfig-6444"))
RENDERED = os.path.join(_IAC, "secrets-rendered")

# <app>-env delivered as a single .env file (mounted as a volume)
FILE_ENV = [
    "ai-agent-service", "chatapi", "mgmtapi",
    "moderationservice", "notifications-delay-worker", "receipt-updater",
    "visual-chat-builder", "websocket",
]
# analytics/extensions/sql-consumer removed: they mount their *-config JSON (see EXTRA), NOT an *-env.
# FILE_ENV was creating orphan analytics-env/extensions-env/sql-consumer-env (mounted by nobody, and the
# analytics/sql-consumer ones are config-wrapped blobs, not valid dotenvs).
# <app>-env delivered as individual KEY=value entries (envFrom)
ENVFROM = ["clamav", "globalwebhooks", "metrics-pro", "notificationscore", "service-search"]

# second artifact some apps additionally mount:  secret -> (key-inside-secret, source file in RENDERED)
EXTRA = {
    "analytics-config":    ("config.json",      "analytics-config.json"),    # JSON config the bytecode requires as ../config.json
    "extensions-config":   ("env.staging.json", "extensions-config.json"),   # JSON config file
    "sql-consumer-config": ("config.json",      "sql-consumer-config.json"), # JSON config file (holds TiDB root pw)
}


def kapply(name, string_data, apply):
    if not apply:
        return "plan"
    manifest = {
        "apiVersion": "v1", "kind": "Secret", "type": "Opaque",
        "metadata": {"name": name, "namespace": NS},
        "stringData": string_data,
    }
    p = subprocess.run(["kubectl", "--kubeconfig", KC, "apply", "-f", "-"],
                       input=json.dumps(manifest), capture_output=True, text=True)
    return "ok" if p.returncode == 0 else f"FAIL: {p.stderr.strip()[:140]}"


def parse_env(path):
    d = {}
    for line in open(path):
        raw = line.rstrip("\n")
        if not raw.strip() or raw.lstrip().startswith("#") or "=" not in raw:
            continue
        k, v = raw.split("=", 1)
        d[k.strip()] = v
    return d


def read(path):
    return open(path).read()


def main():
    apply = "--apply" in sys.argv
    only = [a for a in sys.argv[1:] if not a.startswith("--")]
    def want(app): return (not only) or (app in only)

    print(f"== secrets-from-rendered ({'APPLY' if apply else 'DRY-RUN'}) ==")

    for app in FILE_ENV:
        if not want(app):
            continue
        f = os.path.join(RENDERED, f"{app}.env")
        if not os.path.exists(f):
            print(f"  {app}-env: MISSING {app}.env — skipped"); continue
        n = len(parse_env(f))
        print(f"  {app:<28} file:.env   ({n} vars) -> {kapply(f'{app}-env', {'.env': read(f)}, apply)}")

    for app in ENVFROM:
        if not want(app):
            continue
        f = os.path.join(RENDERED, f"{app}.env")
        if not os.path.exists(f):
            print(f"  {app}-env: MISSING {app}.env — skipped"); continue
        d = parse_env(f)
        print(f"  {app:<28} envFrom     ({len(d)} keys) -> {kapply(f'{app}-env', d, apply)}")

    for secret, (filekey, src) in EXTRA.items():
        app = secret  # for --only matching, accept either the secret name or its base app
        base = src.rsplit(".", 1)[0]
        if only and secret not in only and base not in only:
            continue
        f = os.path.join(RENDERED, src)
        if not os.path.exists(f):
            print(f"  {secret}: MISSING {src} — skipped"); continue
        print(f"  {secret:<28} file:{filekey:<16} -> {kapply(secret, {filekey: read(f)}, apply)}")

    if not apply:
        print("\nDRY-RUN: re-run with --apply to create/replace the live secrets.")


if __name__ == "__main__":
    main()
