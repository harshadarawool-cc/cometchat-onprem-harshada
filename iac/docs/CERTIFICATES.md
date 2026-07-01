# TLS Certificates — full list + certbot (Let's Encrypt DNS-01) commands

> Domain `cometchat-cluster-2.in`, Route53 zone `Z04640112BJ8TJHK3I2RI`.
> Issuance = **Let's Encrypt via DNS-01 over Route53** (works even for hosts with NO public A
> record — so internal services get a real, trusted cert without being internet-exposed).
> All certs land on the single ingress-nginx, served per-host via SNI (one LB).

## Why DNS-01 (not HTTP-01)

HTTP-01 needs the host reachable on :80 from the internet — impossible for our **internal**
services (no public DNS). DNS-01 only needs us to write a `_acme-challenge.<host>` TXT record in
Route53, which certbot does automatically. This is exactly what your colleague's cluster-4 does
(his `_acme-challenge.*` TXT records).

## Prereqs (once)

```bash
pip install certbot certbot-dns-route53
# AWS creds with Route53 access for zone Z04640112BJ8TJHK3I2RI (the 'staging' profile keys):
export AWS_PROFILE=staging          # or AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
```

## The certificate set (per service-group — "multiple certs", one LB)

### PUBLIC certs (internet-facing hosts)

| # | Cert (group) | SANs | certbot `-d` flags |
|---|---|---|---|
| 1 | **chatapi** | api-onprem, apiclient-onprem, *.api-onprem, *.apiclient-onprem | `-d api-onprem.cometchat-cluster-2.in -d apiclient-onprem.cometchat-cluster-2.in -d '*.api-onprem.cometchat-cluster-2.in' -d '*.apiclient-onprem.cometchat-cluster-2.in'` |
| 2 | **websocket** | websocket-onprem, *.websocket-onprem | `-d websocket-onprem.cometchat-cluster-2.in -d '*.websocket-onprem.cometchat-cluster-2.in'` |
| 3 | **dashboard** | app | `-d app.cometchat-cluster-2.in` |
| 4 | **mgmtapi** | apimgmt | `-d apimgmt.cometchat-cluster-2.in` |
| 5 | **extensions** | extensions-onprem, *.extensions-onprem | `-d extensions-onprem.cometchat-cluster-2.in -d '*.extensions-onprem.cometchat-cluster-2.in'` |
| 6 | **media** (seaweedfs ⏸) | media-onprem, files-onprem | `-d media-onprem.cometchat-cluster-2.in -d files-onprem.cometchat-cluster-2.in` |
| 7 | **analytics** | metrics-onprem | `-d metrics-onprem.cometchat-cluster-2.in` |
| 8 | **calls-relay** | rtc-onprem, calls-relay-onprem | `-d rtc-onprem.cometchat-cluster-2.in -d calls-relay-onprem.cometchat-cluster-2.in` |

### INTERNAL certs (app→app TLS only — issued via DNS-01, NO public A record)

| # | Cert | SANs | certbot `-d` flags |
|---|---|---|---|
| 9 | **internal-services** (one SAN cert) | webhooks-onprem, notifications-onprem, rule-onprem, internal-search-onprem, internal-vcb-onprem, metrics-pro-onprem, mail | `-d webhooks-onprem.… -d notifications-onprem.… -d rule-onprem.… -d internal-search-onprem.… -d internal-vcb-onprem.… -d metrics-pro-onprem.… -d mail.cometchat-cluster-2.in` |

> Internal services still need a cert because apps call them over `https://rule-onprem…` (the
> two-axis rule). One grouped SAN cert is fine here since they're never internet-facing. They get
> a **real LE cert** (apps trust the public CA — no custom CA mount), but **no public A record**, so
> they stay unreachable from the internet.

## certbot command template (run per cert above)

```bash
certbot certonly \
  --dns-route53 \
  --non-interactive --agree-tos -m harshada.rawool@cometchat.com \
  --cert-name chatapi \
  -d api-onprem.cometchat-cluster-2.in \
  -d apiclient-onprem.cometchat-cluster-2.in \
  -d '*.api-onprem.cometchat-cluster-2.in' \
  -d '*.apiclient-onprem.cometchat-cluster-2.in'
# → /etc/letsencrypt/live/chatapi/{fullchain.pem,privkey.pem}
```

## Loading a cert into the cluster (k8s TLS secret per cert)

```bash
kubectl -n cometchat create secret tls chatapi-tls \
  --cert=/etc/letsencrypt/live/chatapi/fullchain.pem \
  --key=/etc/letsencrypt/live/chatapi/privkey.pem \
  --dry-run=client -o yaml | kubectl apply -f -
```
Then reference `secretName: chatapi-tls` in that host's Ingress `tls:` block.

## Renewal

`certbot renew` (cron/systemd-timer) re-issues ~30 days before expiry and re-writes the same
`live/<name>/` files; re-run the `kubectl create secret tls … | apply` to push the renewed cert
(or script it in the renewal `--deploy-hook`).

---

### Note: certbot vs the cert-manager we have today

Today the cluster uses **cert-manager** (`ClusterIssuer letsencrypt-route53`) which automates all
of the above in-cluster (issue + store secret + renew). **certbot is the manual/explicit
equivalent** — use it if you want certs managed outside the cluster or per-host control. If we
keep cert-manager, the same set above becomes one `Certificate` per group with the listed
`dnsNames`. Pick one mechanism; don't run both against the same secrets.
