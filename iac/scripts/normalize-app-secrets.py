#!/usr/bin/env python3
"""
normalize-app-secrets.py — make the app secrets (secrets/apps/<app>/{.env,*.json}) match THIS cluster,
so a fresh deploy on a new prefix/CIDR can't ship stale datastore IPs or a shape the app can't parse.
Run by deploy.sh phase_secrets BEFORE sync-app-db-creds.py. Idempotent.

Fixes two whole CLASSES of bug we hit the hard way:

  1) DATASTORE IP DRIFT — the app secrets hardcode datastore VM IPs (DB_HOST=10.23.10.51, REDIS=…, KAFKA=…).
     When the cluster's data subnet changes (v3 10.23.x -> v4 10.24.x -> …), those go stale and every app
     talks to the WRONG (or unreachable) cluster. We rewrite any datastore-shaped IP (X.X.10.<known octet>)
     to THIS cluster's data /24 (from customer.conf SUBNET_DATA_CIDR). Datastore host octets:
       mongo 11-13 · redis 21-29 (shared/analytics/prometrics) + 61-63 (bullmq) · kafka 31-33 · mysql 41 · tidb 51
     Passwords/hostnames are untouched — only the /24 prefix of a datastore IP is rewritten.

  2) MULTI-LINE JSON ENV — some .env values are pretty-printed JSON objects (e.g. CHAT_DB={\n  "host":… }).
     dotenv reads only the first line -> the app gets "{" and fails ("Expected object, received string").
     We collapse any KEY={…}/KEY=[…] multi-line JSON value to a single line so it parses.

Usage:  SUBNET_DATA_CIDR=10.24.10.0/24 python3 normalize-app-secrets.py [secrets/apps]
"""
import os, re, sys, glob, json

IAC = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
APPS = sys.argv[1] if len(sys.argv) > 1 else os.path.join(IAC, "secrets", "apps")
CIDR = os.environ.get("SUBNET_DATA_CIDR", "")
if not CIDR:
    # fall back to reading customer.conf
    conf = os.path.join(IAC, "deploy", "customer.conf")
    if os.path.exists(conf):
        m = re.search(r'^\s*SUBNET_DATA_CIDR\s*=\s*"?([0-9.]+)/\d+', open(conf).read(), re.M)
        if m: CIDR = m.group(1)
if not CIDR:
    print("  ! normalize-app-secrets: SUBNET_DATA_CIDR unknown — skipping IP normalize", file=sys.stderr)

DATA_PREFIX = ".".join(CIDR.split(".")[:3]) if CIDR else ""   # e.g. "10.24.10"
# datastore host octets in the data /24
OCT = r'(1[1-3]|2[0-9]|3[0-3]|41|51|6[0-3])'
IP_RE = re.compile(r'\b\d{1,3}\.\d{1,3}\.10\.' + OCT + r'\b')

def fix_ips(text):
    if not DATA_PREFIX:
        return text, 0
    n = [0]
    def repl(m):
        new = f"{DATA_PREFIX}.{m.group(1)}"
        if m.group(0) != new: n[0] += 1
        return new
    return IP_RE.sub(repl, text), n[0]

def collapse_json_env(text):
    lines = text.split("\n"); out = []; i = 0; fixed = 0
    while i < len(lines):
        m = re.match(r'^([A-Za-z0-9_]+)=(\{|\[)\s*$', lines[i])
        if m:
            key = m.group(1); buf = lines[i].split("=", 1)[1]; j = i + 1
            depth = buf.count("{") + buf.count("[") - buf.count("}") - buf.count("]")
            while j < len(lines) and depth > 0:
                buf += "\n" + lines[j]
                depth += lines[j].count("{") + lines[j].count("[") - lines[j].count("}") - lines[j].count("]")
                j += 1
            try:
                out.append(f"{key}={json.dumps(json.loads(buf), separators=(',', ':'))}")
                fixed += 1; i = j; continue
            except Exception:
                pass
        out.append(lines[i]); i += 1
    return "\n".join(out), fixed

def main():
    # NOTE: glob's "*" does NOT match a leading dot, so ".env" must be matched explicitly (not "*.env").
    files = sorted(glob.glob(os.path.join(APPS, "*", ".env")) +
                   glob.glob(os.path.join(APPS, "*", "*.env")) +
                   glob.glob(os.path.join(APPS, "*", "*.json")))
    files = [f for f in files if os.path.isfile(f) and not f.endswith(".example")]
    tot_ip = tot_js = 0
    for f in files:
        raw = open(f).read(); t = raw
        t, nip = fix_ips(t)
        if f.endswith(".env"):
            t, njs = collapse_json_env(t)
        else:
            njs = 0
        if t != raw:
            open(f, "w").write(t)
            print(f"    {os.path.relpath(f, IAC):45} ip-fix={nip} json-collapse={njs}")
        tot_ip += nip; tot_js += njs
    print(f"  ✓ normalize-app-secrets: data-subnet={DATA_PREFIX or '(unknown)'} · {tot_ip} IP(s) repointed · {tot_js} JSON value(s) collapsed")

if __name__ == "__main__":
    main()
