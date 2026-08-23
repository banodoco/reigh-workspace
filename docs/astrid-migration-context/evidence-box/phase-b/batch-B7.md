# Oracle Review — Batch B7 (Wan2GP binding + five gates)

Scope: c884167e..a338cb50 (phase-b), limited to B7 files: `wgp_{patches,bridge,build,conversion,binding,gates}.py`, six `test_wgp_*.py`, conversion goldens + corpus fixture, fixture-contract cutover commit 1b42665a.

## Verdict: PASS

### Acceptance

1. **Five gates mechanical + CUDA legs documented-skipped** — MET.
   `wgp_gates.py` defines five runners over a `Leg{ok|failed|skipped+reason}` report; `GateReport.ok` fails on any failed leg. Gate① runs git/anchor/schema checks against the vendored tree (`tests/v10/test_wgp_gate1_hermetic_rebase.py`, 8 tests). Gate② boundary contracts are named tests (`test_wgp_gate2_contracts.py`: cwd/argv/env facts recorded by a stub tree at import time; overrides land on live `server_config` AND only `wgp_config.json`; off-schema override refuses typed; full restore after body exception); real-tree `import wgp` leg skips with reason (CUDA-class stack). Gate③ declares per-platform dep plans, asserts decord-stub story + locked `--extra cuda124`, records `real_uv_sync` as skipped with CUDA/network reason. Gate④ replays golden fixtures byte-identical. Gate⑤ runs CPU shape assertions; every semantic-diff leg is recorded `blocked(CUDA)` carrying the phase stop-condition note — asserted present, never dropped.

2. **Rollback drill proven** — MET.
   `test_rollback_drill_n_plus_one_accepted_then_back_to_n`: install N → gated `rollout_swap` to N+1 (drain empty, full gate evidence) → prior==N retained → explicit `rollback_to_prior()` restores N exactly (digest equality) → retention survives reversibly both directions. Refusals proven: swap with work-in-flight, missing gate evidence, no prior, identical-manifest swap, malformed manifest, temp-litter check. Swap mechanics reviewed: atomic same-dir tmpfile + `os.replace`; prior written before current so any crash leaves a consistent pair. Queue/outputs-unharmed holds structurally: the store writes only its two manifest files, and `rollout_swap` refuses while the caller-owned drain reports live WGP attempts — in-flight work cannot be mid-swap-harmed. Observation (non-blocking): no explicit assertion leg that task/output stores are untouched by rollback; the guarantee is by-construction (store root contains nothing else).

3. **Same capability contract, no special casing** — MET.
   `register_task_handler(BINDING_WGP, ...)` in the shared kernel registry; `resolve_task_handler("wgp")` round-trip asserted; double registration of a different factory refuses. Probe lives in the shared `AVAILABILITY_PROBES` table (`wgp_runtime`), returns `(ok, missing)` naming absent artifacts + setup command; capability rows carry `probe="wgp_runtime"` like every other row; `tests/packs/reigh/test_capability_conformance.py` treats WGP rows uniformly. Build fence (`wan2gp_sha == PINNED_WAN2GP_SHA`) precedes conversion/import in `WgpTaskHandler.execute`.

4. **Build-manifest hash in completion provenance** — MET.
   `BuildManifest.digest()` = SHA-256 over canonical JSON; result manifest stamps `inputs.provenance = {kind: wgp.build_manifest, sha256, wan2gp_sha, worker_contract_version}`; `test_execute_end_to_end_stamps_build_provenance` drives the real boundary with a stub `wgp` module and asserts the stamp equals the installed store digest.

5. **Fixture contract + probe honesty cutover** — MET.
   Probe checks real vendored bytes (`wgp.py` + `defaults/`), not the never-present `worker.py`. All fake-runtime fixtures follow the same contract: `tests/integrations/reigh/conftest.py`, `test_family_journeys.py`, `test_orchestrator_interleaving.py`, `tests/packs/reigh/test_capability_conformance.py` all write `wgp.py` + `defaults/`. Vendored pin verified on disk: `vendor/Wan2GP` HEAD == `181bb71a21008032e4771e11663f33e4489c4512`, clean tree, `wgp.py`+`defaults/` present; schema reconstructed from pinned bytes with AST-verified zero drift.

### RUN (executed by oracle)

`python3 -m pytest tests/v10 tests/integrations/reigh tests/packs -q` (without `-x`, to obtain the full failure set for ledger diff): **2984 passed, 63 failed, 94 skipped, 57 errors**, 1080s.

Failure-id diff vs the B-0 ledger (`.oracle/evidence/b0-baseline.txt`, 142 ids): **zero new failures**. The three apparent extra ids in `.pytest_cache/lastfailed` (`test_generate_image_openai.py::{test_llm_client_key_loader_reads_env, test_load_api_key_prefers_env_file_over_process_env, test_load_api_key_reads_env_by_default}`) are stale cache entries for tests renamed pre-B7-base in `1f53c548` — they do not exist in the current file, were not executed, and pass 6/6 standalone. One ledger id resolved green (`test_domain_cli_surface.py::test_dispatch_product_routes_family_and_closes_client`). Zero failing ids touch reigh/wgp surfaces — consistent with the executor's "59 fixture-drift ids resolved" claim.

### Diff-correctness notes (non-blocking observations)

- `wgp_gates.gate2_boundary_contracts()` returns an unconditional-ok delegating leg (documented: stateful process contracts belong to pytest). `rollout_swap` consumes caller-presented evidence, so pipeline output alone never gates a swap — sound, but gate②'s runner leg is a label, not a check.
- `bump_tree_digest` leg (gate①) records the tree digest with status ok unconditionally — it documents rather than compares. Harmless given the separate `submodule_bump_pinned` + clean-tree legs.
- `install()` identical-digest refusal makes no-op upgrades impossible — good silent-swap closure.

No issues requiring fix.
