#!/usr/bin/env python3
"""
Collect EVERY distinct S3 (accessKey, secretKey) pair presented by the apps and emit a JSON array
of SeaweedFS `apps` identities (each with Read/Write/List/Tagging — NOT Admin).

Why: our apps do not all share one S3 key. chatapi presents its SECURED_AWS_* key; extensions
ALSO presents a second plain AWS_* key in its config.json; more may appear. A single identity
would 403 the others. This scans secrets/apps/<app>/{.env,config.json} for both the plain
(AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY) and secured (SECURED_AWS_*) key pairs, in BOTH shell
(KEY=val) and JSON ("KEY": "val") forms, dedupes by access key, and prints the identities array.

deploy.sh (phase_secrets) wraps this output with the console (Admin) identity to form s3config.json.

Usage:  collect-app-s3-identities.py <secrets/apps dir>   ->  prints JSON array to stdout
Prints a human summary (access keys only, secrets redacted) to stderr; NEVER prints secrets to stdout
beyond the identity JSON the filer needs.
"""
import sys, os, re, glob, json

def find(txt, key):
    # matches  KEY=val   and   "KEY": "val"   (val = base64/hex-ish token)
    m = re.search(rf'"?{re.escape(key)}"?\s*[:=]\s*"?([A-Za-z0-9/+=_-]+)', txt)
    return m.group(1) if m else None

def main():
    base = sys.argv[1] if len(sys.argv) > 1 else "iac/secrets/apps"
    pairs = {}   # accessKey -> {secretKey, apps:set()}
    for f in sorted(glob.glob(f"{base}/*/.env")) + sorted(glob.glob(f"{base}/*/config.json")):
        app = os.path.basename(os.path.dirname(f))
        txt = open(f, encoding="utf-8", errors="replace").read()
        for ak_key, sk_key in (("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"),
                               ("SECURED_AWS_ACCESS_KEY_ID", "SECURED_AWS_SECRET_ACCESS_KEY")):
            ak, sk = find(txt, ak_key), find(txt, sk_key)
            if ak and sk:
                rec = pairs.setdefault(ak, {"secretKey": sk, "apps": set()})
                rec["apps"].add(app)
                if rec["secretKey"] != sk:
                    print(f"! WARN: access key {ak} has two different secrets across apps", file=sys.stderr)
    if not pairs:
        print("✗ no app S3 key pairs found — cannot build apps identities", file=sys.stderr)
        sys.exit(1)
    identities = []
    for i, (ak, rec) in enumerate(sorted(pairs.items())):
        identities.append({
            "name": f"apps-{i+1}",
            "credentials": [{"accessKey": ak, "secretKey": rec["secretKey"]}],
            "actions": ["Read", "Write", "List", "Tagging"],
        })
        print(f"  apps-{i+1}: accesskey={ak}  (used by {sorted(rec['apps'])})", file=sys.stderr)
    print(f"✓ {len(identities)} app S3 identit{'y' if len(identities)==1 else 'ies'} collected", file=sys.stderr)
    json.dump(identities, sys.stdout)

if __name__ == "__main__":
    main()
