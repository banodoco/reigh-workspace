# Migration Plan: reigh-worker Execution Backend from Wan2GP to VibeComfy

> **Draft status:** Draft for migration planning, authored 2026-05-05.

This document plans the migration of `reigh-worker` from its current in-process Wan2GP execution backend to VibeComfy while preserving the worker's external queue contracts, output shapes, per-task latency expectations, and non-negotiable memory-profile guarantees. The repos involved live side-by-side under the workspace: `reigh-worker/` is the current Wan2GP consumer, `vibecomfy/` is the target ComfyUI workflow runtime, and `reigh-worker-orchestrator/` provisions GPU worker images and startup commands.

## Table of Contents

1. [Audit reigh-worker to Wan2GP integration](#1-audit-reigh-worker-to-wan2gp-integration)
1A. [Task-type to VibeComfy template triage](#1a-task-type-to-vibecomfy-template-triage)
2. [Audit VibeComfy capabilities](#2-audit-vibecomfy-capabilities)
3. [Parity gaps and required pre-cutover work](#3-parity-gaps-and-required-pre-cutover-work)
3A. [Control rails, LoRA stacking, and pre-processing — concrete recipes](#3a-control-rails-lora-stacking-and-pre-processing--concrete-recipes)
4. [Sprint-by-sprint migration plan](#4-sprint-by-sprint-migration-plan)
5. [Per-task-type cutover order](#5-per-task-type-cutover-order)
6. [Rollback plan](#6-rollback-plan)
7. [Telemetry and observability](#7-telemetry-and-observability)
8. [Final Wan2GP removal](#8-final-wan2gp-removal)
9. [Open questions, assumptions, risks, and mitigations](#9-open-questions-assumptions-risks-and-mitigations)
10. [Closure-sweep procedure](#10-closure-sweep-procedure)
11. [Migration thresholds (single source of truth)](#11-migration-thresholds-single-source-of-truth)
12. [Pre-kickoff confidence checklist (S5)](#12-pre-kickoff-confidence-checklist-s5)

Companion document: [Live Validation Plan: reigh-worker VibeComfy Migration](./migration-vibecomfy-live-validation.md). That document owns the RunPod/cloud validation strategy, worker live-test strategy, ArtAgents semantic grading, and evidence package required before canary.

## Goals

- Preserve the Supabase queue contract observed by `reigh-worker` task claim, dispatch, status update, and completion paths.
- Preserve output shapes for every runtime task type, including image, video, edit, orchestration, raw-Comfy, and interpolation tasks.
- Preserve per-task latency SLOs or document measured exceptions before canary promotion.
- Preserve full memory-profile behavior, including low-VRAM, medium/default, high-VRAM, profiled, and per-task override semantics.
- Coordinate worker image and runtime changes with `reigh-worker-orchestrator` so provisioning, startup, health checks, and rollback all understand the selected backend.
- Retire Wan2GP only after shadow, dual-run comparison, cohort canaries, and closure sweeps demonstrate parity.
- Gate canary promotion on the live validation evidence package defined in `docs/migration-vibecomfy-live-validation.md`.

## Non-Goals

- No Supabase queue schema rework.
- No orchestrator scheduling or scaling algorithm changes beyond worker image/runtime selection and backend flag propagation.
- No `reigh-app` UI or API contract changes.
- No broad task-type redesign beyond the adapter and template-routing work required to preserve existing behavior.
- No deletion of Wan2GP surfaces before the Sprint 8 removal gate.

## Settled Decisions

- **SD-001** — Preserve current queue contracts and output shapes. _load_bearing: true_
  Rationale: `reigh-app`, orchestration handlers, and downstream completion logic depend on the existing worker-facing task contract.
- **SD-002** — Treat memory-profile parity as a pre-cutover gate. _load_bearing: true_
  Rationale: production currently relies on Wan2GP profile behavior for GPU fit, OOM avoidance, and latency/cost predictability.
- **SD-003** — Keep `reigh-worker/`, `reigh-worker-orchestrator/`, and `vibecomfy/` as independent repo workstreams. _load_bearing: true_
  Rationale: the workspace contains nested independent Git repos, so implementation, review, and closure sweeps must be scoped per repo.
- **SD-004** — Refactor the existing `source/models/comfy/` path into the VibeComfy adapter instead of running a second raw-Comfy implementation. _load_bearing: true_
  Rationale: keeping `comfy_handler.py` and `comfy_utils.py` as a parallel subprocess/client stack would leave two Comfy runtimes, two output contracts, and two telemetry paths to support during cutover.
- **SD-005** — Treat dynamic Wan2GP model definitions as build-time frozen VibeComfy template inputs unless Q1 decides otherwise. _load_bearing: true_
  Rationale: runtime-mutable JSON model definitions are a WGP-specific flexibility point; freezing them into reviewed templates and patches lowers cutover risk and makes validation reproducible.
- **SD-006** — Keep WGP and VibeComfy coinstalled in the worker image until the Sprint 8 removal gate. _load_bearing: true_
  Rationale: production rollback depends on switching process-level and task-type-level backend selection without rebuilding the worker image during canary.
- **SD-007** — Use VibeComfy cloud mode as the primary RunPod validation runner for template/runtime proof. _load_bearing: true_
  Rationale: VibeComfy already owns RunPod pod lifecycle, remote execution, matrix polling, artifact download, and termination through `scripts/runpod_runner.py` and the `runpod` command surface; the worker live harness should validate Supabase queue contracts and backend selection rather than duplicating cloud execution machinery.

## Authoritative Paths

### reigh-worker

- `reigh-worker/source/runtime/wgp_bridge.py`
- `reigh-worker/source/models/wgp/orchestrator.py`
- `reigh-worker/source/task_handlers/tasks/task_types.py`
- `reigh-worker/source/task_handlers/tasks/task_registry.py`
- `reigh-worker/source/task_handlers/queue/task_queue.py`
- `reigh-worker/source/runtime/worker/server.py`
- `reigh-worker/source/models/comfy/comfy_handler.py`
- `reigh-worker/source/models/comfy/comfy_utils.py`
- `reigh-worker/source/core/log/display_names.py`
- `reigh-worker/headless_wgp.py`
- `reigh-worker/headless_model_management.py`
- `reigh-worker/source/runtime/entrypoints/headless_wgp.py`
- `reigh-worker/source/runtime/entrypoints/headless_model_management.py`
- `reigh-worker/pyproject.toml:109`
- `reigh-worker/pyproject.toml:165`

### vibecomfy

- `vibecomfy/vibecomfy/runtime/run.py`
- `vibecomfy/vibecomfy/runtime/session.py`
- `vibecomfy/vibecomfy/runtime/server.py`
- `vibecomfy/vibecomfy/runtime/client.py`
- `vibecomfy/ready_templates/`
- `vibecomfy/vibecomfy/registry/ready_template.py`
- `vibecomfy/docs/runtime_surface.md`

### reigh-worker-orchestrator

- `reigh-worker-orchestrator/gpu_orchestrator/runpod/worker_startup.template.sh`
- `reigh-worker-orchestrator/gpu_orchestrator/runpod/startup_script.py`
- `reigh-worker-orchestrator/gpu_orchestrator/Dockerfile`
- `reigh-worker-orchestrator/gpu_orchestrator/requirements.txt`

### Repository Layout For Closure Sweeps

`reigh-worker/`, `reigh-worker-orchestrator/`, and `vibecomfy/` are independent Git repos nested in the workspace. Any Git-aware closure sweep must run per repo, for example with `git -C reigh-worker grep ...` and `git -C reigh-worker-orchestrator grep ...`; a workspace-root `git grep` does not traverse those nested repo histories and can return zero hits for committed files that still exist inside the nested repos.

## External Reference Resources

Whenever a sprint task involves authoring a new VibeComfy template, picking a model variant, choosing a LoRA stacking strategy, deciding on control-rail wiring, or otherwise making a workflow / best-practice judgment call, consult these three sources before guessing. Cite them in the resulting code or doc note so the decision is reproducible.

### 1. AI workflows / best-practices Discord (`message_feed`)

A community Discord aggregating practical advice on AI workflows, ComfyUI graphs, model behavior, LoRA application, and sampler choice. The relevant `message_feed` is queryable directly via Supabase REST — no Discord client needed.

```bash
# Most-recent messages across all channels:
curl "https://ujlwuvkrxlvoswwkerdf.supabase.co/rest/v1/message_feed?select=content,author_name,channel_name,reactions,created_at&order=created_at.desc&limit=50" \
  -H "apikey: sb_publishable_O38oPBafrBoFrpi_rlWJvA_UJrulFsx"

# Filter by channel (e.g. find Wan-related guidance):
curl "https://ujlwuvkrxlvoswwkerdf.supabase.co/rest/v1/message_feed?select=content,author_name,channel_name,created_at&channel_name=ilike.*wan*&order=created_at.desc&limit=50" \
  -H "apikey: sb_publishable_O38oPBafrBoFrpi_rlWJvA_UJrulFsx"

# Free-text search in message bodies:
curl "https://ujlwuvkrxlvoswwkerdf.supabase.co/rest/v1/message_feed?select=content,author_name,channel_name,created_at&content=ilike.*lightx2v*&order=created_at.desc&limit=50" \
  -H "apikey: sb_publishable_O38oPBafrBoFrpi_rlWJvA_UJrulFsx"
```

Use it for: VibeWorkflow IR sketches (people share working node graphs), sampler/sigma settings that match real production, troubleshooting Comfy custom-node breakage, hearing about model regressions before they bite us.

### 2. Wan2GP upstream — `https://github.com/deepbeepmeep/Wan2GP/`

The Wan2GP repo (`deepbeepmeep/Wan2GP`) carries a large body of already-tuned best practices for the exact model families we use: Wan 2.1 / 2.2 cocktails, VACE control, Lightning LoRA stacking, profile-tier memory tradeoffs, prompt-expander defaults, LTX configs, Qwen LoRA key tolerance. Before authoring a new VibeComfy template or deciding how to apply a LoRA stack, look at what Wan2GP already does — `defaults/*.json` for model configs, `wan/`, `ltx_video/`, `qwen/` subtrees for inference recipes, and `mmgp/` for the memory-profile mechanics we are mirroring as `MemoryProfile` in VibeComfy.

Use it for: model-default JSON shapes, LoRA multiplier conventions, prompt-expander behavior, sampler step counts and schedulers per model, VAE/text-encoder pairings, Uni3C ControlNet usage, Lightning baseline cocktails. Cite the upstream `path:line` (or commit SHA) in the resulting template/patch so future readers can re-derive the choice.

### 3. Existing reigh-worker code — current defaults and samples

Our own `reigh-worker/` already encodes a lot of production-validated behavior that should not be re-discovered. Before choosing a new default, search:

- `reigh-worker/Wan2GP/defaults/*.json` — every model config currently in use, with the exact LoRA stacks, sampler steps, and VAE pairings we already ship.
- `reigh-worker/source/models/wgp/lora_setup.py` and `wgp_patches.py:384-483` — how we apply LoRAs today (multiplier syntax, key-tolerance patches, Qwen-specific paths).
- `reigh-worker/source/task_handlers/tasks/task_types.py:TASK_TYPE_TO_MODEL` — the mapping from task types to default model variants the app relies on.
- `reigh-worker/source/runtime/wgp_ports/runtime_registry.py:201-220` — runtime model patch transactions (snapshot/apply/restore) that any VibeComfy equivalent must preserve.
- `reigh-worker/scripts/live_test/` and `scripts/run_worker_matrix.py` — actual production-shape test inputs we already exercise; reuse for baselines.

Use it for: never invent a default we already ship. If WGP emits Wan with `--lora-multiplier 0.8` and 6-step Lightning, the VibeComfy equivalent should match unless we have a measured reason to diverge.

### Default discipline

For any sprint task with the words *"author a template"*, *"pick a model"*, *"decide LoRA"*, *"choose sampler"*, *"set steps"*, or *"recreate behavior"*: read all three sources first; cite the basis in the implementation; flag a Q-row in §9 if the three sources disagree.

## 0A. Production-usage audit (reigh-app call sites)

This section classifies every runtime task type from §1 by whether the live `reigh-app` frontend (Next.js + Supabase Edge Functions) emits it today. The migration scope can ignore UNUSED rows entirely; their handlers stay in the worker for now but are not gated on VibeComfy parity.

Authoritative emit surface is `reigh-app/supabase/functions/create-task/resolvers/*.ts` plus the family map at `reigh-app/supabase/functions/create-task/resolvers/registry.ts:16-30`. Family is the public input; the resolver decides which `task_type` is written to the `tasks` table.

| task_type | usage | call site (path:line) | model variants pinned by app | notes |
| --- | --- | --- | --- | --- |
| `qwen_image` | USED-IN-APP | `reigh-app/supabase/functions/create-task/resolvers/imageGeneration.ts:97` (when `model_name == "qwen-image"` and no style ref) | `model: "qwen-image"` (`imageGeneration.ts:215`); falls back to `"optimised-t2i"` literal | Emitted by image-gen panel; LoRAs and reference params optional. |
| `qwen_image_style` | USED-IN-APP | `imageGeneration.ts:97` (when `model_name == "qwen-image"` and `style_reference_image` set) | `model: "qwen-image"` | Reference-mode variant; populates style/subject/scene params. |
| `qwen_image_2512` | USED-IN-APP | `imageGeneration.ts:99` | `model: "qwen-image-2512"` | Direct T2I path. |
| `z_image_turbo` | USED-IN-APP | `imageGeneration.ts:101` | `model: "z-image"` | Default Z-Image T2I. |
| `wan_2_2_t2i` | USED-IN-APP | `imageGeneration.ts:103` (default branch) | `model: "optimised-t2i"` (literal label, not a worker model id) | Single-frame Wan T2I — the production default for the image-generation tool. |
| `z_image_turbo_i2i` | USED-IN-APP | `reigh-app/supabase/functions/create-task/resolvers/zImageTurboI2I.ts:140` | None pinned (no `model` field in payload) | Lightbox img2img path (`useImg2ImgMode.ts:174`). |
| `qwen_image_edit` | USED-IN-APP | `reigh-app/supabase/functions/create-task/resolvers/magicEdit.ts:139` | `qwen_edit_model: "qwen-edit"` (default), `"qwen-edit-2509"`, `"qwen-edit-2511"` | Frontend `magic_edit` family resolves to the `qwen_image_edit` worker task type — the worker `magic_edit` task type itself is never emitted by the app. Caller: `useMagicEditMode.ts:230`. |
| `image_inpaint` | USED-IN-APP | `reigh-app/supabase/functions/create-task/resolvers/maskedEdit.ts:82` (default), `useRepositionTaskCreation.ts:80`, `inpainting/useTaskGeneration.ts:118` | `qwen_edit_model` optional (same enum as above) | Mask-required edit path. |
| `annotated_image_edit` | USED-IN-APP | `maskedEdit.ts:82` (when `input.task_type == "annotated_image_edit"`); `createInpaintingTaskWorkflow.ts:57`; `inpainting/useTaskGeneration.ts:118` | `qwen_edit_model` optional | Lightbox annotation path. |
| `travel_orchestrator` | USED-IN-APP | `reigh-app/supabase/functions/create-task/resolvers/travelBetweenImages.ts:315` (non-turbo branch) | Default `model_name: "wan_2_2_i2v_lightning_baseline_2_2_2"` (`travelBetweenImages.ts:70`); `model_type: "i2v" \| "vace"` selectable; LTX models also routable (`modelCapabilities.ts:111,138`: `ltx2_22B`, `ltx2_22B_distilled_1_1`) | Travel-between-images tool. |
| `individual_travel_segment` | USED-IN-APP | `reigh-app/supabase/functions/create-task/resolvers/individualTravelSegment.ts:75` | `model_name: "wan_2_2_i2v_lightning_baseline_2_2_2"` default (`individualTravelSegment.ts:242,299`); also accepts caller-supplied `model_name` (Wan 2.2 / 3.3 / LTX variants per `modelPhase.ts`) | Lightbox segment regeneration; same path also created by worker as orchestrator child, but the app-driven re-gen path is the dominant call site. |
| `travel_stitch` | USED-IN-APP | `reigh-app/supabase/functions/create-task/resolvers/crossfadeJoin.ts:83` (worker-created stitch passthrough), `crossfadeJoin.ts:103` (frontend-created join) | None | Frontend-created join clips and worker-created stitch share this task type. |
| `join_clips_orchestrator` | USED-IN-APP | `reigh-app/supabase/functions/create-task/resolvers/joinClips.ts:426` | `model: "wan_2_2_vace_lightning_baseline_2_2_2"` (`joinClips.ts:119`, configurable via `input.model`) | Multi-clip and video-edit joins. |
| `edit_video_orchestrator` | USED-IN-APP | `reigh-app/supabase/functions/create-task/resolvers/editVideoOrchestrator.ts:32` | None | Edit-video tool replace mode. |
| `travel_segment` | USED-INDIRECTLY | Worker creates this as child of `travel_orchestrator` (see `reigh-worker/source/task_handlers/travel/orchestrator.py`); also referenced by `complete_task` segment-tracking config at `reigh-app/supabase/functions/complete_task/constants.ts:6,28-30`. | Inherited from parent orchestrator. | App never inserts this row directly; only `individual_travel_segment` is app-emitted. |
| `join_clips_segment` | USED-INDIRECTLY | Worker creates as child of `join_clips_orchestrator`; tracked at `complete_task/constants.ts:7,36-39`. | Inherited (`wan_2_2_vace_lightning_baseline_2_2_2`). | — |
| `join_final_stitch` | USED-INDIRECTLY | Worker creates as final child of `join_clips_orchestrator`; tracked at `complete_task/constants.ts:9,40-44`. | None | Stitch-only; ffmpeg path. |
| `hunyuan` | UNUSED | `rg -i '\bhunyuan\b\|\bhyvid\b' reigh-app/ → 0 hits` | None | Worker handler exists; app never emits. |
| `flux` | UNUSED | No `task_type: "flux"` literal anywhere in `reigh-app/`. The `family: "klein_edit"` path emits `flux_klein_edit` (a distinct worker task type, outside this migration's catalog). | None | WGP `flux` task type is dead in production. |
| `t2v` | UNUSED | No `task_type: "t2v"` literal in `reigh-app/`. | None | — |
| `t2v_22` | UNUSED | No `task_type: "t2v_22"` literal in `reigh-app/`. | None | — |
| `i2v` | UNUSED | No `task_type: "i2v"` literal in `reigh-app/`. | None | App pins the model `wan_2_2_i2v_lightning_baseline_2_2_2` but routes it through `travel_orchestrator`, not direct `i2v`. |
| `i2v_22` | UNUSED | No `task_type: "i2v_22"` literal in `reigh-app/`. | None | — |
| `vace` | UNUSED | No `task_type: "vace"` literal in `reigh-app/`. | None | The string `'vace'` appears only as a `model_type`/`generationTypeMode` enum value inside travel-segment params, not as a `task_type`. |
| `vace_21` | UNUSED | No `task_type: "vace_21"` literal in `reigh-app/`. | None | — |
| `vace_22` | UNUSED | No `task_type: "vace_22"` literal in `reigh-app/`. | None | — |
| `ltxv` | UNUSED | No `task_type: "ltxv"` literal in `reigh-app/`. | None | — |
| `ltx2` | UNUSED | No `task_type: "ltx2"` literal in `reigh-app/`. | None | LTX models are reachable through `travel_orchestrator` with `model_name` set to an `ltx2_*` variant; `ltx2`-as-task-type is not used. |
| `generate_video` | UNUSED | No `task_type: "generate_video"` literal in `reigh-app/`. | None | — |
| `qwen_image_hires` | UNUSED | No `task_type: "qwen_image_hires"` literal in `reigh-app/`. | None | Hires-fix is layered as `hires_*` params on `qwen_image_edit` payloads (`magicEdit.ts`, `maskedEdit.ts`), not as a separate task type. |
| `magic_edit` | UNUSED (as worker task type) | App `family: "magic_edit"` (`useMagicEditMode.ts:230`) resolves to `task_type: "qwen_image_edit"` via `magicEdit.ts:139`. The worker's `magic_edit` task type (Replicate Flux Kontext path at `reigh-worker/source/task_handlers/magic_edit.py`) is never reached. | N/A | Worker handler is dead code from the app's perspective. |
| `inpaint_frames` | UNUSED | No `task_type: "inpaint_frames"` literal in `reigh-app/`. | None | — |
| `comfy` | UNUSED | No `task_type: "comfy"` literal in `reigh-app/`. | None | Raw-Comfy task path is worker-only; no app surface enqueues it. |
| `create_visualization` | UNUSED | No `task_type: "create_visualization"` literal in `reigh-app/`. | None | — |
| `extract_frame` | UNUSED | No `task_type: "extract_frame"` literal in `reigh-app/`. | None | App extracts frames client-side or via the dedicated edge function `generate-thumbnail`, not by enqueueing this worker task. |
| `rife_interpolate_images` | UNUSED | No `task_type: "rife_interpolate_images"` literal in `reigh-app/`. | None | Frame interpolation is delivered via the `video_enhance` family (FILM-net), which is a different worker task type outside this migration's WGP catalog. |

UNUSED roll-up (cite per row above; aggregate cite: searching `reigh-app/` for `task_type: "<name>"` literal strings returned zero hits for each):

- `hunyuan` (confirmed: `rg -i '\bhunyuan\b|\bhyvid\b' reigh-app/ → 0 hits`)
- `flux`, `t2v`, `t2v_22`, `i2v`, `i2v_22`, `vace`, `vace_21`, `vace_22`, `ltxv`, `ltx2`, `generate_video`, `qwen_image_hires`, `magic_edit`, `inpaint_frames`, `comfy`, `create_visualization`, `extract_frame`, `rife_interpolate_images`

AMBIGUOUS roll-up: none. Every classification above is a deterministic literal-string match; no feature flags, A/B tests, or admin debug surfaces emit any of the UNUSED task types.

App-side discrepancy: `travelBetweenImages.ts:315` emits `task_type: "wan_2_2_i2v"` when `input.turbo_mode === true`. This task type is **not** in the worker's `TASK_TYPE_TO_MODEL` (`reigh-worker/source/task_handlers/tasks/task_types.py:82-117`) or `task_registry` dispatch map. **Resolved via §8A.A:** turbo-mode travel is removed entirely (the UI toggle was already commented out as DISABLED; no production code path sets `turboMode: true`). Sprint 8B owns the cleanup PR.

## 1. Audit reigh-worker to Wan2GP integration

### Runtime Entry Path

`reigh-worker` enters Wan2GP through the worker server process, not through a separate backend service. `source/runtime/worker/server.py:232-243` defines the current WGP CLI surface:

- `--wgp-attention-mode`
- `--wgp-compile`
- `--wgp-profile`
- `--wgp-vae-config`
- `--wgp-boost`
- `--wgp-transformer-quantization`
- `--wgp-transformer-dtype-policy`
- `--wgp-text-encoder-quantization`
- `--wgp-vae-precision`
- `--wgp-mixed-precision`
- `--wgp-preload-policy`
- `--wgp-preload`

Startup then changes into the Wan2GP checkout, inserts it onto `sys.path`, imports `wgp` at `source/runtime/worker/server.py:551`, mutates WGP globals from the CLI flags at `server.py:554-568`, and creates `HeadlessTaskQueue` at `server.py:583-592`. That queue delegates model switching and generation to `WanOrchestrator` through `source/task_handlers/queue/task_queue.py:367-373` and `source/models/wgp/orchestrator.py`.

There are also standalone legacy entrypoints. `reigh-worker/pyproject.toml:109` registers `headless_wgp = source.runtime.entrypoints.headless_wgp:WanOrchestrator`, and `pyproject.toml:165` repeats that registration under `[tool.headless_wan2gp.entrypoints]`. Root scripts `reigh-worker/headless_wgp.py` and `reigh-worker/headless_model_management.py` are wrapped by `source/runtime/entrypoints/headless_wgp.py` and `source/runtime/entrypoints/headless_model_management.py`.

### Memory-Profile System

Wan2GP profile behavior is externally visible and must be preserved. `source/runtime/worker/server.py:605-609` maps profile values to display labels:

| Profile | Display label | Current role |
| --- | --- | --- |
| `1` | Max Performance | Production default and highest-throughput baseline. |
| `2` | High RAM | High-memory mode between max-performance and balanced. |
| `3` | Balanced | Development default and local/live-test baseline. |
| `4` | Conservative | Lower VRAM pressure. |
| `5` | Minimum | Most constrained VRAM mode. |

When `--wgp-profile` is present, `source/runtime/worker/server.py:556-558` sets both `wgp_mod.force_profile_no` and `wgp_mod.default_profile`. Per-task WGP payloads also carry `override_profile`: passthrough mode defaults it to `-1` at `source/models/wgp/generators/wgp_params.py:166`, normal mode reads it from resolved params at `wgp_params.py:237`, and the final WGP parameter dict writes it at `wgp_params.py:374`.

Default profile is environment-specific and Sprint 0 must baseline both:

| Environment | Default | Source |
| --- | --- | --- |
| Production RunPod worker startup | `--wgp-profile 1` | `reigh-worker-orchestrator/gpu_orchestrator/runpod/worker_startup.template.sh:463` |
| Windows/dev helper | `--wgp-profile 3` | `reigh-worker/start_worker.bat:14` |
| Live-test main harness | `--wgp-profile` default `3` | `reigh-worker/scripts/live_test/main.py:27` |
| Live-test smoke harness | `--wgp-profile` default `3` | `reigh-worker/scripts/live_test/smoke.py:27` |

### Task Surface

The migration surface is the union of `TASK_TYPE_CATALOG` in `source/task_handlers/tasks/task_types.py:120-138` and the specialized dispatch keys in `source/task_handlers/tasks/task_registry.py:1442-1511`. Friendly names come from `source/core/log/display_names.py:8-45`; `rife_interpolate` is a friendly alias only, while the runtime dispatch key is `rife_interpolate_images`.

| task_type | Source of truth | default_model | dispatch_path | Current handler module | Output shape | Alias | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `annotated_image_edit` | `task_types.py:106-110,120-138` | `qwen_image_edit_20B` | Direct queue via `_handle_direct_queue_task` | `task_conversion.py` + `QwenHandler.handle_annotated_image_edit` | Single image path | Annotated Image Edit | Empty prompt allowed; Qwen edit family. |
| `comfy` | `task_registry.py:1507-1510` | N/A | Specialized handler | `source/models/comfy/comfy_handler.py` | First downloaded Comfy output path | ComfyUI | Existing raw-workflow Comfy path; retire/refactor decision is in Section 3. |
| `create_visualization` | `task_registry.py:1497-1500` | N/A | Specialized handler | `source/task_handlers/create_visualization.py` | Visualization image/video path | Create Visualization | Utility/debug task, not a WGP model family. |
| `edit_video_orchestrator` | `task_registry.py:1478-1482` | N/A | Specialized orchestrator | `source/task_handlers/edit_video_orchestrator.py` | Orchestrating status or final video path | Edit Video | Creates join/regeneration child work. |
| `extract_frame` | `task_registry.py:1501-1503` | N/A | Specialized handler | `source/task_handlers/extract_frame.py` | Extracted frame image path | Extract Frame | Single-purpose media helper. |
| `flux` | `task_types.py:93-94,120-138` | `flux` | Direct queue | `task_conversion.py` -> `HeadlessTaskQueue` | Single image path | Flux | WGP output task. |
| `generate_video` | `task_types.py:83-84,120-138` | `t2v` | Direct queue | `task_conversion.py` -> `HeadlessTaskQueue` | Video path | Generate Video | Generic fallback video generation. |
| `hunyuan` | `task_types.py:99-101,120-138` | `hunyuan` | Direct queue | `task_conversion.py` -> `HeadlessTaskQueue` | Video path | Hunyuan | VibeComfy has no `ready_templates/video/hunyuan_*` today. |
| `i2v` | `task_types.py:95-97,120-138` | `i2v_14B` | Direct queue | `task_conversion.py` -> `HeadlessTaskQueue` | Video path | Image to Video | Input image/video prompt fields converted to WGP params. |
| `i2v_22` | `task_types.py:95-97,120-138` | `i2v_2_2` | Direct queue | `task_conversion.py` -> `HeadlessTaskQueue` | Video path | Image to Video 2.2 | Wan 2.2 i2v family. |
| `image_inpaint` | `task_types.py:106-110,120-138` | `qwen_image_edit_20B` | Direct queue | `task_conversion.py` + `QwenHandler.handle_image_inpaint` | Single image path | Image Inpaint | Empty prompt allowed; Qwen edit family. |
| `individual_travel_segment` | `task_registry.py:1456-1464` | N/A | Specialized handler using queue seam | `source/task_handlers/travel/segments/segment_queue.py` -> `task_registry._handle_travel_segment_via_queue_impl` | Segment video path | Travel Segment | Standalone segment; receives `context["task_queue"]`. |
| `inpaint_frames` | `task_types.py:102-104,120-138`; `task_registry.py:1492-1496` | `wan_2_2_vace_lightning_baseline_2_2_2` | Specialized handler using queue seam | `source/task_handlers/inpaint_frames.py` | Inpainted video path | Inpaint Frames | Enqueues VACE-style child generation. |
| `join_clips_orchestrator` | `task_registry.py:1473-1477` | N/A | Specialized orchestrator | `source/task_handlers/join/orchestrator.py` | Orchestrating status or final joined video | Join Clips | Creates `join_clips_segment` and sometimes `join_final_stitch`. |
| `join_clips_segment` | `task_types.py:102-104,120-138`; `task_registry.py:1483-1487` | `wan_2_2_vace_lightning_baseline_2_2_2` | Specialized handler using queue seam | `source/task_handlers/join/generation.py` | Transition/joined video path | Join Clips Segment | Requires `task_queue` for VACE generation. |
| `join_final_stitch` | `task_registry.py:1488-1491` | N/A | Specialized handler | `source/task_handlers/join/final_stitch.py` | Final stitched video path | Join Clips Final Stitch | Stitch-only finalization. |
| `ltx2` | `task_types.py:99-101,120-138` | `ltx2_19B` | Direct queue | `task_conversion.py` -> `HeadlessTaskQueue` | Video path | LTX Video 2 | LTX2 WGP model family. |
| `ltxv` | `task_types.py:99-101,120-138` | `ltxv_13B` | Direct queue | `task_conversion.py` -> `HeadlessTaskQueue` | Video path | LTX Video | Legacy LTX WGP family. |
| `magic_edit` | `task_registry.py:1469-1472` | N/A | Specialized handler | `source/task_handlers/magic_edit.py` | Edited image path | Magic Edit | Replicate/Flux Kontext path, not a direct WGP task. |
| `qwen_image` | `task_types.py:111-114,120-138` | `qwen_image_edit_20B` | Direct queue | `task_conversion.py` + `QwenHandler.handle_qwen_image` | Single image path | Qwen Image | Text-to-image Qwen path. |
| `qwen_image_2512` | `task_types.py:111-114,120-138` | `qwen_image_2512_20B` | Direct queue | `task_conversion.py` + `QwenHandler.handle_qwen_image_2512` | Single image path | Qwen Image 2512 | Direct image template candidate. |
| `qwen_image_edit` | `task_types.py:106-110,120-138` | `qwen_image_edit_20B` | Direct queue | `task_conversion.py` + `QwenHandler.handle_qwen_image_edit` | Single image path | Qwen Image Edit | Empty prompt allowed. |
| `qwen_image_hires` | `task_types.py:106-110,120-138` | `qwen_image_edit_20B` | Direct queue | `task_conversion.py` + `QwenHandler.handle_qwen_image_hires` | Single image path | Qwen Image Hi-Res | Present in catalog via `TASK_TYPE_TO_MODEL`; WGP output inclusion is special-cased at `task_types.py:124`. |
| `qwen_image_style` | `task_types.py:106-110,120-138` | `qwen_image_edit_20B` | Direct queue | `task_conversion.py` + `QwenHandler.handle_qwen_image_style` | Single image path | Qwen Image Style | May rewrite prompt/model during conversion. |
| `rife_interpolate_images` | `task_registry.py:1504-1506` | N/A | Specialized handler | `source/task_handlers/rife_interpolate.py` | Interpolated video path | RIFE Interpolate | Runtime name is `rife_interpolate_images`; `rife_interpolate` is alias-only in display labels. |
| `t2v` | `task_types.py:89-92,120-138` | `t2v` | Direct queue | `task_conversion.py` -> `HeadlessTaskQueue` | Video path | Text to Video | Core Wan text-to-video baseline. |
| `t2v_22` | `task_types.py:89-92,120-138` | `t2v_2_2` | Direct queue | `task_conversion.py` -> `HeadlessTaskQueue` | Video path | Text to Video 2.2 | Wan 2.2 text-to-video. |
| `travel_orchestrator` | `task_registry.py:1442-1446` | N/A | Specialized orchestrator | `source/task_handlers/travel/orchestrator.py` | Orchestrating status or final travel output | Travel | Creates `travel_segment`, optional stitch/join children. |
| `travel_segment` | `task_registry.py:1447-1455` | N/A | Specialized handler using queue seam | `source/task_handlers/travel/segments/segment_queue.py` -> `task_registry._handle_travel_segment_via_queue_impl` | Segment video path | Travel Segment | Uses DB task id as queue task id and enqueues WGP child generation at `task_registry.py:1331-1344`. |
| `travel_stitch` | `task_registry.py:1465-1468` | N/A | Specialized handler | `source/task_handlers/travel/stitch.py` | Stitched travel video path | Travel Stitch | Final stitch across segment outputs. |
| `vace` | `task_types.py:85-88,120-138` | `vace_14B_cocktail_2_2` | Direct queue | `task_conversion.py` -> `HeadlessTaskQueue` | Video path | VACE | VACE family; often used for guided/edit video work. |
| `vace_21` | `task_types.py:85-88,120-138` | `vace_14B` | Direct queue | `task_conversion.py` -> `HeadlessTaskQueue` | Video path | VACE 2.1 | Wan 2.1 VACE. |
| `vace_22` | `task_types.py:85-88,120-138` | `vace_14B_cocktail_2_2` | Direct queue | `task_conversion.py` -> `HeadlessTaskQueue` | Video path | VACE 2.2 | Wan 2.2 VACE. |
| `wan_2_2_t2i` | `task_types.py:89-92,120-138`; `task_registry.py:1554-1555` | `t2v_2_2` | Direct queue | `task_conversion.py` -> `HeadlessTaskQueue` | Single image path | Text to Image 2.2 | Forces `video_length = 1`. |
| `z_image_turbo` | `task_types.py:111-116,120-138` | `z_image` | Direct queue | `task_conversion.py` | Single image path | Z Image Turbo | Sets single-frame/image defaults in conversion. |
| `z_image_turbo_i2i` | `task_types.py:111-116,120-138` | `z_image_img2img` | Direct queue | `task_conversion.py` | Single image path | Z Image Turbo I2I | Downloads input image to a local temp file for WGP. |

### Queue and Dispatch Shape

There are two adapter seams to preserve:

```text
Supabase task row
  -> source/runtime/worker/server.py process_single_task
  -> TaskRegistry.dispatch(task_type, context)
     -> Seam A: direct queue task
        _handle_direct_queue_task
          -> db_task_to_generation_task(...)
          -> HeadlessTaskQueue.submit_task(...)
          -> queue status polling
     -> Seam B: specialized handler with context["task_queue"]
        travel_segment / join_clips_segment / inpaint_frames / rife_interpolate_images
          -> handler-specific media prep
          -> child GenerationTask
          -> HeadlessTaskQueue.submit_task(...)
          -> handler-specific post-processing
```

The direct seam is explicit at `source/task_handlers/tasks/task_registry.py:1436-1438` and `1544-1562`. The nested-handler seam is visible in the dispatch context parameters at `task_registry.py:1453`, `1462`, `1487`, `1496`, and `1505`, and in `travel_segment` queue submission at `task_registry.py:1331-1344`. Any VibeComfy adapter that only replaces `_handle_direct_queue_task` will miss child generation inside orchestrated handlers.

Queue wait semantics are also shared in `source/task_handlers/queue/status_wait.py:17-38`, which polls `task_queue.get_task_status` until `completed`, `failed`, `missing`, or `timeout`. `source/runtime/worker/server.py:689-738` preserves the worker-facing result contract: handlers return `(success, output_location)` or `TaskResult`, non-orchestrator success becomes `Complete` with an output path, and orchestrators may remain `In Progress` while children run.

### Model Load, Unload, and Runtime Mutation Lifecycle

Wan2GP model state is mutable process-global state. `source/models/wgp/model_ops.py:65-193` implements `load_model_impl`: it resolves missing model definitions, checks WGP's current `transformer_type`/`reload_needed`, releases the current offload object, clears `wan_model`/`offloadobj`, runs Python and CUDA cleanup, calls `wgp.load_models(model_key)`, and writes the new loaded state back through `source/runtime/wgp_ports/runtime_registry.py:151-160`.

`source/models/wgp/model_ops.py:196-231` implements `unload_model_impl` through WGP's `unload_model_if_needed`, then clears queue/orchestrator tracking and Uni3C cache. `load_missing_model_definition` at `model_ops.py:29-63` dynamically reads JSON model definitions from `Wan2GP/defaults/*.json`; the same repo also carries `Wan2GP/profiles/*`, so migration has to decide whether VibeComfy freezes model routing at build time or keeps a dynamic-model-definition path.

Runtime mutation is isolated through `source/runtime/wgp_ports/runtime_registry.py`, including read-only vs mutable WGP module access, `set_wgp_model_def`, `set_wgp_reload_needed`, loaded model state setters, and runtime model patch transactions at `runtime_registry.py:201-220`. Queue-level model patch helpers also exist in `source/task_handlers/queue/model_patch_session.py:6-19` for snapshot/apply/restore flows. LoRA behavior spans `source/models/wgp/lora_setup.py` and patches in `source/models/wgp/wgp_patches.py`, especially the LoRA-key tolerance patch at `wgp_patches.py:384-483`, Qwen LoRA directory/parser/inpainting patches, and LoRA caching.

### Vendor Surface Re-exported Through WGP Bridge

`source/runtime/wgp_bridge.py` re-exports both WGP runtime operations and vendor utilities from `source/runtime/wgp_ports/vendor_imports.py`. These are migration gaps unless VibeComfy, reigh-worker, or a new extra package owns an equivalent.

| Current surface | Current location | Current consumers / purpose | VibeComfy equivalent / gap |
| --- | --- | --- | --- |
| Qwen prompt expander | `vendor_imports.py:32-45`; `wgp_bridge.py:24,37-38` | Wan/Qwen prompt expansion via Wan2GP modules. | Gap: no VibeComfy wrapper today; likely pre-process before workflow build. |
| RIFE temporal interpolation | `vendor_imports.py:47-55`; `wgp_bridge.py:34,41-42` | `rife_interpolate_images` and guide-video interpolation. | Gap: no VibeComfy helper; keep vendored in `reigh-worker/source/media/` or add VibeComfy extra. |
| Wan2GP `save_video` | `vendor_imports.py:58-73`; `wgp_bridge.py:45-46` | `source/media/structure/{generation.py,compositing.py}` video writing. | Gap: Comfy outputs files, but no callable parity for existing helper. |
| Qwen family handler | `vendor_imports.py:76-78`; `wgp_bridge.py:30` | WGP monkeypatch routes Qwen-family model loading. | Gap: replace with explicit Qwen templates/routes. |
| Shared LoRA utils | `vendor_imports.py:81-83`; `wgp_bridge.py:32` | LoRA multiplier parsing and setup patches. | Gap: VibeComfy needs portable LoRA-node patching and sanitizer. |
| Qwen main module | `vendor_imports.py:86-88`; `wgp_bridge.py:31` | Qwen inpainting LoRA patching. | Gap: model-specific Comfy template policy needed. |
| Flow annotator | `vendor_imports.py:91-93`; `wgp_bridge.py:27` | Structure preprocessing. | Gap: pre-process before VibeWorkflow or package as extra nodes. |
| Flow visualization | `vendor_imports.py:96-98`; `wgp_bridge.py:28` | Optical-flow visualization in structure preprocessing. | Gap: no VibeComfy re-export. |
| Canny annotator | `vendor_imports.py:101-103`; `wgp_bridge.py:25` | Control/structure guide creation. | Gap: pre-process before workflow build or add VibeComfy extra. |
| DepthV2 annotator | `vendor_imports.py:106-108`; `wgp_bridge.py:26` | Depth guide creation/download flow. | Gap: pre-process before workflow build or add VibeComfy extra. |
| Pose annotator | `vendor_imports.py:111-113`; `wgp_bridge.py:29` | Pose/DWPose guide creation. | Gap: pre-process before workflow build or add VibeComfy extra. |
| Uni3C cache/controlnet loader | `vendor_imports.py:116-132`; `model_ops.py:234-260` | Cached Uni3C ControlNet loading for guided Wan generation. | Gap: no VibeComfy cache abstraction; likely Comfy ControlNet patch plus cache policy. |

### Existing ComfyUI Integration in reigh-worker

`source/models/comfy/comfy_handler.py` already handles the `comfy` task type, but it is a separate raw-Comfy path rather than a VibeComfy adapter. It imports `ComfyUIManager`, `ComfyUIClient`, `COMFY_PATH`, and `COMFY_PORT` from `source/models/comfy/comfy_utils.py:15`; lazy-starts a `python main.py --listen 0.0.0.0 --port ...` subprocess through `ComfyUIManager` at `comfy_utils.py:25-60`; submits raw workflow JSON to `/prompt` through `ComfyUIClient` at `comfy_utils.py:126-142`; polls `/history/{prompt_id}` and downloads outputs at `comfy_utils.py:144-199`; then writes the first output under `main_output_dir_base / "comfy"` at `comfy_handler.py:164-175`.

The dispatch branch is `source/task_handlers/tasks/task_registry.py:1507-1510`. Dependent tests include `reigh-worker/tests/test_additional_coverage_modules.py:205-219` and coverage imports in `tests/test_wan2gp_direct_coverage_contracts.py:412-413,960-961`. Section 3 must make this explicit: refactor `comfy_handler.py` to delegate to VibeComfy runtime, retire `comfy_utils.py`, and migrate test imports.

### Error Paths and Telemetry

WGP errors are not always raised as Python exceptions, so `source/models/wgp/error_extraction.py:13-90` scans captured stdout/stderr for OOM, CUDA, model-loading, and generic Python error patterns. Worker failure handling then classifies retryable errors in `source/runtime/worker/server.py:740-757` and requeues or fails tasks.

Logging suppresses known noisy substrings and third-party loggers, including `mmgp`, in `source/core/log/core.py:57-64` and `core.py:108-113`. The queue performs post-task memory cleanup without unloading models via `source/task_handlers/queue/memory_cleanup.py:16-75`, exposed through `HeadlessTaskQueue._cleanup_memory_after_task` at `task_queue.py:343-345`; that cleanup also clears unused Uni3C cache before CUDA/Python garbage collection at `memory_cleanup.py:41-51`. WGP output telemetry includes `source/models/wgp/generators/output.py:182-208`, which logs RAM and CUDA allocated/reserved/total VRAM. The migration needs Comfy/VibeComfy equivalents for these memory stats, task log anchoring, retry classification, and debug-card breadcrumbs.

### Worker-Orchestrator Coupling

`reigh-worker-orchestrator` has hardcoded Wan2GP startup assumptions:

| Coupling | Source | Migration implication |
| --- | --- | --- |
| Legacy worker directory fallback `Headless-Wan2GP` | `gpu_orchestrator/runpod/worker_startup.template.sh:174` and fallback branch at `179-183` | Remove or rename fallback during final Wan2GP cleanup. |
| Wan2GP submodule reconciliation | `worker_startup.template.sh:267-292` | Remove stale `Wan2GP/` cleanup and missing-submodule hard fail once VibeComfy is canonical. |
| Production profile default | `worker_startup.template.sh:463` | Replace `--wgp-profile 1` with VibeComfy profile selection only after profile parity exists. |
| Pod disk sizing | `gpu_orchestrator/worker_spawner.py:279-281` and `391-395` | **H9 RESOLVED (2026-05-05): raise Sprint 0 baseline to 200 GB.** Memory note confirmed 50 GB is too small for WAN 14B alone; dual-stack matrix (WGP + Comfy + ready_templates models) needs further headroom. 200 GB sized for: (a) WGP submodule + checkpoints (~30GB), (b) VibeComfy ready_templates + custom_nodes (~25GB), (c) downloaded model cache for the dual-run corpus (~80GB), (d) RunPod base image + venv (~20GB), (e) artifact/output buffer (~45GB). Sprint 0 first-pod boot validates actual disk usage; if >180GB on first boot, raise to 250GB before Sprint 1. **Decision rationale: maximizes success because under-sized disk caused the prior live-test crash; explicit baseline raise is a one-line change in `worker_spawner.py` that prevents the entire dual-run matrix from crashing pre-LTX.** |
| Worker image Dockerfile | `gpu_orchestrator/Dockerfile` | Verify and remove any Wan2GP install steps if present; current main may be generic and need no edit. |
| `mmgp` runtime dependency | `reigh-worker/pyproject.toml:13` | `mmgp==3.7.6` is WGP-specific and must be removed only after the WGP surface is retired. |

## 1A. Task-type to VibeComfy template triage

Section 1 enumerates the runtime task surface; Section 2 inventories the 50 ready templates under `vibecomfy/ready_templates/`. This section closes the gap between them by classifying every runtime task type (`source/task_handlers/tasks/task_types.py:120-138` ∪ `source/task_handlers/tasks/task_registry.py:1442-1511`) into one of three dispositions:

- **NATIVE** — a `ready_templates/**` template is the direct execution unit; only parameter wiring (prompt, image inputs, seed, resolution, profile overlay) is required.
- **ADAPT** — an existing template is the closest basis but needs concrete graph edits or patches (added/removed nodes, swapped LoRA loaders, control rails spliced in via `replace_edge`, output shape coercion).
- **NEW** — no usable basis exists in `ready_templates/`; a new ready template must be authored against a named ComfyUI workflow / model family before the cohort can canary.

The `concrete edits required` column lists graph-level deltas only, not parameter wiring. Section 3A pins the recipes for the LoRA, control-rail, travel-continuity, and prompt-expander edits that recur across rows.

| task_type | Required by app? | disposition | target template path or basis | concrete edits required | control rails | LoRA handling | cohort/sprint |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `z_image_turbo` | YES (USED-IN-APP) | NATIVE | `ready_templates/image/z_image.py` | None (prompt is registered via `register_input` per `vibecomfy/docs/authoring.md:164`). | None | None | A / Sprint 2 |
| `z_image_turbo_i2i` | YES (USED-IN-APP) | ADAPT | `ready_templates/image/z_image.py` | Add `LoadImage` + `VAEEncode` and splice the latent into the sampler input that currently feeds from `EmptyLatentImage`; change `register_input` for `image` (Section 3A "i2i input adapter"). | None | None | A / Sprint 2 |
| `qwen_image` | YES (USED-IN-APP) | ADAPT | `ready_templates/image/qwen_image_2512.py` | Disable the edit-mode image input branch (no `LoadImage`); keep T2I sampler chain. Verify text encoder + VAE load. | None | LoRA optional; if used, splice `LoraLoaderModelOnly` between the diffusion-model loader and `ModelSamplingAuraFlow` — pattern same as `edit/qwen_image_edit.py:112-130`. | A / Sprint 5 |
| `qwen_image_2512` | YES (USED-IN-APP) | NATIVE | `ready_templates/image/qwen_image_2512.py` | None | None | None by default | A / Sprint 2 |
| `flux` | NO (UNUSED — see §0A) | NEW (escalated; Klein is a different model from FLUX.1 Dev) — **SKIPPABLE** | Must author `ready_templates/image/flux1_dev_t2i.py` (and optionally `flux1_schnell_t2i.py`, `flux1_dev_kontext_edit.py`). | WGP `flux` task type loads **FLUX.1 Dev 12B** (`Wan2GP/defaults/flux.json:3-9`, file `flux1-dev_bf16.safetensors`). All three VibeComfy `image/flux2_klein_*` templates load **Flux 2 Klein** (`flux-2-klein-base-4b.safetensors` at `flux2_klein_4b_t2i.py:69-72`) — a separate Black Forest Labs model with a different VAE (`flux2-vae.safetensors` at `flux2_klein_4b_t2i.py:78-80`) and a different text encoder (`qwen_3_4b.safetensors` at `flux2_klein_4b_t2i.py:73-77`). Klein is not a drop-in for FLUX.1 Dev. | None | None | A / Sprint 5 |
| `flux` (all variants: dev, schnell, dev_kontext) | NO (UNUSED — H11 consolidation 2026-05-05) | **OUT OF SCOPE per §0A.** | n/a | n/a | n/a | n/a | If reintroduced, treat as a separate project. Decision rationale (H11): maximizes success because keeping deferred-but-described Flux variant rows invites accidental scope creep during Sprint 5 (someone reads the row and feels it should ship); collapsing to one out-of-scope row eliminates the temptation. |
| `wan_2_2_t2i` | YES (USED-IN-APP — production default for image-gen tool) | ADAPT | `ready_templates/video/wanvideo_wrapper_22_5b_t2v_controlnet.py` (or `wan_t2v.py` after profile fit) | Force `num_frames=1` on the WanVideo sampler/encode nodes; the `forced_video_length=1` flag at `task_types.py:135` must be applied as a small patch over a Wan T2V template since no `wan_2_2_t2i` template exists. | None | Wan templates use `WanVideoLoraSelect` (kj wrapper, `wanvideo_wrapper_21_14b_i2v.py:79-91`), not `LoraLoaderModelOnly`. | A / Sprint 4 |
| `qwen_image_edit` | YES (USED-IN-APP) | NATIVE | `ready_templates/edit/qwen_image_edit.py` | None | None | Built-in `LoraLoaderModelOnly` for Qwen-Image-Edit-Lightning at `edit/qwen_image_edit.py:112-130`; sanitizer patch (Section 3A) applies if user LoRAs are stacked on top. | B / Sprint 5 |
| `qwen_image_hires` | NO (UNUSED — see §0A; hires-fix is a payload-level decoration on `qwen_image_edit`) | ADAPT — **SKIPPABLE** | `ready_templates/edit/qwen_image_edit.py` | Add a hires upscale stage: latent upscale or pixel upscale + second-pass `KSampler` chain. No existing template covers Qwen hires-fix; either author a recipe or duplicate the edit graph. | None | Same as `qwen_image_edit`. | B / Sprint 5 |
| `qwen_image_style` | YES (USED-IN-APP) | ADAPT | `ready_templates/edit/qwen_image_edit.py` | The handler may rewrite prompt/model during conversion (`task_types.py` notes); keep template, swap LoRA name via `LoraLoaderModelOnly.lora_name` widget; preprocessing performs Qwen prompt expansion (Section 3A). | None | Style LoRA stacked on top of Lightning LoRA — needs sanitizer + multi-LoRA chain. | B / Sprint 5 |
| `image_inpaint` | YES (USED-IN-APP) | ADAPT | `ready_templates/edit/qwen_image_edit.py` | Add mask handling: `LoadImage` (mask) → `MaskComposite` or `SetLatentNoiseMask` spliced into the latent feeding the sampler. The base edit template has no mask path. | None | Same Qwen Lightning LoRA. | B / Sprint 5 |
| `annotated_image_edit` | YES (USED-IN-APP) | ADAPT | `ready_templates/edit/qwen_image_edit.py` | Pre-process: bake annotation onto the source image in reigh-worker before `LoadImage`. Empty prompt allowed (`task_types.py:125-134`); template must accept empty `TextEncodeQwenImageEdit.prompt`. | None (annotation is rasterised) | Same Qwen Lightning LoRA. | B / Sprint 5 |
| `t2v` | NO (UNUSED) | NATIVE — **SKIPPABLE** | `ready_templates/video/wan_t2v.py` | None | None | None | C / Sprint 3 |
| `t2v_22` | NO (UNUSED) | ADAPT — **SKIPPABLE** | `ready_templates/video/wanvideo_wrapper_21_14b_t2v.py` (closest 14B) | Default WGP `t2v_22` is `t2v_2_2`; the wrapper template is 2.1-tagged. Either point at `wan_t2v.py` and use a Wan-2.2 model file via `WanVideoModelLoader.widget_0`, or author `ready_templates/video/wanvideo_wrapper_22_t2v.py` (NEW). Decision: ADAPT via model-file widget swap, with NEW promotion if validation fails. | None | `WanVideoLoraSelectMulti` already present at `wanvideo_wrapper_21_14b_t2v.py:89`. | C / Sprint 4 |
| `i2v` | NO (UNUSED — app reaches Wan i2v models via `travel_orchestrator`, not direct `i2v` task) | NATIVE — **SKIPPABLE** | `ready_templates/video/wan_i2v.py` (or `wanvideo_wrapper_21_14b_i2v.py` for kj wrapper) | Pick one as default in `template_routing.py`; `wan_i2v.py` is the simpler ComfyUI-native path. | None | `WanVideoLoraSelect` if using kj wrapper. | C / Sprint 3 |
| `i2v_22` | NO (UNUSED) | ADAPT — **SKIPPABLE** | `ready_templates/video/wanvideo_wrapper_22_5b_i2v.py` | Verify 5B model fits production profile-1 VRAM budget; otherwise fall back to `wan_i2v.py` with a 2.2 model widget. | None | None by default. | C / Sprint 4 |
| `generate_video` | NO (UNUSED) | ADAPT — **SKIPPABLE** | Same as `t2v` route | Generic fallback: registry resolves to whichever Wan T2V template `t2v` uses; no separate template. | None | None | C / Sprint 3 |
| `ltxv` | NO (UNUSED) | NEW — **SKIPPABLE** | `ready_templates/video/ltx_0_9_8_13b_t2v.py` (must be authored) — LTX 2.3 cannot stand in. | WGP `ltxv_13B` loads `ltxv_0.9.8_13B_dev_bf16.safetensors` (`Wan2GP/defaults/ltxv_13B.json:8`) with `LTXV_config: models/ltx_video/configs/ltxv-13b-0.9.8-dev.yaml` and recommends 30 inference steps. VibeComfy's `ltx2_3_t2v.py:51-55` loads `ltx-2.3-22b-dev.safetensors` (different model generation, 22B vs 13B) and runs the LTX 2.3 distilled `ClownSampler_Beta` at ~8 explicit sigmas (`ltx2_3_t2v.py:78`). Different model, different VAE (`LTXVAudioVAELoader` at `ltx2_3_t2v.py:54-56`), different sampler stack — output frame count, motion characteristics, and per-shot quality will all drift well beyond a Q3 threshold. NEW basis: existing community Comfy LTX 0.9.8 13B workflow (e.g. Lightricks' `ltxv_13b_dev` JSON at `https://github.com/Lightricks/ComfyUI-LTXVideo/tree/main/example_workflows`) ported as a ready template. | None | If the legacy LTX template ships with distilled-LoRA support, mirror the `LoraLoaderModelOnly` chain pattern at `ltx2_3_t2v.py:103-114`. | C / Sprint 5 |
| `ltx2` | NO (UNUSED — see §0A) | NATIVE — **SKIPPABLE** | `ready_templates/video/ltx2_3_t2v.py` (T2V) / `ltx2_3_i2v.py` (I2V) | Registry routes by input shape. Low-RAM variants (`ltx2_3_iamccs_audio_extend_low_ram.py`, `ltx2_3_runexx_music_video_low_ram.py`) are profile-5 candidates. | None | LTX distilled LoRA already in template. | C / Sprint 5 |
| `vace` | NO (UNUSED) | NATIVE — **SKIPPABLE** | `ready_templates/video/wanvideo_wrapper_13b_vace.py` | None for the basic VACE control path; `WanVideoVACEEncode` + `WanVideoVACEStartToEndFrame` already present (`wanvideo_wrapper_13b_vace.py:470-504`). | DepthAnythingV2 in-workflow at `wanvideo_wrapper_13b_vace.py:171-173,388-391`; Canny/Pose/Flow rails would need pre-process (Section 3A). | None by default; LoRA stacking via `WanVideoLoraSelectMulti` patch if needed. | D / Sprint 4 |
| `vace_21` | NO (UNUSED) | NATIVE — **SKIPPABLE** | `ready_templates/video/wanvideo_wrapper_13b_vace.py` | Swap `WanVideoModelLoader.widget_0` to a Wan 2.1 14B model file; underlying graph identical. | Same as `vace` | Same as `vace` | D / Sprint 4 |
| `vace_22` | NO as direct task type, but the Wan 2.2 VACE cocktail **model** is required indirectly via `travel_segment`/`join_clips_segment`/`individual_travel_segment` (which pin `wan_2_2_vace_lightning_baseline_2_2_2`) | NEW (Q17 closed) — REQUIRED for indirect routes only | `ready_templates/video/wanvideo_wrapper_22_14b_vace_cocktail.py` (must be authored — see §3A). | NEW template required: dual `WanVideoModelLoader` (HIGH + LOW), two-stage `WanVideoSampler` chain with sigma cut-over at `switch_threshold` (875 for 2-phase, 883/558 for 3-phase per `Wan2GP/defaults/wan_2_2_vace_lightning_baseline_2_2_2.json:18-20`), `WanVideoLoraSelectMulti` for the 4-LoRA cocktail. | Same as `vace` + Uni3C nodes per §3A (`WanVideoUni3C_ControlnetLoader` + `WanVideoUni3C_embeds` + `WanVideoSampler.uni3c_embeds`). | Same as `vace` | D / Sprint 4 |
| `hunyuan` | NO (UNUSED — `rg -i 'hunyuan\|hyvid' reigh-app/ → 0 hits`) | NEW — **SKIPPABLE** | None — `find vibecomfy/ready_templates -name '*hunyuan*'` is empty | Author `ready_templates/video/hunyuan_*.py`. Basis: HunyuanVideo official ComfyUI workflow (HunyuanVideoSampler / HunyuanVideoVAE node pack). Must accept prompt + optional reference image, emit a `SaveVideo` node. Decision needed: Hunyuan I2V or T2V (or both as separate templates). | TBD by maintainer | TBD; Hunyuan distilled-step LoRAs are public, mirror Wan pattern via `LoraLoaderModelOnly`. | D / Sprint 4 — **REMOVED FROM SCOPE** |
| `comfy` | NO (UNUSED) | ADAPT — **SKIPPABLE** | Bypass — raw API JSON delegates through `vibecomfy.runtime.run_embedded` | No template; the existing raw workflow JSON is the input. `comfy_handler.py` refactor (Section 3) loads the JSON, wraps it with `VibeWorkflow.from_api_json` (or equivalent escape hatch), runs it via `run_embedded`, returns `RunResult.outputs[0]`. | Whatever the user-supplied JSON contains | Whatever the user-supplied JSON contains | E / Sprint 2 |
| `create_visualization` | NO (UNUSED) | NATIVE (no template) — **SKIPPABLE** | N/A — utility task | No VibeComfy execution. `source/task_handlers/create_visualization.py` stays unchanged; backend selection is irrelevant. | N/A | N/A | E / Sprint 6 |
| `extract_frame` | NO (UNUSED) | NATIVE (no template) — **SKIPPABLE** | N/A — utility task | No VibeComfy execution. ffmpeg-based frame extraction stays in `source/task_handlers/extract_frame.py`. | N/A | N/A | E / Sprint 6 |
| `rife_interpolate_images` | NO (UNUSED) | NATIVE (no template) — **SKIPPABLE** | N/A — vendored helper from `vendor_imports.py:47-55` | No VibeComfy execution. RIFE stays under `reigh-worker/source/media/` per Section 3 vendor-utility decision. Runtime name `rife_interpolate_images` is preserved. | N/A | N/A | E / Sprint 6 |
| `magic_edit` | NO (UNUSED — frontend `magic_edit` family resolves to `qwen_image_edit` task type) | NATIVE (no template) — **SKIPPABLE** | N/A — Replicate/Flux Kontext path | No VibeComfy execution; existing `source/task_handlers/magic_edit.py` calls Replicate API directly. | N/A | N/A | E / Sprint 6 |
| `travel_orchestrator` | YES (USED-IN-APP) | NATIVE (no template) | N/A — pure orchestration | Creates `travel_segment` children; no direct VibeComfy run. Backend selection is propagated to children per Section 5. **Cross-reference §3A "Travel-segment configuration matrix" for the full app-exposed combination set.** | N/A | N/A | E / Sprint 6 |
| `travel_segment` | YES (USED-INDIRECTLY — child of `travel_orchestrator`) | NEW for Wan family (Q17 closed); ADAPT for LTX family | Wan family: `ready_templates/video/wanvideo_wrapper_22_14b_vace_cocktail.py` (the same Sprint 4 NEW template — its `start_image`/`end_image` SetNodes mirror `wanvideo_wrapper_13b_vace.py:236-279`). LTX family: `ready_templates/video/ltx2_3_runexx_first_last_frame.py`. **Per-combination wiring: §3A "Travel-segment configuration matrix" (13 rows).** | `_derive_model_family` at `source/task_handlers/travel/orchestrator.py:38-49` chooses Wan vs LTX. `_apply_video_source_continuation` (`task_registry.py:1106-1132`) writes `video_source` into params — maps to a `VHS_LoadVideo` source-node patch on the chosen template. | DepthAnythingV2 inline (Wan-VACE) or pre-processed Canny/Pose/Flow per §3A. Uni3C via §3A nodes when `_apply_uni3c_config` (`task_registry.py:1326-1328`) is active. | Wan: `WanVideoLoraSelectMulti` patch; LTX: `LoraLoaderModelOnly` already in template. | E / Sprint 6 (Wan path blocked on Sprint 4 NEW template) |
| `individual_travel_segment` | YES (USED-IN-APP) | ADAPT | Same as `travel_segment` | Standalone variant (`is_standalone=True` at `task_registry.py:1298-1304`); same template + patches. **Same matrix at §3A applies — the lightbox regen path uses `individualTravelSegment.ts` resolver but produces equivalent orchestrator_details.** | Same as `travel_segment` | Same as `travel_segment` | E / Sprint 6 |
| `travel_stitch` | YES (USED-IN-APP) | NATIVE (no template) | N/A — ffmpeg/media stitcher | No VibeComfy execution. `source/task_handlers/travel/stitch.py:804` references `video_source_path` for chained stitching; backend irrelevant. **Stitcher consumes whatever segment outputs the matrix at §3A produces; no per-row variation.** | N/A | N/A | E / Sprint 6 |
| `inpaint_frames` | NO (UNUSED) | NEW — **SKIPPABLE** | `ready_templates/video/wanvideo_wrapper_22_14b_vace_cocktail.py` extended with mask-mode (`WanVideoVACEEncode.input_masks`, mirrored from `wanvideo_wrapper_13b_vace.py:489-494`). | Default model is `wan_2_2_vace_lightning_baseline_2_2_2` (`task_types.py:104`). Same dual-model 2.2 cocktail constraint as `vace_22`. | DepthAnythingV2 inline + Uni3C nodes per §3A. | None by default. | E / Sprint 6 (blocked on Sprint 4 NEW template) |
| `join_clips_orchestrator` | YES (USED-IN-APP) | NATIVE (no template) | N/A — pure orchestration | Creates `join_clips_segment` and `join_final_stitch` children. | N/A | N/A | E / Sprint 6 |
| `join_clips_segment` | YES (USED-INDIRECTLY) | NEW (Q17 closed) | Same NEW template as `vace_22`/`inpaint_frames`: `ready_templates/video/wanvideo_wrapper_22_14b_vace_cocktail.py`. | Same default as `inpaint_frames` (`task_types.py:103`); requires `task_queue` per Seam B. Per-segment first/last frames feed VACE start/end frame nodes. **Wiring inherits Wan rows 1-6 of §3A "Travel-segment configuration matrix"; only `start_image`/`end_image` SetNode targets differ.** | Same as `vace` | Same as `vace` | E / Sprint 6 (blocked on Sprint 4 NEW template) |
| `join_final_stitch` | YES (USED-INDIRECTLY) | NATIVE (no template) | N/A — stitch-only | No VibeComfy execution. **Same stitch contract as `travel_stitch`; no per-row variation in §3A matrix.** | N/A | N/A | E / Sprint 6 |
| `edit_video_orchestrator` | YES (USED-IN-APP) | NATIVE (no template) | N/A — pure orchestration | Creates child join/regen tasks. | N/A | N/A | E / Sprint 6 |

Disposition counts (35 task types total, including the dispatch-only `comfy`, with three new flux-variant rows): 9 NATIVE-template, 11 ADAPT, 7 NEW (`hunyuan`, Wan 2.2 VACE cocktail covering `vace_22` + `inpaint_frames` + `join_clips_segment` + `travel_segment` Wan path, `ltxv` legacy 13B, `flux` FLUX.1 Dev 12B, plus deferred `flux` schnell + dev_kontext variants), 12 NATIVE (no-template / utility / orchestration).

**After §0A production-usage filter (USED-IN-APP and USED-INDIRECTLY rows only):** 17 task types are in scope, 18 task types are dropped as UNUSED (see §0A roll-up). The Sprint 4 NEW count drops from 2 to **1** (Wan 2.2 VACE cocktail; Hunyuan removed). The Sprint 5 NEW count drops from 2 to **0** (LTX legacy 13B and FLUX.1 Dev both removed — `ltxv`, `ltx2`, and `flux` are all UNUSED). Total NEW templates required by the migration drops from 7 to **1**, all within Sprint 4. The remaining 16 in-scope task types are split: 4 NATIVE-template (`z_image_turbo`, `qwen_image_2512`, `qwen_image_edit`), 5 ADAPT (`z_image_turbo_i2i`, `qwen_image`, `wan_2_2_t2i`, `qwen_image_style`, `image_inpaint`, `annotated_image_edit`, `individual_travel_segment`), and 7 NATIVE (no-template / utility / orchestration: `travel_orchestrator`, `travel_stitch`, `join_clips_orchestrator`, `join_final_stitch`, `edit_video_orchestrator`, plus the indirectly-used `travel_segment`, `join_clips_segment`).

Section 5 is patched downstream to surface the ADAPT/NEW dispositions per cohort so promotion gates check template readiness, not just queue-seam readiness.

## 2. Audit VibeComfy capabilities

### VibeWorkflow IR and Authoring Model

VibeComfy's canonical editable representation is `VibeWorkflow`, not raw Comfy API JSON. `vibecomfy/vibecomfy/workflow.py:76-85` defines the workflow IR with nodes, edges, inputs, outputs, requirements, and metadata. The migration-relevant mutators are:

- `finalize_metadata()` at `workflow.py:99-110`, which rebuilds inputs, outputs, and requirements.
- `add_node()` at `workflow.py:130-134`.
- `connect()` at `workflow.py:145-151`.
- `disconnect()` at `workflow.py:153-163`.
- `replace_edge()` at `workflow.py:165-172`.
- `validate()` at `workflow.py:174-193`.
- `compile("api")` at `workflow.py:195-207`, which produces the dict accepted by ComfyUI `/prompt`.

`vibecomfy/docs/authoring.md:5` states that `VibeWorkflow` is the only editable IR and that API JSON is an escape hatch. The template/patch rule is load-bearing for the migration: `docs/authoring.md:23` says to use blocks/templates when the call changes handles, `docs/authoring.md:50-54` says to use patches for decoration/adjustment, and the rule is repeated as `changes-handles -> new template; decorates-handles -> patch`.

### Ready Templates

The live filesystem count is 50 Python ready templates:

```text
find vibecomfy/ready_templates -type f -name '*.py' | wc -l
=> 50
```

The README's previously cited 46-template figure is stale and should not be used as source of truth for migration planning; the live `find` count is 50. Organization is by media family:

| Directory | Examples | Migration relevance |
| --- | --- | --- |
| `ready_templates/image/` | `z_image.py`, `qwen_image_2512.py`, Flux Klein T2I templates | Direct image queue tasks such as `z_image_turbo`, `qwen_image_2512`, `flux`, and `wan_2_2_t2i` analogues. |
| `ready_templates/edit/` | `qwen_image_edit.py`, Flux Klein image edit templates | Qwen/Flux image edit task families. |
| `ready_templates/video/` | `wan_t2v.py`, `wan_i2v.py`, `ltx2_3_t2v.py`, `wanvideo_wrapper_13b_vace.py`, WanVideoWrapper 2.1/2.2 variants | Wan, LTX, VACE, i2v/t2v direct queue tasks and later orchestrated child tasks. |
| `ready_templates/audio/` | ACE Step and Qwen TTS templates | Not in the current reigh-worker Wan2GP migration surface, but relevant for future media expansion. |

Known direct-queue mapping starting points:

| reigh-worker task family | Candidate VibeComfy ready templates | Gap note |
| --- | --- | --- |
| `z_image_turbo`, `z_image_turbo_i2i` | `image/z_image` | I2I behavior needs explicit routing/patching; text-to-image has a direct template. |
| `qwen_image_2512` | `image/qwen_image_2512` | Direct template exists. |
| `qwen_image`, `qwen_image_edit`, `qwen_image_hires`, `qwen_image_style`, `image_inpaint`, `annotated_image_edit` | `edit/qwen_image_edit` plus Qwen image templates | Needs parameter/output parity and LoRA/key sanitizer equivalents. |
| `flux` | `image/flux2_klein_4b_t2i`, `image/flux2_klein_9b_t2i`, `image/flux2_klein_9b_gguf_t2i` | Model-family mapping decision needed; Wan2GP `flux` is not automatically Flux Klein parity. |
| `t2v`, `t2v_22` | `video/wan_t2v`, `video/wanvideo_wrapper_21_14b_t2v`, `video/wanvideo_wrapper_22_5b_t2v_controlnet` | Needs Wan profile/memory and output-shape parity. |
| `i2v`, `i2v_22` | `video/wan_i2v`, `video/wanvideo_wrapper_21_14b_i2v`, `video/wanvideo_wrapper_22_5b_i2v` | Needs input media and continuation behavior parity. |
| `vace`, `vace_21`, `vace_22` | `video/wanvideo_wrapper_13b_vace`, Wan 2.1/2.2 control templates | Needs VACE/guide-video mapping and Uni3C decision. |
| `ltxv`, `ltx2` | `video/ltx2_3_t2v`, `video/ltx2_3_i2v`, Runexx/IAMCCS/Lightricks LTX templates | Needs WGP LTX parameter parity and low-RAM policy mapping. |
| `hunyuan` | None found by `find vibecomfy/ready_templates -type f -name '*hunyuan*'` | Hard gap: no Hunyuan ready template. |

### Runtime Execution Surface

VibeComfy exposes both one-shot and warm-session execution:

| Path | Source | Behavior |
| --- | --- | --- |
| Embedded one-shot | `vibecomfy/vibecomfy/runtime/run.py:75-84` | `run_embedded` / `run_embedded_sync` create an `EmbeddedSession` from workflow metadata, run it, then stop it. |
| External or managed server one-shot | `runtime/run.py:27-72` | `run` / `run_sync` use `comfy_server`, schema gate with `/object_info`, queue `/prompt`, and return a `RunResult`. |
| Warm embedded session | `vibecomfy/docs/runtime_surface.md:64-105`; `runtime/session.py` | Holds a HiddenSwitch `Comfy()` context across runs and supports `start`, `run`, `flush`, `reconfigure`, `stop`. This is the closest analogue to vendored in-process `wgp.py` for `reigh-worker`. |
| Warm managed server | `runtime/server.py:10-34`; `runtime/session.py` | Starts or reuses `comfyui serve`, uses HTTP readiness and prompt queueing. |
| HTTP client | `runtime/client.py:8-40` | Uses `/system_stats`, `/prompt`, `/api/free`, and `/object_info`. |

`RunResult` is defined at `vibecomfy/vibecomfy/runtime/session.py:35-42` and carries `run_id`, `prompt_id`, `outputs`, `metadata_path`, and `log_path`. `vibecomfy/docs/runtime_surface.md:25-38` documents the HTTP surface currently used, and `runtime_surface.md:40-53` documents the embedded HiddenSwitch surface.

### Existing Memory Controls

VibeComfy has lower-level memory/session knobs, but not Wan2GP's five-tier profile abstraction. `vibecomfy/vibecomfy/runtime/session.py:45-53` defines `SessionConfig` fields:

- `vram_policy`
- `reserve_vram_gb`
- `cache_policy`
- `disable_smart_memory`
- `warm_policy`
- `auto_flush_vram_threshold_gb`
- `port`
- `extra`

There are two translation paths, and the citations are intentionally distinct:

| Translation path | Source | What it builds |
| --- | --- | --- |
| Embedded ComfyUI `Configuration` | `vibecomfy/vibecomfy/runtime/session.py:625-656` | `_embedded_configuration_for_session` maps `vram_policy` to `highvram`/`lowvram`/`normalvram`, maps `reserve_vram_gb` to `reserve_vram`, maps `cache_policy` to `cache_classic`/`cache_none`/`cache_lru`, applies `disable_smart_memory`, then merges `config.extra` and `VIBECOMFY_COMFY_CONFIGURATION` JSON. |
| Managed server CLI argv | `vibecomfy/vibecomfy/runtime/session.py:663-678` | `_comfy_server_argv` maps the same `SessionConfig` to `--highvram`/`--lowvram`/`--normalvram`, `--reserve-vram`, `--disable-smart-memory`, `--cache-classic`/`--cache-none`/`--cache-lru N`, and `--port`. |

The migration gap is not "no memory controls"; the gap is "no Wan2GP-compatible 1-5 profile tier overlay that maps task/global `override_profile` semantics onto these existing knobs."

### Validation Surface

Validation exists at both IR and schema levels:

- `VibeWorkflow.validate()` is in `vibecomfy/vibecomfy/workflow.py:174-193`.
- Schema validation and API link-shape validation are in `vibecomfy/vibecomfy/schema/validate.py:15-174`.
- Runtime/local schema providers and object-info caching are in `vibecomfy/vibecomfy/schema/provider.py:76-158` and `schema/cache.py:11-50`.
- Human-readable issue formatting is in `vibecomfy/vibecomfy/schema/format.py:6-9`.
- `vibecomfy/docs/authoring.md:173-175` documents `doctor --json`; `vibecomfy/docs/adding_templates_models.md:137-143` documents `vibecomfy.cli validate ready_templates/...` and test commands for ready-template changes.

For migration, this gives the adapter a stronger preflight surface than raw WGP parameter construction, but it does not prove output parity. It must be combined with dual-run comparison.

### RunPod Execution Path

VibeComfy delegates RunPod operations to `runpod-lifecycle`. Optional extras in `vibecomfy/pyproject.toml:23-29` include `runpod-lifecycle`, and `vibecomfy/vibecomfy/commands/runpod.py:20-43` imports it from the installed package or a local checkout. The command surface includes list, status, terminate, gpu-types, and corpus-matrix at `commands/runpod.py:46-104`.

For `reigh-worker`, the near-term target should still be `EmbeddedSession`, not the VibeComfy RunPod CLI. The orchestrator already provisions GPU workers; VibeComfy's RunPod path is useful for template corpus validation and smoke tests, while `EmbeddedSession` is the analogue of the current vendored `wgp.py` execution object.

### Explicit VibeComfy Gaps vs Wan2GP

| Gap | Evidence | Cutover impact |
| --- | --- | --- |
| No 1-5 profile tier abstraction | `SessionConfig` exposes lower-level knobs at `runtime/session.py:45-53`; no profile enum/module exists in `vibecomfy/vibecomfy/runtime/`. | P0. Must layer `MemoryProfile` on top of `SessionConfig` before cutover. |
| No per-task `override_profile` semantics | Current Wan2GP params carry `override_profile` at `wgp_params.py:166,237,374`; VibeComfy has no equivalent routing field. | P0. Required for task-level parity. |
| No Hunyuan ready template | `find vibecomfy/ready_templates -type f -name '*hunyuan*'` returns zero files. | P0 for Hunyuan cohort. |
| No LoRA-key sanitizer equivalent | Current sanitizer is WGP monkeypatch code in `source/models/wgp/wgp_patches.py:384-483`. | Needed before Qwen/LoRA-heavy cutover. |
| No Uni3C ControlNet cache | Current cache is in `source/models/wgp/model_ops.py:234-260` via `load_uni3c_controlnet`. | Needed for guided Wan/VACE parity. |
| No RIFE temporal interpolation helper | Current helper is `vendor_imports.py:47-55`. | Keep in reigh-worker or move to VibeComfy extras before `rife_interpolate_images` cutover. |
| No Qwen prompt expander wrapper | Current helper is `vendor_imports.py:32-45`. | Needs pre-processing equivalent if any task depends on WGP expander behavior. |
| No Canny/Depth/Flow/Pose annotator re-exports | Current helpers are `vendor_imports.py:91-113`. | Pre-process before workflow build or expose extras. |
| No Wan2GP `save_video` callable | Current callable is `vendor_imports.py:58-73`. | Existing media helpers need replacement or isolation. |

## 3. Parity gaps and required pre-cutover work

This section turns the audits in Sections 1 and 2 into required pre-cutover work. P0 items block any production canary; P1 items block the cohort that depends on them; P2 items can trail behind dual-run if rollback remains available and output contracts are preserved.

### Parity Gap Matrix

| Capability | Current Wan2GP location | VibeComfy current state | Required work | P-priority | owner-repo | Target sprint |
| --- | --- | --- | --- | --- | --- | --- |
| Five-tier memory profiles and global default profile | `reigh-worker/source/runtime/worker/server.py:556-558,605-609`; prod default in `worker_startup.template.sh:463`; dev defaults in `start_worker.bat:14` and `scripts/live_test/{main,smoke}.py:27` | Lower-level `SessionConfig` knobs only at `vibecomfy/vibecomfy/runtime/session.py:45-53` | Add `vibecomfy.runtime.profile.MemoryProfile` overlay and map profiles 1-5 to `SessionConfig` overrides; baseline prod profile 1 and dev profile 3 | P0 | `vibecomfy` | Sprint 1 |
| Per-call profile override | `reigh-worker/source/models/wgp/generators/wgp_params.py:166,237,374` | No task-level profile field or override semantics | Add `override_profile` handling in the reigh-worker adapter that resolves to `MemoryProfile.to_session_overrides()` before constructing the VibeComfy `SessionConfig` | P0 | `reigh-worker` + `vibecomfy` | Sprint 1-2 |
| Direct task-type routing to templates | Union of `TASK_TYPE_CATALOG` and `task_registry.py:1442-1511` | Ready templates exist for many image/Wan/LTX/VACE families, but no reigh-worker routing registry | Add `reigh-worker/source/models/comfy/template_routing.py` as the only genuinely new `source/models/comfy/` file; cover the full union task surface | P0 | `reigh-worker` | Sprint 2 |
| ~~Hunyuan task parity~~ — **REMOVED FROM SCOPE** (per §0A: app emits zero `hunyuan` tasks; `rg -i 'hunyuan\|hyvid' reigh-app/ → 0 hits`) | `hunyuan` in `source/task_handlers/tasks/task_types.py:99-101,120-138` | No `ready_templates/video/hunyuan_*`; live `find ... -name '*hunyuan*'` returns zero template files | ~~Ship Hunyuan ready template~~. Worker handler can stay; no parity work needed since no production traffic exercises this task type. | P3 (defer indefinitely) | — | — |
| Wan/VACE/Uni3C guided-video parity | `vace*`, `t2v*`, `i2v*`; Uni3C cache in `source/models/wgp/model_ops.py:234-260` | Wan and VACE template candidates exist; no Uni3C cache abstraction | Represent Uni3C as VibeComfy patches over Wan 2.2 templates, with explicit cache/model lifecycle policy | P1 | `vibecomfy` + `reigh-worker` | Sprint 4 |
| Qwen image/edit and prompt-expander parity | Qwen handlers in direct queue conversion; prompt expander from `source/runtime/wgp_ports/vendor_imports.py:32-45` | Qwen image/edit template candidates exist; no prompt-expander wrapper | Run Qwen prompt expansion as reigh-worker pre-processing before workflow build, then route to Qwen templates | P1 | `reigh-worker` | Sprint 5 |
| LoRA-key sanitizer | `source/models/wgp/wgp_patches.py:384-483`; LoRA setup in `source/models/wgp/lora_setup.py` | No portable sanitizer or `LoraLoader` patch | Implement a VibeComfy patch that normalizes/sanitizes LoRA keys over `LoraLoader` nodes and add golden LoRA corpus tests | P1 | `vibecomfy` + `reigh-worker` | Sprint 5 |
| Canny/Depth/Pose/Flow preprocessing | `source/runtime/wgp_ports/vendor_imports.py:91-113`; flow visualization at `vendor_imports.py:96-98` | No VibeComfy re-exports | Keep annotators as reigh-worker pre-processing before workflow build until moved to a VibeComfy extras package | P1 | `reigh-worker` | Sprint 5 |
| RIFE interpolation | `source/runtime/wgp_ports/vendor_imports.py:47-55`; `source/task_handlers/rife_interpolate.py` | No VibeComfy helper | Keep RIFE vendored under `reigh-worker/source/media/` and call it outside VibeComfy for `rife_interpolate_images` | P1 | `reigh-worker` | Sprint 6 |
| Existing raw `comfy` task path | `source/models/comfy/comfy_handler.py`; `source/models/comfy/comfy_utils.py`; dispatch at `task_registry.py:1507-1510` | Separate Comfy subprocess/client stack, not VibeComfy | Refactor `comfy_handler.py` to delegate through `vibecomfy.runtime.run_embedded`; retire `comfy_utils.py`; migrate dependent test imports | P0 | `reigh-worker` | Sprint 2 |
| Model load/unload lifecycle | `source/models/wgp/model_ops.py`; runtime mutation in `source/runtime/wgp_ports/runtime_registry.py` | `EmbeddedSession` supports `start`, `run`, `flush`, `reconfigure`, `stop`; no WGP-like model-definition loader | Use a long-lived `EmbeddedSession` per worker, explicit profile reconfiguration policy, and build-time frozen template/model definitions pending Q1 | P0 | `reigh-worker` + `vibecomfy` | Sprint 1-2 |
| Queue and child-task adapter seams | Direct seam at `_handle_direct_queue_task`; nested seam via handlers receiving `context["task_queue"]` | No reigh-worker adapter yet | Thread `REIGH_BACKEND` through both direct conversion and child-task enqueue paths; preserve existing queue statuses/output shapes | P0 | `reigh-worker` | Sprint 2 |
| Observability and debug-card telemetry | Heartbeat/system logs in worker server, WGP memory stats in `source/models/wgp/generators/output.py:182-208`, debug-card path in `source/core/log/debug_card.py` | `RunResult` has `run_id`, `prompt_id`, `outputs`, `metadata_path`, `log_path` | Translate `RunResult` into existing heartbeat logs, `system_logs`, and debug-card breadcrumbs; add backend/template labels and VRAM stats | P0 | `reigh-worker` | Sprint 2-3 |
| RunPod/orchestrator worker-image coupling | `worker_startup.template.sh:174,179-183,267-292,463`; `gpu_orchestrator/runpod/startup_script.py` | VibeComfy has a RunPod CLI path, but reigh-worker will still be orchestrator-provisioned | Propagate backend/profile flags through the existing orchestrator startup path; keep both stacks installed until Sprint 8 rollback window closes | P1 | `reigh-worker-orchestrator` | Sprint 7-8 |

### Memory-Profile Abstraction (P0)

VibeComfy should not clone Wan2GP internals. It should add a thin compatibility overlay on the existing `SessionConfig` controls in `vibecomfy/vibecomfy/runtime/session.py:45-53`.

Required module:

```text
vibecomfy/vibecomfy/runtime/profile.py
```

Required API:

```python
class MemoryProfile(Enum):
    MAX_PERFORMANCE = 1
    HIGH_RAM = 2
    BALANCED = 3
    CONSERVATIVE = 4
    MINIMUM = 5

    def to_session_overrides(self) -> dict[str, object]:
        ...
```

`to_session_overrides()` returns a partial dict overlay for `SessionConfig` fields only: `vram_policy`, `reserve_vram_gb`, `cache_policy`, and `disable_smart_memory`. The resulting `SessionConfig` must flow through the existing VibeComfy translation paths unchanged: `_embedded_configuration_for_session` at `vibecomfy/vibecomfy/runtime/session.py:625-656` for embedded ComfyUI `Configuration`, and `_comfy_server_argv` at `session.py:663-678` for managed-server CLI argv.

Starting Sprint 1 mapping:

| Wan2GP profile | `MemoryProfile` | `SessionConfig` override |
| --- | --- | --- |
| `1` | `MAX_PERFORMANCE` | `{"vram_policy": "high", "cache_policy": "smart"}` |
| `2` | `HIGH_RAM` | `{"vram_policy": "high", "cache_policy": "lru:32"}` |
| `3` | `BALANCED` | `{"vram_policy": "normal", "cache_policy": "smart"}` |
| `4` | `CONSERVATIVE` | `{"vram_policy": "low", "cache_policy": "classic", "reserve_vram_gb": 2.0}` |
| `5` | `MINIMUM` | `{"vram_policy": "low", "cache_policy": "lru:1", "disable_smart_memory": True, "reserve_vram_gb": 4.0}` (H2: pinned `lru:1` instead of `"none"` so Uni3C-using tasks remain supported under MINIMUM with a tiny cache footprint; Uni3C controlnet weight (~250MB) survives across runs of the same task. **Decision rationale: maximizes success because `cache_policy="none"` would force a 2-minute Uni3C reload every run on profile-5 hardware — `lru:1` preserves functionality with negligible VRAM cost.**) |

`reigh-worker` must mirror WGP `override_profile` semantics: the process default profile is used when no task override is present, and a per-call `override_profile` replaces the default for that single VibeComfy run. The adapter should resolve `override_profile` before workflow execution, not mutate process-global defaults.

Acceptance gates:

- Profile values 1-5 round-trip through `MemoryProfile` into both embedded configuration and managed-server argv tests.
- Profile 1 parity smoke tests use the production baseline from `worker_startup.template.sh:463`.
- Profile 3 parity smoke tests use the development baselines from `start_worker.bat:14` and `scripts/live_test/{main,smoke}.py:27`.
- Smoke coverage includes at least one image path (`z_image_turbo` or `qwen_image_2512`) and one video path (`t2v` or `wan_t2v` template), with VRAM peak, wall-clock latency, OOM count, and output-shape checks.

### Task-Type to VibeComfy Template Registry

Add `reigh-worker/source/models/comfy/template_routing.py` as the adapter's registry and keep it as the only genuinely new file under `source/models/comfy/`. Existing imports that need template lookup should call this registry; they should not scatter task-type conditionals across handlers.

The registry must cover the full union task surface from Section 1:

| Task surface | Registry behavior | Gate |
| --- | --- | --- |
| `z_image_turbo`, `z_image_turbo_i2i` | Route to `image/z_image` with i2i-specific input patching where needed | Cohort A |
| `qwen_image`, `qwen_image_2512` | Route to `image/qwen_image_2512` or Qwen image equivalent; preserve output image shape | Cohort A |
| ~~`flux`~~ — **UNUSED, skip per §0A** | No route required; worker handler is unreachable from app | — |
| `wan_2_2_t2i` | Route through Wan template with single-frame output contract | Cohort A |
| `qwen_image_edit`, `qwen_image_style`, `image_inpaint`, `annotated_image_edit` | Route to `edit/qwen_image_edit` plus prompt/input/LoRA patches | Cohort B |
| ~~`qwen_image_hires`~~ — **UNUSED, skip per §0A** (hires-fix is layered as `hires_*` payload params on `qwen_image_edit`, not a separate task type) | — | — |
| ~~`t2v`, `t2v_22`, `i2v`, `i2v_22`, `generate_video`~~ — **UNUSED, skip per §0A** | — | — |
| ~~`ltxv`, `ltx2`~~ — **UNUSED, skip per §0A** (LTX models are reachable through `travel_orchestrator` with `model_name="ltx2_*"`, not as direct task types) | — | — |
| ~~`vace`, `vace_21`, `vace_22`~~ — **UNUSED as direct task types, skip per §0A**; the Wan 2.2 VACE cocktail **model** is still required indirectly via the travel/join segment paths | — | — |
| ~~`hunyuan`~~ — **UNUSED, removed from scope per §0A** | — | — |
| `travel_orchestrator`, `travel_segment`, `individual_travel_segment`, `travel_stitch`, `join_clips_orchestrator`, `join_clips_segment`, `join_final_stitch`, `edit_video_orchestrator` | Preserve specialized handlers; child generation delegates into VibeComfy where applicable | Cohort E |
| ~~`inpaint_frames`, `magic_edit`, `create_visualization`, `extract_frame`, `rife_interpolate_images`, `comfy`~~ — **UNUSED, skip per §0A** | Worker handlers stay installed for backwards compat; no migration work | — |

Any task type missing from `template_routing.py` should fail closed during VibeComfy backend selection with a typed unsupported-template error, not silently fall back to WGP unless the caller explicitly selected the WGP backend.

### Missing-Template Gates

~~Hunyuan is a P0 hard gate for Cohort D and Sprint 4.~~ **Removed from scope per §0A AND DELETE-NOW per §8A.B (H3 reconciliation 2026-05-05)** — `reigh-app` emits zero `hunyuan` tasks (`rg -i 'hunyuan|hyvid' reigh-app/ → 0 hits`). The earlier hedge that "the worker handler stays installed for backwards compatibility" is **superseded**: §8A.B already lists `hunyuan` as DELETE-NOW (Sprint 8) and §0A confirmed 0 frontend hits, so carrying forward the WGP `hunyuan` direct-queue path violates the user's stated cleanup preference and contradicts §8A.B. If a future feature reintroduces Hunyuan, the right move is to author a fresh VibeComfy `ready_templates/video/hunyuan_*.py` from scratch — preserving dead WGP plumbing buys nothing. **Decision rationale: maximizes success because conflicting H3 hedges create ambiguity in the Sprint 8 closure sweep (do we delete or not?); resolving to DELETE matches §8A.B and the user-stated preference.**

Further gaps from the Section 2 mapping table require explicit cohort gates:

| Gap | Affected cohort | Go/no-go rule |
| --- | --- | --- |
| Flux model-family mismatch | Cohort A | No Cohort A canary for `flux` until the selected Flux ready template is named in `template_routing.py` and baseline output dimensions/format match WGP. |
| Qwen edit/input variants | Cohort B | No Cohort B promotion until Qwen edit, hires, style, inpaint, and annotated-edit routes each have a template/patch test. |
| Wan 2.2 and VACE guide/control mapping | Cohort C-D | No promotion for `t2v_22`, `i2v_22`, or `vace*` until guide media, frame count, dimensions, and profile-specific VRAM are in the dual-run report. |
| LTX low-RAM template selection | Cohort C | No LTX canary until the registry encodes the chosen low-RAM vs standard template policy. |
| Raw `comfy` task semantics | Cohort E | No Cohort E canary until raw workflow submission through `comfy_handler.py` preserves current first-output behavior. |

### Vendor-Utility Shims

Vendor utility ownership should be explicit rather than hidden behind `wgp_bridge.py` compatibility imports:

| Utility | Migration decision | Rationale |
| --- | --- | --- |
| RIFE temporal interpolation | Keep vendored under `reigh-worker/source/media/` and invoke from `rife_interpolate_images` outside VibeComfy. | It is a media post-processing helper, not a workflow-template concern. |
| Uni3C ControlNet | Implement as a VibeComfy patch on Wan 2.2 templates. | It affects workflow graph/control inputs and belongs near template validation. |
| Canny, Depth, Pose, Flow annotators | Run as reigh-worker pre-processing before workflow build. | They transform input media into guide assets that templates consume. |
| Qwen prompt expander | Run as reigh-worker pre-processing before workflow build. | It changes prompt text, not Comfy graph topology. |
| LoRA-key sanitizer | Implement as a VibeComfy patch over `LoraLoader` nodes. | Sanitization should travel with workflow graph validation and should be testable independent of WGP monkeypatches. |

### Dynamic Model Definitions and Model Lifecycle

Recommendation for Open Question Q1: freeze dynamic Wan2GP model definitions into VibeComfy templates and patches at build time. Wan2GP can load JSON model definitions from `Wan2GP/defaults/*` and `Wan2GP/profiles/*` through `load_missing_model_definition`, but carrying that dynamism into VibeComfy would weaken template validation and make rollback comparisons harder to reproduce.

The cutover design should use a long-lived VibeComfy `EmbeddedSession` as the analogue of the current in-process WGP backend. Model management work before cutover:

- Define which template/model packages are present in the worker image at build time.
- Define when `EmbeddedSession.reconfigure()` is allowed for profile changes, and when the worker must restart instead.
- Preserve queue-visible load/unload behavior even if the implementation becomes "select template and warm session" rather than WGP's `load_model_impl` / `unload_model_impl`.
- Keep `headless_model_management` behavior under review until Q11 decides whether any non-WGP callers require migration rather than deletion.

### Existing `source/models/comfy/` Decision

The existing Comfy code path should be refactored, not preserved as-is:

- Refactor `source/models/comfy/comfy_handler.py` to delegate execution through `vibecomfy.runtime.run_embedded` or the warm-session equivalent used by the adapter.
- Retire `source/models/comfy/comfy_utils.py`; it owns a raw `python main.py` subprocess and HTTP client that duplicates VibeComfy runtime responsibilities.
- Add `source/models/comfy/template_routing.py` as the only new file in this package.
- Migrate tests and coverage imports that currently reference `ComfyUIManager`, `ComfyUIClient`, `COMFY_PATH`, or `COMFY_PORT`.
- Preserve the current `comfy` task output contract: first downloaded output path returned to the worker completion path.

### Observability Shim

The VibeComfy adapter must translate `RunResult` from `vibecomfy/vibecomfy/runtime/session.py:35-42` into existing worker telemetry:

| `RunResult` field | Existing telemetry target | Required behavior |
| --- | --- | --- |
| `run_id` | heartbeat logs and `system_logs` | Emit as `vibecomfy.run_id` on task start, completion, and failure records. |
| `prompt_id` | Comfy/debug logs | Emit as `comfy.prompt_id` and include it in retry/debug breadcrumbs. |
| `outputs` | worker completion path | Normalize to the existing output shape for image, video, raw-Comfy, and orchestrated child tasks. |
| `metadata_path` | debug-card context | Attach to `source/core/log/debug_card.py` output when present. |
| `log_path` | debug-card and failure diagnostics | Capture and link the VibeComfy/Comfy log path in debug cards and failure system logs. |

The Comfy backend should mirror WGP's memory telemetry from `source/models/wgp/generators/output.py:182-208`: RAM, CUDA allocated/reserved/total VRAM, selected backend, template id, memory profile, and whether the run used embedded or managed-server execution. Error mapping should classify OOM, model-load, schema-validation, prompt-queue, timeout, and output-missing failures so rollback triggers can compare WGP and VibeComfy runs by error class rather than raw exception text.

## 3A. Control rails, LoRA stacking, and pre-processing — concrete recipes

Section 3 lists these as gaps; this section pins the migration recipes. Every claim cites either a Wan2GP file (current behavior) or a VibeComfy file (target mechanism).

### LoRA stacking and key sanitization

The Wan2GP path performs three LoRA-related transforms that must be reproduced under VibeComfy:

1. **Key tolerance** — `apply_lora_key_tolerance_patch` at `reigh-worker/source/models/wgp/wgp_patches.py:384-483` monkeypatches `wgp.get_loras_preprocessor` to strip keys with no recognized LoRA suffix (e.g. `diff_m`, `norm_k_img` from `lightx2v/Wan2.2-Distill-Loras`) and keys whose module path doesn't exist in the transformer. ComfyUI's native loader silently skips unrecognized keys, so a portion of the WGP behavior is already inherent to the target — but the strict module-name check (`module_name not in modules_set` at `wgp_patches.py:466`) is not.
2. **Qwen LoRA directory routing** — `apply_qwen_lora_directory_patch` at `wgp_patches.py:247-293` redirects `get_lora_dir(model_type)` to `loras_qwen/` for any Qwen model. ComfyUI uses a single `loras/` folder by convention.
3. **Multiplier parser harmonization** — `apply_lora_multiplier_parser_patch` at `wgp_patches.py:326-348` swaps the WGP parser to the 3-phase parser shared with mmgp. This is a WGP-internal concern with no Comfy equivalent.

**Target VibeComfy mechanism — chosen: pre-process the LoRA file once on disk, before the workflow runs.** Under `vibecomfy/docs/authoring.md:50-54`, decoration belongs in patches, but a sanitizer that mutates a tensor file is a **pre-process step in the reigh-worker adapter**, not a graph-level patch. The graph already references a LoRA filename via `LoraLoaderModelOnly.lora_name` widget (`edit/qwen_image_edit.py:112-116`); rewriting the file referenced by that widget is invisible to the IR.

**Why not monkeypatch `comfy.utils.load_torch_file`.** The original Section 3A draft proposed monkeypatching `comfy.utils.load_torch_file` inside `EmbeddedSession`. Three problems with that:

1. `EmbeddedSession.run` (`vibecomfy/vibecomfy/runtime/session.py:112-200`) does not expose any pre-run extension point; the monkeypatch would have to be installed by reigh-worker before `EmbeddedSession.start()` and remain global for the worker process lifetime, polluting any other call site that uses `load_torch_file` (the kj wrapper itself uses it — `ComfyUI-WanVideoWrapper/uni3c/nodes.py:5`, `nodes.py` model loaders).
2. `comfy.utils.load_torch_file` is invoked for every model load, not just LoRAs; the monkeypatch would have to inspect each call's filename to decide whether to sanitize — fragile.
3. The WGP precedent (`wgp_patches.py:384-483`) monkeypatches a WGP-internal function (`wgp.get_loras_preprocessor`), not Comfy's loader. There is no analogous narrow seam in Comfy.

**Pre-process recipe (lives in `reigh-worker/source/models/comfy/lora_sanitize.py`):**

```text
def sanitize_lora_for_comfy(src_path: Path, transformer_module_names: set[str]) -> Path:
    """Reads the LoRA safetensors file, strips keys that ComfyUI/mmgp would reject,
    writes a sanitized copy to a worker-scoped cache (e.g. /tmp/lora_sanitized/<sha>.safetensors),
    and returns the cache path. Idempotent on (src_path mtime, transformer_module_names hash)."""
    sd = load_file(src_path)                                  # safetensors.torch.load_file
    # 1) Strip keys with no recognized LoRA suffix; suffix list ports
    #    VALID_LORA_SUFFIXES from wgp_patches.py:411-419.
    # 2) Strip keys whose module path doesn't exist in transformer_module_names
    #    (matches wgp_patches.py:466 module_name not in modules_set).
    save_file(sd_clean, dst_path)
    return dst_path
```

The reigh-worker adapter resolves the LoRA path before workflow build, sanitizes once per (file × model) pair, sets `LoraLoaderModelOnly.lora_name` to the sanitized filename, and proceeds. The graph is unmodified; no monkeypatch; no custom node; no VibeComfy patch needed.

**Coverage scope (cited).** The WGP key-tolerance patch tolerates two distinct anomaly classes:

- **No recognized LoRA suffix** — keys like `diff_m`, `norm_k_img` from `lightx2v/Wan2.2-Distill-Loras` (cited in `wgp_patches.py:386-392` docstring). The valid-suffix allow-list at `wgp_patches.py:411-419` is `{".lora_down.weight", ".lora_up.weight", ".lora_A.weight", ".lora_B.weight", ".dora_scale", ".diff_b", ".diff"}`. Keys that don't end in one of these are dropped at `wgp_patches.py:460-463`.
- **Unrecognized module path** — keys whose stripped module path is not in `transformer.named_modules()` (`wgp_patches.py:466-468`). The detection requires the live transformer object to know its module-name set.

The pre-process needs the transformer module-name set, but that is available at build time: each Wan/Qwen model's full module map is deterministic per checkpoint. Ship a one-time-built `module_names_<arch>.json` next to the worker image (regeneration script under `reigh-worker/scripts/build_lora_sanitizer_modulemaps.py`), and the sanitizer becomes a pure file-level transformation with no live model required.

**Alternative (rejected): a `vibecomfy/vibecomfy/patches/lora_sanitize.py` graph-level patch.** Could splice a hypothetical `LoRAKeyStrip` custom node before each `LoraLoader*`. Rejected because (a) the custom node does not exist and would have to be authored into a new pack, growing the lockfile, and (b) it duplicates filesystem work — every run would re-strip the same keys instead of writing once and caching.

**Multiple LoRAs.** Sanitizer runs per file, before any stacking. Stacking patterns:

- ComfyUI native chain — daisy-chain `LoraLoaderModelOnly` nodes, each consuming `model` from the previous one's output 0 and setting `lora_name` and `strength_model`. Already done in `ready_templates/video/ltx2_3_t2v.py:103-115` (two LTX distilled LoRAs in series).
- WanVideoWrapper multi — `WanVideoLoraSelectMulti` (`vibecomfy/ready_templates/video/wanvideo_wrapper_22_s2v_context_window.py:60`, `wanvideo_wrapper_21_14b_t2v.py:89`, `wanvideo_wrapper_wan_animate.py:150`) accepts up to N LoRAs in a single node and feeds `WanVideoModelLoader.lora`. Adding LoRAs is a widget edit, not a topology change.

**Qwen LoRA directory.** ComfyUI's `folder_paths.get_filename_list("loras")` is the only directory of record. The migration ships a `loras_qwen/` symlink (or copies LoRAs) into the worker image's `models/loras/` so the Qwen Lightning LoRA at `Qwen-Image-Edit-Lightning-4steps-V1.0-bf16.safetensors` resolves. The directory-routing patch is **not** ported.

**Worked example — Qwen image edit with stacked style LoRA.** Task: `qwen_image_style` runs through `edit/qwen_image_edit.py`. The template already loads the Lightning LoRA at `edit/qwen_image_edit.py:112-116`. To stack a user style LoRA on top, the registry applies a `stack_lora` patch:

```text
1. Find existing LoraLoaderModelOnly node id (call it L1) by class_type.
2. Find the edge L1.0 → ModelSamplingAuraFlow.model (template line `edit/qwen_image_edit.py:132-135`).
3. Insert L2 = LoraLoaderModelOnly(lora_name=<style>, strength_model=<w>); connect L1.0 → L2.model.
4. wf.replace_edge("ModelSamplingAuraFlow.model", "L2.0").
5. Apply lora_sanitize patch (sanitizer is graph-wide so it picks up both L1 and L2).
```

The sanitizer prevents L2 from raising on non-standard keys (the Wan2GP failure mode at `wgp_patches.py:443-468`). Output of the chain is an unchanged `MODEL` handle into `ModelSamplingAuraFlow`, so downstream nodes — `CFGNorm` at `edit/qwen_image_edit.py:136-138` and onward — need no edits. This is a pure decoration, eligible to be a patch under the rule at `vibecomfy/docs/authoring.md:54`.

### Control rails: pre-process vs in-workflow

The current Wan2GP rails enter through `vendor_imports.py:91-113` (`FlowAnnotator`, `CannyVideoAnnotator`, `DepthV2VideoAnnotator`, `PoseBodyFaceVideoAnnotator`) and the Uni3C cache at `model_ops.py:234-260`. ControlNet templates exist in `ready_templates/` (`wanvideo_wrapper_22_5b_i2v_controlnet.py`, `wanvideo_wrapper_22_5b_t2v_controlnet.py`, `wanvideo_wrapper_21_14b_fun_control.py`, `wanvideo_wrapper_13b_control_lora.py`), and DepthAnythingV2 is already a node inside `wanvideo_wrapper_13b_vace.py:171-173,388-391`. Per-rail decision:

| Rail | Decision | Mechanism | Rationale |
| --- | --- | --- | --- |
| Canny | Pre-process | reigh-worker calls `CannyVideoAnnotator` (kept in `source/media/structure/preprocessors.py` per Section 3) and writes a guide video; templates accept it via `VHS_LoadVideo`. | No `CannyEdge` node-pack dependency; reuses existing reigh-worker code; rail is a guide-video, not a graph splice. |
| Depth | In-workflow when the chosen template already has it (e.g. `DepthAnything_V2` node in `wanvideo_wrapper_13b_vace.py:388-391`); pre-process otherwise. | When in-workflow: feed `VHS_LoadVideo.0` into the existing `DepthAnything_V2.images` input. When pre-process: same as Canny. | Avoid double-running depth when the template owns it; avoid forcing a depth node into templates that don't have one. |
| DWPose | Pre-process | reigh-worker calls `PoseBodyFaceVideoAnnotator`; output is a guide video. `ltx2_3_runexx_motion_transfer_dwpose.py` is the LTX-side reference for in-workflow DWPose if a future rail demands it. | DWPose model (`yolox_l.onnx` + `dw-ll_ucoco_384.onnx`) is heavy; one source of truth in reigh-worker is simpler than custom_node bring-up. |
| Optical flow | Pre-process | reigh-worker calls `FlowAnnotator` + `flow_viz` (`vendor_imports.py:91-98`); writes flow-viz frames as a guide video. | Same rationale as DWPose; no widely-adopted Comfy flow node-pack. |
| Uni3C | In-workflow patch; rely on Comfy's native model-management cache, not a reigh-worker dict | `vibecomfy/vibecomfy/patches/uni3c.py` (NEW) splices `WanVideoUni3C_ControlnetLoader` + `WanVideoUni3C_embeds` into a Wan VACE/I2V template; the loader caches its loaded weights via Comfy's `model_patcher` machinery the same way every other Comfy ControlNet does. The graph is identical run-to-run for a given session, so Comfy's smart-memory cache (controlled by `SessionConfig.cache_policy` at `vibecomfy/vibecomfy/runtime/session.py:48`) keeps the controlnet resident across runs without any reigh-worker hook. | `VibeWorkflow` is graph metadata only — no IR slot for "cached weights." Public VibeComfy surface has no `before_run` / `after_run` / model-cache hook (verified by `grep -n "before_run\|hook\|callback\|on_run" vibecomfy/vibecomfy/runtime/session.py vibecomfy/vibecomfy/workflow.py` returning zero). Therefore: do not invent a hook; piggy-back on Comfy's existing patcher cache. The reigh-worker dict approach is rejected because there is no place to attach it to `EmbeddedSession` without forking VibeComfy. |

**Why the previous "before_run hook" plan is dropped.** `EmbeddedSession.run` at `vibecomfy/vibecomfy/runtime/session.py:112-200` is a closed flow: schema-validate → `_prepare_prompt_async` → `Comfy.queue_prompt_api` → write metadata → return `RunResult`. There is no extension point. Adding one would be a VibeComfy public-API change, owned by the VibeComfy maintainer, and out of scope for this migration. The kj-wrapper's own `WanVideoUni3C_ControlnetLoader.loadmodel` at `ComfyUI-WanVideoWrapper/uni3c/nodes.py:42` produces a Comfy `model_patcher`; once Comfy has loaded a model and added it to its registry, subsequent identical loads short-circuit through the patcher's reuse path. This is exactly the cache WGP's `orchestrator._cached_uni3c_controlnet` (`model_ops.py:225,246-269`) was working around — and that workaround is unnecessary in Comfy.

**Custom-node verification — Q14 closed.** `ComfyUI-WanVideoWrapper/uni3c/nodes.py:16-149` ships two nodes that VibeComfy can call directly:

- `WanVideoUni3C_ControlnetLoader` — `INPUT_TYPES` at `uni3c/nodes.py:18-35` takes `model` (from `folder_paths.get_filename_list("controlnet")`), `base_precision`, `quantization`, `load_device`, `attention_mode`, optional `compile_args`. Returns `WANVIDEOCONTROLNET`.
- `WanVideoUni3C_embeds` — produces `UNI3C_EMBEDS` from the controlnet + reference frames.

Both are listed in `ComfyUI-WanVideoWrapper` at lockfile pin `df8f3e49daaad117cf3090cc916c83f3d001494c` (`vibecomfy/custom_nodes.lock:3`). **No reigh-worker custom-node shim is needed.** Q14 is closed: nodes exist, names verified.

**Sampler input is `uni3c_embeds`, not `controlnet`.** `WanVideoSampler.INPUT_TYPES` at `ComfyUI-WanVideoWrapper/nodes.py:2596-2638` lists `uni3c_embeds: UNI3C_EMBEDS` as an optional input (`nodes.py:2635`). The earlier IR sketch's `sampler.controlnet` slot is **wrong** — corrected below.

**IR sketch — Wan I2V + Uni3C control rail (corrected).** Starting from `ready_templates/video/wanvideo_wrapper_21_14b_i2v.py` (already loads Wan I2V via `WanVideoModelLoader` at line 85):

```text
applies_to(wf):
    return any(n.class_type == "WanVideoModelLoader" for n in wf.nodes.values()) \
       and any(n.class_type == "WanVideoSampler" for n in wf.nodes.values())

apply(wf, *, controlnet_filename, ref_video_path, strength=1.0):
    sampler_id = next(nid for nid, n in wf.nodes.items() if n.class_type == "WanVideoSampler")

    # 1. Loader: weights live in models/controlnet/ per uni3c/nodes.py:21.
    cn_loader = wf.add_node("WanVideoUni3C_ControlnetLoader",
                            widget_0=controlnet_filename,
                            widget_1="fp16",          # base_precision
                            widget_2="disabled",      # quantization
                            widget_3="main_device",   # load_device
                            widget_4="sdpa")          # attention_mode

    # 2. Reference video / frames for the embeds node.
    ref = wf.add_node("VHS_LoadVideo", widget_0=ref_video_path)

    # 3. Embeds node consumes the controlnet + ref frames; output type is UNI3C_EMBEDS.
    embeds = wf.add_node("WanVideoUni3C_embeds")
    wf.connect(f"{cn_loader.id}.0", f"{embeds.id}.controlnet")
    wf.connect(f"{ref.id}.0", f"{embeds.id}.ref_images")
    # strength widget on the embeds node (verify slot index via vibecomfy.cli inspect).

    # 4. Sampler optional input is `uni3c_embeds` per ComfyUI-WanVideoWrapper/nodes.py:2635.
    wf.connect(f"{embeds.id}.0", f"{sampler_id}.uni3c_embeds")

    return wf.finalize_metadata()
```

No metadata mark, no before-run hook, no reigh-worker cache. The patch is graph-only, exactly per `vibecomfy/docs/authoring.md:54`.

**Sprint 0 verification gate** (closes Q13 if green):

```bash
python -c "from vibecomfy.workflow import VibeWorkflow; from vibecomfy.ready_templates.video.wanvideo_wrapper_21_14b_i2v import build; \
    wf = build(); \
    from vibecomfy.vibecomfy.patches.uni3c import apply as patch; \
    out = patch(wf, controlnet_filename='uni3c.safetensors', ref_video_path='/tmp/ref.mp4'); \
    print(out.compile('api'))"
```

Pass criterion: compile produces a valid api dict with `WanVideoUni3C_ControlnetLoader` and `WanVideoUni3C_embeds` nodes, and `WanVideoSampler.inputs.uni3c_embeds` references the embeds node. If schema validation rejects `uni3c_embeds` (kj-wrapper revision drift), pin a newer commit in `custom_nodes.lock` rather than building a shim.

### Travel continuity and travel_stitch

Wan2GP travel mechanics are anchored in three files:

- `_handle_travel_segment_via_queue_impl` at `reigh-worker/source/task_handlers/tasks/task_registry.py:1298-1357` resolves segment context, generation inputs, image refs, and structure guidance, then submits a child `GenerationTask` via `task_queue.submit_task(...)` (`task_registry.py:1337-1344`) using the DB task id as the queue task id.
- `_apply_video_source_continuation` at `task_registry.py:1106-1144` writes `video_source` (path of the predecessor segment's tail) into `generation_params` and removes `image_start`. This handles both SVI and `prefix_video_source` strategies.
- `_apply_uni3c_config` at `task_registry.py:1326-1328` (called next) bolts on Uni3C parameters when `travel_guidance_config.kind in {"vace", "uni3c"}` (`travel/orchestrator.py:797`) or when structure guidance is `is_uni3c` (`travel/orchestrator.py:842-844`).

**Pinned templates.**

- Wan-family travel segment (`_derive_model_family(model_name) == "wan"` at `travel/orchestrator.py:38-49`): `ready_templates/video/wanvideo_wrapper_13b_vace.py`. Its `WanVideoVACEStartToEndFrame` node at `wanvideo_wrapper_13b_vace.py:470-475,498-504` is the seed-frame seam; `start_image` and `end_image` SetNodes at `wanvideo_wrapper_13b_vace.py:236-279` are where the per-segment first/last frames bind.
- LTX-family travel segment: `ready_templates/video/ltx2_3_runexx_first_last_frame.py`. Its widgetised first/last frame inputs are the direct LTX equivalent.

**continue_video_path / video_source flow.** When `_apply_video_source_continuation` writes `generation_params["video_source"] = <path>` (`task_registry.py:1119-1120`), the VibeComfy adapter translates that to a template patch:

```text
On the chosen Wan VACE template:
  1. Locate the VHS_LoadVideo node id that currently feeds `vhs_loadvideo_2` →
     ImageResizeKJv2 → SetNode("InputVideo") chain (wanvideo_wrapper_13b_vace.py:204-209).
  2. Set node.widgets["video"] = video_source_path (the predecessor's tail).
  3. wf.finalize_metadata() so `register_input("video_source", ...)` is emitted.
On the LTX runexx_first_last_frame template:
  1. Set the LoadImage node for `start_image` to the predecessor's last extracted frame
     (reigh-worker already extracts via `_resolve_image_references` at task_registry.py:1317).
  2. Set the LoadImage for `end_image` to the next segment's target frame.
```

**SVI vs prefix continuation.** Both strategies share the `video_source` field in WGP (`task_registry.py:1141-1147`). In VibeComfy, both translate to the same `VHS_LoadVideo.video` widget edit; the SVI-specific latent-tail upload at `task_registry.py:1356` (`_upload_svi_latent_tail_if_available`) stays in reigh-worker and is unaffected by backend choice.

**travel_stitch.** This is **NATIVE (no template)** in 1A — `source/task_handlers/travel/stitch.py:804` does ffmpeg-based concatenation with optional VLM enhancement. Backend selection is irrelevant. The only Comfy-side concern is that segment outputs come from `RunResult.outputs[0]` and match the path shape that stitch expects (`current_stitched_video_path` at `stitch.py:804`); the observability shim in Section 7 already normalizes `RunResult.outputs` to existing output-path shapes.

### Travel-segment configuration matrix

This subsection denormalizes the app-exposed travel-segment configuration surface into one row per `(model, guidance kind/mode, execution mode)` combination, then proves each cell has a concrete VibeComfy wiring. The axes are derived from the app spec at `reigh-app/src/tools/travel-between-images/modelCapabilities.ts:13-160` (three `SelectedModel` ids, per-model `supportedGuidanceModes`, `continuationByExecutionMode`, and `resolveExecutionMode` coercion at `modelCapabilities.ts:200-222`) and the worker contract at `reigh-worker/source/core/params/travel_guidance.py:13-69` (the six `_TRAVEL_GUIDANCE_KIND` values gated per-model by `_infer_allowed_kinds`). Continuity sub-cases — first-frame-only / first+last / inter-segment via `video_source` — are orthogonal to every row and resolved through the seams listed in the "continuity wiring" column. LoRA stacks are also orthogonal: `loras` (`travelBetweenImages.ts:59`), `pair_loras` (`travelBetweenImages.ts:58`), and per-phase `phase_config.phases[i].loras` (`taskTypes.ts:159`) all funnel into one of two LoRA-loader patterns named in the "LoRA wiring" column. The `model_type: "i2v"|"vace"` input field at `travelBetweenImages.ts:34` is **coerced**, not free: `resolveExecutionMode` at `modelCapabilities.ts:200-222` forces `vace` whenever guidance kind ∈ {flow,canny,depth,raw} and forces `i2v` for uni3c or LTX, so the combinations below are the full reachable set.

| # | model_family / id | exec mode | guidance kind:mode | LoRA stack | VibeComfy template | continuity wiring | control-rail wiring | LoRA wiring | disposition | verified path:line |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | wan / `wan-2.2` | i2v | none | Lightning baseline (4-LoRA cocktail) ± user `loras` | `wanvideo_wrapper_22_14b_vace_cocktail.py` (Sprint 4 NEW) | `start_image`/`end_image` SetNodes mirror `wanvideo_wrapper_13b_vace.py:236-279`; `video_source` (svi_latent_chaining) → `VHS_LoadVideo.video` widget per §3A "Travel continuity" | None | `WanVideoLoraSelectMulti` (§3A "Multiple LoRAs") | NEW (cocktail) | `modelCapabilities.ts:79-105` × `travel_guidance.py:69` × `wan_2_2_i2v_lightning_baseline_2_2_2` baseline |
| 2 | wan / `wan-2.2` | vace | vace:flow | same as #1 | same as #1 | same as #1 (continuation = guide_overlap_masked → in-graph VACE; no `video_source`) | Pre-process: `FlowAnnotator` (§3A "Control rails", `vendor_imports.py:91-98`); register guide via `VHS_LoadVideo` | same as #1 | NEW (cocktail) + ADAPT (rail) | `modelCapabilities.ts:48` × `travel_guidance.py:411-414` × `orchestrator.py:1166` |
| 3 | wan / `wan-2.2` | vace | vace:canny | same as #1 | same as #1 | same as #2 | Pre-process: `CannyVideoAnnotator` (§3A "Control rails") | same as #1 | NEW (cocktail) + ADAPT (rail) | same as #2 |
| 4 | wan / `wan-2.2` | vace | vace:depth | same as #1 | same as #1 | same as #2 | In-workflow `DepthAnything_V2` already in `wanvideo_wrapper_13b_vace.py:171-173,388-391`; mirror in cocktail template | same as #1 | NEW (cocktail) | same as #2 |
| 5 | wan / `wan-2.2` | vace | vace:raw | same as #1 | same as #1 | same as #2 | Raw guide-video passthrough → `VHS_LoadVideo` (no annotator) | same as #1 | NEW (cocktail) | `travel_guidance.py:330,411-414` |
| 6 | wan / `wan-2.2` | i2v | uni3c | same as #1 | same as #1 | `start_image`/`end_image` + svi_latent_chaining → `VHS_LoadVideo` for `video_source` | §3A "Uni3C" patch — `WanVideoUni3C_ControlnetLoader` + `WanVideoUni3C_embeds` + `WanVideoSampler.uni3c_embeds` | same as #1 | NEW (cocktail) + patch | `modelCapabilities.ts:48` × `travel_guidance.py:69,439-440` × `orchestrator.py:1326-1328` |
| 7 | ltx / `ltx-2.3` | i2v | none (only kind allowed) | LTX 2.3 distilled LoRA in template ± user `loras` | `ready_templates/video/ltx2_3_runexx_first_last_frame.py` | `start_image`/`end_image` widgets; prefix_video_source → `VHS_LoadVideo.video` widget per §3A | None | `LoraLoaderModelOnly` chain (already in template) | ADAPT | `modelCapabilities.ts:107-128` × `travel_guidance.py:65-67` (non-distilled LTX2 ⇒ `{none}` only) |
| 8 | ltx / `ltx-2.3-fast` | i2v | none | distilled-fast LoRA in template ± user `loras` | same as #7 | same as #7 | None | same as #7 | ADAPT | `modelCapabilities.ts:130-160` × `travel_guidance.py:64-66` |
| 9 | ltx / `ltx-2.3-fast` | i2v | ltx_control:video | same as #8 + auto-injected union IC-LoRA (`travel_guidance.py:30-37,305-325`) | same as #7 | same as #7 + a control reference video → `VHS_LoadVideo` (second slot) | Built into LTX 2.3 distilled controlnet path; control video is the rail itself (no preprocessor) | LTX `LoraLoaderModelOnly` chain extended by IC-LoRA injection (§3A LoRA stacking) | ADAPT | `travel_guidance.py:27,305-325,331-336` × `modelCapabilities.ts:49` |
| 10 | ltx / `ltx-2.3-fast` | i2v | ltx_control:pose | same as #9 + cameraman/pose IC-LoRA | same as #7 | same as #9 | Pre-process: `PoseBodyFaceVideoAnnotator` (§3A "Control rails"); guide via `VHS_LoadVideo` | same as #9 | ADAPT | `travel_guidance.py:27,297-303` |
| 11 | ltx / `ltx-2.3-fast` | i2v | ltx_control:depth | same as #9 | same as #7 | same as #9 | In-workflow Depth (when template carries it) or pre-process via `DepthV2VideoAnnotator` (§3A) | same as #9 | ADAPT | `travel_guidance.py:27,297-303` |
| 12 | ltx / `ltx-2.3-fast` | i2v | ltx_control:canny | same as #9 | same as #7 | same as #9 | Pre-process: `CannyVideoAnnotator` (§3A) | same as #9 | ADAPT | `travel_guidance.py:27,297-303` |
| 13 | ltx / `ltx-2.3-fast` | i2v | ltx_control:cameraman | same as #9 + cameraman IC-LoRA (`travel_guidance.py:33-37`) | same as #7 | same as #9 | Cameraman is a metadata-driven control; same `VHS_LoadVideo` slot as `ltx_control:video` | same as #9 | ADAPT | `travel_guidance.py:33-37` |

**Continuity sub-cases (orthogonal to every row).** Three are reachable from the app: (a) first-frame only — `start_image_url` set, `end_image_url` empty (`individualTravelSegment.ts:208-210`); (b) first+last — both set; (c) inter-segment chaining — `_apply_video_source_continuation` at `task_registry.py:1106-1132` writes `video_source` from the predecessor's tail. The wiring is identical for every row in the matrix: SetNode swaps for (a)/(b), `VHS_LoadVideo.video` widget edit for (c). SVI-specific latent-tail upload (`_apply_svi_specific_params` at `task_registry.py:1135-1234`) stays reigh-worker side per §3A "SVI vs prefix continuation" and is unaffected by template choice.

**LoRA-stack sub-cases (orthogonal).** Four reachable from the app, all funneled into either `WanVideoLoraSelectMulti` (Wan rows 1-6) or `LoraLoaderModelOnly` chain (LTX rows 7-13): top-level `loras` (`travelBetweenImages.ts:59`), per-pair `pair_loras` (`travelBetweenImages.ts:58`), per-phase Wan LoRAs (`taskTypes.ts:159`, Wan-only — `supportsPhaseConfig: false` for both LTX specs at `modelCapabilities.ts:122,149`), and the auto-injected IC-LoRA on rows 9-13. Sanitizer pre-process (§3A "LoRA stacking") applies to all four uniformly.

**Holes (combos with no clean mapping).**

- **Mask / inpaint on a travel segment.** `individualTravelSegment.ts` and `travelBetweenImages.ts` have no `mask`/`mask_url`/`alpha` field — `inpaint_frames` is a separate task type, already UNUSED per §0A and queued for deletion in §8A.B. **No hole**: the app cannot send a masked travel segment today. Documented as vestigial.
- **`structure_videos[]` and legacy `structure_guidance` aliases.** Both fields are accepted by the resolvers (`travelBetweenImages.ts:63-64`, `individualTravelSegment.ts:48-49`) and marked deprecated in `taskTypes.ts:205-211`; the worker contract rejects them when combined with the canonical `travel_guidance` (`travel_guidance.py:221-233`). The TODOs at `taskTypes.ts:185,196,206` confirm three writes-side fields (`chain_segments`, `structure_guidance`, `stitch_config`) are never consumed by the resolver. **Disposition: vestigial; covered by §8A.C "Stale TODOs" — promote those rows to DELETE-NOW once Q-blame check is run.**
- **`travel_guidance.kind = 'ltx_hybrid' | 'ltx_anchor'`.** Both kinds are allowed by `_infer_allowed_kinds` for distilled LTX models (`travel_guidance.py:64-66`) and have full validation paths (`travel_guidance.py:419-438`). Neither is in the LTX-fast `supportedGuidanceModes` array (`modelCapabilities.ts:49,156`), so the app cannot reach them. **Disposition: DELETE in Sprint 6 opportunistic cleanup (H7 resolution 2026-05-05; verification grep `rg -n "'ltx_hybrid'|'ltx_anchor'" reigh-app/src/` returns 0 hits). Decision rationale: maximizes success because vestigial validation surface and orchestrator branching (~250 LoC) is dead weight that complicates future work; the verification gate already passed.**
- **Wan 2.1 model family.** `_derive_model_family` at `orchestrator.py:38-49` returns "wan" for any Wan model, but the app's `MODEL_IDS` enum at `modelCapabilities.ts:4` exposes only `wan-2.2` (no `wan-2.1`). **Disposition: vestigial Wan-2.1 plumbing in worker; covered by §8A.B `vace_21` deletion row.**
- **Non-distilled `ltx-2.3` (row 7) with any guidance.** `_infer_allowed_kinds` at `travel_guidance.py:67` restricts non-distilled LTX2 to `{none}` and the spec at `modelCapabilities.ts:128` confirms `supportedGuidanceModes: []`. No hole — guidance is structurally not reachable.

**Matrix-level disposition.** All 13 rows resolve cleanly: 6 Wan rows depend on the Sprint 4 NEW Wan 2.2 VACE cocktail template (§3A "Wan 2.2 VACE cocktail — Q17 verdict"); 7 LTX rows resolve to the existing `ltx2_3_runexx_first_last_frame.py` template plus pre-processing patches and IC-LoRA injection per §3A. Zero holes block migration; four vestigial axes are flagged for §8A cleanup.

### Wan 2.2 VACE cocktail — Q17 verdict (NEW confirmed)

**Verdict: NEW required.** The kj-wrapper graph as currently shipped in `ready_templates/` cannot host the WGP `vace_14B_cocktail_2_2` cocktail via a `WanVideoModelLoader.widget_0` swap. Evidence:

| Cocktail requirement | WGP source | kj-wrapper status |
| --- | --- | --- |
| Two transformer checkpoints (HIGH + LOW noise) | `Wan2GP/defaults/vace_fun_14B_2_2.json:7-15` defines `URLs` (HIGH) + `URLs2` (LOW); `wan_2_2_vace_lightning_baseline_2_2_2.json:6-7` repeats the dual-URL pattern. | All Wan 2.2 templates load **one** model: `wanvideo_wrapper_22_5b_i2v.py:88`, `wanvideo_wrapper_22_5b_t2v_controlnet.py:100-107`, `wanvideo_wrapper_22_s2v_context_window.py:117-124`. None expose a second `WanVideoModelLoader`. |
| Phase switch at sigma threshold (`switch_threshold`, `switch_threshold2`, `model_switch_phase`) | `wan_2_2_vace_lightning_baseline_2_2_2.json:18-20` (3-phase, switch at 883/558); `vace_14B_cocktail_2_2.json:21-26` (2-phase, switch at 875). | `WanVideoSampler` at `ComfyUI-WanVideoWrapper/nodes.py:2596-2640` accepts a single `model: WANVIDEOMODEL` input; no `model_2`, `low_noise_model`, or `switch_threshold` fields. Multi-phase is only achievable by chaining two `WanVideoSampler` nodes with `samples` v2v continuation. |
| Stacked Lightning + accelerator LoRAs (CausVid, AccVid, MoviiGen, DetailEnhancer) | `vace_14B_cocktail_2_2.json:11-18` — 4 LoRAs with `loras_multipliers`. | `WanVideoLoraSelectMulti` (`wanvideo_wrapper_21_14b_t2v.py:89-101`) supports up to 5 LoRAs in one node; this part is achievable as a widget edit, no graph change. |
| 14B base for VACE | `architecture: vace_14B_2_2`, `URLs: t2v_2_2`. | `wanvideo_wrapper_13b_vace.py:228-235` loads `wan2.1_t2v_1.3B_fp16.safetensors` and a 1.3B VACE module. The 14B path requires `WanVideoVACEModelSelect.widget_0` swap to a 14B VACE module (e.g. `Wan2_2_Fun_VACE_A14B_HIGH_*`); architecturally the VACE-module slot is generic, so this part is a widget swap. |

**Why ADAPT is rejected.** Single-loader/single-sampler is hardcoded across every existing 2.x template; the wrapper's `WanVideoSampler.process` signature (`nodes.py:2645-2648`) has no model-switch parameter and no second-model input. Replicating WGP's mid-trajectory model switch requires a two-stage chain: stage 1 runs N steps on the HIGH model and emits a partial latent, stage 2 takes that as `samples` and continues on the LOW model. That is a graph topology change, which under `vibecomfy/docs/authoring.md:23` is a **new template**, not a patch.

**NEW template basis.** Author `ready_templates/video/wanvideo_wrapper_22_14b_vace_cocktail.py` based on the existing `wanvideo_wrapper_13b_vace.py` graph but with these structural changes:

```text
1. Two WanVideoModelLoader nodes:
     loader_high(model="Wan2_2_Fun_VACE_A14B_HIGH_mbf16.safetensors", vace_model=vace_14B_select.0)
     loader_low (model="Wan2_2_Fun_VACE_A14B_LOW_mbf16.safetensors",  vace_model=vace_14B_select.0)
2. WanVideoLoraSelectMulti carrying the 4 cocktail LoRAs at multipliers 1, 0.2, 0.5, 0.5
   (matching vace_14B_cocktail_2_2.json:18); fed into both loaders' lora input.
3. Two WanVideoSampler nodes per VACE branch (existing template has 3 branches):
     sampler_high.steps = floor(num_inference_steps * switch_phase_fraction)
     sampler_low.samples = sampler_high.0
     sampler_low.steps  = num_inference_steps - sampler_high.steps
4. WanVideoDecode reads from sampler_low.0.
5. Sigma cut-over computed from switch_threshold (875 for 2-phase, 883/558 for 3-phase) by
   pre-computing a sigma schedule in reigh-worker and feeding both samplers explicit `sigmas`.
```

**Sprint impact.** Sprint 4 must author one NEW template (not zero). Cohort D's `vace_22`, `inpaint_frames`, `join_clips_segment`, and Wan-family `travel_segment` are all blocked on this template. Risk row in §9 is reaffirmed; Q17 is closed as NEW. Promoted to a Sprint 4 deliverable with a named owner (VibeComfy maintainer + reigh-worker adapter author for the sigma-cut-over pre-compute).

**Sprint 0 verification gate.** Before Sprint 4 commits, run the smaller validation: `python -c "from vibecomfy.ready_templates.video.wanvideo_wrapper_13b_vace import build; w = build(); print(any('model_2' in n.inputs or 'low_noise_model' in n.inputs for n in w.nodes.values()))"` — expected `False`. If a future kj-wrapper revision adds dual-model support to `WanVideoSampler`, that command flipping to `True` is the trigger to revisit ADAPT.

### Qwen prompt expander placement

Decision: **pre-process before workflow build** in reigh-worker. Rationale:

- The expander rewrites prompt text and changes nothing about graph topology, so by the rule at `vibecomfy/docs/authoring.md:54` it is not a template / patch concern.
- The current call site is `vendor_imports.py:32-45` returning Wan2GP's `prompt_enhancer` module. The migration ports the relevant function bodies (or installs the underlying HF model directly) into `reigh-worker/source/media/vlm/` next to the existing VLM service at `source/media/vlm/service.py`.
- The expanded prompt is then written into the relevant `CLIPTextEncode` / `TextEncodeQwenImageEdit` / `WanVideoTextEncode` widget by the registry's parameter-wiring step, identical to how a user-supplied prompt is wired today.
- Sprint 5 cohort B (Qwen) gates on the pre-processed prompt being byte-equivalent to WGP's expander output for a fixed corpus; this is a reigh-worker-only test, no VibeComfy code change.

This decision aligns with Section 3's "Vendor-Utility Shims" table, which already routes Qwen prompt expansion to reigh-worker pre-processing; Section 3A pins it as the canonical answer.

## 4. Sprint-by-sprint migration plan

Each sprint is scoped to one or two weeks. The sequence is designed to retire risk incrementally: discovery freeze and shadow baselines first, then memory-profile parity, adapter wiring, dual-run comparison, cohort canary, cutover, and only then Wan2GP removal.

Critical path:

```text
Sprint 0 -> Sprint 1 -> Sprint 2 -> Sprint 3 -> Sprints 4 and 5 in parallel -> Sprint 6 -> Sprint 7 -> Sprint 8
```

| Sprint | Duration | Goals | Shippable artifacts | Exit criteria | Owner | Main risk | Rollback move |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Sprint 0: Discovery freeze and baselines | 1 week | Freeze the current task surface, profile behavior, template inventory, worker image assumptions, and benchmark matrix before any adapter changes. Establish separate production and development memory-profile baselines. **Entry gate (S2):** §12 confidence checklist signed off by named owner. **Opportunistic cleanup:** while touching `scripts/run_worker_matrix.py`, `scripts/live_test/{main,smoke}.py`, and the baseline doc, delete any §8A.B/§8A.C item whose code path the sprint is already inside (e.g. matrix rows for §0A UNUSED task types), and flag any newly-discovered cruft into §8A.C with `path:line` + verification step. | `reigh-worker/docs/migration-baselines.md` (with per-task-type effective timeout, polling cadence, payload, post-completion artifact paths per G3 lifecycle-contract test prerequisites); **`reigh-worker/scripts/dual_run_compare/migration-thresholds.yaml` per §11 (S4 single-source-of-truth thresholds)**; **`reigh-worker/scripts/dual_run_compare/golden/<task_type>/` WGP-side golden corpus** for every USED task type per §0A; `scripts/run_worker_matrix.py`; checked-in matrix inputs for `scripts/live_test/`; live task-surface inventory from `TASK_TYPE_CATALOG` plus `task_registry.py:1442-1511`; live VibeComfy template inventory using the 50-file `ready_templates/` count; **pod disk-size baseline raised to 200 GB** at `gpu_orchestrator/worker_spawner.py:279-281,391-395` (H9: WAN 14B alone fills 50 GB; dual-stack matrix needs headroom for WGP + Comfy + ready_templates models per memory note). | Baseline doc records prod profile 1 from `worker_startup.template.sh:463` and dev profile 3 from `start_worker.bat:14` plus `scripts/live_test/{main,smoke}.py:27`; every runtime task type has a baseline status of runnable, skipped-with-reason, or blocked; worker disk/startup measurements are captured at the 200 GB baseline; **`migration-thresholds.yaml` is committed and read by Sprint 3 dual-run script in a smoke run**; **golden corpus has at least one reference output per USED task type** (per §0A); **any in-flight cleanup items the sprint touched are either landed or explicitly punted with a §8A.C entry**. | `reigh-worker` with `reigh-worker-orchestrator` input | Baselines miss the prod/dev profile split, an orchestrated child-task path, or per-task-type lifecycle-contract data needed by Sprint 6 G3 unification. | Do not start Sprint 1 implementation; rerun the matrix and update the baseline doc until both profile families, both adapter seams, and per-task-type timeout/cadence are represented. |
| Sprint 1: VibeComfy memory-profile MVP | 2 weeks | **Entry gate (S2):** Sprint 0 baseline doc has prod profile 1 + dev profile 3 measurements committed; `migration-thresholds.yaml` and golden corpus committed and verified by smoke run. Implement the P0 five-tier VibeComfy memory-profile overlay and prove it maps cleanly onto existing `SessionConfig` knobs without modifying `_embedded_configuration_for_session` or `_comfy_server_argv`. **Opportunistic cleanup:** while touching `vibecomfy/vibecomfy/runtime/`, plus reigh-worker `worker_startup.template.sh:463` / `start_worker.bat:14` / `scripts/live_test/{main,smoke}.py:27`, delete any §8A.B/§8A.C item whose code path the sprint is already inside, and flag any newly-discovered cruft into §8A.C with `path:line` + verification step. | `vibecomfy.runtime.profile.MemoryProfile`; tests for `MemoryProfile.to_session_overrides()`; embedded and managed-server argv/config round-trip tests; profile smoke report for `image/z_image` and `video/wan_t2v`. | Profiles 1-5 round-trip on `image/z_image` and `video/wan_t2v`; measured VRAM peak and wall-clock are parity-or-better than `--wgp-profile {1..5}` at the Sprint 0 reference points, with explicit pass/fail for prod profile 1 and dev profile 3; **any in-flight cleanup items the sprint touched are either landed or explicitly punted with a §8A.C entry**. | `vibecomfy` | Profile mapping looks syntactically correct but misses WGP's real OOM/latency behavior under constrained cards. | Keep all `REIGH_BACKEND` defaults on WGP; tune only the overlay mapping and rerun Sprint 0 profile baselines. |
| Sprint 2: Adapter shim and existing Comfy refactor | 2 weeks | **Entry gate (S2):** Sprint 1 profile 1 + profile 3 round-trip tests green on `image/z_image` + `video/wan_t2v` per Sprint 1 exit criteria. Introduce the reigh-worker VibeComfy adapter behind a backend flag, refactor the existing `source/models/comfy/` package, and prove both queue seams can route through the Comfy backend. **Opportunistic cleanup:** while touching `source/models/comfy/`, `source/task_handlers/tasks/{task_registry.py,task_conversion.py,task_types.py}`, `source/task_handlers/queue/`, and `source/runtime/worker/server.py`, delete any §8A.B/§8A.C item whose code path the sprint is already inside (e.g. dispatch entries for §0A UNUSED task types if their handlers are clearly dead, the `comfy` task-type branch since the refactor target is empty per §8A.B), and flag any newly-discovered cruft into §8A.C with `path:line` + verification step. **Note: G3 seam-unification is owned by Sprint 6** (decision recorded 2026-05-05; see §8A.E); Sprint 2 keeps both seams alive but should avoid adding new direct/orchestrated split logic that Sprint 6 will have to undo. | `source/models/comfy/comfy_handler.py` rewritten to call `vibecomfy.runtime.run_embedded` or the warm-session equivalent; `source/models/comfy/template_routing.py`; retired `source/models/comfy/comfy_utils.py`; migrated test imports; `REIGH_BACKEND={wgp|comfy}` threaded through `_handle_direct_queue_task` and through handlers that enqueue child tasks via `context["task_queue"]`; first routes for `z_image_turbo`, `qwen_image_2512`, and `t2v`. | Feature-flagged Comfy path runs end-to-end in dev for `z_image_turbo`, `qwen_image_2512`, and `t2v`; a `travel_segment` smoke run selects `REIGH_BACKEND=comfy` and enqueues a `t2v` child through `context["task_queue"]`; WGP remains the default; **any in-flight cleanup items the sprint touched are either landed or explicitly punted with a §8A.C entry**. | `reigh-worker` | Adapter only covers direct queue tasks and silently misses nested handler-created child tasks. | Flip `REIGH_BACKEND=wgp` at process or task-type level; leave the refactored Comfy path disabled until the missing seam has a passing smoke. |
| Sprint 3: Dual-execution and comparison harness | 2 weeks | **Entry gate (S2):** Sprint 2 feature-flagged Comfy path runs `z_image_turbo`, `qwen_image_2512`, `t2v` end-to-end in dev AND a `travel_segment` Seam-B smoke selects `REIGH_BACKEND=comfy` and successfully enqueues a child. Build the nightly dual-run harness and compare WGP vs VibeComfy outputs across the Sprint 0 matrix before canary. **All comparison logic reads thresholds from §11 `migration-thresholds.yaml`** — no hard-coded numbers; threshold changes require updating the YAML. **Opportunistic cleanup:** while touching `scripts/dual_run_compare.py`, `scripts/run_worker_matrix.py`, telemetry/output-shape code in `source/models/wgp/generators/output.py:182-208` and `source/core/log/debug_card.py`, delete any §8A.B/§8A.C item whose code path the sprint is already inside (e.g. matrix-row entries for §0A UNUSED task types not in the comparison corpus), and flag any newly-discovered cruft into §8A.C with `path:line` + verification step. | `scripts/dual_run_compare.py` (reads §11 thresholds; **fails the report on any threshold breach** per §11 table); persisted comparison reports for image hash, video frame pHash, frame count, dimensions, audio length, latency, VRAM, OOM count, and error class; nightly run configuration across the Sprint 0 matrix. | **Comparison report green = every USED task type within §11 thresholds** (image pHash ≤0.05, SSIM ≥0.92; video per-frame pHash mean ≤0.08 / p95 ≤0.12; latency ≤1.10× WGP baseline; VRAM ≤1.05×; OOM count = 0); covers at least one direct image, one direct video, one edit, and one nested child-task path; all red rows are triaged as blocker, accepted-difference candidate (requires explicit user sign-off and YAML threshold widening), or not-yet-routed; **any in-flight cleanup items the sprint touched are either landed or explicitly punted with a §8A.C entry**. | `reigh-worker` with `vibecomfy` fixes as needed | Comparison accepts superficial success while output shape, duration, or memory behavior diverges. | Keep production on WGP; restrict Comfy backend to local/dev dual-run until report quality and thresholds are reviewed. |
| Sprint 3.5: Wan 2.2 VACE cocktail dry run (S1 — pre-Sprint-4 feasibility gate) | 2–3 days, parallel with late Sprint 3 | **Entry gate (S2):** Sprint 3 dual-run report green for image cohort (Cohort A) AND `migration-thresholds.yaml` checked into Sprint 0 deliverables. Author a minimal Wan 2.2 VACE cocktail template against ONE known reference output (single shot, single profile-3 dev pod), validate per-frame pHash drift hypothesis (Q18). **This is the choke-point de-risk for the entire Sprint 4 NEW-template effort.** | One reference output (Wan 2.2 VACE cocktail, default Lightning baseline LoRAs, single 49-frame shot) compared against §11 video thresholds; written `dry-run-report.md` recording per-frame pHash mean, p95, frame count, duration, and decision (PROCEED / FALL-BACK). | **PROCEED iff** per-frame pHash mean ≤0.08 AND p95 ≤0.12 AND frame count exact AND duration within ±50ms (§11 video thresholds). **FALL-BACK iff** any threshold breach: skip Sprint 4 NEW-template authoring; keep Wan VACE on WGP indefinitely (per §6 rollback); proceed with rest of migration. Either decision documented and committed. | VibeComfy maintainer + reigh-worker adapter author | Drift exceeds §11 thresholds (Q18 negative). | **PROCEED branch:** continue to Sprint 4. **FALL-BACK branch:** mark Wan-family travel/join as permanent dual-stack (WGP-only); update §5 Cohort E entry gate to exclude Wan-family rows of §3A matrix; Sprint 4 becomes 0 NEW templates; Sprint 8 Wan2GP removal scope shrinks to "remove WGP only for non-VACE WGP code" or is deferred entirely until cocktail parity is achievable upstream. |
| Sprint 4: Wan 2.2 VACE cocktail (single NEW template) | 2 weeks | **Entry gate (S2):** Sprint 3.5 dry-run decision = PROCEED (per-frame pHash drift within §11 thresholds) AND Sprint 3 dual-run image cohort green. Author the only NEW template in scope after the §0A audit: `wanvideo_wrapper_22_14b_vace_cocktail.py`, used indirectly by `travel_segment`, `join_clips_segment`, `individual_travel_segment` (their default model is `wan_2_2_vace_lightning_baseline_2_2_2`). **Hunyuan is removed from scope** (UNUSED in app, §0A). **Opportunistic cleanup:** while touching `vibecomfy/ready_templates/video/`, `source/core/params/vace.py`, `source/task_handlers/travel/`, `source/task_handlers/join/`, and any Wan/VACE-adjacent §1A row, delete any §8A.B/§8A.C item whose code path the sprint is already inside (e.g. vestigial `vace_21`/`vace_22` direct dispatch rows, `core/params/vace.py` if confirmed unreached after `task.py:32` deletion check), and flag any newly-discovered cruft into §8A.C with `path:line` + verification step. | `ready_templates/video/wanvideo_wrapper_22_14b_vace_cocktail.py`; route to it from the indirect Wan-family travel/join paths; updated dual-run corpus. | Dual-run parity is green for `travel_segment`/`join_clips_segment`/`individual_travel_segment` Wan-family Lightning-baseline output; cocktail template runnable under profiles 1-5; **any in-flight cleanup items the sprint touched are either landed or explicitly punted with a §8A.C entry**. | `vibecomfy` maintainer with `reigh-worker` adapter support | Cocktail two-stage sampler chain doesn't reproduce WGP mid-trajectory model-switch (Q18); fits in dev but fails prod profile 1. | Keep affected task types on WGP via `backend_for_task_type`; allow Sprint 5 work to continue. |
| Sprint 5: Qwen, edit-mode, and preprocessing parity | 2 weeks | **Entry gate (S2):** Sprint 3 dual-run image+edit cohorts within §11 thresholds; can proceed in parallel with Sprint 4 once Sprint 3.5 PROCEED is confirmed. Finish parity for the in-scope edit-mode tasks and move preprocessing into explicit adapter stages. **`ltxv`, `ltx2`, `flux`, and `qwen_image_hires` are removed from scope** (all UNUSED in app, §0A). **Opportunistic cleanup:** while touching `source/models/model_handlers/qwen_handler.py`, `source/models/comfy/lora_sanitize.py` (new), `source/models/wgp/wgp_patches.py:247-293,326-348,384-483` (LoRA-related patches the sanitizer replaces), `source/media/vlm/`, and `source/runtime/wgp_ports/vendor_imports.py:32-45,91-113`, delete any §8A.B/§8A.C item whose code path the sprint is already inside (e.g. `handle_qwen_image_hires` per §8A.B, vestigial preprocessing wrappers if their last consumer is being deleted), and flag any newly-discovered cruft into §8A.C with `path:line` + verification step. | Template routes and patches for `qwen_image`, `qwen_image_edit`, `qwen_image_style`, `image_inpaint`, `annotated_image_edit`; preprocessing pipeline for Qwen prompt expansion (used by `qwen_image_style`), LoRA-key sanitizer for stacked Qwen Lightning + user LoRAs. Canny/Depth/Pose/Flow preprocessing is no longer Sprint 5 critical-path (the only consumer would have been VACE/`vace_22` direct paths, which are UNUSED; the indirect Wan-family `travel_segment` keeps DepthAnythingV2 inline per §1A). | Dual-run parity is green for all remaining in-scope edit tasks; preprocessing artifacts are captured in logs and are reproducible from task inputs; output shapes match WGP; **any in-flight cleanup items the sprint touched are either landed or explicitly punted with a §8A.C entry**. | `reigh-worker` + `vibecomfy` | Preprocessing behavior drifts from WGP helpers or LoRA key sanitation changes outputs. | Keep affected task types on WGP using per-task-type backend selection; continue canary only for cohorts already green. |
| Sprint 6: Orchestrated handlers, raw-Comfy coverage, and seam unification (G3) | 2 weeks | **Entry gate (S2):** Sprint 4 cocktail template green per §11 thresholds (or PROCEED-with-fallback documented per Sprint 3.5) AND Sprint 5 Qwen/edit cohorts green AND Sprint 0 baseline doc has per-task-type lifecycle data (timeout, polling cadence, payload, post-completion artifacts) needed by the G3 contract test. Make the full in-scope task surface runnable through the Comfy backend, including parent handlers, child-task enqueue paths, media utilities, and the (now §8-deletion-bound) raw-Comfy task path. **Also unify the two-seam dispatcher per §8A.E G3** (decision: UNIFY, 2026-05-05): introduce `_handle_via_queue_task(pre_submit_hooks, post_completion_hooks, wait_timeout_s, overrides)`, fold `_handle_direct_queue_task` into it, replace `DIRECT_QUEUE_TASK_TYPES` with a per-task-type registry, and ship the lifecycle-contract test before merging. **Opportunistic cleanup:** while touching `source/task_handlers/travel/`, `source/task_handlers/join/`, `source/task_handlers/edit_video_orchestrator.py`, `source/task_handlers/tasks/task_registry.py:1442-1602` dispatch + dispatcher, and `source/core/params/{travel_guidance,structure_guidance,phase_config_parser}.py` (the four travel-side params with confirmed importers), delete any §8A.B/§8A.C item whose code path the sprint is already inside (e.g. dispatch entries for §0A UNUSED orchestrated children if their handlers are confirmed dead, vestigial `ltx_hybrid`/`ltx_anchor` branches in §8A.C once the verification grep returns 0 hits), execute the §G1 `core/params/` deletions (`task_metadata.py`, `lora_models.py`, `lora_parsing.py`, `structure_guidance_parsing.py`) and merges (`vace.py`, `generation.py`, `phase.py` → `task.py`), and flag any newly-discovered cruft into §8A.C with `path:line` + verification step. | Comfy backend support for `travel_orchestrator`, `travel_segment`, `individual_travel_segment`, `travel_stitch`, `join_clips_orchestrator`, `join_clips_segment`, `join_final_stitch`, `edit_video_orchestrator`; **unified `_handle_via_queue_task` dispatcher with per-task-type pre/post-hook + timeout registry**; **lifecycle-contract test** asserting pre-unification vs post-unification parity per USED task type; smoke tests for the unified path covering both former seams (direct + child enqueue); §G1 `core/params/` cleanup landed. (UNUSED-per-§0A handlers `inpaint_frames`, `magic_edit`, `create_visualization`, `extract_frame`, `rife_interpolate_images`, `comfy` are not migrated; deletion is owned by Sprint 8 / §8A.B.) | In-scope orchestrated task surface is runnable through the Comfy backend through the unified dispatcher; lifecycle-contract test green for every USED task type against Sprint 0 baselines (timeout, polling cadence, payload, completion artifacts); Cohort E has at least one successful parent-to-child orchestration smoke against the Sprint 4 cocktail template; runtime name `rife_interpolate_images` is preserved in any code that survives Sprint 8; §G1 deletions and merges committed with importer fix-ups; **any in-flight cleanup items the sprint touched are either landed or explicitly punted with a §8A.C entry**. | `reigh-worker` | Unified dispatcher introduces a lifecycle-contract regression (timeout, polling, payload) for direct-queue tasks that wouldn't be caught without the contract test; or orchestrated parents and child tasks choose different backends, creating mixed-output bugs. | Revert dispatcher to dual-seam (both stacks coexist until Sprint 8 anyway) and keep `_handle_direct_queue_task`; force Cohort E parent task types to `wgp`; parent handlers reject Comfy selection if any child-task route remains WGP-only or untested. |
| Sprint 7: Production canary by task-type cohort | 2 weeks | **Entry gate (S2):** Sprint 6 unified dispatcher contract test green for every USED task type AND every §3A travel-segment matrix row tested through the unified dispatcher AND **pre-staged rollback PRs (S3) drafted and rebased current** for every cohort being promoted AND per-cohort canary owner has confirmed the auto-rollback trigger wiring against §11 thresholds. Gradually promote Comfy backend in production by task-type cohort using a server-side selector read at task claim time. **Opportunistic cleanup:** while touching `reigh-worker-orchestrator/gpu_orchestrator/runpod/{worker_startup.template.sh,startup_script.py}`, the `--wgp-*` CLI flag surface in `source/runtime/worker/server.py:232-243`, and `source/core/log/{display_names.py,debug_card.py}`, delete any §8A.B/§8A.C item whose code path the sprint is already inside (e.g. dashboard label entries for §0A UNUSED task types as cohorts are flipped Comfy-only), and flag any newly-discovered cruft into §8A.C with `path:line` + verification step. **Note: the prod profile-1 vs dev profile-3 split (G4) stays intact** — both are load-bearing per §3 and Q10. | Server-side `backend_for_task_type` map; worker startup support for backend/profile flags; canary dashboard labels for backend, template id, memory profile, error class, latency, VRAM, and output divergence; **pre-staged rollback PRs in draft state per cohort, mergeable in <5 min, rebased weekly during the canary window (S3)**; **automated rollback trigger wiring** that reads §11 thresholds and flips `backend_for_task_type[<cohort>] = "wgp"` when output-divergence rate >1% over 24h OR p95 latency >1.10× baseline sustained 24h OR OOM count >0 over 1h; 48-hour hold report for each cohort. | Each cohort holds for 48 hours before the next cohort is promoted; **rollback triggers fire automatically per §11 thresholds** (output-divergence >1% over 24h, p95 latency >1.10× baseline sustained 24h, OOM count >0 over 1h); all promoted cohorts have WGP fallback still installed; **any in-flight cleanup items the sprint touched are either landed or explicitly punted with a §8A.C entry**. | `reigh-worker` + `reigh-worker-orchestrator` | Canary selector or worker startup flag applies too broadly and promotes a task family before its dependencies are ready. | Set `backend_for_task_type` entries back to WGP and/or launch workers with `REIGH_BACKEND=wgp`; both stacks remain in the image. |
| Sprint 8: Wan2GP removal + UNUSED-handler purge | 1 week | **Entry gate (S2):** Every Sprint 7 cohort has held for 48h+ at green per §11 thresholds AND post-canary stability window (≥7 days) has zero auto-rollback triggers fired AND all §8A.C AMBIGUOUS rows resolved per G8 query plan. Remove Wan2GP only after all cohorts are stable on VibeComfy and rollback no longer depends on WGP in the worker image. Bundle the §8A.B UNUSED task-type handler purge into the same removal PR(s) since they share the same dispatch deletion. **Closure sweep (not opportunistic):** Sprint 8 owns the final §8A.B/§8A.C/§8.{Removal,Option-A} sweep. By this point the per-sprint clauses above should have absorbed most §8A.C AMBIGUOUS rows once their verification grep/SQL completed; Sprint 8 handles the residual WGP-coupled items (`wgp_patches.py` whole-file delete per G2, `core/params/` 14-of-19 unimported helpers per G1, `mmgp` logger noise suppression per G5) plus anything the per-sprint clauses explicitly punted. | Final removal PRs for reigh-worker WGP roots, entrypoints, package metadata, tests, `Wan2GP/` submodule, `source/runtime/wgp_*`, `source/models/wgp/`, WGP CLI flags, orchestrator Wan2GP startup assumptions, **plus the §8A.B UNUSED handler files** (`magic_edit.py`, `inpaint_frames.py`, `extract_frame.py`, `create_visualization.py`, `models/comfy/comfy_handler.py`, `qwen_handler.handle_qwen_image_hires`, `inpaint_frames_example.py`) and their dispatch/display-name entries; final closure-sweep report. | Full Sprint 8 checklist in Section 8 (including the new "UNUSED Task-Type Handlers" subsection) is complete; pre-removal per-repo grep surfaced files have been handled; post-removal filesystem `rg` sweep has zero unexpected WGP hits excluding explicitly retained archival docs; **every §8A.C row tagged `Sprint X (per-sprint cleanup)` has either landed or has a closing comment explaining why it was deferred to 8/8B**. | `reigh-worker` + `reigh-worker-orchestrator` | Residual WGP entrypoint, dependency, startup fallback, test import, or §8A.B handler reference survives directory deletion. | Revert the removal PR or restore the last dual-stack worker image; do not delete WGP image artifacts until post-removal sweep passes. |
| Sprint 8B: Concurrent cleanup (parallel, not migration-blocking) | 0.5–1 week | Remove turbo-mode travel scaffolding (§8A.A), the duplicate `[tool.headless_wan2gp.entrypoints]` + `[tool.headless_wan2gp.deprecation]` `pyproject.toml` tables (§8A.C), and any of the AMBIGUOUS rows in §8A.C confirmed dead by their stated verification queries. Independent of canary state — can land in any sprint window from Sprint 4 onward. **Opportunistic cleanup:** while touching `reigh-app/src/tools/travel-between-images/`, `reigh-app/supabase/functions/`, `reigh-worker/pyproject.toml`, and any `legacy_*` UI scaffolding, delete any §8A.B/§8A.C item whose code path the sprint is already inside, and flag any newly-discovered cruft into §8A.C with `path:line` + verification step. | One PR per cleanup category in `reigh-app` (turbo-mode + dead toggles + AMBIGUOUS rows whose queries returned 0) and `reigh-worker` (pyproject deduplication). New Supabase migration that strips `turbo_mode`/`turboMode` JSON keys from persisted settings. | Turbo-mode references are zero across `reigh-app/src/` and `reigh-app/supabase/functions/` (`rg -n 'turbo_mode\|turboMode' → 0 hits`); `[tool.headless_wan2gp.entrypoints]` and `[tool.headless_wan2gp.deprecation]` tables removed; AMBIGUOUS rows resolved with cite-able queries; **any in-flight cleanup items the sprint touched are either landed or explicitly punted with a §8A.C entry**. | `reigh-app` (primary) + `reigh-worker` for the pyproject change | Persisted `turboMode: true` rows in legacy `travel_settings` JSON cause silent ignore vs. error during canary. | Add a migration that strips the field from `travel_settings`/`raw_settings`/`share_data` JSON columns before the resolver branch is removed; both must ship together. |

Sprint 4 and Sprint 5 may proceed in parallel only after Sprint 3 has a green-enough comparison report. Sprint 6 is the convergence point: no production canary should begin until both direct-queue parity and orchestrated-handler parity are represented in the dual-run reports.

## 5. Per-task-type cutover order

Cutover is by runtime task type, not by friendly display name. The canary selector reads a server-side `backend_for_task_type` map at task claim time, so rollback can flip a cohort or an individual task type back to WGP without changing the queue schema.

| Cohort | Risk level | Task types | Template readiness (per 1A) | Rationale | Entry gate | Promotion gate | Rollback selector |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Cohort A | Lowest: image-only and comparatively deterministic | `z_image_turbo`, `z_image_turbo_i2i`, `qwen_image`, `qwen_image_2512`, `wan_2_2_t2i` (~~`flux` removed: UNUSED per §0A~~) | NATIVE: `z_image_turbo`, `qwen_image_2512`. ADAPT: `z_image_turbo_i2i` (i2i adapter), `qwen_image` (disable edit branch), `wan_2_2_t2i` (forced `num_frames=1` patch). | These tasks have single-image output shapes, simpler completion paths, and no orchestrated child-task dependency. `wan_2_2_t2i` is included because it is a single-frame output contract even though it routes through Wan-family templates. | Sprint 2 adapter is green for `z_image_turbo`, `qwen_image_2512`, and one single-frame/Wan route; Sprint 5 resolves Qwen-specific gaps before promoting those task types. ADAPT rows must have their patches landed and tested before promotion (not just queue-seam wiring). | 48-hour canary hold with no p95 latency regression beyond threshold, no error-class spike, and output dimensions/format matching baselines. | Set each Cohort A key in `backend_for_task_type` back to `wgp`. |
| Cohort B | Medium: image edits with prompt/input preprocessing | `qwen_image_edit`, `qwen_image_style`, `image_inpaint`, `annotated_image_edit` (~~`qwen_image_hires` removed: UNUSED per §0A — hires-fix is a payload param on `qwen_image_edit`~~) | NATIVE: `qwen_image_edit`. ADAPT: `qwen_image_style` (LoRA stack + Qwen prompt expander pre-process), `image_inpaint` (mask handling), `annotated_image_edit` (annotation rasterised pre-process). | These are still image outputs, but they depend on edit-mode input handling, empty-prompt allowances, Qwen prompt behavior, masks/annotations, and LoRA/key sanitation. | Sprint 5 Qwen/edit parity is green; preprocessing artifacts and LoRA sanitizer behavior are logged and reproducible. ADAPT rows require Section 3A's `lora_sanitize` patch to be merged and the Qwen prompt expander pre-process to be byte-stable against WGP. | 48-hour canary hold per task type; compare input mask/annotation handling, output image path shape, retry class, latency, and VRAM. | Set affected edit task types in `backend_for_task_type` back to `wgp`; leave Cohort A on Comfy if stable. |
| ~~Cohort C~~ | ~~Medium-high: video generation~~ | **REMOVED FROM SCOPE** — `t2v`, `t2v_22`, `i2v`, `i2v_22`, `ltxv`, `ltx2`, `generate_video` are all UNUSED per §0A. App-side video generation routes exclusively through `travel_orchestrator` (Cohort E), not through direct video task types. | — | — | — | — | — |
| ~~Cohort D~~ | ~~High: VACE plus Hunyuan~~ | **REMOVED FROM SCOPE as direct task types** — `vace`, `vace_21`, `vace_22`, `hunyuan` are all UNUSED per §0A. The Wan 2.2 VACE cocktail **template** (Sprint 4 NEW) is still required, but it is consumed indirectly through the Cohort E travel/join paths whose default model is `wan_2_2_vace_lightning_baseline_2_2_2`. | — | — | — | — | — |
| Cohort E | Highest: orchestrated paths (the bulk of remaining migration scope) | `travel_orchestrator`, `travel_segment`, `individual_travel_segment`, `travel_stitch`, `join_clips_orchestrator`, `join_clips_segment`, `join_final_stitch`, `edit_video_orchestrator` (~~`inpaint_frames`, `magic_edit`, `create_visualization`, `extract_frame`, `rife_interpolate_images`, `comfy` removed: all UNUSED per §0A~~) | NATIVE (no template): `travel_orchestrator`, `travel_stitch`, `join_clips_orchestrator`, `join_final_stitch`, `edit_video_orchestrator`. ADAPT: `travel_segment` / `individual_travel_segment` (Wan VACE cocktail Sprint 4 NEW template, or LTX first-last-frame template, + `video_source` widget patch per Section 3A), `join_clips_segment` (Wan VACE cocktail). | These paths combine parent orchestration, nested child-task enqueueing, and completion semantics that may span several queue rows. With the §0A scope reduction, Cohort E is now the dominant migration cohort: it carries every Wan/VACE/LTX video path that production actually uses (via the `travel_orchestrator`'s `model_name` field). | Sprint 6 proves the in-scope union task surface through Comfy through the **unified `_handle_via_queue_task` dispatcher** (G3 decision: UNIFY — see §8A.E). The unified dispatcher must satisfy the lifecycle-contract test against Sprint 0 baselines for every USED task type. ADAPT rows additionally require the Section 3A travel-continuity patch (`video_source` → `VHS_LoadVideo.video` widget edit) and the LoRA sanitizer patch to be merged. The Sprint 4 NEW Wan 2.2 VACE cocktail template must be live before the Wan-family travel/join paths can canary. | Parent backend selection and child backend selection agree; **lifecycle-contract test is green for every USED task type against Sprint 0 baselines**; **every row of the §3A "Travel-segment configuration matrix" (13 rows) must produce a passing smoke through the unified dispatcher before Cohort E promotion** — not just one parent-to-child travel smoke. Smokes must cover all three continuity sub-cases (first-frame-only, first+last, inter-segment `video_source`) for at least row 1 (Wan i2v), row 4 (Wan vace:depth), row 6 (Wan uni3c), row 8 (LTX-fast none), and row 9 (LTX-fast ltx_control:video). Plus one join/edit child smoke against the Wan VACE cocktail template. | Force Cohort E parent task types to `wgp`; revert dispatcher unification to dual-seam if the contract test surfaces a regression that can't be fixed in-sprint (both stacks coexist in the worker until Sprint 8 anyway); parent handlers must reject Comfy selection if any child-task route remains WGP-only or untested. |

The selector contract is:

```text
task claim
  -> read backend_for_task_type[task_type]
  -> default to process --backend / REIGH_BACKEND
  -> dispatch through the selected backend
```

For Cohort E, the parent task's backend selection is authoritative for child generation unless a child route is explicitly blocked. That prevents mixed WGP/Comfy orchestration where the parent reports Comfy telemetry while the child is silently submitted to WGP.

## 6. Rollback plan

Rollback must stay operational until Sprint 8 starts. Before then, every Comfy canary is reversible by selection, not by rebuilding an image.

### Rollback Controls

| Control | Scope | Required behavior |
| --- | --- | --- |
| `--backend wgp|comfy` | Worker process | Process-level default set by the worker startup command. This should map to `REIGH_BACKEND={wgp|comfy}` internally. |
| `REIGH_BACKEND={wgp|comfy}` | Worker process / local dev | Environment default used by scripts, live tests, and fallback startup paths. |
| `backend_for_task_type` | Server-side task-type override | Read at task claim time. A present task-type value overrides the process default; an absent value falls back to `--backend` / `REIGH_BACKEND`. |
| Cohort rollback | Server-side selector update | Flip one cohort or individual task type back to `wgp` without changing task payloads, queue rows, or Supabase schema. |
| Worker image rollback | Orchestrator deployment | Until Sprint 8, WGP and VibeComfy both remain in the worker image, so the orchestrator can launch WGP-default workers immediately. |

The adapter scope for rollback is the same as the adapter scope for migration:

- Direct-queue seam: `_handle_direct_queue_task` -> `db_task_to_generation_task` -> backend queue submission.
- Nested-handler seam: handlers receiving `context["task_queue"]` and enqueueing child generation tasks.

If either seam cannot honor `REIGH_BACKEND` and `backend_for_task_type`, the relevant cohort remains WGP-only.

### Trigger Conditions

Rollback triggers are defined by §11 thresholds (single source of truth) and Sprint 0 baselines:

| Trigger (concrete threshold per §11) | Action |
| --- | --- |
| p95 latency >1.10× WGP baseline for a cohort, sustained 24h | **Auto-rollback:** flip cohort's `backend_for_task_type` entries back to `wgp` via the pre-staged rollback PR (S3); keep collecting Comfy shadow data if possible. |
| Error-class spike for OOM (any non-zero rate), model-load, schema-validation, prompt-queue, timeout, or missing-output (>2× baseline rate) | Roll back affected task types first via pre-staged PR; roll back full cohort if error classes cross task-family boundaries. |
| Output-divergence rate >1% over a 24h window (per-frame pHash p95 breach rate per §11) | **Auto-rollback:** stop promotion for the cohort; restore WGP for divergent task types via pre-staged PR; add examples to the dual-run corpus. |
| VRAM peak >1.05× WGP profile-1 or profile-3 baseline | Roll back affected memory profile / task family and retune `MemoryProfile.to_session_overrides()`. |
| Parent/child backend mismatch in orchestrated tasks | Roll back Cohort E immediately via pre-staged PR; block further promotion until child-task seam tests pass. |
| Worker startup or health-check regression after orchestrator flag changes | Launch workers with `REIGH_BACKEND=wgp` and revert the startup-template change that passed the Comfy default. |

### Pre-staged rollback PRs (S3)

Each cohort canary in Sprint 7 has a pre-prepared rollback PR sitting in **draft state**, mergeable in <5 minutes, that flips that cohort's `backend_for_task_type` entries back to `wgp` and reverts any cohort-specific code changes. Drafts must land before promotion, not after the trigger fires.

| Cohort | Pre-staged rollback PR | Mergeable in |
| --- | --- | --- |
| A (image-only) | Drafts `backend_for_task_type[<A task types>] = "wgp"` selector revert | < 5 min |
| B (image edits) | Drafts `backend_for_task_type[<B task types>] = "wgp"` selector revert + Qwen-edit code revert | < 5 min |
| E (orchestrated) | Drafts `backend_for_task_type[<E task types>] = "wgp"` AND drafts `_handle_via_queue_task` revert to dual-seam (G3 fallback) | < 10 min (two-PR sequence; second only needed if dispatcher regression) |

PR ownership: Sprint 7 canary owner (named at Sprint 7 kickoff). Drafts open at Sprint 7 setup; one rebase per week to keep them mergeable.

`reigh-worker-orchestrator/gpu_orchestrator/runpod/worker_startup.template.sh` must pass the selected backend/profile through the worker startup command during canary. That change is reversible until Sprint 8 because the dual-stack worker image still contains WGP.

## 7. Telemetry and observability

Telemetry must let operators compare WGP and VibeComfy runs at the same level of detail during shadow, dual-run, and canary. The goal is not a new observability system; it is a compatibility shim that makes Comfy runs show up in existing heartbeat logs, `system_logs`, and debug-card diagnostics.

### Required Labels and Fields

| Field | Applies to | Purpose |
| --- | --- | --- |
| `backend` | All task logs and status updates | Values: `wgp` or `comfy`; required for cohort dashboards and rollback filters. |
| `template_id` | Comfy/VibeComfy runs | VibeComfy ready-template id or raw `comfy` workflow route used by the task. |
| `memory_profile` | Both backends | Numeric profile 1-5 plus resolved display name; required for prod profile 1 and dev profile 3 baseline comparison. |
| `vibecomfy.run_id` | VibeComfy runs | `RunResult.run_id` from `vibecomfy/vibecomfy/runtime/session.py:35-42`; attach to start, completion, and failure logs. |
| `comfy.prompt_id` | Comfy prompt submissions | `RunResult.prompt_id`; useful for Comfy history, queue, and prompt failure lookup. |
| `metadata_path` | VibeComfy runs | `RunResult.metadata_path`; attach to debug-card context where present. |
| `log_path` | VibeComfy runs | `RunResult.log_path`; capture into `source/core/log/debug_card.py` and failure diagnostics. |

### Memory and Runtime Metrics

The Comfy path must mirror the memory-stat shape currently emitted by WGP output logging in `source/models/wgp/generators/output.py:182-208`. At minimum, each run should log:

- Host RAM used/available.
- CUDA allocated and reserved VRAM.
- Total CUDA VRAM.
- Selected backend.
- Template id.
- Memory profile 1-5.
- Embedded vs managed-server execution path.
- OOM count and error class when the run fails.

### Log Translation

| Source | Existing target | Required translation |
| --- | --- | --- |
| `RunResult.outputs` | Worker completion output path | Normalize to the existing output shape for image, video, raw-Comfy, and orchestrated child tasks. |
| `RunResult.run_id` | heartbeat logs and `system_logs` | Emit as `vibecomfy.run_id` consistently across start, success, retry, and failure paths. |
| `RunResult.prompt_id` | debug breadcrumbs and Comfy diagnostics | Emit as `comfy.prompt_id`; include in failure and timeout messages. |
| `RunResult.log_path` | `source/core/log/debug_card.py` | Add a debug-card link or path entry so support can inspect Comfy/VibeComfy logs. |
| VibeComfy validation failures | Worker retry/fail classification | Map to schema-validation or template-routing error class, not generic Python failure. |

Dual-run reports and canary dashboards should group metrics by `task_type`, `backend`, `template_id`, `memory_profile`, error class, and worker image version. Without these labels, rollback decisions will rely on raw exception text and task ids, which is too slow for production canary.

## 8. Final Wan2GP removal

Do not start this checklist until Sprint 7 canaries are stable, all promoted cohorts have completed their hold windows, and rollback no longer depends on WGP being present in the worker image. Sprint 8 is removal work, not parity work.

### Reigh-Worker Removal Checklist

| Area | Remove or migrate | Notes |
| --- | --- | --- |
| Root scripts | `reigh-worker/headless_wgp.py`; `reigh-worker/headless_model_management.py` | Delete only after Q11 confirms there are no non-WGP callers needing a VibeComfy management replacement. |
| Entrypoint shims | `reigh-worker/source/runtime/entrypoints/headless_wgp.py`; `reigh-worker/source/runtime/entrypoints/headless_model_management.py` | Remove with the root scripts and package metadata. |
| Package metadata | `reigh-worker/pyproject.toml:109`; `reigh-worker/pyproject.toml:165`; `mmgp==3.7.6`; `uv.lock` | Both `headless_wgp` console-script registrations must be removed; sync `uv.lock` after dropping `mmgp==3.7.6`. |
| Wan2GP submodule | `reigh-worker/Wan2GP/`; `.gitmodules` entry for `Wan2GP/` | Remove submodule metadata and ensure no startup code hard-fails when the directory is absent. |
| Runtime WGP packages | `reigh-worker/source/runtime/wgp_*`; full `reigh-worker/source/runtime/wgp_ports/` subtree including `wgp_bridge.py` and vendor import ports | Remove after all imports are migrated to VibeComfy adapter, media utilities, or deleted tests. |
| Model WGP packages | Full `reigh-worker/source/models/wgp/` subtree including `orchestrator.py`, `model_ops.py`, `lora_setup.py`, `wgp_patches.py`, `generators/`, and `error_extraction.py` | The VibeComfy adapter, template registry, preprocessing shims, and telemetry mapper must own all surviving behavior first. |
| Worker server WGP override block | `reigh-worker/source/runtime/worker/server.py:544-595` | Remove WGP module import, `sys.path` mutation, `mmgp` global overrides, preload setup, and WGP-specific queue construction. |
| WGP CLI flags | All `--wgp-*` flags in worker startup/server paths | Rename surviving profile selection to `--vibecomfy-profile` or move it to env/config; do not leave inert WGP flags. |
| Existing Comfy refactor residue | `reigh-worker/source/models/comfy/comfy_utils.py` | This should already be retired in Sprint 2; verify it is removed and no tests import it. |

### WGP Test Suite Removal

Remove or migrate all seven WGP-specific test files:

- `reigh-worker/tests/test_wgp_bridge_contracts.py`
- `reigh-worker/tests/test_wgp_bridge_ports_contracts.py`
- `reigh-worker/tests/test_wgp_init_bootstrap_contracts.py`
- `reigh-worker/tests/test_wgp_output_contracts.py`
- `reigh-worker/tests/test_wgp_params_overrides.py`
- `reigh-worker/tests/test_wgp_patch_context_contracts.py`
- `reigh-worker/tests/test_wgp_patch_lifecycle.py`

Also remove or migrate any architecture and coverage tests that import retired WGP surfaces. The mandatory pre-Sprint-8 per-repo grep sweep in Section 10 is the source for any additional files not listed here.

### Reigh-Worker-Orchestrator Removal Checklist

| Area | Remove or migrate | Notes |
| --- | --- | --- |
| Worker directory fallback | `reigh-worker-orchestrator/gpu_orchestrator/runpod/worker_startup.template.sh:174` and `179-183` | Remove `FALLBACK_DIR="$WORKSPACE_DIR/Headless-Wan2GP"` and the `elif [ -d "$FALLBACK_DIR" ]` fallback branch. |
| Wan2GP submodule reconciliation | `worker_startup.template.sh:267-292` | Remove the stale-clone removal block at `267-277` and the missing-submodule hard fail at `284-292`. |
| Production profile flag | `worker_startup.template.sh:463` | Change `--wgp-profile 1` to `--vibecomfy-profile 1`, or remove it if profile selection has moved to env/config. |
| RunPod startup discovery snippet | `reigh-worker-orchestrator/gpu_orchestrator/runpod/startup_script.py` | `_WORKDIR_DISCOVERY_SNIPPET` embeds `Headless-Wan2GP`; remove that fallback discovery. The snippet is consumed by `build_launch_command`, `build_log_retrieval_command`, and `build_startup_status_check_command`. |
| Dockerfile | `reigh-worker-orchestrator/gpu_orchestrator/Dockerfile` | Verify and remove any Wan2GP install steps if present; current main may be generic and need no edit. |
| Python requirements | `requirements.txt`; `requirements-dev.txt` | Drop any `mmgp` dependency if present directly or transitively through orchestrator tooling. |
| Environment examples | env-example files and deployment docs | Replace WGP backend/profile variables with VibeComfy backend/profile variables. |

### Removal Exit Criteria

- Both reigh-worker and reigh-worker-orchestrator build without `Wan2GP/`, `mmgp`, WGP entrypoints, or WGP tests.
- Worker startup succeeds without `Headless-Wan2GP` fallback discovery.
- `--vibecomfy-profile` or its env/config replacement preserves profile 1 production default semantics.
- Post-removal closure sweep has zero unexpected WGP hits, excluding this migration document and explicitly retained archival docs.
- Last dual-stack image remains restorable until the post-removal production smoke has passed.

### UNUSED Task-Type Handlers (per §8A.B)

Per §0A and §8A.B, the following task types are unused by the production app and their handlers are dead from the app's perspective. They are deleted in Sprint 8 alongside the WGP runtime. See §8A.B for the full per-task-type breakdown including dispatch entries, display-name entries, tests to update, and external-consumer verification.

Handler files to delete:

- `reigh-worker/source/task_handlers/magic_edit.py`
- `reigh-worker/source/task_handlers/inpaint_frames.py`
- `reigh-worker/source/task_handlers/extract_frame.py`
- `reigh-worker/source/task_handlers/create_visualization.py`
- `reigh-worker/source/models/comfy/comfy_handler.py` (in addition to `comfy_utils.py` already listed above)
- `reigh-worker/source/models/model_handlers/qwen_handler.py:536-575` — `handle_qwen_image_hires` method (file itself stays for `handle_qwen_image_edit`/`handle_qwen_image_2512`/`handle_qwen_image_style`/`handle_image_inpaint`/`handle_annotated_image_edit`)
- `reigh-worker/source/task_handlers/tasks/task_conversion.py:127-128` — `qwen_image_hires` branch
- `reigh-worker/source/task_handlers/tasks/dispatch_manifest.py:5` — `extract_frame` manifest entry
- `reigh-worker/source/task_handlers/tasks/specialized_dispatch.py` — **DELETE-NOW (Sprint 8) per H10 resolution 2026-05-05.** Entire module deleted after §8 `task_registry.py` deletion absorbs its remaining role; the `extract_frame` dispatch branch at `:32-34,93-109` was its only non-trivial content. Decision rationale: maximizes success because hedging "consider deleting" leaves a 100-LoC dead module in the codebase post-cutover; the §8 task_registry deletion already absorbs its role, so the deletion is mechanical.
- `reigh-worker/examples/inpaint_frames_example.py`

Tests to update or delete:

- `reigh-worker/tests/test_task_result_handler_contracts.py` — drop `magic_edit` and `inpaint_frames` imports and tests (file may become empty after; delete if so).
- `reigh-worker/tests/test_lifecycle.py:95,145` — replace `"magic_edit"` literals with `"qwen_image_edit"`.
- `reigh-worker/tests/test_examples_cli.py` — references `examples.inpaint_frames_example`; delete the file if the only surviving example is `join_clips_example.py` and a slimmer test exists.
- `reigh-worker/tests/test_specialized_dispatch_contracts.py:63-110` — delete the two `extract_frame` tests.
- `reigh-worker/tests/test_task_type_catalog.py` — drop rows for every task type listed in §8A.B.
- `reigh-worker/tests/test_display_names.py` — drop assertions for deleted entries.
- `reigh-worker/source/task_handlers/__init__.py:12-15` and `source/utils/orchestrator_utils.py:20` — drop docstring lines referencing the deleted handlers.

The display_names entries to remove from `reigh-worker/source/core/log/display_names.py` (in both `TASK_TYPE_LABELS` and `_TASK_TYPE_SHORT_NAMES`):

`hunyuan`, `flux`, `t2v`, `t2v_22`, `i2v`, `i2v_22`, `vace`, `vace_21`, `vace_22`, `ltxv`, `ltx2`, `generate_video`, `qwen_image_hires`, `magic_edit`, `inpaint_frames`, `comfy`, `extract_frame`, `rife_interpolate`, `rife_interpolate_images`. (`create_visualization` already has no entry.)

### Option A Sweep-Surfaced Additions

The T9 pre-Sprint-8 Option A sweep surfaced the following committed paths outside the broad WGP package/root-script checklist above. Sprint 8 must classify each path as delete, migrate, or retained archive before closure. Retained archival paths are allowed to keep historical WGP references only if they stay listed here and are excluded from the post-deletion zero-hit assertion in Section 10.

Additional `reigh-worker` delete/migrate candidates:

- `reigh-worker/.github/workflows/wan2gp-drift.yml`
- `reigh-worker/.gitignore`
- `reigh-worker/README.md`
- `reigh-worker/STRUCTURE.md`
- `reigh-worker/requirements.txt`
- `reigh-worker/start_worker.bat`
- `reigh-worker/preview_drive_selector.py`
- `reigh-worker/examples/inpaint_frames_example.py`
- `reigh-worker/examples/join_clips_example.py`
- `reigh-worker/scripts/live_test/{launch_command.py,main.py,smoke.py,stage1_findings.md,variant_fresh.py,variant_update.py}`
- `reigh-worker/scripts/live_test/tests/test_primitives.py`
- `reigh-worker/scripts/preview/{run_preview.py,wgp_spoof.py}`
- `reigh-worker/scripts/run_worker_matrix.py`
- `reigh-worker/source/__init__.py`
- `reigh-worker/source/core/log/{core.py,display_names.py,safe.py}`
- `reigh-worker/source/core/params/{__init__.py,base.py,generation.py,lora.py,phase.py,phase_config.py,phase_config_parser.py,structure_guidance.py,task.py,task_metadata.py,travel_guidance.py,vace.py}`
- `reigh-worker/source/core/runtime_paths.py`
- `reigh-worker/source/media/structure/{compositing.py,download.py,generation.py,loading.py,preprocessors.py}`
- `reigh-worker/source/media/video/{hires_utils.py,travel_guide.py}`
- `reigh-worker/source/media/vlm/{service.py,single_image_prompts.py,transition_prompts.py}`
- `reigh-worker/source/models/lora/{lora_paths.py,lora_utils.py}`
- `reigh-worker/source/models/model_handlers/qwen_handler.py`
- `reigh-worker/source/runtime/__init__.py`
- `reigh-worker/source/runtime/worker/{bootstrap_gate.py,postprocess.py}`
- `reigh-worker/source/task_handlers/join/vlm_enhancement.py`
- `reigh-worker/source/task_handlers/orchestration/finalization_service.py`
- `reigh-worker/source/task_handlers/queue/{bootstrap_gate.py,download_ops.py,memory_cleanup.py,queue_lifecycle.py,task_processor.py,task_queue.py,wgp_init.py}`
- `reigh-worker/source/task_handlers/rife_interpolate.py`
- `reigh-worker/source/task_handlers/tasks/{task_conversion.py,task_registry.py,task_types.py}`
- `reigh-worker/source/task_handlers/travel/{chaining.py,orchestrator.py}`
- `reigh-worker/source/utils/{frame_utils.py,resolution_utils.py}`
- `reigh-worker/tests/{test_additional_coverage_modules.py,test_clear_conditioning_byte_identity.py,test_join_orchestrator_loop_reverse.py,test_lora_flow.py,test_lora_formats_baseline.py,test_ltx_hybrid_travel.py,test_pose_preprocessor.py,test_runtime_model_patch_contracts.py,test_travel_guidance_config.py}`

Additional `reigh-worker` archival paths surfaced by the sweep. Keep only if they are intentionally historical; otherwise migrate/delete them with the candidates above:

- `reigh-worker/artifacts/worker-matrix/20260316T*/{traceback.txt,rerun_failed.sh,summary.md}`
- `reigh-worker/docs/{KIJAI_SVI_IMPLEMENTATION.md,LTX_MULTI_FRAME_TRAVEL.md,ORIGINAL_SVI_APPROACH.md,SVI_END_FRAME.md,SVI_IMPLEMENTATION.md,WAN2GP_FORK_MIGRATION_PLAN.md,wan2gp-rebase-runbook.md,wan2gp-triage.csv,worker-matrix-runner.md}`
- `reigh-worker/docs/wan2gp-migration-history/**`
- `reigh-worker/scripts/sprint3/capture_clear_conditioning_fixture.py`
- `reigh-worker/scripts/sprint4/{patch_lifecycle_smoke.py,upstream_prs/*.md}`

Additional `reigh-worker-orchestrator` paths surfaced by the sweep:

- `reigh-worker-orchestrator/scripts/ssh_to_worker.py` - migrate/delete WGP workdir assumptions.
- `reigh-worker-orchestrator/tests/gpu_orchestrator/runpod/test_startup_script.py` - migrate expected startup-script text away from `Headless-Wan2GP`.
- `reigh-worker-orchestrator/.megaplan/plans/add-a-sentinel-skip-20260428-0103/state.json` - retain only as generated planning archive, or delete if planning artifacts are not meant to remain in the repo.

## 8A. Bundled cleanup scope (cruft & dead code)

This section captures cruft surfaced during the §0A audit follow-up, plus a parallel audit of feature flags, dead handler files, and stale UI scaffolding. These deletions ride along with the migration: they don't unblock cutover, but Sprint 7→8 is the moment to remove them rather than carry them forward into the post-migration codebase.

Two streams:

- **Sprint 8 (migration-coupled):** UNUSED Wan2GP-task-type handlers and their support code. Enumerated below; cross-reference to §8 deletion checklist.
- **Sprint 8B (concurrent cleanup, not gated on migration):** Turbo-mode travel removal, dead UI/feature-flag scaffolding, and other non-WGP cruft. Independent of canary state; can be PR'd at any point during Sprints 4–8.

### A. Turbo-mode travel removal

`reigh-app/supabase/functions/create-task/resolvers/travelBetweenImages.ts:314-315` writes `task_type: "wan_2_2_i2v"` when `input.turbo_mode === true`. The worker's `TASK_TYPE_TO_MODEL` (`reigh-worker/source/task_handlers/tasks/task_types.py:82-117`) and `task_registry.py:1442-1511` both omit this string — `rg -n 'wan_2_2_i2v\b' reigh-worker/source/ → 0 hits`. Any task carrying that type would fail on dispatch.

The UI surface that would emit `turbo_mode === true` is **already disabled**: the toggle is commented out at `reigh-app/src/tools/travel-between-images/components/BatchSettingsForm.tsx:532-556` ("Turbo Mode Toggle - DISABLED - keeping code for potential future use"). Grep for places that *set* the boolean to true (excluding tests) returns zero hits in `reigh-app/src/`. Settings default is `false` (`settings.ts:182`). The remaining `turboMode` plumbing exists only to read-as-`false`, gate UI affordances against it, and route into the dead `wan_2_2_i2v` branch.

**Disposition: DELETE-NOW (Sprint 8B).** Eliminate the dead toggle and the task-type branch in one cleanup PR.

Files to edit (cite `path:line`):

| File | Change |
| --- | --- |
| `reigh-app/supabase/functions/create-task/resolvers/travelBetweenImages.ts:314-315` | Remove `isTurboMode` and ternary; emit `task_type: "travel_orchestrator"` directly. |
| `reigh-app/supabase/functions/create-task/resolvers/travelBetweenImages.ts:40` | Remove `turbo_mode?: boolean` from input type. |
| `reigh-app/src/shared/lib/tasks/travelBetweenImages/taskTypes.ts:132,169` | Remove `turbo_mode` field from `TravelBetweenImagesTaskInput` and request payload. |
| `reigh-app/src/tools/travel-between-images/settings.ts:86,182,392` | Remove `turboMode` from `MotionSettings` type, defaults, and parser. |
| `reigh-app/src/tools/travel-between-images/modelCapabilities.ts:24,93,121,148` | Remove `ui.turboMode: boolean` from `ModelSpec` and per-model spec entries. |
| `reigh-app/src/tools/travel-between-images/components/BatchSettingsForm.tsx:75-76,123,380,532-556,581-582` | Remove `turboMode`/`onTurboModeChange` props and the commented disabled-toggle block; remove `!turboMode &&` and `disabled={turboMode}` gating. |
| `reigh-app/src/tools/travel-between-images/components/MotionControl.tsx:53,87,93,104` | Remove `turboMode` from `stateOverrides`, the early-return guard in `handleModeChange`, and the `disabled={turboMode}` on the Advanced tab trigger. |
| `reigh-app/src/tools/travel-between-images/components/MotionControl.types.ts:49` | Remove from `stateOverrides`. |
| `reigh-app/src/tools/travel-between-images/components/VideoGenerationModalSections.tsx:215-216,281` | Remove `turboMode`/`onTurboModeChange` props passed to `BatchSettingsForm` and `MotionControl`. |
| `reigh-app/src/tools/travel-between-images/components/SharedGenerationView.tsx:83,208,330` | Drop `turboMode` derivation and prop pass-through. |
| `reigh-app/src/tools/travel-between-images/providers/VideoTravelSettingsProvider.tsx:232-234,461,468` | Remove `turboMode` from spec-driven settings reset, `motionSettings`, and dependency array. |
| `reigh-app/src/tools/travel-between-images/hooks/settings/useVideoTravelSettingsHandlers.ts:220,225,303` | Drop `handleTurboModeChange` and the `turboMode + advanced` gating. |
| `reigh-app/src/tools/travel-between-images/pages/ShotEditorView.tsx:285,290-297` | Remove the `turboMode` destructure and the two effects (cloud-disable + advanced-mode reset). |
| `reigh-app/src/tools/travel-between-images/components/ShotEditor/services/applySettings/{taskDataService.ts:159,generationSettingsService.ts:166-167,types.ts:52}` | Drop applySettings turbo plumbing. |
| `reigh-app/src/tools/travel-between-images/components/ShotEditor/services/generateVideoService.ts:408,446` | Remove `turboMode: modelConfig.turbo_mode` and the request-body override. |
| `reigh-app/src/tools/travel-between-images/components/ShotEditor/services/generateVideo/{requestBody.ts:67,130,types.ts:121}` | Remove `turboMode`/`turbo_mode` field from request body. |
| `reigh-app/src/tools/travel-between-images/components/ShotEditor/controllers/{useGenerationController.ts:42,158,208,useGenerationControllerInputModel.ts:28,139,177}` | Drop `turboMode` from controller input model. |
| `reigh-app/src/tools/travel-between-images/components/ShotEditor/hooks/actions/useSteerableMotionHandlers.ts:24,51` | Drop from action handler input. |
| `reigh-app/src/tools/travel-between-images/components/hooks/useBatchVideoGeneration.ts:139` | Stop passing `turbo_mode: settings.turboMode \|\| false`. |
| `reigh-app/supabase/functions/ai-timeline-agent/tool-schemas.ts:303-306` | Delete `turbo_mode` JSON schema property and description. |
| `reigh-app/supabase/functions/ai-timeline-agent/tools/create-task.ts:507` | Drop `turbo_mode: typeof args.turbo_mode === "boolean" ? args.turbo_mode : travelContext?.turboMode`. |
| `reigh-app/supabase/functions/ai-timeline-agent/{db.ts:513,types.ts:155,tools/loras.ts:26}` | Remove `turboMode` from agent settings type, db parser default, and lora-tool default. |
| `reigh-app/supabase/migrations/*` (`20260118000001`, `20260104000002`, `20260105000001`, `20260128000002`-`20260128000006`) | Either leave existing migrations untouched (already applied) and add a new `2026MMDDHHMMSS_drop_turbo_mode.sql` migration that strips the key from `travel_settings`/`raw_settings`/`share_data` JSON columns, OR document them as historical-only. **Recommended: write a new migration; do not edit applied ones.** |
| Tests (`MotionControl.test.tsx`, `requestBody.test.ts`, `generateVideoService.test.ts`, `useGenerationController.test.tsx`, `VideoTravelSettingsProvider.test.tsx`, `index.test.tsx`, `BatchModeContent.test.tsx`, `useBatchVideoGeneration.test.tsx`, `useVideoGenerationModalController.test.tsx`, `useGenerationControllerInputModel.test.tsx`, `useGenerateBatch.ts`, `useShotEditorController.ts`) | Drop turbo assertions; rewrite scenarios that depended on `turboMode: true` to exercise the surviving non-turbo path. |

**Worker-side residue:** none — `rg -n 'turbo_mode\|turboMode' reigh-worker/source/ → 0 hits`. Worker already ignores the field.

**Estimated volume:** ~50 files touched; ~250 LoC removed (most files have 1–3 turbo touchpoints).

### A.1 — Server-side `model_type` validation (H8: 2026-05-05)

The frontend coerces `model_type ∈ {"i2v", "vace"}` via `resolveExecutionMode` at `reigh-app/src/tools/travel-between-images/modelCapabilities.ts:200-222` so the value reaching the resolver is always in `supportedGuidanceModes`. The resolver `reigh-app/supabase/functions/create-task/resolvers/travelBetweenImages.ts:34` passes it through raw — server-side validation is implicit-trust on a coerced client value, which is a contract bug.

**Disposition: DELETE-NOW (Sprint 8B): add server-side `model_type` validation in `travelBetweenImages.ts` resolver.** Reject `model_type` values not in the per-`model_id` `supportedGuidanceModes` set with a typed error. Same change applies to `individualTravelSegment.ts` resolver if it accepts `model_type`. Tests must cover (a) coerced valid values pass through unchanged, (b) explicit invalid values are rejected with a descriptive error, (c) missing `model_type` is rejected when the model requires one.

**Decision rationale (H8): maximizes success because trusting a client-side coercion server-side is a footgun for any future caller (AI agent, third-party integration, manual API user) that bypasses the UI; one short PR closes the contract gap before cutover.**

### B. UNUSED Wan2GP-task-type handler removal (Sprint 8)

These rows live in §8 because they belong with the WGP removal: deleting `task_handlers/tasks/task_types.py` and `task_registry.py` (already on the §8 sweep list) drops most of the dispatch entries automatically. The work captured here is the **handler files and their tests** that survive the dispatch-table deletion.

Note on default-JSON files: the entire `reigh-worker/Wan2GP/` submodule is deleted in Sprint 8 (§8 row "Wan2GP submodule"), so per-task-type model defaults under `Wan2GP/defaults/*.json` need no separate enumeration.

| task_type | Handler file(s) to delete | Dispatch entries to remove (in addition to §8 wholesale `task_registry.py` deletion) | display_names entries | Tests to update | external consumers (verified absent) | Disposition |
| --- | --- | --- | --- | --- | --- | --- |
| `hunyuan` | none (direct-queue, lives in `task_types.py` only — deleted by §8) | `task_types.py:36,99-101` | `display_names.py:15,55` | `test_task_type_catalog.py` (drop `hunyuan` row); `test_display_names.py` (drop label assertion if any) | `rg -i '\bhunyuan\|\bhyvid' reigh-worker/source/ → matches in `Wan2GP/` only`; `rg -n 'hunyuan' reigh-worker/scripts/ reigh-worker/examples/ → 0 hits` | DELETE-NOW (Sprint 8) |
| `flux` | none | `task_types.py:30,57-58,93-94` | `display_names.py:13,53` | `test_task_type_catalog.py` | `rg -n '"flux"\|task_type.*flux\b' reigh-worker/source/ → 0 hits outside Wan2GP submodule` | DELETE-NOW (Sprint 8) |
| `t2v`, `t2v_22` | none | `task_types.py:32,59-60,84,91-92` | `display_names.py:35-36,75-76` | `test_task_type_catalog.py` | `rg -n 'task_type.*"t2v"\|task_type.*"t2v_22"' reigh-worker/source/ → 0 hits` | DELETE-NOW (Sprint 8) |
| `i2v`, `i2v_22` | none | `task_types.py:34,61-62,95-97` | `display_names.py:16-17,56-57` | `test_task_type_catalog.py` | `rg -n 'task_type.*"i2v"\|task_type.*"i2v_22"' reigh-worker/source/ → 0 hits` | DELETE-NOW (Sprint 8) |
| `vace`, `vace_21`, `vace_22` | none (the templates remain via §1A indirect Wan-VACE-cocktail use) | `task_types.py:28,55-56,86-88` | `display_names.py:40-42,80-82` | `test_task_type_catalog.py` | `rg -n 'task_type.*"vace"\|task_type.*"vace_2[12]"' reigh-worker/source/ → 0 hits`; `'vace'` appears as `model_type` enum, not `task_type`. | DELETE-NOW (Sprint 8) |
| `ltxv`, `ltx2` | none | `task_types.py:36,64,100-101` | `display_names.py:25-26,65-66` | `test_task_type_catalog.py` | `rg -n 'task_type.*"ltxv"\|task_type.*"ltx2"' reigh-worker/source/ → 0 hits` | DELETE-NOW (Sprint 8) |
| `generate_video` | none | `task_types.py:42,66,84` | `display_names.py:14,54` | `test_task_type_catalog.py` | none | DELETE-NOW (Sprint 8) |
| `qwen_image_hires` | `source/models/model_handlers/qwen_handler.py:536-575` (`handle_qwen_image_hires` method); `source/task_handlers/tasks/task_conversion.py:127-128` (the `elif task_type == "qwen_image_hires"` branch) | `task_types.py:107,127` | `display_names.py:31,71` | `test_qwen_handler*` if any reference hires; `test_task_type_catalog.py` | `rg -n 'qwen_image_hires\|handle_qwen_image_hires' reigh-worker/ → only the listed sites and Wan2GP/__init__.py` | DELETE-NOW (Sprint 8) |
| `magic_edit` | **`source/task_handlers/magic_edit.py`** (226 LoC) | `task_registry.py:52,1469-1472` | `display_names.py:27,67` | `tests/test_task_result_handler_contracts.py:7,12-25` (`test_magic_edit_handler_returns_task_result_on_env_failure` — DELETE entire test); `tests/test_lifecycle.py:95,145` (replace `"magic_edit"` literals with another task_type still in the catalog, e.g. `"qwen_image_edit"`); `source/utils/orchestrator_utils.py:20` (docstring reference — drop). Also `source/task_handlers/__init__.py:12` docstring | none — Replicate Flux Kontext path is reachable only via this handler; `rg -n 'flux-kontext-dev-lora' reigh-worker/ → 1 hit (handler itself)` | DELETE-NOW (Sprint 8) |
| `inpaint_frames` | **`source/task_handlers/inpaint_frames.py`** (327 LoC); **`examples/inpaint_frames_example.py`** (and `_common.py` if no longer referenced) | `task_registry.py:57,1492-1496`; `task_types.py:41,104` | `display_names.py:20,60` | `tests/test_task_result_handler_contracts.py:9,26+` (drop `inpaint_frames` import + test); `tests/test_examples_cli.py:17-100` (entire file references `examples.inpaint_frames_example` — DELETE if it only covers this and join_clips_example) | none — handler only invoked via dispatch | DELETE-NOW (Sprint 8) |
| `comfy` | `source/models/comfy/comfy_handler.py` (191 LoC); `source/models/comfy/comfy_utils.py` (199 LoC) — note: §8 already lists `comfy_utils.py` for retire; this entry adds `comfy_handler.py`. Sprint 2 was originally to *refactor* `comfy_handler.py` into a VibeComfy delegator (per §8 row "Existing Comfy refactor residue" and Q9). With §0A confirming `task_type: "comfy"` is unemitted by the app, the refactor target is now empty — delete instead. | `task_registry.py:1507-1510` | `display_names.py:10,50` | any test importing `source.models.comfy.comfy_handler` | none — `rg -n 'task_type.*"comfy"' reigh-app/ → 0 hits`; raw-Comfy is not enqueued | DELETE-NOW (Sprint 8). Closes Q9: deprecation path was "preserve via VibeComfy delegation"; updated path is "delete." |
| `create_visualization` | **`source/task_handlers/create_visualization.py`** (140 LoC) | `task_registry.py:58,1497-1500` | none in `display_names.py` (no entry); `_TASK_TYPE_SHORT_NAMES` has no entry either — both already absent. Verify: `grep -n 'create_visualization' source/core/log/display_names.py → 0 hits` | grep tests for `create_visualization` import | none. Handler is debug-only | DELETE-NOW (Sprint 8) |
| `extract_frame` | **`source/task_handlers/extract_frame.py`** (80 LoC) | `task_registry.py:47,1501-1503`; `task_handlers/tasks/dispatch_manifest.py:5`; `task_handlers/tasks/specialized_dispatch.py:32-34,93-109` (`extract_frame` branch and its dispatcher tests) | `display_names.py:12,52` | `tests/test_specialized_dispatch_contracts.py:63-110` (two tests are extract_frame-specific — DELETE both); `tests/test_task_dispatch_manifest_contracts.py` if it asserts the manifest contains `extract_frame` | none — app uses `generate-thumbnail` edge function (§0A row) | DELETE-NOW (Sprint 8) |
| `rife_interpolate_images` | **handler wrapper only**: `source/task_handlers/rife_interpolate.py` (113 LoC). **DO NOT delete** the underlying `rife_interpolate_images_to_video` helper at `source/media/video/travel_guide.py:38` — still used by `source/task_handlers/travel/api.py:20-21` and `source/task_handlers/travel/guidance/guide_video_ops.py:12-60`. | `task_registry.py:48,1504-1506` | `display_names.py:33-34,73-74` (both `rife_interpolate` alias and `rife_interpolate_images` runtime entries can be deleted) | none specific (verify `test_travel_api_wrappers.py` tests the helper, not the dispatch handler) | none | DELETE-NOW (Sprint 8) — keep RIFE helper. |

**Sprint 8 §8 cross-reference:** the §8 "Option A Sweep-Surfaced Additions" already covers `rife_interpolate.py`, `task_conversion.py`, `task_registry.py`, `task_types.py` (full file deletions). This table adds: `magic_edit.py`, `inpaint_frames.py`, `extract_frame.py`, `create_visualization.py`, `models/comfy/comfy_handler.py` to the deletion enumeration.

**Estimated volume:** ~5 handler files × avg 175 LoC + 1 example file + 4 dead test functions ≈ ~1,000 LoC removed; ~6 files deleted outright.

### C. Additional cruft

| Category | path:line | Evidence of deadness | Disposition | Verification step (for AMBIGUOUS) |
| --- | --- | --- | --- | --- |
| Dead UI block (commented) | `reigh-app/src/tools/travel-between-images/components/BatchSettingsForm.tsx:532-556` | "DISABLED - keeping code for potential future use" — 25-line commented-out toggle. With §8A.A removing turbo_mode entirely, future-use is gone. | DELETE-NOW (Sprint 8B) — covered by §8A.A. | — |
| Duplicate console-script registrations | `reigh-worker/pyproject.toml:104-109` AND `reigh-worker/pyproject.toml:160-165` | The `[tool.headless_wan2gp.entrypoints]` table at 160-165 mirrors `[project.scripts]` at 104-109 verbatim for ALL 5 entries (worker, run_worker, heartbeat_guardian, headless_model_management, headless_wgp), not just `headless_wgp` as Q12 suggests. The `[tool.headless_wan2gp.entrypoints]` table has no consumer (`rg -n 'tool.headless_wan2gp.entrypoints\|headless_wan2gp.entrypoints' reigh-worker/ reigh-worker-orchestrator/ → 0 hits outside the file itself`). | DELETE-NOW (Sprint 8B). Update Q12 stance: delete the entire `[tool.headless_wan2gp.entrypoints]` table (160-165), not just the `headless_wgp` line. The 4 non-WGP entries (worker, run_worker, heartbeat_guardian, headless_model_management) survive only via `[project.scripts]`. | — |
| Unused vendored deprecation table | `reigh-worker/pyproject.toml:167-169` | `[tool.headless_wan2gp.deprecation]` block (`db_operations_remove_ready=false`, `db_operations_warning_date="2026-12-31"`). `rg -n 'db_operations_remove_ready\|headless_wan2gp.deprecation' reigh-worker/ → 0 hits outside the file`. | DELETE-NOW (Sprint 8B) | — |
| Worker startup CLI flag | `reigh-worker-orchestrator/gpu_orchestrator/runpod/worker_startup.template.sh:463` | `--wgp-profile 1` already on the §8 list (renamed to `--vibecomfy-profile`); no extra cleanup. | n/a — already in §8. | — |
| Worker REIGH env-var split | `reigh-worker/source/core/log/core.py:100-101` | Only `REIGH_DEBUG` is consumed; `REIGH_BACKEND` (introduced by §3 "Adapter shim") will be added by Sprint 2. No live cruft today. | — | — |
| Stale TODOs (H6: DELETE-NOW unconditionally) | `reigh-app/src/shared/lib/tasks/travelBetweenImages/taskTypes.ts:185,196,206` | Three "TODO: wire through to orchestrator_details" comments on travel input fields (`chain_segments`, `structure_guidance`, `stitch_config`). They are accepted by the request type but never wired into `orchestrator_details` by the resolver — a silent contract bug, not a feature. | **DELETE-NOW (Sprint 8B)** per H6 resolution 2026-05-05. Decision rationale: maximizes success because TODO fields that silently no-op are a contract bug; deleting them removes a footgun for any future resolver author who assumes the field is wired. | n/a — unconditional delete |
| Legacy worker-model alias | `reigh-app/src/tools/travel-between-images/modelCapabilities.ts:176-178` | `LEGACY_WORKER_MODEL_ALIASES = { ltx2_22B_distilled: 'ltx-2.3-fast' }`. Used by `resolveSelectedModelFromModelName()`. Live tasks may still carry the old `ltx2_22B_distilled` model_name in their persisted shot settings. | AMBIGUOUS | Query `SELECT count(*) FROM tasks WHERE params->>'model_name' = 'ltx2_22B_distilled' AND created_at > now() - interval '90 days';` — if 0, delete the alias and rename the test fixtures. Otherwise keep until backfill. |
| Legacy generated-lane enum value | `reigh-app/src/tools/video-editor/lib/generated-lanes.ts:2`, `src/tools/video-editor/sequences/generation.ts:66,120` | `'trusted_v1'` is the only lane value used. No `'trusted_v2'` exists. Looks like a pinned version that never had a successor. | AMBIGUOUS | Confirm with timeline-tool owner whether `_v1` suffix is intentional version-pinning vs cruft. Sprint 8B candidate. |
| Legacy timeline marker enums | `reigh-app/src/tools/video-editor/lib/timeline-domain.ts:18-20,353,516,551` | `'legacy_pinned_shot_group_repaired'`, `'legacy_tracks_migrated'`, `'legacy_background_clip_inserted'` are emitted as ephemeral migration markers; whether they're still needed depends on whether unmigrated timelines exist in prod. | AMBIGUOUS | Query: `SELECT count(*) FROM timelines WHERE NOT (data ? 'tracks_migrated_at')` (or equivalent) over 90 days. If zero, drop the legacy migration paths. Sprint 8B. |
| Legacy prompt-assembly policy | `reigh-app/src/shared/lib/tasks/promptAssembly.ts:1,5`, `src/shared/components/ImageGenerationForm/lib/buildBatchTaskParams.ts:34` | `'legacy_batch_comma'` policy alongside current `'batch_comma'`. | AMBIGUOUS | Verify whether any task row carries `prompt_assembly: 'legacy_batch_comma'`. If only test fixtures, delete. Sprint 8B. |
| Pre-Comfy ComfyUI scaffolding | `reigh-worker/source/models/comfy/comfy_handler.py`, `comfy_utils.py` | Originally Sprint 2's refactor target. With `task_type: "comfy"` UNUSED (§0A), there is no consumer to refactor toward. | DELETE-NOW (Sprint 8). Folded into §8A.B `comfy` row above. | — |
| Vestigial LTX hybrid/anchor travel guidance kinds (H7: DELETE in Sprint 6) | `reigh-worker/source/core/params/travel_guidance.py:13-20,419-438`; `reigh-worker/source/task_handlers/travel/orchestrator.py:2114-2163` (`is_ltx_hybrid`/`is_ltx_anchor` branches and `_build_segment_anchor_guidance_config`). Surfaced by §3A "Travel-segment configuration matrix" holes block. | App-side spec (`reigh-app/src/tools/travel-between-images/modelCapabilities.ts:48-49,156`) does not list `ltx_hybrid` or `ltx_anchor` in any `supportedGuidanceModes`. `travelGuidance.ts:10` enum and `travelGuidance.ts:258,274` validation paths gate these kinds out of any UI emission. **Verification grep confirmed 0 hits.** | **DELETE-NOW (Sprint 6 opportunistic cleanup)** per H7 resolution 2026-05-05. ~250 LoC removable. Decision rationale: maximizes success because verification already green; carrying dead validation surface forward complicates Sprint 6 dispatcher unification. | n/a — verified |
| Legacy `structure_guidance` / `structure_videos` write aliases | `reigh-app/src/shared/lib/tasks/travelBetweenImages/taskTypes.ts:185-211` (TODOs at :185,196,206 already flagged in §8A.C "Stale TODOs"); resolver passthrough at `reigh-app/supabase/functions/create-task/resolvers/travelBetweenImages.ts:63-64` and `individualTravelSegment.ts:48-49`. | Worker's canonical `travel_guidance` contract rejects the legacy keys when both are present (`reigh-worker/source/core/params/travel_guidance.py:221-233`). The TODOs at `taskTypes.ts:185,196,206` confirm `chain_segments`, `structure_guidance`, and `stitch_config` are accepted by the request type but never wired into `orchestrator_details` by the resolver. | AMBIGUOUS | After git-blame check at `taskTypes.ts:185,196,206` confirms TODOs are >6 months old, drop the three input fields, the legacy `TravelBetweenImagesLegacyCompatInput` block, and the resolver passthroughs. Sprint 8B candidate. |
| Klein edit task path | `reigh-app/supabase/functions/create-task/resolvers/kleinEdit.ts:108`, `useMagicEditMode.ts:197,212` | `family: 'klein_edit'` resolves to worker `task_type: "flux_klein_edit"` — outside this migration's WGP catalog. Active and emitted (`useMagicEditMode.ts:197` `useKlein ? 'flux_klein_edit' : 'qwen_image_edit'`). | KEEP — out of scope. | — |
| Vendored WGP modules | `reigh-worker/source/runtime/wgp_ports/vendor_imports.py` and consumers | All consumers are inside `source/runtime/wgp_*` which §8 deletes wholesale. | n/a — covered by §8 "Runtime WGP packages" row. | — |

### D. Out-of-scope cruft (NOT deleting)

| Item | Reason for keeping |
| --- | --- |
| `source/media/video/travel_guide.py:38` `rife_interpolate_images_to_video` helper | Still used by `source/task_handlers/travel/api.py:20-21` and `source/task_handlers/travel/guidance/guide_video_ops.py:12-60`. Only the dispatch wrapper at `task_handlers/rife_interpolate.py` is dead. |
| `source/media/video/extract_frames_from_video`, `extract_frame_range_to_video` | Used by `task_handlers/edit_video_orchestrator.py:32`, `task_handlers/inpaint_frames.py:27` (the latter dies in §8A.B but the former still consumes), `task_handlers/join/{generation.py,vlm_enhancement.py}`. Only the dispatch handler at `task_handlers/extract_frame.py` is dead. |
| `family: "klein_edit"` / worker `task_type: "flux_klein_edit"` | Live, app-emitted, outside the WGP catalog. Independent migration if/when needed. |
| Wan 2.1 model entries (`vace_21`, `i2v_14B` defaults) inside `Wan2GP/defaults/` | Wan2GP submodule is deleted wholesale by §8. Don't enumerate per-file. |
| Memory profiles 2 and 4 (`High RAM`, `Conservative`) | §1.2 confirms all five tiers have a defined display label and are part of the contract preserved by Sprint 1. Even if no current deploy pins profile 2 or 4, the contract is canonical. |
| `LEGACY_WORKER_MODEL_ALIASES.ltx2_22B_distilled` | Possibly still needed for in-flight tasks; AMBIGUOUS in §8A.C. |
| All `legacy_*` timeline domain markers (`timeline-domain.ts`) | Possibly still needed for unmigrated timelines; AMBIGUOUS in §8A.C. |

### E. Per-sprint opportunistic cleanup convention

§4 sprint rows now each carry a uniform clause:

> **Opportunistic cleanup:** while touching `<areas this sprint owns>`, delete any §8A.B/§8A.C item whose code path the sprint is already inside, and flag any newly-discovered cruft into §8A.C with `path:line` + verification step.

…and a corresponding exit-criteria line: *"any in-flight cleanup items the sprint touched are either landed or explicitly punted with a §8A.C entry."*

The intent: thread cleanup through the migration as code is touched, so Sprint 8 / 8B is the closure sweep rather than the only delete window. Cleanup must remain *opportunistic* — it never blocks the sprint's primary deliverable, and it never expands a sprint's `<areas>` to chase cruft outside that surface.

**§8A.C row labels.** When a per-sprint clause picks up a row, mark its disposition in §8A.C as `DELETE-IN-SPRINT-N (opportunistic, <date landed>)`. When a sprint touches the row but defers, mark `PUNTED-FROM-SPRINT-N (reason)` and roll into Sprint 8.

### F. Gremlin audit follow-ups (G1–G8 from 2026-05-05)

The following items were surfaced during the abstraction-level / operational gremlin pass and either confirm existing dispositions or add new rows. Each cites code; each lists a sprint.

#### G1 — `core/params/` 14-of-19 modules unimported externally

`reigh-worker/source/core/params/` actually contains **19 .py files** (3,273 LoC), not 13. Importer audit (`rg -l "from source.core.params.<m>" reigh-worker/{source,tests}`):

| Module | LoC | External importers | Disposition |
| --- | --- | --- | --- |
| `__init__.py` | 41 | re-exports `ParamGroup`, `LoRAConfig`, `LoRAEntry`, `LoRAStatus`, `VACEConfig`, `GenerationConfig`, `PhaseConfig`, `TaskConfig`, `TravelGuidanceConfig`, `ContinuationPolicy`, `GenerationPolicy`, `StructureGuidanceConfig`, `StructureVideoEntry`, `TaskDispatchContext`, `OrchestratorDetails`, `validate_orchestrator_details` | KEEP (re-export surface) |
| `base.py` | 154 | indirect via `ParamGroup` only | KEEP-while-children-live |
| `task.py` | 227 | `TaskConfig` is the WGP-format funnel (`generation_strategies.py:160-167`, `download_ops.py:74-128`, `task_queue.py:497`) | KEEP-but-WGP-coupled (deletion in §8 alongside `to_wgp_format()` consumers) |
| `lora.py` | 347 | `LoRAConfig`, `LoRAEntry`, `LoRAStatus` exported from `__init__.py`; consumed by `tests/test_lora_flow.py:16` | KEEP (active) |
| `travel_guidance.py` | 555 | 4 importers (`task_registry.py:40`, `travel/segment_processor.py:21`, `travel/guide_builder.py:20`, tests) | KEEP (active, anchors §3A travel matrix) |
| `structure_guidance.py` | 454 | 2 importers (`task_registry.py:39`, `travel/guide_builder.py:19`); `normalize_structure_treatment` used by 3 media files | KEEP (active) |
| `phase_config_parser.py` | 281 | 1 importer (`task_registry.py:37`) plus internal use by `phase.py:49` | KEEP (active) |
| `generation_policy.py` | 82 | 1 external importer (`task_registry.py:38`) + tests | KEEP (active) |
| `contracts.py` | 175 | 1 importer (`task_registry.py:31,43`, `travel/contracts/orchestrator_details.py:7`, `travel/orchestrator.py:428`) | KEEP (active) |
| `task_result.py` | 145 | 4 importers (`server.py:19`, `magic_edit.py:24`, `inpaint_frames.py:34`, `travel/orchestration/orchestrator.py:10`, `join/orchestrator.py:25`, `join/shared.py:18`) | KEEP (active) |
| `phase_multiplier_utils.py` | 331 | `qwen_handler.py:17`, `hires_utils.py:124` (lazy) | KEEP (active) |
| `vace.py` | 59 | 0 external importers; only used as `TaskConfig.vace` field (`task.py:32,56`) | DELETE-NOW or merge into `task.py` (G1-1) |
| `generation.py` | 107 | 0 external importers; only used as `TaskConfig.generation` field | MERGE-INTO-`task.py` (G1-2) |
| `phase.py` | 122 | 0 external importers; only used as `TaskConfig.phase` field | MERGE-INTO-`task.py` (G1-3) |
| `phase_config.py` | 75 | `task_processor.py:381,565` (lazy `apply_phase_config_patch`/`restore_model_patches`) | KEEP (active) |
| `task_metadata.py` | 63 | 0 external importers (`grep -rn "task_metadata\|TaskMetadata" source/ → only the file itself`) | DELETE-NOW (G1-4) |
| `lora_models.py` | 5 | 0 external importers; only re-exports `LoRAEntry`, `LoRAStatus` already exported by `__init__.py` | DELETE-NOW (G1-5) |
| `lora_parsing.py` | 28 | 0 external importers | DELETE-NOW (G1-6) |
| `structure_guidance_parsing.py` | 22 | 0 external importers | DELETE-NOW (G1-7) |

**Disposition summary:**

| Action | Modules | LoC saved |
| --- | --- | --- |
| DELETE-NOW | `task_metadata.py`, `lora_models.py`, `lora_parsing.py`, `structure_guidance_parsing.py` | 118 |
| MERGE-INTO-`task.py` | `vace.py`, `generation.py`, `phase.py` | 288 (folded, not deleted; net structural simplification only) |
| KEEP | 12 modules carrying real functionality | — |

**Sprint:** Sprint 6 (per-sprint clause already names `core/params/{travel_guidance,structure_guidance,phase_config_parser}.py`). The 4 DELETE-NOW modules are unimported external-surface dead code; the 3 MERGE candidates are leaves of `TaskConfig` and can be folded if the merge is mechanical. Verification before delete: `git -C reigh-worker grep -l "<module_name>"` returns only the module itself.

#### G2 — `wgp_patches.py` (678 LoC) is a clean whole-file delete in Sprint 8

Enumerated via `rg -n "^def " source/models/wgp/wgp_patches.py`:

| Patch | Lines | What it modifies | Replacement target |
| --- | --- | --- | --- |
| `apply_runtime_model_definition_patch` | 120-179 | Wan2GP runtime model-definition mutation | Sprint 1 (build-time frozen templates per Q1; no replacement) |
| `apply_qwen_model_routing_patch` | 180-246 | WGP Qwen-family loader routing | Replaced by per-template Qwen routes (Sprint 5) |
| `apply_qwen_lora_directory_patch` | 247-295 | redirects `get_lora_dir(model_type)` → `loras_qwen/` | Replaced by `loras_qwen/` symlink in worker image (§3A "Qwen LoRA directory") |
| `apply_ltx2_runtime_fork_markers_patch` | 296-325 | LTX2 fork-marker mutation | None needed — `ltxv`/`ltx2` UNUSED per §0A |
| `apply_lora_multiplier_parser_patch` | 326-350 | swaps WGP parser to 3-phase parser shared with mmgp | None needed — WGP-internal; gone with WGP |
| `apply_qwen_inpainting_lora_patch` | 351-383 | Qwen inpainting LoRA patch | Sprint 5 (Qwen edit templates carry their own LoRA chain) |
| `apply_lora_key_tolerance_patch` | 384-490 | strips unrecognized LoRA keys | Replaced by `source/models/comfy/lora_sanitize.py` (§3A "LoRA stacking", Sprint 5) |
| `apply_lora_caching_patch` | 491-587 | WGP LoRA cache | None needed — Comfy `model_patcher` cache covers this (§3A "Uni3C") |
| `apply_headless_app_stub` | 588-611 | gradio shim | None needed — gone with WGP |
| `apply_all_wgp_patches` | 630-678 | orchestration of the above | gone |

Plus context bookkeeping (`_normalize_patch_context_id`, `_context_patch_state`, `_context_patch_rollbacks`, `_register_patch_application`, `get_wgp_patch_state`, `clear_wgp_patch_context`, `rollback_wgp_patches`, `_rollback_qwen_lora_directory_patch`, `_rollback_lora_caching_patch`).

**Verdict: clean whole-file delete in Sprint 8.** Every patch's intent is either (a) WGP-only and dies with WGP, or (b) replaced by an explicit non-monkeypatch mechanism elsewhere in the migration plan. **No patch needs an explicit migration target that doesn't already have one.** Already covered by §8 "Model WGP packages" row; no new row required. (G2 closes.)

#### G3 — Two-seam adapter unification (USER DECISION: UNIFY — Sprint 6 deliverable)

**Decision (2026-05-05): UNIFY.** User chose the aggressive option. Sprint 6 absorbs the dispatcher refactor; Sprint 6 scope grows by ~1–2 days of structural work + smoke retargeting. See §4 Sprint 6 row and the new §9 risk entry.

**Trade-off context (recorded for the implementer).** Today `_handle_direct_queue_task` (`task_registry.py:1543-1562`) and the `context["task_queue"]` injection sites (`task_registry.py:1437,1453,1462,1487,1496,1505,1538,1546`) coexist for these reasons:

| Reason | Cite | Wan2GP-specific? |
| --- | --- | --- |
| Direct seam waits up to 3600s (`task_registry.py:1565`) for a single completion; orchestrated seam waits 1800s and runs chaining post-WGP (`task_registry.py:1346-1364`). | `task_registry.py:1543-1600` vs `:1298-1357` | No — different lifecycle, not Wan2GP-specific |
| Orchestrated handlers run media-prep / image-ref resolution / structure-guidance / continuation-uni3c **before** queue submission (`_resolve_segment_context`, `_resolve_image_references`, `_process_structure_guidance`, `_apply_video_source_continuation`, `_apply_uni3c_config`). | `task_registry.py:1311-1328` | No — these are Comfy-side concerns too |
| Orchestrated handlers run chaining **after** completion (`handle_travel_chaining_after_wgp`). | `task_registry.py:1363-1364` | Function name has `_wgp` suffix, but the chaining itself is media-side (extract tail frame, color-match, mask-active-frames) |
| Direct seam writes `_source_task_type` only on travel paths (`task_registry.py:1334`) and applies one task-type override (`wan_2_2_t2i` → `video_length=1` at `task_registry.py:1554`). | as cited | Wan2GP param name (`video_length`) is leaking, but the override pattern itself isn't WGP-bound |

**Could Sprint 6 or 8B unify them?** Yes, in principle: a single `_handle_via_queue_task` could take a pre-submit hook (media prep) and a post-completion hook (chaining), and the direct-queue path would pass `(None, None)`. The seam delete would land in `task_registry.py:1543-1602` plus the `_handle_direct_queue_task` short-circuit at `:1437-1438` and `:1538-1539`.

**Files that disappear (under unification):**

- `_handle_direct_queue_task` (60 LoC at `task_registry.py:1543-1602`) — folded into the orchestrated wait loop.
- The `task_type in DIRECT_QUEUE_TASK_TYPES and context["task_queue"]` branch at `:1437-1438` — replaced by registry lookup with default-pre/post hooks.
- Possibly `DIRECT_QUEUE_TASK_TYPES` set itself if the registry is structured by task type.

**Concrete unification design (Sprint 6 implementer guidance):**

1. New single dispatcher `_handle_via_queue_task(db_task, context, *, pre_submit_hooks=None, post_completion_hooks=None, wait_timeout_s=None)`. Both seams call it.
2. **Pre-submit hooks** capture today's orchestrated pre-work as a typed list of optional callables: `[_resolve_segment_context, _resolve_image_references, _process_structure_guidance, _apply_video_source_continuation, _apply_uni3c_config]`. Direct-queue tasks pass `pre_submit_hooks=None` (or an empty list); orchestrated tasks pass the relevant subset per task type.
3. **Post-completion hooks** capture today's chaining work: `[handle_travel_chaining_after_wgp]` (rename to `handle_travel_chaining` as part of the WGP-name closure sweep). Direct-queue passes `None`.
4. **Timeout convergence:** the existing 3600s vs 1800s split is preserved per task type, but as an explicit `wait_timeout_s` argument resolved from a per-task-type registry, not from which seam was taken. Default to 1800s; direct-queue task types that legitimately need 3600s declare it. Sprint 0 baselines must record the per-task-type effective timeout so this isn't a silent change.
5. **Override registry:** the `wan_2_2_t2i` → `video_length=1` override at `task_registry.py:1554` becomes a per-task-type override map that the unified dispatcher applies before submit. (`video_length` field name is renamed during the WGP-name closure sweep.)
6. **`DIRECT_QUEUE_TASK_TYPES` set:** deleted; replaced by registry lookup keyed on `task_type` returning `(pre_hooks, post_hooks, wait_timeout_s, overrides)`.
7. **Lifecycle contract test:** before unification merges, write a contract test asserting that for every USED task type the pre-unification dispatch path and the post-unification path produce identical:
   - Submitted `GenerationTask` payload (modulo determinism — diff after applying the same hooks).
   - Completion polling cadence and timeout budget.
   - Post-completion artifact paths and DB updates.
   This is the safety net that lets Sprint 6 take the refactor without regressing anything Sprint 0 baselined.

**Files that disappear:**

- `_handle_direct_queue_task` (60 LoC at `task_registry.py:1543-1602`) — folded into `_handle_via_queue_task`.
- The `task_type in DIRECT_QUEUE_TASK_TYPES and context["task_queue"]` branch at `task_registry.py:1437-1438` and `:1538-1539` — replaced by registry lookup.
- The `DIRECT_QUEUE_TASK_TYPES` constant — replaced by the per-task-type registry.

**Why we did this even though "keep both" was defensible.** (1) After Sprint 8 the only meaningful split between direct and orchestrated is which hooks run; encoding that as data (pre/post-hook lists) is cleaner than encoding it as a control-flow seam. (2) Bundling the refactor into Sprint 6 means the dispatcher is touched once, while we're already in there. Splitting it across migration + post-migration cleanup risks the cleanup never happening. (3) The contract test (item 7 above) prevents lifecycle-contract drift from being a silent regression. (4) `DIRECT_QUEUE_TASK_TYPES` and the seam-split branch are the kind of leaky abstraction the user explicitly wanted off the books while we're in here.

**Disposition: UNIFY — Sprint 6 deliverable.** Sprint 6 row in §4 and §5 Cohort E entry conditions updated. New §9 risk row added: "Unified dispatcher introduces a lifecycle-contract regression for direct-queue tasks (e.g. timeout, polling cadence) that Sprint 0 baselines wouldn't catch unless the contract test runs against the recorded baseline." Mitigation: contract test (item 7), Sprint 0 must capture per-task-type timeout/cadence baselines; rollback is to revert the dispatcher change and keep both seams temporarily — both stacks coexist in the worker until Sprint 8 anyway.

#### G4 — Profile-1 (prod) vs Profile-3 (dev) split is load-bearing post-migration; keep both

`worker_startup.template.sh:463` pins `--wgp-profile 1` (Max Performance: high VRAM, fastest) and `start_worker.bat:14` / `scripts/live_test/{main,smoke}.py:27` default to `--wgp-profile 3` (Balanced). Material differences from §1 + §3 mapping:

| Profile | `vram_policy` | `cache_policy` | Other | Matters because |
| --- | --- | --- | --- | --- |
| 1 | `high` | `smart` | none | Production GPU is consistent and large (typically 80GB H100 / 48GB A100) — leaves room for caching across runs |
| 3 | `normal` | `smart` | none | Dev GPUs (3090 24GB / 4090 24GB / Mac unified memory) — cannot afford the high-VRAM caching pressure |

**Verdict: split is still load-bearing post-migration.** Q10 already documents the same conclusion; Sprint 1 acceptance gates require parity tests for both. (G4 closes — no new row, no consolidation.) Sprint 7 per-sprint clause was patched to make this explicit so a canary refactor doesn't accidentally collapse the two.

#### G5 — Operational scaffolding sweep additions

| Finding | path:line | Disposition |
| --- | --- | --- |
| `worker_startup.template.sh:267-292` Wan2GP submodule reconciliation block (stale-clone removal + missing-submodule hard-fail) | `worker_startup.template.sh:267-292` | Already in §8 row "Wan2GP submodule reconciliation". No new row. |
| `worker_startup.template.sh:174,179-183` `Headless-Wan2GP` fallback dir | as cited | Already in §8 row "Worker directory fallback". No new row. |
| `worker_startup.template.sh:463` `--wgp-profile 1` | as cited | Already in §8 row "Production profile flag". No new row. |
| Stdout-noise filter substring `"Incorrect version of mmgp"` | `reigh-worker/source/core/log/core.py:59` | DELETE-IN-SPRINT-8 (G5-1) — vestigial after WGP removal. |
| Library-logger noise suppression for `"mmgp"` | `reigh-worker/source/core/log/core.py:112` | DELETE-IN-SPRINT-8 (G5-2) — same justification. |
| `reigh-worker/pyproject.toml:11` description `"Headless Wan2GP worker for Reigh"` | as cited | DELETE-OR-RENAME-IN-SPRINT-8 (G5-3) — update description; no functional change. |
| `reigh-worker/pyproject.toml:13-16` comment-block `"# Wan2GP base dependencies"` plus `mmgp==3.7.6` (already in §8) | as cited | Comment cleanup rides with `mmgp` removal in Sprint 8. (G5-4) |
| `reigh-worker/requirements.txt` header `"# Headless-Wan2GP project requirements\n# Only includes dependencies NOT already in Wan2GP/requirements.txt\n# Note: Install Wan2GP/requirements.txt first, then this file\n# CONFLICT-FREE: Removed packages that conflict with upstream Wan2GP"` | `reigh-worker/requirements.txt:1-4` | DELETE-IN-SPRINT-8 (G5-5) — the entire "split" premise dies with the submodule. The whole `requirements.txt` may be redundant with `pyproject.toml`; verify before delete. |
| No `Dockerfile` or `nixpacks.toml` in reigh-worker; install path is `pyproject.toml` only via uv from `worker_startup.template.sh` | (none) | KEEP — no new install-step cruft to delete. |
| WGP-only transitive deps reachable only through WGP (`mmgp`, plus possibly `gradio==5.29.0`, `dashscope`, `s3tokenizer`, `chumpy`, `smplfitter`, `taichi`, `flash-linear-attention`, `vector-quantize-pytorch`, `gguf`, `insightface`, `facexlib`, `wetext`, `audio-separator`, `pyannote.audio`, `speechbrain`, `torchcodec`) | `reigh-worker/pyproject.toml:13-77` | **DELETE-IN-SPRINT-8 per H4 resolution (2026-05-05).** Per-dep deletion command (run for each candidate after WGP source removal lands but before final `pyproject.toml` purge): `rg "^(import\|from) <dep_top_level>(\b\|\.)" reigh-worker/source/ vibecomfy/vibecomfy/ \| rg -v 'reigh-worker/source/(runtime/wgp_\|models/wgp/\|task_handlers/(magic_edit\|inpaint_frames\|extract_frame\|create_visualization\|rife_interpolate)\.py)'`. **Threshold: if remaining hits = 0, delete unconditionally; if hits > 0, file follow-up issue and migrate the consumer in the same Sprint-8 PR (do not punt past cutover).** Per-package top-level import names: `mmgp`→`mmgp`, `gradio`→`gradio`, `dashscope`→`dashscope`, `s3tokenizer`→`s3tokenizer`, `chumpy`→`chumpy`, `smplfitter`→`smplfitter`, `taichi`→`taichi`, `flash-linear-attention`→`fla`, `vector-quantize-pytorch`→`vector_quantize_pytorch`, `gguf`→`gguf`, `insightface`→`insightface`, `facexlib`→`facexlib`, `wetext`→`wetext`, `audio-separator`→`audio_separator`, `pyannote.audio`→`pyannote`, `speechbrain`→`speechbrain`, `torchcodec`→`torchcodec`. **Estimated 8–12 packages droppable; ~1 GB image size reduction.** **Decision rationale: maximizes success because hedging "audit-in-Sprint-8" leaves dead deps in production indefinitely; codified per-dep grep with hard threshold lets the Sprint 8 PR be mechanical and reviewable.** |

#### G6 — `Wan2GP/defaults/*.json` data migration: zero runtime consumers

`grep -rln "Wan2GP/defaults"` across the entire workspace (excluding `.git`, `node_modules`, `.venv`, `Wan2GP/` itself) returns **only this migration doc**. `grep -rln "Wan2GP/defaults" reigh-worker/source/` is 0 hits.

The only runtime entry point is `load_missing_model_definition` at `source/models/wgp/model_ops.py:29-63`, which reads JSON definitions from inside the WGP submodule via WGP's own helpers — not from a hardcoded `Wan2GP/defaults/...` path in reigh-worker source. After WGP deletion, that loader is gone.

**Verdict: NO PORT NEEDED.** Wan2GP defaults JSON files are inputs to WGP itself, not to any reigh-worker code path that survives Sprint 8. Deleting `reigh-worker/Wan2GP/` (already in §8 "Wan2GP submodule" row) drops them cleanly. (G6 closes — no new row.) The §3 / §3A migration plan correctly treats VibeComfy templates as the new source of defaults; the WGP defaults are referenced by the migration plan as *historical evidence of what to preserve*, not as files that need data migration.

#### G7 — `headless_wgp` external consumer check: clean

`grep -rln "headless_wgp\|HeadlessWGP"` across the workspace excluding `reigh-worker/Wan2GP/` returns hits **only inside `reigh-worker/`** (`STRUCTURE.md`, `pyproject.toml`, `headless_wgp.py`, `source/models/wgp/orchestrator.py`, `source/task_handlers/queue/task_queue.py`, `source/task_handlers/queue/task_processor.py`). `reigh-worker-orchestrator/`, `vibecomfy/`, all docs, all scripts, and all reigh-app code: **0 hits.**

**Verdict: CLEAN.** No external consumer needs a coordinated rename or migration. The §8 "Root scripts" + "Entrypoint shims" + "Package metadata" rows + the §8A.C `[tool.headless_wan2gp.entrypoints]` table delete are sufficient. Q11 (does `headless_model_management` have non-WGP callers?) gets a parallel clean answer: same grep pattern returns the same internal-only result. (G7 closes — both `headless_wgp` and `headless_model_management` are delete-only in Sprint 8.)

#### G8 — Frontend AMBIGUOUS rows: queries to run before deletion

For each AMBIGUOUS row in §8A.C, the exact query to run, the threshold, and the sprint slot once resolved:

| AMBIGUOUS row | path:line | Query | Threshold for delete | Sprint on resolution |
| --- | --- | --- | --- | --- |
| `LEGACY_WORKER_MODEL_ALIASES.ltx2_22B_distilled` | `modelCapabilities.ts:176-178` | `SELECT count(*) FROM tasks WHERE params->>'model_name' = 'ltx2_22B_distilled' AND created_at > now() - interval '90 days';` | 0 rows | Sprint 8B |
| `'trusted_v1'` lane enum | `generated-lanes.ts:2`, `sequences/generation.ts:66,120` | Owner check (Q-row already noted) — there's no DB column to query; ask timeline-tool owner whether `_v1` is a deliberate version pin. | Owner says "not pinned" | Sprint 8B |
| `legacy_pinned_shot_group_repaired`, `legacy_tracks_migrated`, `legacy_background_clip_inserted` markers | `timeline-domain.ts:18-20,353,516,551` | `SELECT count(*) FROM timelines WHERE NOT (data ? 'tracks_migrated_at') AND created_at > now() - interval '90 days';` (or equivalent — exact column name needs DBA check) | 0 rows over 90 days | Sprint 8B |
| `'legacy_batch_comma'` prompt-assembly policy | `promptAssembly.ts:1,5`, `buildBatchTaskParams.ts:34` | `SELECT count(*) FROM tasks WHERE params->>'prompt_assembly' = 'legacy_batch_comma' AND created_at > now() - interval '90 days';` | 0 rows over 90 days | Sprint 8B |
| `taskTypes.ts:185,196,206` TODOs (`chain_segments`, `structure_guidance`, `stitch_config` accepted-but-never-wired fields) | as cited | `git -C reigh-app blame src/shared/lib/tasks/travelBetweenImages/taskTypes.ts -L 185,210` | TODOs older than 6 months AND `rg -n "orchestrator_details.chain_segments\|orchestrator_details.structure_guidance\|orchestrator_details.stitch_config" reigh-app/supabase/functions/ → 0 hits` | Sprint 8B (couples with Klein/legacy field cleanup) |
| `kind ∈ {ltx_hybrid, ltx_anchor}` validation surface in worker | `travel_guidance.py:13-20,419-438` + orchestrator branches | `rg -n "'ltx_hybrid'\|'ltx_anchor'\|kind.*['\"]ltx_(hybrid\|anchor)" reigh-app/src/ reigh-app/supabase/` | 0 hits | Sprint 6 (per-sprint clause) or Sprint 8 (per §8A.C entry) |
| `taskTypes.ts:159` per-phase Wan LoRAs (Wan-only `phase_config.phases[i].loras`) | as cited | already wired through (`travel_guidance.py:30-37`) | n/a — KEEP | — |

**Note on running the DB queries.** This subagent cannot run them; the Sprint 8B PR author runs them at PR time and includes the result count in the PR description.

**H5 thresholds and deadlines (2026-05-05):**

- **Deadline:** All G8 verification queries MUST run no later than the start of Sprint 7 (so the cleanup PRs don't slip past cutover). The Sprint 7 entry gate (S2) lists "all §8A.C AMBIGUOUS rows resolved per G8 query plan" as a precondition.
- **Threshold for `LEGACY_WORKER_MODEL_ALIASES.ltx2_22B_distilled` and timeline `legacy_*` markers:** if query returns 0 in-flight tasks (90 days), DELETE-NOW (Sprint 8B). If >0 over 90 days, set 7-day backfill window via a one-shot migration (rewrite stale `model_name`/timeline marker), then delete in Sprint 8B follow-up. Maximum 2-week slip past cutover.
- **Threshold for `'trusted_v1'` lane enum:** owner-confirmation question — if owner confirms "not pinned" within 48h, DELETE-NOW (Sprint 8B); if owner says "pinned", convert to documented version-pin with a comment and KEEP.
- **Threshold for `'legacy_batch_comma'` prompt-assembly policy:** if DB query returns 0 over 90 days, DELETE-NOW (Sprint 8B); >0, 7-day backfill window then delete.
- **Threshold for `taskTypes.ts:185,196,206` TODO no-op fields (`chain_segments`, `structure_guidance`, `stitch_config`):** **DELETE UNCONDITIONALLY (H6 resolution 2026-05-05).** They literally don't do anything — the request type accepting them silently is a contract bug, not a feature. Sprint 8B PR removes the input fields, the legacy compat block, and the resolver passthroughs. No DB query needed.
- **Threshold for `kind ∈ {ltx_hybrid, ltx_anchor}`:** **DELETE-NOW per H7 resolution (2026-05-05)** — verification grep already confirmed 0 hits. Owns Sprint 6 opportunistic cleanup; covers both worker validation paths and orchestrator branches (~250 LoC).

**Decision rationale (H5/H6/H7): maximizes success because per-row threshold + deadline converts AMBIGUOUS rows from "we'll figure it out later" into mechanical PRs that can be authored before Sprint 8B even starts; eliminates the failure mode where post-cutover cleanup never lands.**

If a query returns >0 hits AND no backfill plan is feasible within the 7-day window, the row stays AMBIGUOUS and the field stays — but this is a documented exception, not a default.

## 9. Open questions, assumptions, risks, and mitigations

### Open Questions

| ID | Question | Decision needed by | Default stance until answered |
| --- | --- | --- | --- |
| Q1 | Should VibeComfy template authoring be static/build-time frozen, or should it preserve Wan2GP-style dynamic model-definition loading from JSON? | Sprint 1 design review | Freeze at build time, as recommended in Section 3, unless a concrete runtime-mutation requirement appears. |
| Q2 | Can the five-tier `MemoryProfile` -> `SessionConfig` overlay switch safely per task, or do some profile changes require process/session restart? | Sprint 1 exit | Assume per-task overlay is allowed only when `EmbeddedSession.reconfigure()` proves safe; otherwise restart the session between profile families. |
| Q3 | ~~What exact dual-run divergence thresholds are acceptable for image hash, video pHash, frame count, dimensions, audio length, latency, VRAM, and OOM count?~~ — **CLOSED (2026-05-05).** Thresholds pinned in §11 "Migration thresholds" (single-source-of-truth artifact). Sprint 3 dual-run report fails on any breach; Sprint 7 canary auto-rollbacks on output-divergence rate >1% over a 24h window. **Decision rationale: maximizes success because subjective "green" gates were the largest hidden risk in the plan — concrete numbers convert dual-run from human-review into automatable pass/fail, eliminating the silent-acceptance failure mode.** | — | Closed. |
| Q4 | Should Canny, Depth, Pose, Flow, and related preprocessing annotators live in `reigh-worker`, or move into a `vibecomfy_extras/` package? | Sprint 5 | Keep preprocessing in `reigh-worker` until VibeComfy extras have ownership and tests. |
| Q5 | ~~What RunPod startup-time and `disk_size_gb` impact does dual-stack WGP + VibeComfy have during Sprint 7 canary?~~ — **CLOSED (H9 resolution, 2026-05-05).** Sprint 0 baseline raised to 200 GB at `gpu_orchestrator/worker_spawner.py:279-281,391-395`; first-pod boot in Sprint 0 validates actual usage. | — | Closed. |
| Q6 | Is the LoRA-key sanitizer currently mmgp/Wan2GP-specific, or should it become a portable ComfyUI `LoraLoader` patch? | Sprint 5 | Treat it as a portable VibeComfy patch over `LoraLoader` nodes. |
| Q7 | Where should RIFE and Uni3C live after cutover? | Sprint 6 | Keep RIFE under `reigh-worker/source/media/`; implement Uni3C as a VibeComfy patch on Wan 2.2 templates. |
| Q8 | Who owns the Hunyuan ready template and what is the committed Sprint 4 delivery timeline? | Sprint 4 start | Owner is VibeComfy maintainer; Cohort D stays blocked until `ready_templates/video/hunyuan_*` ships. |
| Q9 | What is the long-term fate of the raw `comfy` task type? | Sprint 6 | Preserve it through `comfy_handler.py` delegating to VibeComfy runtime; revisit deprecation after cutover. |
| Q10 | Should dev and prod default profiles remain divergent, with prod profile 1 and dev profile 3, after VibeComfy cutover? | Sprint 1 / Sprint 7 | Preserve divergence for parity: prod profile 1, dev profile 3. |
| Q11 | Does `headless_model_management` have non-WGP callers that need migration to VibeComfy management, or can it be deleted in Sprint 8? | Sprint 8 planning | Treat it as delete-only unless grep/caller review finds live non-WGP callers. |
| Q12 | ~~Are the duplicate `headless_wgp` registrations at `pyproject.toml:109` and `pyproject.toml:165` intentional, or a copy-paste bug?~~ — **CLOSED, escalated.** The duplication isn't limited to `headless_wgp`: `[tool.headless_wan2gp.entrypoints]` at lines 160-165 mirrors *all five* entries in `[project.scripts]` at 104-109 (`worker`, `run_worker`, `heartbeat_guardian`, `headless_model_management`, `headless_wgp`). The `[tool.headless_wan2gp.entrypoints]` table has no consumer (`rg -n 'tool.headless_wan2gp.entrypoints' reigh-worker/ reigh-worker-orchestrator/ → 0 hits outside the file`). Delete the entire table in Sprint 8B (§8A.C). The 4 non-WGP entries survive only via `[project.scripts]`. | — | Closed. |
| Q13 | ~~Where does the Uni3C runtime cache live in VibeComfy~~ — **CLOSED.** Comfy's native `model_patcher` already caches loaded controlnets across runs of the same warm session; no reigh-worker dict and no VibeComfy hook are needed. See §3A "Uni3C" row. | — | Closed. |
| Q14 | ~~Does the installed `ComfyUI-WanVideoWrapper` expose a `WanVideoUni3CController` node~~ — **CLOSED.** `ComfyUI-WanVideoWrapper/uni3c/nodes.py:16-149` ships `WanVideoUni3C_ControlnetLoader` (output `WANVIDEOCONTROLNET`) and `WanVideoUni3C_embeds` (output `UNI3C_EMBEDS`); `WanVideoSampler.INPUT_TYPES` accepts `uni3c_embeds` at `nodes.py:2635`. No shim required. | — | Closed. |
| Q15 | ~~Is the WGP `ltxv_13B` → LTX 2.3 version bump acceptable as documented divergence~~ — **CLOSED, escalated.** Different model generation (0.9.8 13B vs 2.3 22B), different VAE, different sampler — output divergence is large and not threshold-bounded. The §1A `ltxv` row is now NEW: author `ready_templates/video/ltx_0_9_8_13b_t2v.py` against the upstream Lightricks workflow. | — | Closed → NEW required. |
| Q16 | ~~Which Flux Klein variant maps to the WGP `flux` task type~~ — **CLOSED, escalated.** WGP `flux` is FLUX.1 Dev 12B (`Wan2GP/defaults/flux.json:3-9`), not Flux 2 Klein. All three `image/flux2_klein_*` templates load Flux 2 Klein weights/VAE/text-encoder. The §1A `flux` row is now NEW: author `ready_templates/image/flux1_dev_t2i.py`. | — | Closed → NEW required. |
| Q17 | ~~Does `wanvideo_wrapper_13b_vace.py` accept the Wan 2.2 cocktail via `WanVideoModelLoader.widget_0` swap~~ — **CLOSED, NEW required.** All existing kj-wrapper templates are single-loader/single-sampler. `WanVideoSampler` (`ComfyUI-WanVideoWrapper/nodes.py:2596-2648`) has no `model_2` / `low_noise_model` / `switch_threshold` input. The HIGH/LOW dual-model phase-switch in `Wan2GP/defaults/vace_fun_14B_2_2.json:7-15` requires authoring a NEW `wanvideo_wrapper_22_14b_vace_cocktail.py`. See §3A "Wan 2.2 VACE cocktail" for the structural sketch. | — | Closed → NEW required. |
| Q18 (new) | Does the kj-wrapper's two-stage HIGH→LOW sampler chain (`WanVideoSampler.sigmas` schedule + `samples` continuation) bit-stable-reproduce WGP's mid-trajectory model-switch trajectory at the same `switch_threshold`? | Sprint 4 NEW-template smoke | Default acceptance is "matches frame count + duration + dimensions; pHash drift bounded by Q3 threshold." Hard byte-parity is not a goal. |
| Q19 (new) | Where does `reigh-worker/scripts/build_lora_sanitizer_modulemaps.py` get authoritative module-name sets for each Wan/Qwen architecture without needing to load every model on the build host? | Sprint 5 entry | Run a one-shot script on a dev pod with the full model set during release prep; ship the resulting `module_names_<arch>.json` files in the worker image. |

### Assumptions

- Queue contracts and Supabase schema remain unchanged.
- `reigh-app` UI and API behavior remain unaffected.
- VibeComfy is the canonical home for new templates.
- The five-tier memory-profile display contract is preserved.
- Default profile remains environment-specific unless Q10 decides otherwise: production profile 1 from `worker_startup.template.sh:463`, development profile 3 from `start_worker.bat:14` and `scripts/live_test/{main,smoke}.py:27`.
- Both `pyproject.toml` `headless_wgp` entries, at lines 109 and 165, are treated as duplicate WGP registrations and both must be removed in Sprint 8.
- `reigh-worker/`, `reigh-worker-orchestrator/`, and `vibecomfy/` are independent Git repos nested in the workspace. Git-aware closure sweeps must use per-repo `git -C` invocations, or use filesystem traversal with `rg`.
- WGP and VibeComfy stay coinstalled in the worker image until Sprint 8 starts.

### Risks and Mitigations

**S6 (2026-05-05):** Status column added. Values: OPEN (no mitigation in flight), MITIGATED (mitigation is in flight or shipped per the cited sprint), ACCEPTED (acknowledged but not actively mitigated), CLOSED (no longer applicable).

| Risk | Impact | Mitigation | Status |
| --- | --- | --- | --- |
| Missing 1-5 profile tier | P0 blocker; cutover would lose the non-negotiable memory contract. | Sprint 1 `MemoryProfile` overlay, profile 1 and profile 3 baselines, and per-profile smoke tests. | MITIGATED (Sprint 1) |
| Embedded ComfyUI cold boot or session churn | Latency regression and failed canary SLOs. | Use a long-lived `EmbeddedSession`; measure cold and warm timings in Sprint 0/Sprint 3. | MITIGATED (Sprint 0/3) |
| Template catalog drift | Task routing silently points at stale or renamed ready templates. | Add `template_routing.py` tests that validate every routed template id exists and compiles. | MITIGATED (Sprint 2) |
| ~~Hunyuan template absence~~ | — | — | CLOSED (§0A; H3: handler also DELETE-NOW Sprint 8) |
| LoRA divergence | Output drift or failed runs for Qwen/edit workflows. | Golden-output LoRA corpus and VibeComfy `LoraLoader` sanitizer patch. | MITIGATED (Sprint 5) |
| Pod disk too small during dual-run | Worker startup or model download failures. | H9 RESOLVED 2026-05-05: Sprint 0 baseline raised to 200 GB at `gpu_orchestrator/worker_spawner.py:279-281,391-395`. | MITIGATED (Sprint 0, H9) |
| Orchestrated child-task seam missed by adapter | Parent tasks report Comfy while child generation still uses WGP or fails. | Sprint 2 dual-seam wiring; Sprint 6 parent-to-child smokes; Cohort E promotion blocked until both seams pass. | MITIGATED (Sprint 2/6) |
| Existing `source/models/comfy` integration drifts | Two Comfy implementations survive and split output/telemetry behavior. | Sprint 2 retire/refactor: `comfy_handler.py` delegates to VibeComfy, `comfy_utils.py` is removed, tests migrate. **Updated 2026-05-05:** with §0A confirming `task_type:"comfy"` UNUSED, the refactor target is empty — `comfy_handler.py` is deleted in Sprint 8 (§8A.B) instead of refactored. | MITIGATED (Sprint 8) |
| Orchestrator startup-script Wan2GP coupling missed at cleanup | New worker image still discovers or expects `Headless-Wan2GP`. | Section 8 checklist explicitly names `worker_startup.template.sh` touchpoints and `gpu_orchestrator/runpod/startup_script.py`. | MITIGATED (Sprint 8) |
| Residual WGP entrypoints/tests left after directory deletion | Build/test failures or dead CLI surfaces after Sprint 8. | Section 8 explicit per-file list plus mandatory Section 10 per-repo grep sweep. | MITIGATED (Sprint 8/§10) |
| Closure sweep run from workspace root silently skips nested repos | False clean result before WGP deletion. | Section 10 requires per-repo `git -C` Option A and filesystem `rg` Option B. | MITIGATED (§10) |
| ~~Hunyuan NEW template under-specified~~ | — | — | CLOSED (§0A) |
| Wan 2.2 VACE cocktail requires a NEW template (Q17 closed) | Confirmed NEW: `vace_22`, `inpaint_frames`, `join_clips_segment`, and Wan-family `travel_segment` block on `ready_templates/video/wanvideo_wrapper_22_14b_vace_cocktail.py`. The kj-wrapper has no dual-model sampler; must implement HIGH→LOW two-stage sampler chain with sigma cut-over per §3A. Sprint 4 scope grows by one NEW template (was zero on the ADAPT-path assumption). | Name owner at Sprint 4 kickoff (VibeComfy maintainer for graph + reigh-worker for sigma-schedule pre-compute). Block Cohort D promotion until template lands. **S1 ADDITION 2026-05-05:** Sprint 3.5 dry-run gate (single shot, single profile-3) validates per-frame pHash drift hypothesis before Sprint 4 commits. If dry run fails §11 thresholds, fall back per §6 (keep Wan VACE on WGP indefinitely). | MITIGATED (Sprint 3.5/4) |
| Two-stage sampler may not reproduce WGP model-switch trajectory exactly | The kj-wrapper's `WanVideoSampler` chain runs N steps on HIGH, hands off `samples`, runs M steps on LOW. WGP's switch is mid-trajectory in a single sampler with a phase-aware scheduler. Frame count and dimensions will match; per-frame pHash and motion fidelity may drift. | Q18 verification gate; **§11 thresholds govern acceptance** (per-frame pHash mean ≤0.08 / p95 ≤0.12). Pre-Sprint-4 dry run (S1) catches this before Sprint 4 commits. If drift exceeds threshold, escalate to upstream kj wrapper for native dual-model support or accept divergence with user sign-off (and keep Wan VACE on WGP per §6 fallback). | MITIGATED (S1 + §11) |
| Uni3C dependency on Comfy's smart-memory cache | Decision in §3A relies on Comfy's `model_patcher` keeping the controlnet warm across runs. **H2 RESOLVED (2026-05-05):** Sprint 1 maps profile 5 MINIMUM to `cache_policy="lru:1"` (not `"none"`), so Uni3C tasks remain supported on profile 5 with a 1-entry LRU cache (~250MB VRAM). The 2-minute Uni3C reload from `model_ops.py:225` is avoided. | See §3 mapping table; profile 5 = `lru:1`. | MITIGATED (Sprint 1, H2) |
| ~~Flux NEW template absence~~ | — | — | CLOSED (§0A; H11 consolidation) |
| ~~LTX legacy 13B NEW template absence~~ | — | — | CLOSED (§0A) |
| LoRA sanitizer module-name table generation | The pre-process recipe needs per-architecture `module_names_<arch>.json` files. Generating these requires loading every supported transformer at build time, which is expensive and pod-bound (Q19). | One-shot generation script run during release prep; cache the JSON files in the repo and image. | MITIGATED (Sprint 5) |
| Wan2GP LoRA-key tolerance is stricter than ComfyUI native | Stacked user LoRAs that loaded under WGP via `apply_lora_key_tolerance_patch` could still raise under ComfyUI's stricter validators if the sanitizer patch in Section 3A is incomplete. | Sprint 5 corpus must include the lightx2v Wan 2.2 distilled-LoRA family that originally motivated `wgp_patches.py:384-483`; promotion blocked until those LoRAs round-trip clean. | MITIGATED (Sprint 5) |
| ~~App emits `wan_2_2_i2v` task type that the worker registry doesn't recognize~~ | — | — | CLOSED (§8A.A) |
| Custom-node dependencies surface that aren't in `custom_nodes.lock` | Templates such as `wanvideo_wrapper_22_5b_i2v_controlnet` declare `ComfyUI-WanVideoWrapper`/`ComfyUI-VideoHelperSuite`/`ComfyUI-KJNodes` (`READY_REQUIREMENTS.custom_nodes`); Flux Klein GGUF variant adds `ComfyUI-GGUF`; Hunyuan NEW will likely add another node pack. | Pre-canary, the worker image's custom-node lockfile must enumerate every pack referenced by any template `template_routing.py` can select; CI step lists `READY_REQUIREMENTS.custom_nodes` across selected templates and diffs against the lock. Item also surfaced in §12 confidence checklist. | MITIGATED (Sprint 2/§12) |
| Travel-segment matrix coverage drift | The 13-row §3A matrix is denormalized from `modelCapabilities.ts:13-160` and `travel_guidance.py:13-69`. Either side can grow (new model id, new guidance kind, new continuation strategy) without the matrix being updated, silently introducing an uncovered combination at canary. | Add a CI assertion that cross-products `MODEL_SPEC_REGISTRY[*].supportedGuidanceModes` × `_TRAVEL_GUIDANCE_KIND` and fails when the row count diverges from the matrix. Owner: reigh-app + reigh-worker matrix smoke author. | MITIGATED (Sprint 6/CI) |
| Vestigial LTX-hybrid / LTX-anchor codepaths in worker | `travel_guidance.py:13-20` accepts `ltx_hybrid` and `ltx_anchor` kinds with full validation (`travel_guidance.py:419-438`) and segment-anchor guidance plumbing (`orchestrator.py:2123-2163`). Neither is reachable from `modelCapabilities.ts:49,156`. Migration carries dead validation surface and 200+ LoC of orchestrator branching forward. | **H7 RESOLVED 2026-05-05:** verification grep confirmed 0 hits; DELETE in Sprint 6 opportunistic cleanup per §8A.C and §3A holes block. | MITIGATED (Sprint 6, H7) |
| **G3 unified dispatcher introduces a lifecycle-contract regression** | Sprint 6 collapses `_handle_direct_queue_task` and the `context["task_queue"]` orchestrated seam into a single `_handle_via_queue_task(pre_submit_hooks, post_completion_hooks, wait_timeout_s, overrides)` per the §8A.E G3 decision (UNIFY, 2026-05-05). Direct-queue tasks today wait up to 3600s (`task_registry.py:1565`); orchestrated tasks 1800s (`task_registry.py:1346-1364`). If the per-task-type timeout/cadence registry under-specifies any direct-queue task, that task silently regresses on completion semantics — and Sprint 0 baselines won't catch it unless the contract test is asserted against the recorded baseline. | (1) Sprint 0 captures per-task-type effective timeout, polling cadence, payload shape, and post-completion artifact paths into the baseline doc — not aggregated, per task type (now Sprint 0 deliverable). (2) Sprint 6 ships the lifecycle-contract test BEFORE the dispatcher refactor merges. (3) Rollback is to revert the dispatcher change and restore the dual-seam. | MITIGATED (Sprint 0/6 + S3 rollback PR) |
| **Subjective dual-run "green" gate** (H1) | Sprint 3 "green-enough" report and Sprint 7 "p95 within threshold" canary triggers were both subjective. Hidden risk: a divergent run could be silently accepted because no one wrote down the failure number. | **H1 RESOLVED 2026-05-05:** §11 pins concrete thresholds (image pHash ≤0.05, SSIM ≥0.92; video per-frame pHash mean ≤0.08 / p95 ≤0.12; latency ≤1.10×; VRAM ≤1.05×; OOM=0; canary divergence ≤1% over 24h auto-rollback). Sprint 3 dual-run script reads thresholds from `migration-thresholds.yaml`; Sprint 7 canary auto-rollback wired to same source. | MITIGATED (Sprint 0/3/7, H1) |
| **Cascading sprint slippage from missing entry gates** (S2) | Each sprint had exit criteria but no entry gates; an upstream sprint silently failing its exit criteria would let the next sprint start anyway and discover the gap mid-flight. | **S2 ADDED 2026-05-05:** every Sprint N row in §4 now carries an explicit "Entry gate" line listing what must be true before the sprint starts (Sprint 0 = §12 confidence checklist; Sprint 1 = baseline doc + thresholds + golden corpus; Sprint 4 = Sprint 3.5 PROCEED + Cohort A green; Sprint 7 = Sprint 6 contract test green + pre-staged rollback PRs drafted). | MITIGATED (Sprint 0–8) |

## 10. Closure-sweep procedure

This sweep is mandatory before and after Sprint 8. A workspace-root `git grep` is not sufficient because `reigh-worker/`, `reigh-worker-orchestrator/`, and `vibecomfy/` are independent Git repos nested under the workspace. Running `git grep` from `/Users/peteromalley/Documents/reigh-workspace` can return zero hits while committed WGP references still exist inside the nested repos.

### Option A: Git-Aware Committed-File Sweep

Use this before Sprint 8 removal to find committed files that are not already in the Section 8 checklist. Run both commands from the workspace root:

```bash
git -C reigh-worker grep -lE 'wgp_|headless_wgp|headless_model_management|mmgp|Wan2GP|WanOrchestrator|--wgp-' | sed 's|^|reigh-worker/|'
```

```bash
git -C reigh-worker-orchestrator grep -lE 'wgp_|headless_wgp|headless_model_management|mmgp|Wan2GP|WanOrchestrator|--wgp-' | sed 's|^|reigh-worker-orchestrator/|'
```

Pre-Sprint-8 rule: append any surfaced files not already listed in Section 8 to the deletion/migration checklist before starting removal. If a surfaced path is intentionally retained as archival documentation, list that retained path explicitly in this document.

### Option B: Filesystem Traversal Sweep

Use this after deletion to catch untracked files and filesystem residue:

```bash
rg -l 'wgp_|headless_wgp|headless_model_management|mmgp|Wan2GP|WanOrchestrator|--wgp-' reigh-worker/ reigh-worker-orchestrator/
```

Post-deletion rule: assert zero unexpected hits. Exclusions are limited to:

- `docs/migration-vibecomfy.md`.
- Historical changelog or docs entries explicitly retained for archive.
- Any retained path listed in this document with a reason.

If Option B finds code, tests, startup scripts, package metadata, or environment examples, Sprint 8 is not complete. Either remove/migrate the file or document the intentional retention before cutover is considered closed.

## 11. Migration thresholds (single source of truth)

**Status (2026-05-05):** Pinned. Closes H1 / Q3. All dual-run scripts (Sprint 3), pre-Sprint-4 dry run (S1), and Sprint 7 canary triggers MUST read these values from one artifact: `reigh-worker/scripts/dual_run_compare/migration-thresholds.yaml` (Sprint 0 deliverable, owned by reigh-worker, mirrors the table below). Changing a threshold requires updating both the YAML and this section in the same PR.

### Per-task-type acceptance thresholds

| Class | Metric | Threshold | Failure action |
| --- | --- | --- | --- |
| Image dual-run | Perceptual hash difference (normalized Hamming) | ≤ 0.05 | Mark task RED in Sprint 3 report; block cohort canary |
| Image dual-run | SSIM | ≥ 0.92 | Mark task RED |
| Image dual-run | Pixel dimensions | EXACT match | Mark task RED |
| Image dual-run | Format / container | EXACT match | Mark task RED |
| Video dual-run | Frame count | EXACT match | Mark task RED |
| Video dual-run | Per-frame pHash mean | ≤ 0.08 | Mark task RED |
| Video dual-run | Per-frame pHash p95 | ≤ 0.12 | Mark task RED |
| Video dual-run | Duration | within ±50ms | Mark task RED |
| Video dual-run | FPS | EXACT match | Mark task RED |
| Video dual-run | Audio duration (when present) | within ±50ms | Mark task RED |
| Latency | Comfy p95 wall-clock per task type | ≤ 1.10× WGP p95 baseline | Mark task RED; cohort canary auto-rollback if sustained 24h |
| VRAM | Comfy peak VRAM per task type per profile | ≤ 1.05× WGP peak | Mark task RED |
| Error class | OOM count over dual-run corpus | EXACTLY 0 | Block cohort canary |
| Canary divergence | Output-divergence rate per cohort (per-frame pHash p95 breach rate) | ≤ 1% of tasks over 24h window | **Auto-rollback** Sprint 7 cohort selector to `wgp` |

### Sprint 0 deliverables added by H1

- `reigh-worker/scripts/dual_run_compare/migration-thresholds.yaml` — machine-readable copy of the table above.
- `reigh-worker/scripts/dual_run_compare/golden/<task_type>/` — WGP-side golden corpus (reference outputs) for every USED task type per §0A. Sprint 3 dual-run compares Comfy outputs against this corpus + a fresh WGP run.
- Per-task-type effective timeout, polling cadence, payload shape, and post-completion artifact paths captured into `reigh-worker/docs/migration-baselines.md` per the G3 lifecycle-contract test prerequisites (§9 risk row).

### Cross-references

- Sprint 3 exit criteria: "Comparison report fails (red) if any threshold above is exceeded; green requires every task type ≤ threshold."
- Sprint 4 entry gate (S1 dry run): "Per-frame pHash mean ≤ 0.08 AND p95 ≤ 0.12 on the Wan 2.2 VACE cocktail single-shot dry run; otherwise fall back per §6 (keep Wan VACE on WGP indefinitely; remainder of migration proceeds)."
- Sprint 7 rollback trigger: auto-flip cohort to `wgp` when canary output-divergence rate >1% over 24h, OR p95 latency >1.10× baseline sustained 24h, OR OOM count >0 over 1h window.
- §6 rollback table is patched accordingly.

## 12. Pre-kickoff confidence checklist (S5)

Before Sprint 0 starts, the user (or named owner) explicitly checks each of the following. Unchecked items block kickoff.

- [ ] **Thresholds pinned** (§11 / H1) — `migration-thresholds.yaml` is committed and readable by all three consumer scripts (Sprint 3 dual-run, S1 dry run, Sprint 7 canary).
- [ ] **Per-sprint entry gates credible** (S2) — every Sprint N row in §4 has an "Entry gate" line and the predecessor sprint's exit criteria can be verified.
- [ ] **Pre-Sprint-4 dry run plan staffed** (S1) — owner named (VibeComfy maintainer + reigh-worker adapter author per §3A "Wan 2.2 VACE cocktail"); reference output identified; dry-run pod budgeted.
- [ ] **Rollback PRs have an owner** (S3) — Sprint 7 canary owner has committed to staging draft rollback PRs per cohort before promotion.
- [ ] **§8A pre-resolved queries run where possible** (H5, G8) — every AMBIGUOUS row whose query can run pre-Sprint-7 (i.e. doesn't depend on canary state) has been run; results captured against the row.
- [ ] **§9 risk table audited** (S6) — every row has a Status column value (OPEN / MITIGATED / ACCEPTED / CLOSED).
- [ ] **Pod disk size raised to 200 GB Sprint 0 baseline** (H9) — `reigh-worker-orchestrator/gpu_orchestrator/worker_spawner.py:279-281,391-395` updated; first dual-stack pod confirms it boots and downloads ready_templates models without filling disk.
- [ ] **Custom-node lockfile audited** — every template `template_routing.py` can select has its `READY_REQUIREMENTS.custom_nodes` represented in `vibecomfy/custom_nodes.lock`.

If any item is unchecked at kickoff, Sprint 0 does not start.
