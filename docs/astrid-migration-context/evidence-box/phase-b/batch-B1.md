# Oracle Review — Batch B1 (baseline lock + pin the data)

Scope reviewed: dd1bbe3a..HEAD, commits b2ea2a62 (B-0 ledger) and 0d7db2bb (pin the data). Later converge commits are prior-Phase-A state, out of scope.

## VERDICT: PASS

(with two non-blocking observations, below)

## Acceptance criteria

### 1. Tampered workflow => fail-closed refusal before any byte write — MET
- `astrid/core/integrations/reigh/capabilities.py`: `load_workflow_snapshot()` reads vendored bytes, sha256-checks against `entry.template`, raises `CapabilityUnavailable` on missing file or drift; never falls back to re-reading drifted bytes.
- `bridge_service.admit` calls `load_workflow_snapshot(entry)` inside the capability-resolution try block BEFORE building spec / running the write command; snapshot lands in `spec["workflow"]` provenance.
- Named test `tests/integrations/reigh/test_workflow_digest_fence.py::test_tampered_workflow_refuses_admission_before_any_write` PASSED: tamper `basic_image_upscale.json` -> HTTP 422 `capability_unavailable` with "digest mismatch", `COUNT(tasks)==0`, `command_receipts` unchanged vs recorded baseline. Import-time fence tests (`fails_closed_on_digest_drift`, `fails_closed_on_missing_file`) PASSED; `verify_registry_workflows()` runs inside `_validate_registry()` at module import (verified by importing the package).
- Fence pins DATA (vendored workflow bytes), not code — matches north star; no digest-the-code pinning.

### 2. Zero floating refs in requirements files — MET
PCRE check `git+ ... @<40-hex>` across all `requirements*.txt` under repo: exactly three `git+` lines exist, ALL pinned:
`vibecomfy @ git+https://github.com/peteromallet/VibeComfy.git@054bce5bdc9c63d68ac7e6141063e1f029a70dcb`
(`astrid/packs/comfy_wrap/executors/run/requirements.txt`, `astrid/packs/vibecomfy/executors/run/requirements.txt`, `astrid/packs/vibecomfy/executors/validate/requirements.txt`). Floating-ref filter exits empty.

### 3. CapabilityEntry.template complete + digests match disk — MET
- Registry introspection: 12/12 vibecomfy-bound entries have `template=(path, sha256)`; zero without. Non-vibecomfy bindings correctly carry none (11 parametrized skips are legitimate, skip reason "non-vibecomfy binding carries no vendored workflow").
- Independent verification with `sha256sum` on ALL 8 vendored files under `astrid/core/integrations/reigh/workflows/` — every digest matches its pinned value in capabilities.py (samples required >=2; delivered 8/8), e.g. qwen_image_2512.json = 2db0bd63…af0b7, z_image.json = b7348cdc…fe427.
- `test_every_shipped_workflow_file_is_pinned_by_some_entry` PASSED (no orphan workflow files); `test_vibecomfy_entries_pin_vendored_bytes_matching_disk[*]` all PASSED.

### 4. .oracle/evidence/b0-baseline.txt exists with full-suite output — MET
23,117 lines, real `pytest tests -q` output @ 0b69557b (78 failed, 7265 passed, 94 skipped, 64 errors, 557 subtests, 1748.73s), short-test-summary verbatim, plus appended ledger notes naming the two DC-6 collection errors (`tests/packs/rendering/test_timeline_visualize_parity.py`, `tests/timeline/test_inverses.py`) verbatim by path with explicit provenance ("recorded here verbatim from the DC-6 documentation because they no longer occur").

## Mandated run

`python3 -m pytest tests/v10 tests/integrations/reigh tests/packs -q`:
**63 failed, 2847 passed, 91 skipped, 57 errors, 172 subtests passed** (~15 min). NOT literally green.

JUnit-XML diff of every failed/error ID against the B-0 ledger (in-scope extraction):
- NEW failures vs ledger: **NONE** (120/120 current IDs match ledger IDs).
- Ledger failures absent now: 1 — `tests/v10/test_domain_cli_surface.py::test_dispatch_product_routes_family_and_closes_client` (now passes; baseline flake, improvement).
- All remaining failures are the ledger's documented pre-existing clusters: timeline-visualize `'app'` schema-property drift, ffmpeg compositor pixel rounding (254-vs-255 off-by-one), experiment-import hardlink/media assertions, remotion registry fixture assumption. None touch reigh bridge/registry surfaces mutated by B1; `tests/integrations/reigh` and `tests/v10` are fully green.

The literal "-x … must be green" reading is unsatisfiable given the ledger itself records 142 pre-existing failures/errors; the operative contract (commit message, plan.md row 1/B10) is "zero NEW failures against this ledger," which holds.

## Observations (non-blocking)

1. **"Must be green" wording vs documented baseline.** The mandated command cannot be green on this branch by design until the pre-existing clusters are fixed (later batches). Recommend future batch briefs phrase the gate as "zero new failures vs b0-baseline.txt" to remove ambiguity. Evidence above.
2. **Collection errors recorded by reference, not captured output.** Both files collect cleanly at B-0 time (verified: `pytest <file> --collect-only` exits 0, 77 tests collected). The executor chose recording them from DC-6 docs with provenance over fabricating pytest output — correct call; noting the deviation from the literal brief wording.

## Verification performed (read-only)

- sha256sum of all 8 vendored workflow files vs pinned digests: 8/8 match.
- Registry import + introspection: import-time fence executes; 12 vibecomfy entries templated.
- Digest-fence suite: `pytest tests/integrations/reigh/test_workflow_digest_fence.py -v` → 19 passed, 11 skipped (all skips = non-vibecomfy bindings).
- Floating-ref grep (PCRE) over repo requirements files: zero floating.
- Two full runs of `pytest tests/v10 tests/integrations/reigh tests/packs -q` (reproducible: identical counts both runs), junitxml ID-level diff vs ledger.

— ox-alpha, independent oracle reviewer, 2026-08-22
