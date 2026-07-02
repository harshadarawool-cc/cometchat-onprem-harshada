#!/usr/bin/env python3
"""
sync-app-db-creds.py — stamp the freshly-generated datastore passwords (from secrets/infra/cluster-creds.yml)
into the application secrets (secrets/apps/<app>/), so every app authenticates with EXACTLY what ansible
provisioned the datastores with. Run by deploy.sh phase_secrets BEFORE secrets-from-rendered.py. Both this
script AND ansible read cluster-creds.yml -> the datastore creds and the app secrets can never drift.

Robust to every shape these secrets take (context-based, never matches the old value):
  * Mongo  : every  mongodb://<user>:<pw>@  (admin/extadmin/webhookuser) -> that user's fresh pw. Any format.
  * MySQL/TiDB root, wherever host+password sit together:
      - plain .env  : DB_*PASSWORD* whose sibling *HOST(NAME)* is the MySQL/TiDB ip.
      - JSON value  : KEY={...}/[...] with {"host": <ip>, "password": ...}  (e.g. CHAT_DB, PRIVATE_DATABASES).
      - whole JSON  : *-config.json / *.env that are pure JSON blobs, same {"host","password"} walk.
    App-to-app passwords (paired with a NON-datastore host) are left untouched.

Idempotent. FAILS LOUDLY if a cred is missing or none of the 5 datastore creds end up in the app secrets.
"""
import os, re, sys, glob, json

IAC = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CREDS = os.environ.get("CC_CREDS", os.path.join(IAC, "secrets", "infra", "cluster-creds.yml"))
RENDERED = os.environ.get("CC_RENDERED", os.path.join(IAC, "secrets", "apps"))   # per-app folders: apps/<app>/{.env,config.json}
INVENTORY = os.environ.get("CC_INVENTORY", os.path.join(IAC, "ansible", "inventory", "hosts.yml"))
MONGO_USER_TO_CRED = {"admin": "vault_mongo_app_admin_password",
                      "extadmin": "vault_mongo_extadmin_password",
                      "webhookuser": "vault_mongo_webhookuser_password"}

def die(m): print(f"  ✗ sync-app-db-creds: {m}", file=sys.stderr); sys.exit(1)

def load_creds():
    if not os.path.exists(CREDS):
        die(f"missing {CREDS} — run scripts/gen-cluster-creds.sh (deploy.sh phase_credgen) first")
    creds = {}
    for ln in open(CREDS):
        m = re.match(r'\s*([a-z_]+_password)\s*:\s*"?([^"#\s]+)"?', ln)
        if m: creds[m.group(1)] = m.group(2)
    for k in ("vault_mysql_root_password","vault_tidb_root_password","vault_mongo_app_admin_password",
              "vault_mongo_extadmin_password","vault_mongo_webhookuser_password"):
        if not creds.get(k): die(f"cred '{k}' missing/empty in cluster-creds.yml")
    return creds

def datastore_ips():
    mysql_ip = tidb_ip = None
    if os.path.exists(INVENTORY):
        t = open(INVENTORY).read()
        a = re.search(r'mysql-\d+:\s*\{\s*int_ip:\s*([0-9.]+)', t); mysql_ip = a.group(1) if a else None
        b = re.search(r'tidb-\d+:\s*\{\s*int_ip:\s*([0-9.]+)',  t); tidb_ip  = b.group(1) if b else None
    return mysql_ip or "10.24.10.41", tidb_ip or "10.24.10.51"

def mongo_sub(text, creds):
    return re.sub(r'mongodb://(admin|extadmin|webhookuser):[^@]+@',
                  lambda m: f'mongodb://{m.group(1)}:{creds[MONGO_USER_TO_CRED[m.group(1)]]}@', text)

def walk_hostpw(o, creds, mysql_ip, tidb_ip, cnt):
    """set password of any {"host": <mysql|tidb ip>, "password": ...} object to that datastore's root pw."""
    if isinstance(o, dict):
        h = o.get("host")
        if h in (mysql_ip, tidb_ip) and "password" in o:
            o["password"] = creds["vault_mysql_root_password"] if h == mysql_ip else creds["vault_tidb_root_password"]
            cnt[0] += 1
        for v in o.values(): walk_hostpw(v, creds, mysql_ip, tidb_ip, cnt)
    elif isinstance(o, list):
        for v in o: walk_hostpw(v, creds, mysql_ip, tidb_ip, cnt)

def json_value_spans(text):
    """yield (start, end, key) for each  KEY={...} / KEY=[...]  with balanced brackets (single- OR multi-line)."""
    spans = []
    for m in re.finditer(r'(?:^|\n)([A-Za-z0-9_]+)=([{\[])', text):
        start = m.start(2); depth = 0; in_str = False; esc = False; j = start
        while j < len(text):
            c = text[j]
            if in_str:
                if esc: esc = False
                elif c == '\\': esc = True
                elif c == '"': in_str = False
            elif c == '"': in_str = True
            elif c in '{[': depth += 1
            elif c in '}]':
                depth -= 1
                if depth == 0: break
            j += 1
        spans.append((start, j + 1, m.group(1)))
    return spans

def patch_file(path, creds, mysql_ip, tidb_ip):
    raw = open(path).read()
    changed = []
    m2 = mongo_sub(raw, creds)
    if m2 != raw: raw = m2; changed.append("mongo")
    # (a) whole-file JSON blob
    if raw.lstrip()[:1] in "{[":
        try:
            data = json.loads(raw); cnt = [0]; walk_hostpw(data, creds, mysql_ip, tidb_ip, cnt)
            if cnt[0]: changed.append(f"json-db×{cnt[0]}"); raw = json.dumps(data, indent=2) + "\n"
            if changed: open(path, "w").write(raw)
            return changed
        except json.JSONDecodeError:
            pass
    # (b) JSON-in-value spans (KEY={...}/[...], possibly multi-line) — splice in reverse to keep offsets
    for start, end, key in reversed(json_value_spans(raw)):
        try:
            jv = json.loads(raw[start:end]); cnt = [0]; walk_hostpw(jv, creds, mysql_ip, tidb_ip, cnt)
            if cnt[0]:
                raw = raw[:start] + json.dumps(jv, indent=2) + raw[end:]; changed.append(f"{key}(json×{cnt[0]})")
        except json.JSONDecodeError:
            pass
    # (c) plain .env  DB_*PASSWORD* whose sibling *HOST(NAME)* is a datastore ip
    lines = raw.splitlines()
    kv = {l.split("=",1)[0].strip(): l.split("=",1)[1].strip()
          for l in lines if "=" in l and not l.lstrip().startswith("#")}
    def cred_for(h): return "vault_mysql_root_password" if h == mysql_ip else ("vault_tidb_root_password" if h == tidb_ip else None)
    def sib(pk):
        for r in ("HOSTNAME","HOST"):
            hk = pk.replace("PASSWORD", r, 1)
            if hk in kv: return kv[hk]
        return None
    out = []
    for l in lines:
        mp = re.match(r'^([A-Za-z0-9_]*PASSWORD[A-Za-z0-9_]*)=(.*)$', l)
        if mp:
            c = cred_for(sib(mp.group(1)) or "")
            if c: out.append(f"{mp.group(1)}={creds[c]}"); changed.append(mp.group(1)); continue
        out.append(l)
    new = "\n".join(out) + "\n"
    if new != raw: raw = new
    if changed: open(path, "w").write(raw)
    return changed

def main():
    creds = load_creds(); mysql_ip, tidb_ip = datastore_ips()
    print(f"  sync-app-db-creds: MySQL={mysql_ip} TiDB={tidb_ip}; patching {RENDERED}")
    files = sorted(glob.glob(os.path.join(RENDERED, "*", ".env")) + glob.glob(os.path.join(RENDERED, "*", "config.json")))
    files = [f for f in files if os.path.isfile(f)]
    if not files: die(f"no apps/<app>/.env under {RENDERED}")
    total = 0
    for f in files:
        ch = patch_file(f, creds, mysql_ip, tidb_ip)
        if ch: total += len(ch); print(f"    {os.path.basename(f):<30} -> {', '.join(ch)}")
    blob = "".join(open(f).read() for f in files)
    for k in ("vault_mysql_root_password","vault_tidb_root_password","vault_mongo_app_admin_password",
              "vault_mongo_extadmin_password","vault_mongo_webhookuser_password"):
        if creds[k] not in blob: die(f"post-sync check FAILED: {k} not in any app secret — did NOT sync")
    print(f"  ✓ synced {total} field(s); all 5 datastore creds verified present in app secrets")

if __name__ == "__main__":
    main()
