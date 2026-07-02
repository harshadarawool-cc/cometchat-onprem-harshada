# HA & Resource-Allocation Plan — DEFERRED

> **Status: NOT YET IMPLEMENTED.** Do this pass **after all services + the end-to-end workflow
> are completed and validated**, then apply HA + right-sizing as one clean change.
> Captured 2026-06-23 from the Costa Crociere sizing discussion.

---

## 1. Sizing target
- **Customer:** Costa Crociere. Working assumption: **10k MAU × 10% PCC = 1,000 Peak Concurrent Connections.**
- **Benchmark (anchor):** `48 vCPU + 96 GiB` app-tier compute per **1,000 PCC**.
- **Goal:** size the app tier to the benchmark, then add **N-1 HA** + an **extra headroom gap** on top.
  (Client flagged 10% PCC may be high for their real use; we size conservatively to 1,000 PCC anyway.)

## 2. Decisions locked
| Topic | Decision |
|---|---|
| **Ollama** | **CPU-only** — no GPU node pool. (e2 family has no GPU support; AI/LLM not GPU-accelerated.) |
| **MySQL + TiDB** | **Make HA** (topology below — adds VMs). |
| **Workers** | Default **3 × e2-standard-32**. Alternatives: `4 × e2-standard-16` (cost-optimal N-1), `7 × e2-standard-8`. *Confirm before implementing.* |

## 3. Node plan (terraform)
| Tier | Now | Target | Notes |
|---|---|---|---|
| Control plane (`rke2_server`) | 1 × e2-standard-4 | **3 × e2-standard-4** | etcd quorum = real HA |
| Workers (`rke2_agent`) | 3 × e2-standard-8 (24 vCPU/96 GiB) | **3 × e2-standard-32** (96 vCPU/384 GiB) | N-1 = 2 nodes = 64 vCPU > 48 benchmark ✅ |
| Zones | likely 1 | **spread across 3 GCP zones** | survive a zone failure |
| Mongo / Kafka / Redis | 3 each ✅ | keep 3 (bump size only if msg-rate demands) | already HA |
| **MySQL** | 1 | **3-node InnoDB Cluster** (Group Replication, auto-failover) + MySQL Router | **+2 VMs** |
| **TiDB** | 1 | **3× PD + 3× TiKV + 2× TiDB-server** (min real HA) | **+7 VMs** — confirm full vs leaner |

> N-1 reminder: `6 × e2-standard-8` was rejected — on a node loss it drops to 40 vCPU (< 48), i.e. not
> truly HA. The smaller-node route needs **7×** to satisfy N-1.

## 4. Per-pod HA + restricted resources (all ~20 deployments)
- **`replicas ≥ 2`** — heavy services (chatapi, websocket, notificationscore, mgmtapi) = **3**.
- **`podAntiAffinity`** — spread replicas across workers/zones.
- **`PodDisruptionBudget` `minAvailable: 1`** — drains/upgrades never take a service fully down.
- **Right-sized `requests`/`limits`** on every pod (tiered heavy/medium/light), peak target ~50–60% (the gap).
- **Pod Security Standard `restricted`** namespace-wide + `securityContext` on pods that lack it
  (drop ALL caps, runAsNonRoot, no privilege escalation, seccomp `RuntimeDefault`).
- Optional **HPA** on chatapi/websocket (scale on CPU).

### Live-usage baseline (near-idle, 1 app, captured 2026-06-23 — floor for `requests`)
`ai-agent 371m/2.2Gi · sql-consumer 779m/1.27Gi · websocket 412m/669Mi · moderationservice 55m/1.1Gi ·
opensearch 5m/1.05Gi · extensions 248m/460Mi · metrics-pro 266m/172Mi · chatapi 13m/397Mi (idle).`
These will grow with load — size to the benchmark, not this idle floor.

## 5. Where the knobs live
- **Nodes:** `terraform/variables.tf` (`rke2_server`, `rke2_agent`, `mysql`, `tidb` objects) + `deploy/customer.conf`
  (`RKE2_SERVER_COUNT/TYPE`, `RKE2_AGENT_COUNT/TYPE`). HA control plane already documented: *"set count=3"*.
- **Per-pod:** each `k8s/*.yaml` deployment — add `replicas`, `resources`, `affinity`; add PDBs; Pod Security label on ns.
- **Zones:** terraform instance `zone` / regional spread.

## 6. Open items to settle before implementing
1. **Confirm worker shape** (default `3 × e2-standard-32`).
2. **Confirm TiDB HA topology** (full `3 PD + 3 TiKV + 2 TiDB`, or leaner).
3. **Get message throughput** (msgs/sec) — drives Kafka/Redis/Mongo datastore sizing (connections drive RAM, msg-rate drives CPU).
4. Re-confirm PCC with the client (they think 10% is high) — may allow shrinking workers.

Related: see `NETWORK-AND-SECURITY.md` §6 (egress lockdown, secrets-encryption, NetworkPolicies — pair these P0/P1 hardening items with this HA pass).
