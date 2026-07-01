# External / non-in-cluster dependencies (verified audit, 2026-06-21)

Exhaustive + adversarially-verified scan of the staging Vault envs. **These do NOT rewrite
any env** (per decision: only datastore endpoints are rewritten). This is the map for:
- **CoreDNS** → resolve the host to the in-cluster twin (traffic stays inside, env unchanged).
- **Egress firewall** → allow or block (data-residency decision per feature).

## A. Redirect inside via CoreDNS (has an in-cluster twin — no egress)

| Env host (unchanged) | → in-cluster service |
|---|---|
| `ws-us.cometchat-staging.com` | websocket |
| `api-us.cometchat-staging.com` / `apiclient-us` | chatapi |
| `apimgmt.cometchat-staging.com` | mgmtapi |
| `metrics-us` / `metrics-%s.cometchat-staging.com` | analytics-api |
| `metrics-pro-%s.cometchat-staging.com` | metrics-pro |
| `proxy.cometchat-staging.com` | proxy-router |
| `app-beta.cometchat-staging.com` | dashboard |
| `data-us` / `media-us` / `files-us.cometchat-staging.com` | media-onprem (object storage) |
| `files-us.cometchat-cluster-2.in` | internal platform |
| `rule-us` / `notifications-us` / `internal-search-us` / `webhooks-us` / `internal-vcb-us` / `test.antivirus` `.cometchat-cluster-2.in` | moderation / notificationscore / service-search / globalwebhooks / vcb / clamav |

## B. Genuinely external → EGRESS decision (allow per-feature, else block)

**⚠️ Data-residency sensitive — these send data OUT of the customer network:**

| External endpoint | Used by | Notes / decision |
|---|---|---|
| `api.openai.com` | ai-agent-service, ai-agent-rag, **moderationservice** | LLM calls — chat/content leaves network |
| `api.firecrawl.dev` | ai-agent-service, ai-agent-rag | web scraping SaaS |
| `gateway.helicone.ai` (EU) | ai-agent-service | LLM gateway (proxies OpenAI when on) |
| `api.notion.com` | ai-agent-service | Notion OAuth + KB |
| `oauth-agentic-tools.cometchat.io` | ai-agent-service | Composio OAuth |
| `s3.us-east-2.amazonaws.com` (agentic-ai-service-uploads/-vector) | ai-agent-service, ai-agent-rag | **AWS S3 + live AKIA keys** |
| `sqs.us-east-2.amazonaws.com/.../agentic-ai-service-uploads-queue` | ai-agent-service | AWS SQS |
| `…lambda-url.us-east-2.on.aws` | ai-agent-service | AWS Lambda (KB OAuth) |
| `arn:aws:states:…us-notfications-core-delay-step-function` | notificationscore | AWS Step Functions — **leftover, already replaced by BullMQ** (safe to ignore) |
| `recordings-us.cometchat-staging.com` | calls-relay, globalwebhooks, analytics | call recordings (AWS) |
| `rtcv5-us.cometchat-staging.com` | chatapi | RTC/calls SFU |
| `files-us.cc-cluster-2.com` | clamav | the OTHER prod Akamai cluster |
| `hooks.slack.com` | umc | Slack logging webhook |
| `hooks.zapier.com` | mgmtapi | webhook allow-list (customer-defined) |
| `httpdump.app` | campaigns | **test/requestbin endpoint — should be removed** |

**Not egress (identifiers, not call targets):** `GOOGLE_CLIENT_ID` (.apps.googleusercontent.com), `JWT_AUD`/`JWT_ISS` (rtc-us/apiclient-us as JWT claim strings).
**Excluded false positives:** websocket Kafka group-IDs ending in `.dev` (e.g. `websocket-service-messages.dev`) are consumer-group names, NOT hosts. websocket `DIAGNOSTIC_S3_BUCKET` inactive (DIAGNOSTIC_TRANSPORT=kafka).

> Of the 18 in-scope services, the AI ones (ai-agent-service, moderationservice) are the
> main data-egress concern (OpenAI/Firecrawl/Helicone/Notion/S3). For "data must not leave",
> these features must be disabled or the endpoints self-hosted, unless the customer accepts it.
