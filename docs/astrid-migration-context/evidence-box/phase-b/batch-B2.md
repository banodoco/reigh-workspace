# Oracle Verdict — Batch B2 (generic VibeComfy handler + E2E journey)

Reviewed: diff `0d7db2bb..HEAD`, Batch B2 scope only
(`astrid/core/integrations/reigh/vibecomfy_binding.py`,
`local_workflows.py`, `capabilities.py`, `bridge_service.py`,
`astrid/core/task_executor/service.py`, `tests/v10/test_vibecomfy_binding.py`,
`tests/v10/test_multi_task_journey.py`, digest-fence/capabilities test edits).
Branch `phase-b` @ 15fbddba. Date 2026-08-22.

## VERDICT: PASS (with minor non-blocking notes)

## Acceptance evidence

1. **Digest mismatch refuses before spawn** — PASS.
   `VibeComfyTaskHandler.execute` calls `_fenced_workflow` (snapshot-vs-authority
   digest + path, then on-disk bytes vs pin via `verify_workflow_bytes`) at step 1,
   BEFORE `resolve_runtime()` and the only `subprocess.run` call
   (`vibecomfy_binding.py:494→497→524`). Named test
   `test_digest_mismatch_refuses_before_subprocess_spawn`
   (tests/v10/test_vibecomfy_binding.py:108) monkeypatches `binding.subprocess.run`
   to `pytest.fail`, re-stamps the declaration row so ONLY the handler fences can
   catch drift, and asserts `WorkflowDigestMismatch`. Ran green.

2. **Typed-port injection t2i/i2i/edit** — PASS.
   `test_inject_t2i_shape_prompt_seed_size`, `test_inject_i2i_shape_image_strength`,
   `test_inject_edit_shape_prompt_and_negative` all green; plus negative tests
   (`test_supplied_port_without_target_refuses`,
   `test_missing_image_asset_refuses`) prove the invisible-failure default:
   supplied port with no target raises typed `PortInjectionError`, never drops.

3. **CPU smoke determinism** — PASS.
   `test_cpu_smoke_deterministic_across_three_invocations`: 3 real-subprocess
   runs through the handler; decoded-RGB-pixel SHA-256 equal across all three;
   manifest validated by the strict kernel validator in a separate test.
   Timing note below (observed ~25s/run here vs ~13s claimed warm); the
   assertion is pixel stability and holds.

4. **Journey green end-to-end** — PASS.
   `TestVibeComfyBindingJourney::test_declared_custom_workflow_runs_end_to_end_through_real_subprocess`
   (tests/v10/test_multi_task_journey.py:1053): R1 admission of family
   `local.workflow.run` derives `local.smoke_red` from the declared YAML row,
   snapshots bytes+digest into spec provenance; fenced `/queue/claim`; REAL
   subprocess through the one registered generic handler; multipart complete →
   asserted atomic terminal state `{media:1, task_outputs:1, generations:1}`,
   task+attempt both `succeeded`, CAS media at content-addressed path byte-equal,
   `failed_attempts == 0` (zero exceptions). The custom-YAML round trip exercises
   the identical `resolve_task_handler("vibecomfy")` handler as vendored rows.

## Correctness read

- **Fence ordering**: verified in source; digest verification precedes runtime
  resolution and spawn; unreadable/malformed/non-graph bytes also refuse typed
  pre-spawn (named tests with subprocess tripwire for each).
- **Registration**: explicit import-time `register_task_handler`; duplicate
  binding raises `TaskExecutorError`. No plugin discovery, no filesystem scan,
  no importlib/exec anywhere in the new modules (grepped). Growth by declaration
  honored: YAML rows are data; unknown keys trimmed; malformed rows/duplicate
  ids/bad digests refuse fail-closed at load.
- **One authority**: both vendored rows and declared local rows feed the single
  generic `VibeComfyTaskHandler`.

## Test runs

- `pytest tests/integrations/reigh/test_workflow_digest_fence.py
  tests/v10/test_multi_task_journey.py -q` → **22 passed, 12 skipped**
  (skips = parametrized non-vibecomfy binding rows + generic local row without
  template; expected).
- `pytest tests/v10/test_vibecomfy_binding.py -q` → **12 passed** (includes CPU
  smoke, 75.46s for 3 invocations under this box's load).
- Full `pytest tests/v10 tests/integrations/reigh tests/packs -q` → **63 failed,
  57 errors, 2860 passed**; every failure/error is in `tests/packs`
  (timeline_visualize_*, ffmpeg_compositor off-by-one pixel assert,
  pack_enum_recoverability, experiment_import). ZERO failures in B2 scope
  (`tests/v10`, `tests/integrations/reigh`). The diff touches no packs/rendering
  files; ffmpeg pixel off-by-one is environment-dependent rendering-pack drift,
  pre-existing, out of B2 scope.

## Notes (non-blocking)

1. Dead helper: `_resolve_via_table` (vibecomfy_binding.py:202-221) is never
   called; `_resolve_port_target` calls `_resolve_node_target` directly. Its
   docstring's rename mapping is stale (identity dict). Fix: delete it.
2. Admission/execution declaration-visibility asymmetry: admission resolves
   declarations with `projects_root` (bridge_service passes it), but the
   execution fence's `resolve_local_declaration(capability_id)` does not, so a
   declaration visible only under `<projects_root>/.astrid/workflows` admits yet
   refuses at execution ("no local workflow declaration found") unless
   ASTRID_LOCAL_WORKFLOWS covers it. Fail-closed typed refusal (no safety gap),
   but a capability can be admitted while unexecutable. Fix: thread
   projects_root into the fence or make the admitted snapshot the execution
   authority after digest cross-check.
3. RUN-command spec discrepancy: `tests/integrations/reigh/
   test_multi_task_journey.py` does not exist; the journey lives at
   `tests/v10/test_multi_task_journey.py` (run accordingly).
4. CPU smoke timing observed ~25s/invocation (75s total) vs "~13s warm" prose;
   determinism assertion unaffected.
