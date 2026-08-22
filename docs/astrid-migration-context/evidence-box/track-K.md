# Oracle Review — track-K (B1: kernel §5 amendment + crash-proof foundation)

**Verdict: PASS** (reviewed dd1bbe3a..cc1d854b; 2026-08-22)

## Evidence

1. **Spike (bytes durable before BEGIN IMMEDIATE)** — `tests/v10/test_crash_atomicity.py::test_publication_is_durable_before_begin_immediate_at_every_boundary` learns the unified boundary trace from two deterministic full runs, asserts `published_index < begin_index` on the trace itself (line 1786), then crashes a real child process (`os._exit(137)`) at every boundary and classifies reopen state: SQL old-or-complete vs references, digest bytes absent/durable — never partial/mutated; every boundary ≥ publication finds bytes durable. PASS.

2. **§5 amendment at both seams** — Both `materialize_prepared` (media.py ~1866) and `_insert`/`import_prepared` (~2226/~936) route through new `_resolve_publication` (media.py:730), which accepts the pre-transaction `published` record. New API in io/media_import.py: `publish_prepared_for_commit` (stage→fsync→verify→atomic install→file+dir fsyncs, idempotent) + `validate_published_presence`, both exported. Existing callers (conformance kit, sdk, packs) omit `published=` and keep the documented compatibility path — none broken. Note: no production caller yet passes `published=`; the hoist is seam+API capability, consistent with B1 foundation scope (fault-matrix docstring states convergence phase wires the fenced completion command).

3. **O(stat)-only in-lock** — With `published` supplied: type check, digest equality check, one `stat()` (`validate_published_presence`), then `repo.published` crash point. Proven by `test_pre_published_import_in_lock_work_is_stat_only`: source fixture AND staging tree deleted before the UoW; success requires zero byte copies; observed hooks == `["repo.published"]`. Mismatched digest and absent managed object both raise before any projection write. PASS.

4. **Fault-matrix skeleton** — `tests/v10/test_phase_a_fault_matrix.py`: labeled points (`upload/hash/publish/pre_commit/post_commit/response`), frozen validated `FaultInjection` schedule, child-process injector crashing at exactly one (point, occurrence), old-vs-complete reference classification, chain verification on reopen, evidence rows persisted to `phase_a_fault_evidence` sqlite table. PASS.

5. **Suites green** — `pytest tests/v10/test_crash_atomicity.py tests/v10/test_phase_a_fault_matrix.py -x -q`: **8 passed** (73s). `pytest tests/v10 -k completion -x -q`: **2 passed, 1039 deselected** (15s).

## Non-blocking nits

- Triple blank line after `validate_published_presence` in media_import.py (cosmetic).
