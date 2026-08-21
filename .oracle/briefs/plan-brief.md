# Plan brief — Phase-A vertical-slice foundation (read-only planning)

You are the PLANNER. Working directory: /Users/peteromalley/Documents/reigh-workspace-oracle. READ-ONLY — do not modify any file. Produce a plan only.

## Read first (in this order)
1. `.oracle/northstar.md` — durable direction + anti-patterns
2. `.oracle/agent_goal.md` — the frozen contract: scope, done criteria (1–7), validation commands, model policy
3. `docs/astrid-migration-context/27-build-spec.md` — THE build contract (product boundary, capability registry, HTTP contract, atomic completion UoW, worker model, polling)
4. `docs/astrid-migration-context/22-codex-roadmap.md` — Phases A/B/C
5. Ground truth: `docs/astrid-migration-context/29-ground-truth-sensecheck.md` (verified vs amendment — note its #1 finding: §5 pre-transaction CAS publication is an AMENDMENT; current kernel publishes inside the writer lock via materialize_prepared), 28-engineering-answers-judgment.md (adopted mechanisms), 30-build-estimate.md (effort/risks/fastest path)
6. As needed: 16-capability-map.md (19 capabilities + families), grok/second-opinion-decisions.md (ratified refinements: flat names, one binding, snapshots-only, trimmed defs, reject dead types, executor-only child admission)
7. The code you are planning changes to: `/Users/peteromalley/Documents/Astrid-oracle/` — read enough real files/functions to ground tasks: astrid/core/repositories/tasks.py + media.py + io/media_import.py (completion call-graph, materialize_prepared), core/receipts/, packs/shots/ (v1 migration/repository to copy), packs/timeline/repository.py (CAS save + registry merge patterns), integrations/reigh/local_bridge_server.py + bridge_service.py (route plumbing, where token/Host gate hooks), tests/ layout + how integration tests boot DB/bridge.

## Deliverable (your entire output)
Markdown plan with EXACTLY these sections:

### 1. Tasklist covering the ENTIRE agent goal
Ordered tasks, each: id, title, exact files to change/create in Astrid-oracle, which done-criterion (1–7 from agent_goal.md) it advances, dependencies, acceptance check (test/command). Cover: kernel §5 amendment (pre-transaction CAS publication reorder); shots-pack v2 migration (generations/generation_variants DDL, no event stream) + GenerationRepository + record_completion in the completion UoW; capability registry (flat names, allowlist, one binding) + R1 admission (Idempotency-Key, 201/200/409); claim (leased running attempt, capability match, keyless) / heartbeat (lease + progress JSON) / complete (multipart files+fence→hash→atomic UoW) / fail routes; child-admission executor-only hard gate; local-trust gate (per-boot token, Host validation, custom header, 0700 data dirs); deterministic test executor binding; journey harness (admit→claim→complete→gallery row→registry merge→timeline visibility) with forced failures; crash-point fault-injection matrix (≥100 injected crashes, DB→tree totality assertions, receipt replay exactly-once, orphan report); full-suite regression pass.

### 2. Additional areas to explore (for the explorer fan-out)
5–7 areas where uncertainty could change the plan (e.g. exact current completion call-graph through tasks.py/media.py/io; bridge request plumbing + where the trust gate hooks; shots-pack v1 migration/repository/conformance patterns to mirror; pytest conventions for integration tests booting DB+bridge; timeline registry-merge internals; multipart handling precedents in the bridge). For each: what to verify, why it matters.

### 3. Open questions
Only questions whose answers could change the plan. If none, say none.

### 4. North Star check
One paragraph: how this plan advances each North Star principle and explicitly avoids every named anti-pattern.

Cap ~1,800 words. No implementation, no file writes.