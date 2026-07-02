#!/usr/bin/env python3
"""Pull LIVE k8s env secrets back into secrets-rendered/ (the reverse of secret-sync.py).

Source of truth = what's actually mounted in the pods. For each app we read the live
`<app>-env` secret and write its decoded contents to secrets-rendered/<app>.env, so the
local baseline reflects any drift from live `kubectl edit`/patch changes.

Two live storage styles are handled automatically:
  * file style   -> secret has a single `.env` key (mounted as a file volume)
  * envFrom style -> secret has one entry per variable (injected via envFrom)
Either way the rendered file is written as KEY=value lines.

Default is DRY-RUN: it only reports drift (key names + counts, never values).
Pass --write to actually update the files (existing files are backed up first).

  ./scripts/secret-pull.py                # report drift for all apps
  ./scripts/secret-pull.py --write        # apply (with backup)
  ./scripts/secret-pull.py chatapi mongo  # limit to named apps
"""
import base64, json, os, subprocess, sys, time

NS = os.environ.get("NS", "cometchat")
_IAC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # .../iac
KUBECONFIG = os.environ.get("KUBECONFIG", os.path.join(_IAC, "kubeconfig-6444"))
OUT = os.path.join(_IAC, "secrets-rendered")

# rendered file stem  ==  live secret base name (secret is "<stem>-env")
APPS = [
    "ai-agent-service", "analytics", "chatapi", "clamav",
    "extensions", "globalwebhooks", "metrics-pro", "mgmtapi", "moderationservice",
    "notifications-delay-worker", "notificationscore", "receipt-updater",
    "service-search", "sql-consumer", "visual-chat-builder", "websocket",
]


def get_secret(name):
    p = subprocess.run(
        ["kubectl", "--kubeconfig", KUBECONFIG, "-n", NS, "get", "secret", name, "-o", "json"],
        capture_output=True, text=True)
    if p.returncode != 0:
        return None
    return json.loads(p.stdout).get("data", {})


def decode(b64):
    return base64.b64decode(b64).decode("utf-8", "replace")


def kv_parse(text):
    """Parse KEY=value lines, preserving first-seen order. Comments/blank/no-'=' ignored."""
    d, order = {}, []
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        k = k.strip()
        if k not in d:
            order.append(k)
        d[k] = v
    return d, order


def build_new(data, old_text):
    """Return (new_text, multiline_keys). Preserve old file order, append new keys sorted."""
    if list(data.keys()) == [".env"]:
        # file style: the decoded blob IS the file content
        text = decode(data[".env"])
        if not text.endswith("\n"):
            text += "\n"
        ml = [k for k, v in kv_parse(text)[0].items() if "\n" in v]
        return text, ml
    # envFrom style: reconstruct KEY=value
    sec = {k: decode(v) for k, v in data.items()}
    _, old_order = kv_parse(old_text)
    lines, seen = [], set()
    for k in old_order:
        if k in sec:
            lines.append(f"{k}={sec[k]}")
            seen.add(k)
    for k in sorted(sec):
        if k not in seen:
            lines.append(f"{k}={sec[k]}")
    ml = [k for k, v in sec.items() if "\n" in v]
    return "\n".join(lines) + "\n", ml


def report(app, old_text, new_text):
    od, _ = kv_parse(old_text)
    nd, _ = kv_parse(new_text)
    added = sorted(set(nd) - set(od))
    removed = sorted(set(od) - set(nd))
    changed = sorted(k for k in set(od) & set(nd) if od[k] != nd[k])
    if not (added or removed or changed) and old_text == new_text:
        print(f"  {app:<28} in sync")
        return False
    print(f"  {app:<28} DRIFT  +{len(added)} added  -{len(removed)} removed  ~{len(changed)} changed")
    if added:   print(f"        added  : {', '.join(added)}")
    if removed: print(f"        removed: {', '.join(removed)}")
    if changed: print(f"        changed: {', '.join(changed)}")
    return True


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    write = "--write" in sys.argv
    apps = args or APPS

    backup = None
    if write:
        backup = os.path.join(OUT, ".bak-" + time.strftime("%Y%m%d-%H%M%S"))
        os.makedirs(backup, exist_ok=True)

    drifted = 0
    for app in apps:
        data = get_secret(f"{app}-env")
        envfile = os.path.join(OUT, f"{app}.env")
        old_text = open(envfile).read() if os.path.exists(envfile) else ""
        if data is None:
            print(f"  {app:<28} SECRET MISSING in cluster — skipped")
            continue
        new_text, ml = build_new(data, old_text)
        if ml:
            print(f"  {app:<28} ⚠ multi-line values (KEY=value may be lossy): {', '.join(ml)}")
        if report(app, old_text, new_text):
            drifted += 1
            if write:
                if old_text:
                    open(os.path.join(backup, f"{app}.env"), "w").write(old_text)
                open(envfile, "w").write(new_text)

    print()
    if write:
        print(f"✓ wrote {drifted} changed file(s); backups in {backup}")
    else:
        print(f"DRY-RUN: {drifted} app(s) drifted. Re-run with --write to apply.")


if __name__ == "__main__":
    main()
