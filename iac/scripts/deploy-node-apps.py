#!/usr/bin/env python3
"""Generate + apply manifests for the NODE-ONLY ECR apps that have NO curated manifest in
k8s/apps/.  Each: ECR image + ecr-pull + <svc>-env mounted as .env file. websocket also mounts
jwtrsakey.pem. Workers: no Service. dashboard: nginx-serves-the-baked-build.

IMPORTANT — single source of truth (PROBLEMS I*/audit 2026-06-24):
  Services that have a curated, digest-pinned manifest in k8s/apps/* (notificationscore,
  globalwebhooks, service-search, analytics, metrics-pro, extensions, sql-consumer) and
  calls-relay (k8s/apps/disabled/) are deployed by the `apps` phase ONLY. They are deliberately
  NOT in the lists below so this script can no longer clobber them with generic, mutable-tag
  copies. This script owns ONLY the services below — the ones with no .yaml anywhere else.

Kubeconfig: KUBECONFIG env wins, else iac/kubeconfig-6444 resolved relative to this file (so a
clean checkout on any machine works — no hardcoded /Users path)."""
import subprocess, tempfile, os
ECR = os.environ.get("ECR_IMAGES_REPO", "894996064311.dkr.ecr.us-east-2.amazonaws.com/on-prem-docker-images")
NS = os.environ.get("NS", "cometchat")
_IAC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # .../iac
KC = os.environ.get("KUBECONFIG", os.path.join(_IAC, "kubeconfig-6444"))

# name, digest, port, env_path, health_path(None=tcp), wants_jwt, tls_sidecar
# ONLY services with NO curated k8s/apps manifest (see header).
# Pinned by DIGEST (immutable) — was mutable :tag. Repin from the ECR digest table when updating.
# tls_sidecar: True  -> per-pod nginx dual :80/:443 sidecar (colleague/pod-TLS parity) + <name>-nginx
#              ConfigMap (WS Upgrade headers, wildcard-tls at /tls) + Service http/https/app ports.
#              False -> bare pod (app container only, Service targets the app port directly).
# ai-agent-service STAYS BARE (tls_sidecar=False) — no east-west TLS front.
NODE = [
    ("websocket", "sha256:57c6d000f704f5c0f4cab6f46ca6f6ef982ab46eb3d79dc48265c58e8c2e3972", 8080, "/app/.env", "/v1/health", True, True),
    ("moderationservice", "sha256:b6dcb064715215059bc7b3db4c001e912bdf0b629defc59504e5ae70b61f0f5d", 3000, "/app/.env", "/health", False, True),
    ("visual-chat-builder", "sha256:8c0f173baa57ddf24d38c56a4b5bc607d27e256cc40f410aa8447f125215a168", 3000, "/app/.env", "/v1/health-check", False, True),  # user-pinned 2026-07-02 (branch fix + npm audit)
    ("ai-agent-service", "sha256:5adf6f3fec9768699eb4df8dd9ef1962a2a4d72eed621a062e79dc0ebe7207df", 4002, "/app/.env", None, False, False),
]
# name, digest, env_path, start_cmd  (workers: no Service)
WORKERS = [
    # name, digest, env_path, start_cmd  (None = use the image's default entrypoint)
    ("receipt-updater", "sha256:070b74b4a41bb7281714a866cd0b9066826e37076c384277cb67cbc0b153b41e", "/app/.env", None),
    # The delay-worker image has NO dotenv, so worker.js's require('dotenv') silently fails and a
    # mounted /app/.env would never load. The image is also distroless (no shell) so we can't source
    # it with sh either. Instead we inject env vars directly via envFrom (the <name>-env secret) and
    # run the image's native entrypoint (start_cmd=None) — no .env file, no sh.
    ("notifications-delay-worker", "sha256:cf49d977d26e8e64f2dfc79a400bf434cea940a78e35efee08d24b5e5584807a", "/app/.env",
     None),
]

def probe(health, port):
    if health:
        return f"httpGet: {{ path: {health}, port: {port} }}"
    return f"tcpSocket: {{ port: {port} }}"

# Per-service app-container memory limit override. moderationservice loads transformers.js ML models
# (sentiment/toxicity) and OOMs (exit 137) at the 1Gi default — it needs ~3Gi; 4Gi gives headroom.
MEM = {"moderationservice": "4Gi"}

def node_yaml(name, digest, port, envp, health, jwt, tls=False):
    mem = MEM.get(name, "1Gi")   # app-container memory limit (default 1Gi; override above)
    jwt_mount = f"\n            - {{ name: jwt, mountPath: /app/jwtrsakey.pem, subPath: jwtrsakey.pem, readOnly: true }}" if jwt else ""
    jwt_vol = "\n        - { name: jwt, secret: { secretName: jwt-public } }" if jwt else ""
    if not tls:
        # BARE pod (no per-pod TLS sidecar) — app container only, Service targets the app port directly.
        # ai-agent-service intentionally lives here (excluded from the pod-TLS front).
        return f"""---
apiVersion: apps/v1
kind: Deployment
metadata: {{ name: {name}, namespace: {NS}, labels: {{ app.kubernetes.io/name: {name} }} }}
spec:
  replicas: 1
  selector: {{ matchLabels: {{ app.kubernetes.io/name: {name} }} }}
  template:
    metadata: {{ labels: {{ app.kubernetes.io/name: {name} }} }}
    spec:
      imagePullSecrets: [{{ name: ecr-pull }}]
      containers:
        - name: {name}
          image: {ECR}@{digest}
          ports: [{{ containerPort: {port} }}]
          volumeMounts:
            - {{ name: env, mountPath: {envp}, subPath: .env, readOnly: true }}{jwt_mount}
          readinessProbe: {{ {probe(health, port)}, initialDelaySeconds: 15, periodSeconds: 10, failureThreshold: 12 }}
          resources: {{ requests: {{ cpu: 100m, memory: 256Mi }}, limits: {{ cpu: "1", memory: {mem} }} }}
      volumes:
        - {{ name: env, secret: {{ secretName: {name}-env }} }}{jwt_vol}
---
apiVersion: v1
kind: Service
metadata: {{ name: {name}, namespace: {NS}, labels: {{ app.kubernetes.io/name: {name} }} }}
spec:
  selector: {{ app.kubernetes.io/name: {name} }}
  ports: [{{ name: http, port: 80, targetPort: {port} }}, {{ name: app, port: {port}, targetPort: {port} }}]
"""
    # PER-POD TLS sidecar (pod-TLS / colleague parity). Adds ONLY the pod-TLS bits on top of the bare
    # pod: a <name>-nginx ConfigMap with dual :80/:443 server blocks (WS Upgrade headers +
    # underscores_in_headers on / ignore_invalid_headers off — LOAD-BEARING for east-west auth headers
    # app_secret/api_key that carry underscores), an nginx:1.27-alpine sidecar exposing :80 + :443 with
    # wildcard-tls mounted at /tls, and a Service exposing http/https/app. The app container, its port,
    # digest, jwt mount and readinessProbe are UNCHANGED from the bare path above.
    return f"""---
apiVersion: v1
kind: ConfigMap
metadata: {{ name: {name}-nginx, namespace: {NS} }}
data:
  default.conf: |
    server {{
      listen 80; server_name _; client_max_body_size 50M;
      underscores_in_headers on; ignore_invalid_headers off;
      location = /nginx-health {{ access_log off; add_header Content-Type application/json; return 200 '{{"status":"ok"}}'; }}
      location / {{
        proxy_pass http://127.0.0.1:{port};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 600;
      }}
    }}
    # pod-TLS (colleague parity): terminate the wildcard cert on :443 so east-west calls (CoreDNS ->
    # Service ClusterIP:443) are real HTTPS verified against *.<domain>, not just ingress-terminated.
    server {{
      listen 443 ssl; server_name _; client_max_body_size 50M;
      ssl_certificate /tls/tls.crt; ssl_certificate_key /tls/tls.key;
      underscores_in_headers on; ignore_invalid_headers off;
      location = /nginx-health {{ access_log off; add_header Content-Type application/json; return 200 '{{"status":"ok"}}'; }}
      location / {{
        proxy_pass http://127.0.0.1:{port};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 600;
      }}
    }}
---
apiVersion: apps/v1
kind: Deployment
metadata: {{ name: {name}, namespace: {NS}, labels: {{ app.kubernetes.io/name: {name} }} }}
spec:
  replicas: 1
  selector: {{ matchLabels: {{ app.kubernetes.io/name: {name} }} }}
  template:
    metadata: {{ labels: {{ app.kubernetes.io/name: {name} }} }}
    spec:
      imagePullSecrets: [{{ name: ecr-pull }}]
      containers:
        - name: {name}
          image: {ECR}@{digest}
          ports: [{{ containerPort: {port} }}]
          volumeMounts:
            - {{ name: env, mountPath: {envp}, subPath: .env, readOnly: true }}{jwt_mount}
          readinessProbe: {{ {probe(health, port)}, initialDelaySeconds: 15, periodSeconds: 10, failureThreshold: 12 }}
          resources: {{ requests: {{ cpu: 100m, memory: 256Mi }}, limits: {{ cpu: "1", memory: {mem} }} }}
        - name: nginx
          image: nginx:1.27-alpine
          ports: [{{ containerPort: 80, name: http }}, {{ containerPort: 443, name: https }}]
          volumeMounts:
            - {{ name: nginxcfg, mountPath: /etc/nginx/conf.d/default.conf, subPath: default.conf, readOnly: true }}
            - {{ name: tls, mountPath: /tls, readOnly: true }}
          readinessProbe: {{ httpGet: {{ path: /nginx-health, port: 80 }}, initialDelaySeconds: 10, periodSeconds: 10 }}
          resources: {{ requests: {{ cpu: 25m, memory: 64Mi }}, limits: {{ cpu: 200m, memory: 128Mi }} }}
      volumes:
        - {{ name: env, secret: {{ secretName: {name}-env }} }}{jwt_vol}
        - {{ name: nginxcfg, configMap: {{ name: {name}-nginx }} }}
        - {{ name: tls, secret: {{ secretName: wildcard-tls }} }}
---
apiVersion: v1
kind: Service
metadata: {{ name: {name}, namespace: {NS}, labels: {{ app.kubernetes.io/name: {name} }} }}
spec:
  selector: {{ app.kubernetes.io/name: {name} }}
  ports: [{{ name: http, port: 80, targetPort: 80 }}, {{ name: https, port: 443, targetPort: 443 }}, {{ name: app, port: {port}, targetPort: {port} }}]
"""

def worker_yaml(name, digest, envp, cmd=None):
    cmd_line = f'\n          command: ["sh","-c","{cmd}"]' if cmd else ""
    mem = MEM.get(name, "1Gi")   # per-service app-container memory limit (default 1Gi; MEM overrides)
    return f"""---
apiVersion: apps/v1
kind: Deployment
metadata: {{ name: {name}, namespace: {NS}, labels: {{ app.kubernetes.io/name: {name} }} }}
spec:
  replicas: 1
  selector: {{ matchLabels: {{ app.kubernetes.io/name: {name} }} }}
  template:
    metadata: {{ labels: {{ app.kubernetes.io/name: {name} }} }}
    spec:
      imagePullSecrets: [{{ name: ecr-pull }}]
      containers:
        - name: {name}
          image: {ECR}@{digest}{cmd_line}
          # Inject config as real env vars (image lacks dotenv; distroless has no shell to source a
          # .env). The .env is still mounted for images that read it directly, but envFrom is the
          # reliable path for native-entrypoint workers.
          envFrom: [{{ secretRef: {{ name: {name}-env }} }}]
          volumeMounts: [{{ name: env, mountPath: {envp}, subPath: .env, readOnly: true }}]
          resources: {{ requests: {{ cpu: 100m, memory: 256Mi }}, limits: {{ cpu: "1", memory: {mem} }} }}
      volumes: [{{ name: env, secret: {{ secretName: {name}-env }} }}]
"""

DASHBOARD = f"""---
apiVersion: v1
kind: ConfigMap
metadata: {{ name: dashboard-nginx, namespace: {NS} }}
data:
  default.conf: |
    server {{ listen 80; root /usr/share/nginx/html; index index.html;
      location = /nginx-health {{ access_log off; return 200 'ok'; }}
      location / {{ try_files $uri $uri/ /index.html; }} }}
---
apiVersion: apps/v1
kind: Deployment
metadata: {{ name: dashboard, namespace: {NS}, labels: {{ app.kubernetes.io/name: dashboard }} }}
spec:
  replicas: 1
  selector: {{ matchLabels: {{ app.kubernetes.io/name: dashboard }} }}
  template:
    metadata: {{ labels: {{ app.kubernetes.io/name: dashboard }} }}
    spec:
      imagePullSecrets: [{{ name: ecr-pull }}]
      initContainers:
        - name: copy-build
          image: {ECR}@sha256:28078c3bbd84ebfeb08dce31916735baca1c6ddd77604d1efd4db895577c3457
          command: ["sh","-c","cp -r /app/build/. /web/ 2>/dev/null || cp -r /usr/share/nginx/html/. /web/ 2>/dev/null || cp -r /app/dist/. /web/; echo copied $(find /web -type f | wc -l) files"]
          volumeMounts: [{{ name: web, mountPath: /web }}]
      containers:
        - name: nginx
          image: nginx:1.27-alpine
          ports: [{{ containerPort: 80 }}]
          volumeMounts:
            - {{ name: web, mountPath: /usr/share/nginx/html }}
            - {{ name: cfg, mountPath: /etc/nginx/conf.d/default.conf, subPath: default.conf }}
          resources: {{ requests: {{ cpu: 25m, memory: 48Mi }}, limits: {{ cpu: 200m, memory: 128Mi }} }}
      volumes:
        - {{ name: web, emptyDir: {{}} }}
        - {{ name: cfg, configMap: {{ name: dashboard-nginx }} }}
---
apiVersion: v1
kind: Service
metadata: {{ name: dashboard, namespace: {NS}, labels: {{ app.kubernetes.io/name: dashboard }} }}
spec:
  selector: {{ app.kubernetes.io/name: dashboard }}
  ports: [{{ name: http, port: 80, targetPort: 80 }}]
"""

def apply(yaml, label):
    with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False) as f:
        f.write(yaml); path = f.name
    p = subprocess.run(f"kubectl --kubeconfig {KC} apply -f {path} --validate=false", shell=True, capture_output=True, text=True)
    os.unlink(path)
    print(f"  {label}: {'ok' if p.returncode==0 else 'FAIL '+p.stderr.strip()[:100]}")

print("Node services:")
for n in NODE: apply(node_yaml(*n), n[0])
print("Workers:")
for w in WORKERS: apply(worker_yaml(*w), w[0])
# Dashboard is owned by k8s/dashboard.yaml + k8s/dashboard-nginx.yaml (applied by deploy.sh phase_node_apps),
# NOT here. The DASHBOARD template above lacks the config.json (dashboard-config) mount, so rendering it drops
# the on-prem API URL and the SPA falls back to its baked-in cometchat-staging.com default -> CORS on the
# dashboard. Left in place for reference only; do NOT re-enable without the appconfig/config.json mount.
print("Dashboard: owned by k8s/dashboard.yaml (applied by deploy.sh) — skipped here")
