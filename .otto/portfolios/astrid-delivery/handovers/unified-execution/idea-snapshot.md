> Frozen reference snapshot. Current state and receiving authority are governed by the package START-HERE and authority.md; preserve the existing live run. Paths below are source references, not missing package requirements.

# Complete the astrid-gpu-single-path operation (UNIFIED-PLAN v3)

## Goal

Execute the ratified UNIFIED-PLAN v3 end-to-end: recover the lost fire-19 backend code, integrate the two divergent VibeComfy branches, build the engine-neutral SessionManager (warm-weight residency for all generation backends), convert the C12 harness to session-aware evidence, and close the 45-task ledger with one final budgeted GPU acceptance run — 45/45 or an honest terminal.

## Settled Decisions

- **Architecture:** one engine-neutral `SessionManager` under GenericPackHost (Worker → GenericPackHost → SessionManager → engine children); adapters per engine; NOT Comfy-specific, NOT MCP-stdio-based (rejected by Astra second opinion).
- **Warmth contract:** seven operations (`observe`, `resident_key`, `prepare`, `run`, `fence`, `release`, `close`); three distinct identities (`session_incarnation`, `resident_key`, `AdmissionToken`); resident_key NEVER contains prompt/seed/task-id. Capability descriptor per adapter (ownership mode, residency support, admission capacity, cancellation strength, close semantics).
- **Warm flag flips are evidence-gated:** `warm_reuse_expected` flips only with process incarnation + no-reconstruction event + VRAM telemetry + load-time delta + canonical output equality. Failed feasibility gates are recorded honestly.
- **Evidence integrity:** no acceptance from archived overlays; the fire-19 sitecustomize overlay contained verification bypasses (no-op source verification, timestamp liveness, digest substitution, settlement rewriting) — barred from the final composition. Any verification bypass = immediate stop.
- **Ledger correction of record (Astra GPT-6 adjudication):** 22 accepted closures, 1 reopened (R1-B03-T01 HC-04 correction), 22 pending ALL OPEN. No pending row closes on discovered evidence. B03-T05a-e receipts are BLOCKED, not completions.
- **Vibe integration:** real content merge (base = `cb130f1b` lineage containing `c7f5b33d` launch-marker ownership; integrate `fix/S1-warm-snapshot-field-scoped-r12` @ `5b39fea5` authored content). NOT the ancestry-only probe merge. Isolated clean worktree; ~30 file reconciliation expected; independent review gate on the merge.
- **Harness conversion required:** C12 harness currently asserts per-task engine-process death and listener-port warmth — incompatible with retained sessions. Must be converted to session-aware manager-issued evidence before checkout_server can pass. Delete `start_checkout()`. Freeze the executable case inventory from the actual harness (the "89 cases" number was unverified).
- **Order:** P0 (custody/recovery/budgets) → P1 (Vibe merge) → P2 (manager core) → P3 (harness) → P4 (checkout GPU proof) → P5 (Wan persistent runner) → P6 (embedded retained session) → P7 (frozen composition → one budgeted full C12 GPU run → 45-row ledger closed → independent review → zero pods).

## Constraints (frozen, from the run's northstar/agent_goal)

- One owned pod at a time; ≤2 live attempts per engine/profile cluster
- **USD 6 aggregate provider cap** — historical spend must be reconciled before any new GPU fire; per-fire budget ledger (max minutes/dollars, abort conditions) required; reserved final-run budget
- ≤3 hours per pod; terminate + verify zero pods (by provider observation) on every exit
- No model downloads — weights pre-provisioned on `/runpod-volume`
- No production deployment
- **No fake PASS** — 45/45 or an honest terminal stating what failed/blocked; "EXECUTED" forbidden for unsuccessful outcomes
- 4 GiB local free-space floor; 2 GiB run-generated evidence cap; isolated-worktree mutation rules
- Source of record = tracked git only; no overlay-only behavior in the final composition

## Key artifacts

- Plan authority: `c12-safety-snapshot-20260908/UNIFIED-PLAN-v3.md`
- Adjudication: `c12-safety-snapshot-20260908/ASTRA-ADJUDICATION-FINAL.md` (RATIFY-WITH-AMENDMENTS; 22/1/22 ledger ruling; 8 mandatory amendments — all incorporated in v3)
- Fire-19 evidence: `c12-safety-snapshot-20260908/FIRE19-FINAL-EVIDENCE.txt` (wan2gp cold/warm PASS, pip_embedded cold/warm PASS, checkout deferred)
- Pod-only code preserved: `pod-c12-safety.tgz`, `pod-overlays-*.tgz`, `production_*-fire7.py`, `worker-fix.tgz`
- Recovered compositions: branches `otto/astrid-gpu-b03-b04-composition-20260906` (30 commits, tip `ffef517a`), `b03-t07`, `b04-t01`, `b04-t02` — pushed to GitHub + offline bundle

## Repos

- Astrid: `peteromallet/Astrid` (main `c2c9bb2a`; fi6-fast branch merged; work at `Astrid-fi6-fast-20260905` checkout)
- VibeComfy: `peteromallet/VibeComfy` (main `fbc25a37`; ownership-proof commit `c7f5b33d` on divergent lineage — P1 integrates)
- Worker: `banodoco/banodoco-workspace-worker` (main `d8fb2887`)
- Runtime: `banodoco/banodoco-workspace-runtime` (main `4050394`; fi6-identity integration branch pushed)
- Reigh app: `banodoco/reigh-app` (main `3e5115e79`)

## Acceptance (what earns 45/45)

Per adjudication evidence classes: P00-B05 rows close on source + focused CPU tests + fixtures + docs + accepted reviews; B06-T01/T02 on frozen composition + fresh preflight; B06-T03 on the final CPU journey; B06-T04/T05 on the final real-GPU journey + live recovery proof; B06-T06 on durable post-run evidence + cost accounting + cleanup; B06-T07 on independent integrated acceptance. Re-scoping alone earns nothing.

## Agent routing (standing policy)

- Astra (GPT-6, low): direction, briefs, custody, user updates
- Sol (GPT-5.6): P1 merge, P2 manager, fire-19 reconstruction; independent final reviewer (never reviews own implementation)
- Luna (GPT-5.6): adapters, harness conversion, tests, evidence prep
- Grok: not on default path (fallback after receipted exhaustion; user may re-open oracle routing)