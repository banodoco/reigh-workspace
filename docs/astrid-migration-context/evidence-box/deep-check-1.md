# Deep check-in #1 — independent audit of track-K / track-S / track-R

Date: 2026-08-22 ~02:45 UTC. Auditor: stealth/ox-alpha (independent). Base dd1bbe3a.
Note: an earlier `deep-check-1.log` launch at root crashed before writing any report; this file supersedes it.

## Verdicts

| Track | Verdict | Summary |
|---|---|---|
| track-K | **HEALTHY** | §5 amendment landed cleanly at both seams; crash tests prove the invariant |
| track-S | **HEALTHY** | Shots v2 exact DDL, receipt-free repo, additive registry merge; no anti-patterns |
| track-R | **HEALTHY** | Registry + routes + trust gate solid; one minor fd leak; sweeper seam unowned |

## 1. What actually landed

- **track-K** (`7fc0e3fa`, `936facd3`, `cc1d854b`): `publish_prepared_for_commit` + `validate_published_presence` exported from `core/io/media_import.py`; both publication sites (`materialize_prepared`, `_insert`/import path) route through `MediaRepository._resolve_publication` (`core/repositories/media.py`) — caller-supplied `published=` ⇒ O(stat) in-lock; bare-UoW callers keep the old in-UoW publish. Fault-matrix harness with real child-crash lanes + SQLite evidence table. All five `import_prepared` callers untouched (verified).
- **track-S** (`57fd4e82`…`fb962595`, 8 commits): `0002_generations.sql` (exact doc-17 DDL minus `shot_generation_items`), frozen-20→22 bumped in all homes incl. the `m4_gate.py:568` latent-bug fix, `generation_repository.py` (838 lines, receipt/event-free, caller-UoW), `timeline.registry_merged` kind + `TimelineRepository.merge_registry` (additive upsert, hash-chained `{assets, added_keys, base_head}`, internal head CAS, archive fence, byte-identical `document_json`).
- **track-R** (`d7c73634`…`1d638604`, 6 commits): typed capability registry (19 IDs + render, dead-type reject incl. `wan_lora_training`), R1 admission trio, executor-only child gate (deterministic `reigh.orch:v1:<parent>:<role>:<index>`, live parent lease/fence at `bridge_service.py:654-716`), local-trust gate in `parse_request` (Host+token `hmac.compare_digest`, custom header, OPTIONS exempt, 0700 dirs), claim/heartbeat/cancel, bounded streaming `multipart.py` (347 lines), complete/fail with real `UnitOfWork` writes.

## 2. Code quality vs doc 27

High. K's `_resolve_publication` validates digest match before any write; mismatch raises pre-projection. S's `merge_registry` reuses the existing event append machinery (no second CAS protocol); zero-new-keys short-circuits without appending. R's parser fails closed: cap checks pre-read, per-field/per-file caps, required `--boundary--`, unlink-on-abort. Tests are invariant-grade, not smoke: K crashes a child at *every* boundary asserting old-or-complete SQL + durable-or-absent bytes (`test_phase_a_fault_matrix.py:546`); S covers one-primary partial-index rejection, `ON DELETE RESTRICT`, unique membership, soft-delete idempotence, merge additivity/CAS; R covers admission replay trio, wrong-fence 409 zero-rows, poisoned-bytes zero-rows, parser abuse suite.

## 3. North Star alignment

Clean. No mirrored state (generations have no event stream, no receipt, no denormalized primary pointer — DDL partial index is the authority). No second CAS protocol. Registry merge mutates `asset_registry_json` inside the completion UoW against current head — explicitly not a placement store. Trust gate fail-closed; no middleware layer invented; no fallback paths. Only nit: `publish_prepared_for_commit` is a thin comprehension wrapper — acceptable as a named §5 seam.

## 4. Progress vs T1–T14 (~62% of plan tasks substantively done)

Done: T1 (K, latent — see §7), T2, T3-repo/merge (S), T4, T5, T6-routes, T7, T8, T9 (R). Partial: T13 (skeleton mechanism green; HTTP-level points upload/hash/response stubbed for convergence, per brief). Not started: **T10, T11, T12, T14** (convergence-owned).

Velocity: all three tracks finished their assigned slices inside the ~2h window with green focused suites — on plan. Drift risk is entirely in the unstarted convergence half: journey harness, fault-point filling, full regression.

## 5. Test status (run by auditor, read-only)

- track-K: `pytest tests/v10/test_crash_atomicity.py tests/v10/test_phase_a_fault_matrix.py -q` → **8 passed** (73.8s)
- track-S: `test_generation_repository.py test_timeline_registry_merge.py test_registry.py test_m8_installed_contract.py -q` → **79 passed** (12.8s)
- track-R: `pytest tests/integrations/reigh -q` → **244 passed** (72.7s)

## 6. Blockers / wedges

No `track-*.blocked` files exist anywhere. All three supervisor logs end "exhausted relaunches" with tracks reporting complete and clean trees — nothing wedged; the tracks are simply out of work in their ownership scopes. Known environment noise: committed `artifacts/m4/finalizer-admission.json` records `exit: 1` from pre-existing `_check_cli_surface` drift that also fails at base `dd1bbe3a` (not track-S's doing).

## 7. Corrective recommendations (ranked)

1. **Wire the lease-expiry sweeper — currently UNOWNED and MISSING.** Plan T6 requires the daemon in `compose_standard_bridge` (`packs/__init__.py:199`); E6 found `expire_overdue` (`tasks.py:2358`) has zero production callers. Verified absent on ALL THREE branches. A crashed executor still wedges its task `running` forever; blocks T12/T13 acceptance. Assign to convergence owner now (~30 lines + liveness test).
2. **Converge the completion path**: R's complete route must pass K's `published=` (currently latent — no production caller) and invoke S's `record_completion` + `merge_registry`. Until then §5 step 6–7 ordering is unproven end-to-end.
3. **Fix multipart fd leak** (`multipart.py` `stage_file_until.spill` raises `fail()` without `os.close(handle_fd)` on oversize rejection — reviewer reproduced 200 reqs growing fds 6→206). ~3 lines; do before T12.
4. **Run T10/T11/T12** (test-executor binding + t2i fixture, gallery reads, journey harness) — the largest remaining Phase-A chunk; gallery reads are small given `GenerationRepository` paging already exists.
5. **Fill T13 HTTP-level labeled points** after (2) lands, and measure wall-clock vs the 900s CI lane first (plan N3).
6. Cosmetic: triple blank line after `validate_published_presence` in `media_import.py`; reconcile stale `_check_cli_surface` constants or annotate the admission artifact.
