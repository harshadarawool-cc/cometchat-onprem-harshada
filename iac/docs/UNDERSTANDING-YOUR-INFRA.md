# Understanding your infra — a plain-language guide to the CometChat on-prem chat platform

> Read this first if you want the **mental model**, not the config. It teaches what every piece is, why
> it exists, who talks to whom, and exactly what happens when a message is sent — from basics to advanced.
> For the precise config, jump to the ★ docs ([00-INDEX](00-INDEX.md)); this doc is the "why".

---

## Part 1 — What does a chat platform actually need?

Forget servers for a second. A chat product has to do a handful of jobs, and **every component in your
cluster exists to do one of these jobs**:

1. **Take in messages** and decide if they're allowed (auth, permissions, moderation). → *chatapi*
2. **Remember everything** — messages, conversations, users, groups — forever and reliably. → *TiDB*
3. **Deliver messages instantly** to people who are online, without them refreshing. → *websocket + Redis*
4. **Tell the rest of the system** something happened, so many features can react at once. → *Kafka*
5. **Reach people who are offline** (push / email / SMS). → *notificationscore*
6. **Store pictures, videos, files** somewhere that isn't the database. → *SeaweedFS (object storage)*
7. **Find old messages** (search). → *service-search + OpenSearch*
8. **Let admins configure the app** (create apps, set rules, see metrics). → *mgmtapi + dashboard + analytics*
9. **Extra features** — stickers, polls, link previews, collaborative docs/whiteboards, AI agents,
   moderation with AI. → *extensions, document-embed, whiteboard, ai-agent, moderationservice*
10. **Notify outside systems** when things happen (customer's own servers). → *globalwebhooks*

If you keep those 10 jobs in mind, the whole cluster stops looking like a pile of pods and starts looking
like a **team of specialists**, each doing one job and calling the others when needed.

---

## Part 2 — The 10,000-foot view

Your platform runs in **three "planes"** (layers), plus an admin path:

```
   People on the internet (mobile apps, web SDK, browsers)
                     │  HTTPS
        ┌────────────▼────────────┐
        │  EDGE PLANE: 2 HAProxy   │   the front door. Reads the hostname, forwards to the right service.
        │  VMs (SNI passthrough)   │   Does NOT read your messages (encryption stays sealed until the pod).
        └────────────┬────────────┘
        ┌────────────▼─────────────────────────────────────────┐
        │  APP PLANE: the Kubernetes cluster (RKE2)             │   the "team of specialists" (the 16 services)
        │  chatapi, websocket, moderation, notifications, …     │   each pod ends TLS itself (per-pod nginx)
        └────────────┬─────────────────────────────────────────┘
        ┌────────────▼─────────────────────────────────────────┐
        │  DATA PLANE: the memory + plumbing                    │   where everything is stored and shuttled
        │  TiDB · Mongo · Redis · Kafka · MySQL · OpenSearch    │   (these run on their own VMs)
        │  SeaweedFS (object storage) · Ollama (AI)             │
        └───────────────────────────────────────────────────────┘

   Admins reach everything through a private Google IAP tunnel — never the public internet.
```

**One golden rule to remember:** services talk to each other by **hostname** (like
`rule-onprem.cometchat-cluster-2.in`), and a clever DNS trick (split-horizon) makes those hostnames resolve
**inside the cluster** when one service calls another — so internal traffic never leaves your private
network, even though the names look public. (More in Part 7.)

---

## Part 3 — The data plane: what each datastore is *for*

This is the part most people find confusing: "why so many databases?" Because they each do a *different*
job well. Here's each one, in plain terms, with what it stores and who uses it.

### TiDB — the message vault (the most important store)
- **What it is:** a database that speaks MySQL's language but is **distributed** — it spreads data across
  several nodes so it can grow huge and survive a node dying. (Think "MySQL that scales like a warehouse.")
- **What it holds:** the **chat data** — messages, conversations, who's in which group. The stuff that must
  never be lost and grows forever.
- **Who uses it:** `chatapi` (reads/writes messages), `sql-consumer` (writes messages that arrive via
  Kafka), `receipt-updater` (delivery/read receipts).
- **Analogy:** the bank vault. Slower to change than a whiteboard, but it's the source of truth.

### MongoDB — the flexible-shape store
- **What it is:** a "document" database — stores JSON-like records with no fixed columns. Runs as a
  **replica set** (`rs0`, 3 copies) so if one node dies the others keep serving.
- **What it holds:** things whose shape varies a lot — webhook/event definitions, moderation rules,
  visual-chat-builder templates, notification settings/templates, some extension data.
- **Who uses it:** `globalwebhooks` (the `events` DB), `moderationservice`, `visual-chat-builder`,
  `notificationscore`, `extensions`, `ai-agent-service`. (Note: **chatapi does *not* use Mongo** — chat
  messages live in TiDB. Mongo is only for the flexible-shape config/rules/templates these services keep.)
- **Analogy:** a filing cabinet where every folder can have a different layout.

### Redis — the fast scratchpad + megaphone (you have **four** separate ones)
- **What it is:** an in-memory store — blazing fast, but for short-lived / hot data. Runs with **Sentinel**
  (a watchdog that promotes a replica to master if the master dies).
- **What it holds & does:** caching (avoid hitting TiDB for hot data), **pub/sub** (a "megaphone" for
  real-time — see Part 5), presence ("who's online"), and job queues.
- **Why four separate clusters?** So one noisy workload can't starve another, and so the internal name
  (`mymaster`) never collides:
  - **shared** — general cache + pub/sub + presence (chatapi, websocket, ai-agent, receipt-updater)
  - **analytics** — just the analytics service
  - **prometrics** — just the pro-metrics service
  - **bullmq** — a **delayed-job queue** for notifications (BullMQ) — "send this push in 5 minutes if still unread"
- **Analogy:** a whiteboard next to each team — instant to read/write, wiped often, not the permanent record.

### Kafka — the event bus / conveyor belt (the nervous system)
- **What it is:** a **durable message queue / event log**. One service "publishes" an event; many others
  "subscribe" and each reacts independently. Runs 3 brokers in **KRaft** mode (no separate ZooKeeper).
- **What it does:** decouples the system. When a chat message is sent, chatapi doesn't have to call search
  *and* receipts *and* webhooks *and* analytics one by one — it drops **one event** on Kafka, and each of
  those consumers picks it up on its own schedule. If one is slow or down, the others are unaffected.
- **Who uses it:** almost everyone — chatapi, websocket, notificationscore, moderationservice,
  service-search, extensions, metrics-pro, sql-consumer, receipt-updater, ai-agent.
- **Analogy:** a conveyor belt in a factory — one station puts a part on it; many downstream stations each
  take what they need. **This is the single most important concept for understanding the flow.**

### MySQL — the classic app database (for the "management" side)
- **What it is:** plain MySQL 8, single node.
- **What it holds:** the **control-plane** data, not chat: `pulsecustomerdb` (mgmt-api: your apps,
  regions, plans), `metrics`, `analytics_logs`, and the Etherpad DB (collaborative documents).
- **Who uses it:** `mgmtapi`, `metrics-pro`, `analytics`, `document-embed`.
- **Analogy:** the office admin's spreadsheet — accounts, settings, billing-ish data.

### OpenSearch — the search engine
- **What it is:** a search index (the open-source cousin of Elasticsearch).
- **What it does:** lets users **search their message history** fast. Messages get indexed here in addition
  to being stored in TiDB (TiDB is for "give me this conversation"; OpenSearch is for "find messages containing 'invoice'").
- **Who uses it:** `service-search` (which sits in front of it; chatapi calls service-search).
- **Analogy:** the index at the back of a book.

### Ollama — the local AI brain
- **What it is:** a server that runs AI/LLM models **locally** (no data sent to OpenAI for these).
- **What it does:** powers AI moderation (e.g. "is this image/text harmful?") and the AI agent, on-prem.
- **Who uses it:** `moderationservice` (vision), `ai-agent-service`.

### SeaweedFS — the object storage (files, images, video) — *see Part 6 for the full "why"*
- **What it is:** an **S3-compatible object store** you host yourself. It stores **blobs** (pictures,
  videos, documents, stickers, avatars) — the stuff that doesn't belong in a database.
- **Who uses it:** `chatapi` (chat media), `extensions` (assets), `visual-chat-builder` (builder zips).

> **The "which store for what" cheat-sheet:**
> chat messages → **TiDB** · flexible config/rules/templates → **Mongo** · hot/temporary + real-time
> megaphone → **Redis** · "something happened" events → **Kafka** · admin/app settings → **MySQL** ·
> search → **OpenSearch** · files & images → **SeaweedFS** · AI → **Ollama**.

---

## Part 4 — The app plane: the 16 services, by job

Grouped by the *job* they do (full table with ports/health paths: [SERVICES.md](SERVICES.md)):

- **Core messaging:** `chatapi` — the heart. Every send/read/create goes through it. Public host `api-onprem`.
- **Real-time delivery:** `websocket` — holds the always-open connections to online clients and pushes
  messages the instant they arrive. Public host `websocket-onprem` (clients) / `ws-onprem` (chatapi's name for it).
- **Safety:** `moderationservice` (host `rule-onprem`) + `clamav` (virus scan) + `ollama` (AI checks).
- **Reaching offline users:** `notificationscore` (host `notifications-onprem`) — push, email, SMS; uses
  the **bullmq** Redis for "send later" jobs.
- **Telling outside systems:** `globalwebhooks` (host `webhooks-onprem`) — fires HTTP callbacks to the
  customer's own servers when events happen.
- **Search:** `service-search` (host `internal-search-onprem`) → OpenSearch.
- **Admin & config:** `mgmtapi` (host `apimgmt`) + `dashboard` (host `app`, the web UI) + `analytics`
  (host `metrics-onprem`) + `metrics-pro` (internal).
- **Extra features:** `extensions` (stickers, polls, link-previews, thumbnails, and the document/whiteboard
  *create* API — host `extensions-onprem`), `document-embed` (the Etherpad editor iframe), `whiteboard`
  (the whiteboard iframe), `visual-chat-builder` (no-code chat UI builder).
- **AI:** `ai-agent-service` — AI chatbots/agents (host `*.ai-agent-service`, HTTP internal).
- **Background workers (no web address, just consume Kafka & update stores):** `sql-consumer`
  (Kafka→TiDB), `receipt-updater` (delivery/read receipts), `notifications-delay-worker` (delayed pushes),
  `metrics-pro-timer` (periodic counts).

**Public vs internal:** anything a phone/browser must reach directly is **public** (chatapi, websocket,
dashboard, mgmtapi, analytics, extensions, notifications, media, the editors). The rest are **internal** —
only other services call them, and they have no public address at all (moderation, webhooks, search,
metrics-pro, vcb, ai-agent). Why: smaller attack surface. Full split: [SERVICES.md](SERVICES.md).

---

## Part 5 — How a real-time chat message actually flows (the money section)

Let's send one message from **Alice** to **Bob** and follow it through the whole system. (Where an exact
internal split is an app decision, I say so — but the participants and order are what matter.)

```
Alice's app                          Bob's app (online)                 Bob (offline)
    │ 1. POST message (HTTPS)             ▲ 7. delivered live                 ▲ 8. push/email/SMS
    ▼                                     │                                    │
  HAProxy ──▶ chatapi ──2─▶ moderation   │                                    │
                │           (rule-onprem) │                                    │
                │ 3. persist              │                                    │
                ▼                         │                                    │
              TiDB (message vault)        │                                    │
                │ 4. publish "message.sent" event                             │
                ▼                                                              │
             Kafka  ──────────────┬───────────┬───────────┬──────────────┐    │
                                  ▼           ▼           ▼              ▼    │
                          5a. websocket  5b. search   5c. receipts   5d. webhooks
                          (via Redis     (index in    (receipt-      (globalwebhooks
                           pub/sub) ─────┘ OpenSearch) updater→TiDB)   → customer)   │
                                  │                                                  │
                                  └── 6. push to Bob's open WebSocket ──────────────┘
                                       if Bob is OFFLINE → notificationscore ────────┘
```

**Step by step, in words:**

1. **Alice sends.** Her app makes an HTTPS `POST` to `chatapi` (`<appId>.api-onprem…`). The request goes
   through HAProxy (which just forwards by hostname) and lands on a chatapi pod, where TLS is decrypted.
2. **chatapi checks it.** It authenticates the app/user, checks permissions, and asks
   **moderationservice** (`rule-onprem`) whether the content is allowed (which may use ClamAV for files and
   Ollama for AI checks). Blocked → Alice gets an error. Allowed → continue.
3. **chatapi remembers it.** The message is persisted to **TiDB**, the durable vault. (Some writes go
   straight to TiDB; some flow through Kafka → `sql-consumer` → TiDB. Either way, TiDB ends up as the
   source of truth.)
4. **chatapi announces it.** chatapi drops a single **event** ("a message was sent") onto **Kafka**. This
   is the key move — chatapi's job is now essentially done; it doesn't wait on all the downstream work.
5. **Everyone who cares reacts, in parallel, off Kafka:**
   - **5a — real-time delivery:** the **websocket** service learns about the message (via Redis **pub/sub**
     — the "megaphone" that lets any websocket node reach the node Bob happens to be connected to) and
     prepares to push it.
   - **5b — search:** `service-search` indexes the message into **OpenSearch** so it's findable later.
   - **5c — receipts:** `receipt-updater` records delivery/read state (in TiDB/Redis).
   - **5d — webhooks:** `globalwebhooks` fires an HTTP callback to the **customer's own servers** if they've
     subscribed to message events.
   - (analytics/metrics also count it.)
6. **Push to Bob.** If **Bob is online**, he has a live **WebSocket** connection open to `websocket-onprem`.
   The websocket service pushes the message down that open pipe — Bob sees it **instantly**, no refresh.
7. **Bob's app shows it** and sends back a "read" receipt, which flows the same way (→ receipt-updater).
8. **If Bob is offline**, there's no open socket to push to. So chatapi/notifications asks
   **notificationscore** (`notifications-onprem`) to send a **push notification / email / SMS**.
   notificationscore uses the **bullmq** Redis for "send in N minutes if still unread" style delays and
   Mongo for templates/settings.

**Why this design is good (the lesson):** by putting **Kafka** in the middle, sending a message is fast for
Alice (chatapi just writes + publishes), and every *reaction* (search, receipts, webhooks, notifications)
happens independently. If search is slow or webhooks are down, **Alice's message still sends and Bob still
gets it**. That decoupling is the whole point of an event bus.

---

## Part 6 — Why object storage? (SeaweedFS, from scratch)

**The problem:** chat isn't just text. People send photos, videos, PDFs, voice notes. Where do those go?

**Why not the database?** Databases are built for small, structured rows you query and update. Large binary
files (a 20 MB video) in a database make it **bloated, slow, expensive to back up, and hard to scale** —
and you rarely "query" a video, you just fetch it whole. It's the wrong tool.

**The right tool: object storage.** Object storage (Amazon **S3** is the famous one) is built exactly for
"store this blob, give me back a URL, let me fetch it later by URL." It's cheap, scales to petabytes, and
serves files directly over HTTP. So the pattern everywhere in tech is:

> **Store the *file* in object storage; store only its *URL/metadata* in the database.**

**Why self-host it (SeaweedFS) instead of AWS S3?** CometChat's cloud uses AWS S3. But your whole reason
for going on-prem is **data residency** — customer data (including uploaded files) must **stay inside your
network**. So you replace S3 with **SeaweedFS**, which is **S3-compatible** (speaks the same API, so the
apps don't need rewriting) but runs on **your** VMs. Nothing leaves the VPC. (Background: SeaweedFS stores
each file as "chunks" across volume servers, keeps 2 copies of everything for durability, and a "filer"
tracks where each file's chunks live and exposes the S3 API on port 8333.)

**How a media message works:**
1. Alice picks a photo. Her app (or chatapi) **uploads** it to SeaweedFS — a `PUT` to
   `https://media-onprem…/uploads/<appId>/…`. It lands in the private `uploads` bucket, **encrypted at rest**.
2. The **message row** (in TiDB) stores just the **URL**, not the bytes.
3. Bob's app renders the message; the `<img>` tag's URL points at `media-onprem…`; his browser **downloads**
   the photo straight from SeaweedFS. The chatapi service never has to stream the bytes.

**Buckets (folders) and who can read them:**
- `uploads` — **private** chat media (`<appId>/…`). Readable by URL (so images render) but not listable.
- `assets`, `stickers`, `visual-chat-builder-app` — **public** (default stickers, sample avatars, builder downloads).
- `observability` — internal logs/metrics.

**One neat trick you're relying on:** the host `media-onprem` resolves **two ways** (split-horizon): from a
browser it goes to your edge; from inside the cluster it stays in-cluster. So the *same* URL works for both
the browser (download) and chatapi (server-side upload) — which is what makes uploaded images actually
display. Full detail: [SEAWEEDFS.md](SEAWEEDFS.md).

---

## Part 7 — How the pieces talk (networking, in plain language)

Three ideas, and you understand the whole network:

1. **The front door is dumb on purpose (HAProxy).** Your 2 HAProxy VMs read only the **hostname** in the
   TLS handshake (the "SNI") and forward the still-encrypted connection to the right service. They **never
   decrypt** your traffic. Two of them + DNS handing out both their IPs = if one dies, the other serves.
   *(Why not a cloud load balancer? Kubernetes-on-VMs (RKE2) can't auto-create one, and we want encryption
   to stay sealed until the pod — so plain HAProxy VMs are the clean fit.)*

2. **Every pod ends its own encryption (per-pod TLS).** Instead of one place decrypting everything, each
   service pod runs a tiny **nginx sidecar** that terminates HTTPS right there. So traffic is encrypted
   **all the way to the destination pod** — nowhere in the middle sees plaintext. Great for data residency.

3. **The same hostname answers differently inside vs outside (split-horizon DNS).** This is the clever bit.
   `api-onprem…` from the **internet** → your HAProxy (public). `api-onprem…` from **another service inside
   the cluster** → straight to the chatapi pod (private). A component called **CoreDNS** rewrites internal
   lookups to the in-cluster address. Result: services call each other by friendly public-looking names,
   but that traffic **never leaves your private network**.

Put together: **outside traffic** comes in the front door (HAProxy → pod), and **inside traffic**
(service→service) short-circuits privately (CoreDNS → pod). Both end at a pod that decrypts its own TLS.
Full detail: [NETWORKING.md](NETWORKING.md), [HAPROXY-EDGE.md](HAPROXY-EDGE.md).

---

## Part 8 — Keeping data safe (encryption at rest, in plain language)

"At rest" = data sitting on disk (as opposed to "in transit" = moving over the network). You protect it in
three independent layers, so cracking one doesn't expose the data:

1. **The disks themselves** are encrypted (Google encrypts every disk; optionally with *your* key, CMEK).
2. **Kubernetes secrets** (passwords, keys) are encrypted inside the cluster's database (etcd).
3. **Uploaded files** in SeaweedFS are encrypted with a dedicated key — the file service literally refuses
   to start without it.

In transit, everything is HTTPS (per-pod TLS, Part 7). Details: [ENCRYPTION-AT-REST.md](ENCRYPTION-AT-REST.md),
[SECURITY.md](SECURITY.md).

---

## Part 9 — Three end-to-end journeys (to cement it)

**A) Send a text message** → chatapi (auth + moderate) → TiDB (save) → Kafka (announce) → websocket pushes
to the online recipient via Redis pub/sub; search/receipts/webhooks react off Kafka; if recipient offline →
notificationscore push. *(Part 5.)*

**B) Send a photo** → app uploads photo to SeaweedFS (`uploads` bucket, encrypted) → sends a normal text
message whose body carries the photo's URL → recipient's app fetches the photo directly from `media-onprem`.
*(Part 6.)*

**C) Admin creates a new app** → you log into the **dashboard** (`app`) → it calls **mgmtapi** (`apimgmt`)
→ mgmtapi writes to **MySQL** (`pulsecustomerdb`) and tells **chatapi** (`api-onprem`) → the new app is
ready, with its own `<appId>.api-onprem…` address. *(Verified: mgmtapi's `ADMIN_API_HOST=api-onprem`.)*

---

## Part 10 — Glossary (plain definitions)

- **Pod / container:** one running copy of a service inside Kubernetes.
- **Kubernetes / RKE2:** the system that runs, restarts, and connects your service pods. RKE2 is a
  lightweight Kubernetes distribution.
- **Service (in k8s):** a stable internal address for a set of pods.
- **NodePort:** a fixed port on the cluster nodes that HAProxy forwards to.
- **Sidecar:** a helper container in the same pod (here: the nginx that does per-pod TLS).
- **TLS / SNI:** TLS = HTTPS encryption; SNI = the hostname sent (unencrypted) at the start of a TLS
  handshake, which lets HAProxy route without decrypting.
- **Split-horizon DNS:** the same name resolving differently for inside vs outside callers.
- **Replica set (Mongo):** 3 copies of the data with automatic failover.
- **Sentinel (Redis):** a watchdog that promotes a replica if the master dies.
- **KRaft (Kafka):** Kafka's built-in way to manage itself without ZooKeeper.
- **Pub/sub:** publish/subscribe — one publisher, many listeners (Redis and Kafka both do a form of this;
  Redis for instant/ephemeral, Kafka for durable/replayable).
- **Event bus:** the conveyor belt (Kafka) that decouples "something happened" from "who reacts".
- **Object storage / S3 / bucket / blob:** storage for whole files, addressed by URL; a "bucket" is a
  top-level folder; a "blob" is one stored file.
- **Presigned / public URL:** a link that lets a browser fetch a file from object storage directly.
- **At rest / in transit:** data on disk vs data moving over the network.
- **Data residency:** the requirement that data physically stays within a defined boundary (your VPC).
- **IAP (Google Identity-Aware Proxy):** the private tunnel admins use instead of public SSH.
- **Digest (image):** the exact fingerprint (`sha256:…`) of a container image, so you always run the exact
  same build (see [IMAGES.md](IMAGES.md)).

---

### Where to go next
- Exact call graph + datastore endpoints: [INTERNAL-CONNECTIONS.md](INTERNAL-CONNECTIONS.md)
- The services list: [SERVICES.md](SERVICES.md) · the images: [IMAGES.md](IMAGES.md)
- Networking internals: [NETWORKING.md](NETWORKING.md) · [HAPROXY-EDGE.md](HAPROXY-EDGE.md)
- Object store: [SEAWEEDFS.md](SEAWEEDFS.md) · Encryption: [ENCRYPTION-AT-REST.md](ENCRYPTION-AT-REST.md)
- Deploy it: [DEPLOYMENT.md](DEPLOYMENT.md) · Architecture summary: [ARCHITECTURE.md](ARCHITECTURE.md)
