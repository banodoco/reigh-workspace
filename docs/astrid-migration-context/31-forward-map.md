# 31 — Forward map: Phases B and C in full

> Status: PLAN OF RECORD (2026-08-22). Continues doc 22's three-phase structure at workstream granularity after Phase A completion (`origin/Astrid/oracle-run` @ `0b69557b`). Everything here inherits the ratified constitution (15/24/25 + Grok second opinion + 24) and the build contract (27). BC2 sense-checks every 3 passed batches; DC deep audits every 3 hours on-box; BC3-style convergence reviews at each phase boundary.

## Where Phase A landed (entry state)

`Astrid/oracle-run @ 0b69557b`: kernel §5 amendment proven by a 107-crash fault matrix (zero DB/tree disagreement); shots-pack v2 (generations/generation_variants, event-less, one-primary index); capability registry (flat names, one binding, dead types rejected); fenced routes (admission/claim/heartbeat/cancel/complete/fail/task-reads); child-admission executor-only gate; local-trust perimeter; gallery + media-content serving; journey harness green; full suite green minus pre-existing baseline (documented in doc 29/30 and the box evidence).

Executor seam status: deterministic TEST binding only. Real Wan2GP/VibeComfy bindings are Phase B.

## Phase B — populate the catalog, make upgrades boring

Sequenced dependency-first. B-1 unlocks most of B-2; B-3 is independent until convergence.

### B-1 — Generic VibeComfy executor binding (first)
- Template-digest pinning (scratchpad snapshots + in-repo ready_templates per ratified D4).
- Typed ports → input validation → `vibecomfy run` invocation → outputs into atomic completion.
- Gate: ONE non-Wan capability (e.g. `reigh.image.upscale`) runs end-to-end through the real binding on the CUDA box.

### B-2 — Capability fan-out (~15 capabilities)
Each = registry entry + input validator + conformance fixture (~1–2 days once B-1 lands):
qwen generate/style/2512/edit · z_image (+i2i) · image upscale · flux_klein edit · video_enhance · animate_character · inpaint/annotated_edit.
Gate: per-capability fixture green; availability probe truthful (missing model → hidden + setup hint).

### B-3 — Orchestrator children (hardest; start by week 3 regardless of B-2 state)
- Leased parents (running under LeaseKeeper, no kernel yield transition).
- Attempt-independent child keys `reigh.orch:v1:<parent>:<role>:<index>`; pure `derive_children(spec)`; receipted admission through the executor-only gate.
- Replay coordinator + checked transition table + deterministic-scheduler interleaving suite (lease expiry mid-fan-out, lost acks, zombie executors, cancel-during-replay).
- travel/join/edit orchestrator families ported onto it.
Gate: zero duplicate children + exactly-one parent-terminal across all adversary permutations.

### B-4 — Wan2GP binding + five-gate upgrade pipeline
- WGP binds the wan/travel/join family (in-process cwd/sys.path contract preserved).
- Gates: hermetic rebase build → contract tests (wgp_bridge symbols, config keys, layout) → platform resolution (darwin-arm64 decord) → conversion fixtures → seeded output corpus + semantic diff.
- Drain-and-swap rollout; prior manifest retained for pointer-flip rollback; boot-manifest hash stamped into completion provenance.
Gate: accept N+1 → roll back to N → queue and outputs unharmed.

### B-5 — Model acquisition
- Setup journal/state machine (absent→downloading(offset)→verifying→installed / corrupt→repair), signed version-pinned manifest, tier discovery probe, disk preflight, doctor repair, truthful advertisement closure.
- Acquisition is the ONLY sanctioned outbound networking (setup mode).
Gate: fresh clean install reaches first generation with no manual path surgery.

### B-6 — Conformance completion
Fixture per shipped capability; conformance-suite result hash stamped into the boot manifest; startup fails closed on bridge/worker registry digest disagreement.

**Phase B exit:** every shipped capability has a passing fixture; orchestrator interleaving suite green; Wan rollback drill green; fresh-install gate green.

## Phase C — the app becomes the product

| Order | Workstream | Contents | Exit |
|---|---|---|---|
| C-0 (week 1 of A/B — do early) | Cutover inventory | Enumerate every supabase-js touchpoint in reigh-app incl. hidden ones (doc 06 §8 is the seed) | Complete call-site list with per-site target (bridge client / cut / defer) |
| C-1 | Domain client cutover | AstridLocalClient replaces supabase-js; realtime → 2s/10s/30s polling; auth/session machinery removed | App runs fully against the bridge |
| C-2 | Shot mode as view | Shot groups/pools/boundaries from the timeline document; promote-primary via pack commands; deep-copy duplicate | Shot UX feature-complete vs doc 06 §3.2–3.3 inventory |
| C-3 | Render/export UX | Render-as-task UI; progress via polling; MP4 playback via Range/ETag; destination selection | One supported export path proven |
| C-4 | Ops surfaces | Backup/restore UI, onboarding + model-setup screens, doctor integration, typed error/recovery UX | Every typed failure maps to one next action |
| C-5 | Acceptance | Clean-install on both hardware tiers; Supabase + provider networking OS-blocked; budgets met on floor tier; full suite + journey + matrix green | Sign-off |

**Phase C exit:** the app is unrecognizable as ever having had a backend — no Supabase code paths, credentials, or network calls anywhere in the supported surface.

## Phase D — release mechanics

Push `oracle-run` branches → tag → clean-install distribution packaging → retire the Supabase project after the agreed window. The box container remains the build/test rig.

## Cross-cutting cadence (continues from Phase A)

- BC2 BIG sense-checks every 3 passed batches or on any gate failure (multi-lens, multi-round).
- DC deep progress audits every 3 hours when running on-box.
- Oracle review per batch checkpoint (one pass; rework loops until PASS).
- "Name the row" governance: every new abstraction must name the option/invariant it protects.

## Effort frame (from doc 30, solo / 2-eng)

Phase B expected 11 / 7 wk · Phase C expected 8 / 5 wk · release mechanics ~1 wk. Observed agentic velocity in Phase A materially beat these frames; treat doc 30's ranges as the conservative bound and re-baseline after B-1/B-3 land.

## Top risks carried forward

1. Orchestrator replay correctness (B-3) — transition-table-first, timebox one redesign loop.
2. Wan2GP rebases (B-4) — gates mechanical, rollback always retained.
3. Hidden Supabase dependencies surfacing late (C) — mitigated by C-0 inventory done in week 1.
4. Model acquisition edge cases (B-5) — partial downloads, license records, platform gaps treated as first-class states.
