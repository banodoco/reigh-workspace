# Live Validation Plan: reigh-worker Dual Backend VibeComfy Migration

> **Draft status:** Sister plan for `migration-vibecomfy.md`, authored 2026-05-05.

This document defines how to test the addition of VibeComfy as a peer execution backend alongside Wan2GP, live and end-to-end on real RunPod GPUs. It complements `migration-vibecomfy.md`: that document owns the migration design; this document owns the validation harness, acceptance gates, and evidence package required before canary and dual-executor steady state.

## Threshold and Route Version 0B (2026-05-05)

The executable threshold and route source of truth for Sprint 0B and later dual-run, dry-run, and canary consumers is `reigh-worker/scripts/dual_run_compare/migration-thresholds.yaml` (`version: 0B-2026-05-05`, `schema_version: 1`). Later scripts must load this YAML through `python -m scripts.dual_run_compare.check_thresholds --strict` and the `Thresholds` API rather than copying values from this document or `migration-vibecomfy.md`.

Metric rows in version `0B-2026-05-05`:

- `image_phash_normalized_hamming`
- `image_ssim`
- `image_pixel_dimensions`
- `image_format_container`
- `video_frame_count`
- `video_phash_mean`
- `video_phash_p95`
- `video_duration_ms`
- `video_fps`
- `video_audio_duration_ms`
- `latency_p95_wall_clock_ratio`
- `vram_peak_ratio`
- `error_oom_count`
- `canary_output_divergence_rate`

Route key canonicalization is defined in `reigh-worker/scripts/dual_run_compare/route_keys.py`. Cohort A/B direct product routes use direct route keys; Cohort B edit variants add dimensions when variant dimensions are present; Cohort E route keys are dimensional and include task type, model family, guidance kind, continuity case, and profile.

Golden corpus and fixture layout:

- `reigh-worker/scripts/dual_run_compare/golden/<route_key>/manifest.json`
- `reigh-worker/scripts/dual_run_compare/fixtures/golden_seed_payloads/`
- `reigh-worker/scripts/dual_run_compare/fixtures/non_rayworker/`

WGP repeatability evidence for this version is committed at:

- `reigh-worker/scripts/dual_run_compare/reports/wgp-self-repeat-0b-2026-05-05-deferral.json`
- `reigh-worker/scripts/dual_run_compare/reports/wgp-self-repeat-0b-2026-05-05-deferral.md`

Status summary: all 14 route keys in the YAML and report are currently marked `deferred_pending_sprint_0c_disk`. The report records the attempted WGP-vs-WGP command shape for every required route, but it contains no paired WGP metric observations. This is not a RunPod-access failure: the agent separately verified live RunPod lifecycle on 2026-05-05 with pod `f9s5vqk15gux9d` through launch, SSH readiness, GPU visibility, storage health, pod listing, termination, and post-terminate absence. After user correction, WGP is treated as the trusted control; paired WGP self-repeatability should run only when a later sprint needs fresh measured drift to promote route statuses.

## Execution Primitive

The migration execution unit is a VibeComfy Python ready template under `vibecomfy/ready_templates/**/*.py`.

Raw Comfy JSON can remain as import/source material under `workflow_corpus/`, and tiny JSON fixtures may remain for parser or runtime unit tests, but live migration validation must not treat JSON fixture execution as the standard path. A RunPod validation row should execute a Python ready template by ready-template id or path, for example:

```bash
python3 -m vibecomfy.cli run smoke/empty_image_red --ready --runtime embedded --backend graphbuilder
python3 -m vibecomfy.cli run image/qwen_image_2512 --ready --runtime embedded --backend graphbuilder
```

Each production row must report the ready-template id, Python source path, `READY_REQUIREMENTS`, staged model URLs/paths, VibeComfy run id, Comfy prompt id, outputs, and artifact paths. If a validation command runs a raw JSON workflow directly, it is only a low-level runtime smoke and cannot satisfy a migration gate.

## Goals

- Prove each production-used task type can run through the VibeComfy backend on real RunPod hardware.
- Reuse VibeComfy's existing cloud/RunPod mode for template and workflow execution validation instead of duplicating pod lifecycle code in `reigh-worker`.
- Preserve `reigh-worker` live-test coverage for Supabase queue behavior, task claiming, completion, generation linking, output shape, logs, and rollback.
- Add semantic media grading through ArtAgents `builtin.understand` so live tests check whether outputs are coherent and intent-preserving, not only whether files exist.
- Produce a durable evidence bundle per run: task payload, backend, template id, RunPod pod id, worker id, output paths, timings, failure class, media descriptions, rubric scores, and final gate decision.

## Non-Goals

- No replacement of VibeComfy's existing RunPod/cloud scripts.
- No new production queue schema.
- No requirement that automated visual grading be the only approval signal. It is a promotion gate and triage aid; final canary still requires human review of sampled outputs.
- No migration coverage for task types classified as UNUSED in `migration-vibecomfy.md` §0A.
- No Wan2GP retirement validation. WGP remains the control backend and a supported rollback executor.

## Existing Surfaces To Reuse

### VibeComfy Cloud / RunPod Mode

VibeComfy already has the primary cloud validation machinery:

- `vibecomfy/scripts/runpod_runner.py`
  - `PodGuard` launches and terminates RunPod pods with a max-runtime watchdog.
  - `run_pod()` uploads the local VibeComfy checkout, runs a remote script, prints pod id and SSH details, and terminates in `finally`.
  - `run_pod_detached()` runs long matrix jobs, polls `results.tsv` / media / logs, downloads `out/corpus_matrix`, `output`, and `out/runs` artifacts, then terminates in `finally`.
- `vibecomfy/scripts/runpod_validate.py`
  - Cheap live smoke: install VibeComfy, install HiddenSwitch ComfyUI and ComfyScript, run tests, run runtime smoke, then execute the minimal Python ready template `ready_templates/smoke/empty_image_red.py`.
- `vibecomfy/scripts/runpod_model_matrix.py`
  - Proper model-backed matrix: baseline `comfyui run-workflow`, convert to VibeComfy scratchpad, run via embedded Comfy, record output counts and timings.
- `vibecomfy/scripts/runpod_corpus_matrix.py`
  - Corpus-scale remote matrix with detached polling and artifact download.
- `vibecomfy/vibecomfy/commands/runpod.py`
  - CLI forwarding for `vibecomfy runpod list/status/terminate/gpu-types/corpus-matrix`.
- `vibecomfy/tests/smoke/test_*runpod*.py`
  - Opt-in pytest markers `runpod` and `runpod_full` for real GPU smoke and matrix coverage.

This should be the foundation for template execution, model staging, custom-node installation, artifact capture, and pod lifecycle safety.

### reigh-worker Live Harness

`reigh-worker` already has a queue-realistic harness:

- `reigh-worker/scripts/live_test/main.py`
  - CLI entrypoint with `fresh` and `update` variants, WGP profile argument, task timeouts, and anchor image overrides.
- `reigh-worker/scripts/live_test/variant_fresh.py`
  - Launches a fresh pod, clones `Reigh-Worker`, starts the worker, inserts live tasks, polls completion, writes a report, terminates.
- `reigh-worker/scripts/live_test/variant_update.py`
  - Takes over an existing orchestrator-managed pod or spawns one, pushes the local branch to a temp branch, starts the worker, runs the task matrix, restores prior remote state.
- `reigh-worker/scripts/live_test/matrix.py`
  - Fixture-backed matrix for `travel_orchestrator`, `individual_travel_segment`, Qwen image/edit/style, Qwen 2512, and `z_image_turbo_i2i`.
- `reigh-worker/scripts/live_test/task_spoofer.py`
  - Inserts Supabase task rows from worker-matrix fixtures and marks `params.live_test = true`.
- `reigh-worker/scripts/live_test/completion_poller.py`
  - Polls terminal task status and linked `generations` rows.
- `reigh-worker/scripts/live_test/report.py`
  - Writes `report.json` and `report.md`.

This should remain the authority for queue contract validation. It should not grow a second full VibeComfy cloud runner.

### ArtAgents Media Understanding

ArtAgents has the pieces needed for semantic validation:

- `ArtAgents/artagents/packs/builtin/generate_image/run.py`
  - Generates fixture and reference images through GPT Image models.
- `ArtAgents/artagents/packs/builtin/understand/run.py`
  - Dispatcher for modality-specific understanding.
- `ArtAgents/artagents/packs/builtin/visual_understand/run.py`
  - Calls OpenAI Responses API with image inputs, supports contact sheets, crop variants, `fast` and `best` modes, and writes JSON output.

Use ArtAgents after live output artifacts are available. It should not run inside the GPU worker process.

## Architecture

Use a two-layer validation system.

### Layer 1: VibeComfy Cloud Validation

Purpose: prove the target runtime can execute the selected workflows/templates on real GPUs independent of Reigh queue concerns.

Runner: VibeComfy cloud mode executing Python ready templates. `scripts/runpod_validate.py` is a launch/artifact/termination smoke; task-family proof must use `scripts/runpod_corpus_matrix.py` or a Reigh-aware wrapper that selects production ready-template rows.

Inputs:

- VibeComfy ready-template id and Python source path.
- Source workflow provenance, if the ready template was derived from raw Comfy JSON.
- Reigh task fixture parameters translated into VibeComfy template inputs.
- Deterministic seed where supported.
- Small but realistic image/video fixture assets.
- Memory profile target mapped to VibeComfy `SessionConfig`.

Outputs:

- VibeComfy `RunResult` metadata.
- `READY_REQUIREMENTS` model/custom-node declarations, including URL-backed model assets.
- Staged model evidence: source URL, target path, byte size, checksum, and skipped/downloaded status.
- Generated media artifacts.
- `results.tsv` or JSON equivalent with status, runtime seconds, media count, byte count, failure class.
- Downloaded artifact directory under `vibecomfy/out/runpod_artifacts/<run>/`.

Gate:

- Template validates locally.
- Template executes on RunPod.
- Output files exist, are non-empty, have expected modality and dimensions/duration.
- No OOM, missing-node, model-missing, prompt-queue, or output-missing errors.
- For migration cohorts, ArtAgents semantic score meets the task-specific threshold.

### Layer 2: reigh-worker Live Queue Validation

Purpose: prove production queue semantics still work when `REIGH_BACKEND=vibecomfy` is selected.

Runner: existing `reigh-worker/scripts/live_test` harness, with a new backend flag and validation hook.

Inputs:

- Existing worker-matrix fixtures.
- Backend selection: `wgp`, `vibecomfy`, or `dual`.
- Optional VibeComfy artifact/template evidence from Layer 1.
- Same anchor images and prompts used for Layer 1 where possible.

Outputs:

- Supabase task rows move `Queued -> In Progress -> Complete` or classified failure.
- Linked `generations` rows are created.
- `output_location` and generation media are reachable.
- Worker logs include backend, template id, memory profile, VibeComfy run id, Comfy prompt id, and failure class.
- Existing `report.json` / `report.md` plus semantic validation results.

Gate:

- All cohort task types complete through the VibeComfy backend.
- Output shape matches current WGP behavior.
- Linked generation rows are present.
- Telemetry fields required by `migration-vibecomfy.md` §3 Observability Shim are present.
- Semantic score is passing or explicitly marked `human_review_required` with a sampled approval.

## Why This Split

VibeComfy cloud mode already solves the expensive and failure-prone part: GPU pod lifecycle, remote installation, model/template execution, long-running matrix polling, artifact download, and forced termination. Reusing it avoids maintaining two divergent RunPod runners.

The worker live harness solves a different problem: it proves the Reigh worker still respects the database, auth, task insertion, task claim, task completion, generation linking, and rollback contracts. Those checks are invisible to a pure VibeComfy matrix.

The migration should connect the two layers through shared fixtures, shared artifact schemas, and shared pass/fail gates, not by merging the harnesses.

## Production Cohorts

The migration scope follows `migration-vibecomfy.md` §0A. Start with only production-used task types.

| Cohort | Task types | Primary validation |
| --- | --- | --- |
| A: image generation | `qwen_image`, `qwen_image_2512`, `z_image_turbo`, `wan_2_2_t2i` | VibeComfy template run + worker queue live test + ArtAgents image rubric |
| B: image edit/reference | `qwen_image_style`, `qwen_image_edit`, `image_inpaint`, `annotated_image_edit`, `z_image_turbo_i2i` | Reference/input preservation rubric, mask/annotation checks, queue live test |
| C: travel generation | `travel_orchestrator`, `travel_segment`, `individual_travel_segment`, `travel_stitch` | Segment motion/endpoint consistency rubric, child-task tracking, stitch output |
| D: join/edit video | `join_clips_orchestrator`, `join_clips_segment`, `join_final_stitch`, `edit_video_orchestrator` | Clip-order, transition coherence, final stitch duration, child-task tracking |

Do not block migration on UNUSED worker task types unless a new production call site appears.

## Fixture Strategy

Use deterministic, versioned fixtures for every task type.

### Fixture Sources

- Existing `reigh-worker/scripts/worker_matrix_cases.json` and `worker_matrix_db_snapshots.json`.
- Existing worker live-test anchor images from `scripts/live_test/config.py`.
- VibeComfy `workflow_corpus/input/` fixtures where they already match the target template.
- New ArtAgents-generated reference images where the current fixture is too ambiguous for semantic grading.

### Fixture Generation

For semantic tests, each fixture should carry:

- `intent`: one-sentence expected output description.
- `must_include`: visible objects/attributes that must appear.
- `must_not_include`: visible objects/attributes that must not appear.
- `reference_roles`: e.g. `style`, `subject`, `start_frame`, `end_frame`, `mask`, `annotation`.
- `output_modality`: `image` or `video`.
- `rubric`: task-specific scoring instructions.

Use ArtAgents `builtin.generate_image` only for missing or weak fixtures. Prefer stable committed fixtures when they already exercise the production path.

## Semantic Validation

### Image Outputs

After output download, call ArtAgents visual understanding:

```bash
cd ArtAgents
python3 -m artagents.packs.builtin.visual_understand.run \
  --image /path/to/output.png \
  --query "$(cat /path/to/rubric.txt)" \
  --mode best \
  --detail high \
  --out /path/to/semantic.json
```

The query should request structured JSON:

```json
{
  "description": "short factual description",
  "matches_intent": true,
  "required_elements_present": [],
  "forbidden_elements_present": [],
  "reference_preservation": 0.0,
  "artifact_severity": "none|minor|major|fatal",
  "score": 0,
  "reasons": []
}
```

### Video Outputs

Sample frames before calling visual understanding:

- first frame
- 25% frame
- midpoint
- 75% frame
- final frame
- additional frames around stitch boundaries for travel/join outputs

Use one contact sheet per video so the model can judge temporal coherence cheaply. The ArtAgents visual understand tool already supports multiple images/contact sheets and timestamp labels.

Required video checks:

- Output duration within allowed tolerance.
- Output resolution and frame count match contract.
- Start and end frames preserve the intended anchors for travel tasks.
- Motion is coherent across sampled frames.
- Stitch boundaries are not blank, frozen, or visibly reordered.

### Scoring Policy

Use a two-tier policy:

- `pass`: score >= 4/5, no fatal artifacts, all required elements present.
- `human_review_required`: score 3/5 or model uncertainty; keep the output for sampled human review.
- `fail`: score <= 2/5, missing required content, forbidden content present, blank output, severe artifacts, or incoherent video.

Promotion requires all Layer 1 and Layer 2 structural gates to pass, plus either semantic `pass` or documented human approval for each `human_review_required` case.

## Evidence Schema

Each live run should write a single JSON record per case:

```json
{
  "case_id": "qwen_image_2512_basic",
  "cohort": "A",
  "task_type": "qwen_image_2512",
  "backend": "vibecomfy",
  "template_id": "image/qwen_image_2512",
  "memory_profile": 3,
  "runpod_pod_id": "pod-id",
  "worker_id": "worker-id-or-null",
  "task_id": "supabase-task-id-or-null",
  "generation_ids": [],
  "vibecomfy_run_id": "run-id-or-null",
  "comfy_prompt_id": "prompt-id-or-null",
  "output_artifacts": [],
  "timings": {
    "queue_seconds": 0,
    "execution_seconds": 0,
    "total_seconds": 0
  },
  "structural": {
    "status": "pass|fail",
    "media_count": 1,
    "bytes": 0,
    "dimensions": "1024x1024",
    "duration_seconds": null,
    "failure_class": null
  },
  "semantic": {
    "status": "pass|human_review_required|fail",
    "score": 5,
    "description": "",
    "reasons": []
  },
  "decision": "pass|fail|blocked"
}
```

Layer 1 can leave `worker_id`, `task_id`, and `generation_ids` null. Layer 2 must populate them.

## Implementation Plan

### Step 1: Make VibeComfy Cloud Mode Reigh-Aware

Add a Reigh migration matrix entrypoint in VibeComfy, using existing cloud mode:

```text
vibecomfy/scripts/runpod_reigh_matrix.py
```

It should:

- Reuse `run_pod_detached()` from `scripts/runpod_runner.py`.
- Materialize one case per production-used task type/cohort.
- Translate Reigh fixture params into VibeComfy template inputs.
- Run the same template locally enough to validate before remote execution.
- Execute on RunPod.
- Download artifacts.
- Emit `reigh_results.json` and `reigh_results.md`.

Do not add new pod lifecycle code unless `runpod_runner.py` is missing a narrow reusable hook.

### Step 2: Add Worker Backend Matrix Mode

Extend `reigh-worker/scripts/live_test/main.py` with:

```text
--backend wgp|vibecomfy|dual
--validation-artifacts /path/to/vibecomfy/out/runpod_artifacts/<run>
--semantic-validation off|fast|best
```

The worker harness should:

- Start the worker with `REIGH_BACKEND=<backend>`.
- Preserve the existing `fresh` and `update` variants.
- Run only task types in the selected cohort.
- Require VibeComfy telemetry in logs when backend is `vibecomfy`.
- Attach semantic validation records to the existing report.

### Step 3: Add Artifact Fetch/Resolve

Layer 2 currently records `output_location` and linked generation ids. Add a helper that resolves each generation location to a local media file for ArtAgents validation.

Resolution order:

1. Supabase storage signed URL/download, if the location is remote.
2. Worker pod artifact fetch for local-only outputs.
3. VibeComfy artifact directory from `--validation-artifacts`, for dual-run comparisons.

### Step 4: Add ArtAgents Semantic Scorer

Add a small scorer module, preferably outside the worker runtime path:

```text
reigh-worker/scripts/live_test/semantic_validation.py
```

It should shell out to ArtAgents, never import ArtAgents into the worker server. The scorer takes local media paths and a rubric JSON, writes raw ArtAgents output, parses the structured JSON answer, and returns `pass`, `human_review_required`, or `fail`.

### Step 5: Dual-Run Comparison

For high-risk cohorts, run `--backend dual`:

- WGP output remains the control.
- VibeComfy output is the candidate.
- ArtAgents describes both outputs with the same rubric.
- The comparison prompt asks whether both satisfy the same intent, not whether they are pixel-identical.

Dual-run pass means both outputs are structurally valid and semantically acceptable, and VibeComfy is not materially worse on required elements, reference preservation, or motion coherence.

Live canary output-divergence checks require an isolated shadow-run path: the WGP reference run must write to isolated storage and must not trigger completion, billing, uploads to user-visible destinations, or duplicate product side effects. If that isolation is not implemented for a cohort, output divergence remains sampled/offline evidence; automatic canary rollback is limited to latency, OOM, and classified error triggers from `migration-vibecomfy.md` §11.

## Per-Cohort Gates

### Cohort A: Image Generation

Required cases:

- `qwen_image`
- `qwen_image_2512`
- `z_image_turbo`
- `wan_2_2_t2i`

Pass criteria:

- Output is a valid image.
- Dimensions match task contract.
- Prompt intent is visible.
- No blank, text-corrupted, or unrelated output.
- Latency and VRAM are recorded.

### Cohort B: Image Edit / Reference

Required cases:

- `qwen_image_style`
- `qwen_image_edit`
- `image_inpaint`
- `annotated_image_edit`
- `z_image_turbo_i2i`

Pass criteria:

- Required input/reference relationship is visible.
- Edited area changes when requested.
- Unmasked areas are preserved for inpaint tasks.
- Style/reference tasks preserve the declared style/subject role.
- No severe identity drift for subject-preservation cases.

### Cohort C: Travel

Required cases:

- `individual_travel_segment`
- `travel_orchestrator` with one segment
- `travel_orchestrator` with an LTX-backed segment if still app-routable
- `travel_stitch`

Pass criteria:

- Child tasks are created and linked correctly.
- Segment output starts near anchor A and ends near anchor B.
- No blank/frozen frames in sampled frames.
- Stitch output has expected duration and ordering.
- Completion path matches existing WGP generation-linking behavior.

### Cohort D: Join / Edit Video

Required cases:

- `join_clips_orchestrator`
- `join_clips_segment`
- `join_final_stitch`
- `edit_video_orchestrator`

Pass criteria:

- Child task tracking matches current production behavior.
- Clip order is preserved.
- Join boundaries are coherent.
- Final output duration is within tolerance.
- Failed child tasks propagate a classified failure, not a silent success.

## Promotion Gates

A task type may enter canary only after:

1. VibeComfy local validation passes.
2. VibeComfy cloud matrix passes on RunPod for the task's template.
3. Worker live queue test passes with `REIGH_BACKEND=vibecomfy`.
4. Output artifacts pass structural checks.
5. Semantic validation passes or has documented human approval.
6. Telemetry includes backend, template id, memory profile, VibeComfy run id, Comfy prompt id, and failure class when applicable.
7. Rollback has been tested by rerunning the same case with `REIGH_BACKEND=wgp`.
8. The Sprint 6.5 selector/orchestrator readiness evidence from `migration-vibecomfy.md` is linked: route selector version, explicit allowlist behavior, WGP/no-claim default for missing production keys, backend-aware worker pool startup, image-version guard, and staged rollback exercise.
9. If output-divergence auto-rollback is enabled for the cohort, the isolated shadow-run evidence proves no duplicate completion, billing, upload, or user-visible side effects.

Canary promotion should be cohort-scoped, not all-or-nothing across every production task.

## Open Questions

- Should `runpod_reigh_matrix.py` live in `vibecomfy/scripts/` or be a `vibecomfy runpod reigh-matrix` subcommand from day one?
- Should semantic validation call ArtAgents directly from VibeComfy Layer 1, or only from the worker Layer 2 report after artifacts are downloaded?
- Which Supabase storage download helper is safest for private generation outputs in live tests?
- What is the minimum human-review sample size per cohort before production canary?
- Should dual-run create separate task rows or one task row with two backend attempts recorded in test-only metadata?

## Recommended Default

Use VibeComfy cloud mode for every template/runtime proof. Use the worker live harness only after VibeComfy has produced a green cloud result for that task family. Then run worker live tests with `REIGH_BACKEND=vibecomfy` to prove queue semantics, telemetry, and production output contracts. Finally, run ArtAgents semantic validation on the combined artifact bundle and require the evidence JSON before canary.

## 2026-05-05 Pilot Result

We ran a live pilot of the proposed Layer 1 path against VibeComfy cloud mode on 2026-05-05.

### What Passed

- VibeComfy cloud mode launched a real RunPod pod: `06td09ne5zfm7f`.
- The pod reached SSH and reported an RTX 4090.
- The run used `scripts.runpod_runner.run_pod_detached()` with `upload_mode="tarball"`, detached polling, and artifact download.
- Remote script installed VibeComfy and HiddenSwitch ComfyUI, ran `vibecomfy runtime doctor`, then ran:

```bash
python3 -m vibecomfy.cli run tests/smoke_fixtures/smoke_empty_image_red.json --runtime embedded --backend graphbuilder
```

This was useful as a first lifecycle probe, but it used a raw JSON fixture. That fixture has since been removed from the cloud smoke path because it is not the migration primitive.

- VibeComfy produced one PNG:

```text
vibecomfy/out/runpod_artifacts/1777991492/output/vibecomfy_smoke_red_00001_.png
```

- Structural validation confirmed the output is `64x64`, RGB, solid red at pixel `(0,0) = (255, 0, 0)`.
- VibeComfy metadata was downloaded:
  - artifact root: `vibecomfy/out/runpod_artifacts/1777991492`
  - run id: `run-1777991482`
  - prompt id: `b49e93cd-0bac-47c6-ad5c-95bf0b356aad`
  - workflow hash: `b7e39026c029321fb5a38a049470b903dc4971441cc2c3f601644c2b597f657f`
  - runtime: `embedded`
- Results table:

```text
id	status	seconds	media_files	bytes	failure
empty_image_red	ok	91	1	493
```

- The launched pod was terminated by the cloud runner.

### What Failed Or Needs Fixing

1. **Default SFTP upload mode is too silent.** Running `scripts/runpod_validate.py` directly launched pod `pn3g89l2a1wqsa` and reached SSH/GPU discovery, then appeared hung during recursive SFTP upload. Root cause: `runpod_runner.upload_dir()` performs synchronous Paramiko SFTP recursion with no per-file or heartbeat logging.
2. **Ctrl-C handling is brittle during upload.** Interrupting the silent run raised `KeyboardInterrupt` from the event-loop signal handler and cancelled the task before the runner reported a clean `finally` termination. The pod was then terminated manually through `vibecomfy runpod terminate pn3g89l2a1wqsa --yes`.
3. **Tarball upload needs a tight exclude set.** The first tarball attempt launched pod `9tkw15j5d9156x`, then failed locally with `OSError: [Errno 28] No space left on device` while archiving the default repo payload. The failed temp archive consumed ~2.8GB. Excluding `.git`, `.venv`, `out`, `output`, `vendor`, `workflow_corpus`, `custom_nodes`, `input`, and cache directories made the tarball path work.
4. **ArtAgents semantic validation reached the right API path but was blocked by quota.** The command wrote `vibecomfy/out/runpod_artifacts/1777991492/semantic_red_square.json`, but OpenAI returned HTTP 429 `insufficient_quota` for `gpt-4o-mini`. This is an account/billing blocker, not a harness-shape failure.
5. **Watchdog classification is noisy for successful tiny runs.** `out/runs/run-1777991482/watchdog.json` reports `diagnosis=crashed` because `/system_stats` stopped responding, while metadata and output show the prompt completed successfully. The validation harness should treat this as a warning when output exists and `stop_reason="completed"`, and should file/fix the watchdog diagnosis separately.

### Pilot Conclusion

The core approach is valid: VibeComfy cloud mode can be used as the Layer 1 RunPod execution proof, and its detached runner can provide live progress plus downloaded artifacts. The corrected smoke path is `scripts/runpod_validate.py` executing `ready_templates/smoke/empty_image_red.py`, and all production cohort validation must execute Python ready templates. The default invocation needs cleanup before it becomes the migration-standard command:

- Prefer `run_pod_detached(..., upload_mode="tarball")` for migration validation.
- Use a small, explicit upload payload or remote git install; do not archive old `out/`, `.venv`, `.git`, `vendor`, or corpus artifacts.
- Add upload progress/heartbeat logs to both SFTP and tarball modes.
- Make signal handling cancel-safe enough that `finally` visibly terminates the pod.
- Keep ArtAgents semantic scoring in the pipeline, but mark it `blocked_external_quota` when the OpenAI API key cannot run vision calls.

## 2026-05-05 Ready-Template Smoke Result

After correcting `scripts/runpod_validate.py`, we reran the live cloud smoke with the Python ready-template primitive.

- RunPod pod: `l91mkxuh582ros`.
- Command path: `python3 -m vibecomfy.cli run smoke/empty_image_red --ready --runtime embedded --backend graphbuilder`.
- Ready template: `vibecomfy/ready_templates/smoke/empty_image_red.py`.
- Result row: `ready_template_empty_image_red ok 10 1 505`.
- Output: `vibecomfy/out/runpod_artifacts/20260505T151632Z/output/vibecomfy_ready_smoke_red_00001_.png`.
- Output dimensions: `64x64`.
- VibeComfy run id: `run-1777994172`.
- Comfy prompt id: `6682151f-2e29-45b6-9c89-fae6437de6d7`.
- Artifact manifest: `vibecomfy/out/runpod_artifacts/20260505T151632Z/manifest.json`.
- Artifact report: `vibecomfy/out/runpod_artifacts/20260505T151632Z/report.md`.
- Independent pod check after termination: `pod l91mkxuh582ros not found`.

This is now the baseline launch/artifact/termination smoke. It still does not prove production model coverage; production gates must use model-backed ready templates such as `image/qwen_image_2512`, `edit/qwen_image_edit`, `image/z_image`, and the selected Wan/LTX templates.
