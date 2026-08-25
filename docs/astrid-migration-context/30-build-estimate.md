# 30 — Rough build estimate: Reigh-on-Astrid (Phases A–C)

> **Status: PLANNING INPUT (2026-08-22).** Ranges, not promises. Grounded in docs 22, 27, 29, and the WGP forensic report. All effort figures `[INFERENCE]` unless tied to a doc finding.

## Assumptions

- Engineers already fluent in Astrid kernel, reigh-app, reigh-worker; solo vs 2-engineer both given.
- Kernel + bridge exist and are tested (doc 29 §1 verifies every cited primitive). Incremental build, not greenfield — but doc 29's biggest finding is that §5's pre-transaction CAS publication is an **amendment to current kernel behavior** (bytes today publish inside the writer lock), so Phase A includes real kernel surgery.
- Hardware: an M-series Mac for bridge/app/render work **and** a CUDA box (local 4090-class or RunPod-equivalent) for the WGP/VibeComfy generation slice and both doc 27 §7.2 tiers. Without a CUDA box, add ~2–4 weeks of friction to A and B.
- Constitution and doc 27 are frozen; no scope creep.
- Note: doc 22 Phase-A step 10 puts the setup journal in Phase A; this estimate follows the tasking's scoping (setup journal/doctor in Phase B). If it stays in A, move ~1–2 weeks from B to A.

## 1. Per-phase ranges (calendar weeks)

### Phase A — vertical slice (falsification)

| Crew | Best | Expected | Worst |
|---|---|---|---|
| Solo | 5 | 8 | 14 |
| 2 eng | 3.5 | 5.5 | 9 |

What the gates realistically add: the §5 crash/fault-injection matrix (labeled crash points, `SQLITE_IOERR`/`FULL`, replay, concurrent identical-byte publication) plus its declarative fault schedule and evidence table is ~1.5–2 weeks by itself — it is a test harness, not a test suite. The local-trust gate with hostile fixtures (~0.5–1w) and the save-storm + floor-tier perf baseline (~0.5–1w) are also gate-driven, not feature-driven. The t2i→gallery→timeline→render→Range journey in a real browser is the long pole once the protocol works.

### Phase B — remaining surface

| Crew | Best | Expected | Worst |
|---|---|---|---|
| Solo | 7 | 11 | 18 |
| 2 eng | 4.5 | 7 | 11 |

~18 capabilities are repetitive *once* the generic VibeComfy handler and registry pattern exist: ~1–2 days each including its conformance fixture (doc 27 §3.6) → ~4–6 weeks solo. The orchestrator machinery (leased parents, attempt-independent keys, replay coordinator, checked transition table, deterministic-scheduler interleavings) is genuinely hard distributed-systems work: 2–4 weeks. Wan five-gate upgrade pipeline + N→N+1→N rollback drill: 1–2 weeks. Custom YAML path: ~1 week. Setup journal/doctor: 1–2 weeks.

### Phase C — app cutover + release

| Crew | Best | Expected | Worst |
|---|---|---|---|
| Solo | 5 | 8 | 12 |
| 2 eng | 3 | 5 | 8 |

Wide but shallow: supabase→bridge domain clients, realtime→2s/10s/30s polling, shot mode as a view, gallery/status UI, deep-copy duplicate, backup/restore round trip, clean-install + Supabase-blocked acceptance. Parallelizes well (one frontend, one backend/acceptance). Gates add ~1 week: two-tier calibrated budgets and blocked-network acceptance on a clean machine.

## 2. Total to releasable local v1

- **Solo: 17 / 27 / 44 weeks** (best/expected/worst) — roughly 4–10 months.
- **2 engineers: 11 / 18 / 28 weeks** — roughly 2.5–7 months.

Two engineers is not 2× on A (the crash matrix and browser acceptance are serializing), is close to 2× on B (capability fixtures fan out cleanly), and parallelizes well on C.

## 3. Biggest estimate risks (could double a phase)

1. **Pre-transaction CAS publication reorder (doc 27 §5; doc 29 finding #2).** Touches the kernel writer core and depends on real fsync/durability semantics across APFS and ext4. *Trigger:* durability tests fail on one filesystem, or the reorder regresses existing kernel completion paths. *Mitigation:* one-week spike on publication order + crash tests **before** building any routes; adopt the kernel's demonstrated durable-commit setting rather than inventing one.
2. **Wan2GP in-process coupling.** cwd/import contract, monkeypatches vs upstream, `decord` wheel gaps on Darwin-arm64, ckpts disk, headless driving (WGP report §3). *Trigger:* WGP won't run reliably headless on the Mac. *Mitigation:* doc 27 §3.1 already sanctions VibeComfy-on-clean-CUDA-machine as the Phase-A t2i binding — take that exit immediately rather than debugging WGP in-process; keep WGP as a Phase-B binding.
3. **Orchestrator replay correctness.** Attempt-independent keys + fenced replay + interleaving suite (lease expiry mid-fan-out, lost acks, zombie attempts) is where schedules historically die. *Trigger:* the interleaving suite keeps finding new races after the transition table. *Mitigation:* write the checked transition table and key lint **first**, build the deterministic scheduler against it, and timebox one redesign loop rather than patching races ad hoc.

(Honorable mention: Phase C breadth — hidden Supabase/auth/realtime dependencies in reigh-app (doc 06) surfacing late. Mitigation: inventory cutover call sites in week 1 of A, not C.)

## 4. Fastest credible path to the bottom of the range

- Phase A t2i via **VibeComfy on the CUDA box**, not WGP in-process (saves the single largest unknown from the critical path).
- Land the fault-injection harness and CAS-publication spike in week 1–2; everything else in A reuses them.
- One conformance fixture per capability, minimum viable (doc 27 §3.6 allows this); no broad matrix.
- Defer comfortable-tier separate baselines; ship floor-tier calibrated budgets only (doc 27 permits shared ceilings initially).
- Sequence B as: generic VibeComfy handler + registry pattern → fan out simple capabilities → orchestrators last (they need the most stable protocol).
- Keep thumbnails, paging, registry prune, and SSE deferred as already ruled (docs 27 §10, 22 §7).

## 5. Where to spend review effort

1. **The §5 completion UoW design** — ordering, durability, quarantine, receipt replay. Every later phase trusts it; a flaw here invalidates the Phase-A gate and much of B.
2. **Executor-only child admission gate** — the envelope/fence/allowlist seam is the product's one security boundary (doc 27 §3.5); a design review before implementation is cheap insurance.
3. **The Wan2GP five-gate upgrade pipeline** — its cost recurs on every upstream bump; getting gates 1–4 mechanical vs manual is the difference between a 1-week and a 3-week recurring tax.
