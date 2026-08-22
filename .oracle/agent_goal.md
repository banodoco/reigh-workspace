# Agent Goal — megado run: Reigh-on-Astrid Phase-A vertical-slice foundation

**North Star:** [North Star](./northstar.md) — this run delivers the first executable proof of the one-authority architecture: the kernel amendment, the content schema, and the fenced task path, tested to doc-27 gates.

## Objective
Build and prove the Phase-A vertical-slice foundation in `Astrid-oracle` exactly as specified by **doc 27 (27-build-spec.md)**, adapted per **docs 28/29/30**: shots-pack v2 (`generations` + `generation_variants`, no event stream), capability registry (flat `reigh.<normalized>` names, ONE binding), task admission + claim/heartbeat/complete/fail routes with fences and receipts, the §5 atomic-completion UoW with **pre-transaction CAS publication** (kernel amendment — current kernel publishes inside the writer lock, per doc 29 finding) proven by a crash-point fault-injection matrix, local-trust gate (per-boot token, Host check, custom header, 0700 dirs), an executor seam with a deterministic TEST binding, and a journey harness (admit → claim → complete → gallery row → registry merge, with forced failures). All green under the repo's test runner.

## Authoritative inputs (immutable)
- Constitution: docs/astrid-migration-context/{15,24,25}.md + grok/second-opinion-decisions.md
- Build contract: docs/astrid-migration-context/27-build-spec.md; roadmap 22; estimate 30; audit 29; judgment 28; task model 26
- Source refs: see [custody.md](./custody.md) (Astrid @ dd1bbe3a, workspace @ f17dc11)

## In scope
`Astrid-oracle` only (kernel amend + packs/shots v2 + bridge routes/trust gate + registry + tests + journey harness with test executor binding).

## Non-goals / blocked (explicit)
- Real Wan2GP/VibeComfy generation journeys (**blocked: no CUDA box attached**; executor seam gets a deterministic test binding instead).
- reigh-app changes; orchestrator children (Phase B); model-acquisition journal (Phase B); render pipeline validation beyond task admission; SSE.

## Authorization
- Mutate ONLY `/Users/peteromalley/Documents/Astrid-oracle` and `/Users/peteromalley/Documents/reigh-workspace-oracle` (.oracle artifacts).

- Commit to each repo's `oracle-run` branch at batch checkpoints.
- Sync: at Phase-6 completion, push touched `oracle-run` branches to their `origin` remotes. Never merge to main.

## Sense-check cadence (USER-DIRECTED — supersedes default review-count policy)
This is a very-large-project run: in addition to routine per-batch oracle check-ins, schedule **BIG sense-checks** at sensible spots — each BIG sense-check runs **multiple independent review passes and multiple rounds** (review → reconcile → fix → re-review) until verdicts converge; divergence is never averaged away:
- **BC1 — post-plan / pre-tasklist-freeze:** ≥3 independent stealth/ox-alpha passes per round, distinct lenses: (a) correctness vs doc 27 build spec, (b) North Star principles + anti-patterns, (c) ground-truth vs actual Astrid-oracle code. Rounds repeat until all lenses converge.
- **BC2 — mid-execution:** trigger a BIG sense-check after every 3 passed batches, or immediately after any batch gate failure; same multi-pass, multi-round discipline.
- **BC3 — pre-completion:** ≥5 independent passes across the lenses above plus an operations/performance lens, round-until-converged.
All reviewers are stealth/ox-alpha (user-pinned). Convergence is the pass condition; divergence is a stop-and-reconcile signal, never averaged away.
- **DC — every 3 hours:** deploy a stealth/ox-alpha subagent for a DEEP progress audit of all track branches — in-depth report covering: code quality of the accumulated diff (vs doc 27 contract), North Star alignment (principles + anti-patterns), efficiency of progress (tasks completed vs plan/estimate, velocity), test status, blockers, and corrective recommendations. Report persisted under .oracle/evidence/deep-check-<n>.md; findings route through oracle triage like any review.
## Model policy (USER-PINNED FOR EVERY TASK CLASS)
Planner = Explorer = Normal executor = Oracle/reviewer = `[XHARD]` executor = **stealth/ox-alpha** (`launch_hermes_agent.py --model="stealth/ox-alpha"` via omp/openrouter). Owner pinned one model for all classes ("stealth/ox-alpha should be doing EVERYTHING"); no auto-routing; no switches without owner approval.

## Done criteria (all must hold)
1. Pack v2 migration applies cleanly on a fresh Astrid-oracle DB; 22→23 tables… *(corrected by doc 29/Grok review: without shot_generation_items the count is 22 tables)*; live probe passes.
2. Crash-point fault-injection matrix green: zero DB/tree disagreement across ≥100 injected crashes; receipt replay exactly-once.
3. R1 admission (allowlist + Idempotency-Key + 201/200/409), R3 claim (capability match, fence), heartbeat extends lease, complete/fail fenced — all route tests green.
4. Child-admission hard gate: browser-origin child admits rejected.
5. Local-trust fixtures: hostile page (rebinding/no-cors POST) fails; missing token rejected.
6. Journey harness green end-to-end with the test binding, including duplicate-admission replay and poisoned-output rejection.
7. Full Astrid test suite green; no regressions.

## Stop conditions
`blocked` = CUDA hardware required (live-generation checks); `failed` = reproducible unmet criterion after one rework loop; `escalate` = kernel-state-machine change beyond §5 amendment needed.

## Validation commands
- `cd /Users/peteromalley/Documents/Astrid-oracle && python3 -m pytest astrid/tests -x -q` (full suite)
- Journey harness: `python3 -m pytest astrid/tests/integrations/reigh -k journey -x -q`
- Fault matrix: the Phase-A fault-injection runner (built in-batch) with evidence table under .oracle/evidence/
