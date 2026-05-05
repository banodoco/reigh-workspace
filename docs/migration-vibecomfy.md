# Migration Plan: reigh-worker Dual Execution Backend with Wan2GP and VibeComfy

> **Draft status:** Draft for migration planning, authored 2026-05-05.

This document plans the addition of VibeComfy as a peer execution backend alongside the current in-process Wan2GP backend while preserving the worker's external queue contracts, output shapes, per-task latency expectations, and non-negotiable memory-profile guarantees. The intended end state is a dual-executor worker platform: `reigh-worker/` can run WGP or VibeComfy by route selector, `vibecomfy/` supplies the ComfyUI workflow runtime, and `reigh-worker-orchestrator/` provisions GPU worker images and startup commands that understand both executors.

## Table of Contents

1. [Current worker contract](#1-current-worker-contract)
1A. [Task-type to VibeComfy template triage](#1a-task-type-to-vibecomfy-template-triage)
2. [VibeComfy capability summary](#2-vibecomfy-capability-summary)
3. [Parity gaps and required pre-cutover work](#3-parity-gaps-and-required-pre-cutover-work)
3A. [Control rails, LoRA stacking, and pre-processing — concrete recipes](#3a-control-rails-lora-stacking-and-pre-processing--concrete-recipes)
4. [Sprint-by-sprint migration plan](#4-sprint-by-sprint-migration-plan)
5. [Per-task-type cutover order](#5-per-task-type-cutover-order)
6. [Rollback plan](#6-rollback-plan)
7. [Telemetry and observability](#7-telemetry-and-observability)
8. [Dual-executor steady state](#8-dual-executor-steady-state)
9. [Open questions, assumptions, risks, and mitigations](#9-open-questions-assumptions-risks-and-mitigations)
10. [Closure-sweep procedure](#10-closure-sweep-procedure)
11. [Migration thresholds (single source of truth)](#11-migration-thresholds-single-source-of-truth)
12. [Pre-kickoff confidence checklist](#12-pre-kickoff-confidence-checklist)

Companion document: [Live Validation Plan: reigh-worker VibeComfy Migration](./migration-vibecomfy-live-validation.md). That document owns the RunPod/cloud validation strategy, worker live-test strategy, ArtAgents semantic grading, and evidence package required before canary.

## Goals

- Preserve the Supabase queue contract observed by `reigh-worker` task claim, dispatch, status update, and completion paths.
- Preserve output shapes for every `USED-IN-APP` and `USED-INDIRECTLY` runtime task type from §0A, including image, edit, orchestration, travel/join video child generation, and stitch/finalization paths.
- Preserve per-task latency SLOs or document measured exceptions before canary promotion.
- Preserve full memory-profile behavior, including low-VRAM, medium/default, high-VRAM, profiled, and per-task override semantics.
- Coordinate worker image and runtime changes with `reigh-worker-orchestrator` so provisioning, startup, health checks, and rollback all understand the selected backend.
- End with WGP and VibeComfy both available as selectable executors, with route-level backend selection and tested rollback in both directions where both routes are supported.
- Gate canary promotion on the live validation evidence package defined in `docs/migration-vibecomfy-live-validation.md`.

## Non-Goals

- No Supabase queue schema rework.
- No orchestrator scheduling or scaling algorithm changes beyond worker image/runtime selection and backend flag propagation.
- No broad `reigh-app` UI or API contract changes, except targeted resolver/API safety fixes explicitly listed as Sprint 0 blockers.
- No broad task-type redesign beyond the adapter and template-routing work required to preserve existing behavior.
- No deletion of Wan2GP runtime surfaces as part of this epic; WGP remains a supported executor in the final state.
- No Sprint 12B `reigh-app` cleanup, turbo-mode cleanup, or Supabase JSON cleanup is a migration prerequisite unless it lands before Sprint 0 baselines and those baselines are regenerated.

## Settled Decisions

- **SD-001** — Preserve current queue contracts and output shapes. _load_bearing: true_
  Rationale: `reigh-app`, orchestration handlers, and downstream completion logic depend on the existing worker-facing task contract.
- **SD-002** — Treat memory-profile parity as a pre-cutover gate. _load_bearing: true_
  Rationale: production currently relies on Wan2GP profile behavior for GPU fit, OOM avoidance, and latency/cost predictability.
- **SD-003** — Keep `reigh-worker/`, `reigh-worker-orchestrator/`, and `vibecomfy/` as independent repo workstreams. _load_bearing: true_
  Rationale: the workspace contains nested independent Git repos, so implementation, review, and closure sweeps must be scoped per repo.
- **SD-004** — Do not migrate the unused raw `comfy` task path into VibeComfy; deletion remains a cleanup candidate only after the §8A deletion gate. _load_bearing: true_
  Rationale: §0A confirms `task_type: "comfy"` is not emitted by the production app, so raw-workflow Comfy parity is not a migration gate. However, UNUSED is not by itself a deletion proof; `comfy_handler.py` / `comfy_utils.py` can be removed only after DB/admin/debug/direct-emitter checks and owner sign-off.
- **SD-005** — Treat dynamic Wan2GP model definitions as build-time frozen VibeComfy template inputs unless Q1 decides otherwise. _load_bearing: true_
  Rationale: runtime-mutable JSON model definitions are a WGP-specific flexibility point; freezing them into reviewed templates and patches lowers cutover risk and makes validation reproducible.
- **SD-006** — Keep WGP and VibeComfy coinstalled in the worker image as the steady-state architecture. _load_bearing: true_
  Rationale: production control depends on switching process-level and route-level backend selection without rebuilding the worker image, and some routes may remain WGP-preferred or WGP-only indefinitely.
- **SD-007** — Use VibeComfy cloud mode as the primary RunPod validation runner for template/runtime proof. _load_bearing: true_
  Rationale: VibeComfy already owns RunPod pod lifecycle, remote execution, matrix polling, artifact download, and termination through `scripts/runpod_runner.py` and the `runpod` command surface; the worker live harness should validate Supabase queue contracts and backend selection rather than duplicating cloud execution machinery.

## Epic Shape

This plan uses the following boundaries:

- Practical execution is sequential two-week-max sprints, with shorter 3-4 day readiness or feasibility sprints where appropriate.
- Selector and claim semantics are pulled earlier than canary readiness so orchestrated route work has a stable contract to build against.
- Sprint 4 no longer requires full worker-level orchestrated parity before parent/child propagation exists; it proves Wan template feasibility and isolated child-route behavior only.
- Cleanup is not part of migration closure unless it blocks dual-executor correctness. Deletion-gated cleanup belongs in Sprint 12B or separate post-canary PRs.
- The main canary blockers are executable contracts: selector/claim behavior, product and billing oracles, artifact lifecycle, orchestrator pool behavior, rollback repair tooling, and route-specific validation evidence.

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

### reigh-app / Supabase

- `reigh-app/supabase/functions/create-task/resolvers/`
- `reigh-app/supabase/functions/create-task/resolvers/registry.ts`
- `reigh-app/supabase/functions/complete_task/`
- `reigh-app/supabase/functions/ai-timeline-agent/`
- `reigh-app/src/shared/lib/tasks/travelBetweenImages/`
- `reigh-app/src/tools/travel-between-images/`
- `reigh-app/src/tools/video-editor/`
- Supabase migrations that touch task params, travel settings, gallery/lightbox/timeline output metadata, billing/credits, or persisted share/history data.

### Repository Layout For Closure Sweeps

`reigh-worker/`, `reigh-worker-orchestrator/`, and `vibecomfy/` are independent Git repos nested in the workspace. Any Git-aware closure sweep must run per repo, for example with `git -C reigh-worker grep ...` and `git -C reigh-worker-orchestrator grep ...`; a workspace-root `git grep` does not traverse those nested repo histories and can return zero hits for committed files that still exist inside the nested repos.

## External Reference Resources

Template, model, sampler, LoRA, and control-rail decisions must cite the basis used to recreate current behavior. Use the following sources in this order when authoring or materially changing a VibeComfy route:

1. Existing `reigh-worker/` behavior: current task mappings, WGP defaults, live-test inputs, LoRA setup, runtime model patching, and production-shaped scripts.
2. Wan2GP upstream: model defaults, sampler and LoRA recipes, memory-profile behavior, prompt expansion, and control-rail conventions.
3. AI workflow / best-practices Discord `message_feed`: practical ComfyUI graph, sampler, model, and custom-node notes when local/upstream sources disagree or are incomplete.

Default rule: do not invent a default that the current worker already ships. If the sources disagree, record the disagreement as an open question or route-specific risk before promotion.

## 0A. Project generation scope and RayWorker migration scope

This section classifies the active project generation surface, then distinguishes which routes need RayWorker/WGP-to-VibeComfy parity. The epic includes active app generation routes even when they are currently handled by Cloud Worker or another non-RayWorker service, because their contracts still need to be preserved through the migration. However, only RayWorker-owned WGP routes require VibeComfy template/adapter parity unless a route is explicitly moved into RayWorker.

`UNUSED` means "not emitted by the current app resolver surface into a RayWorker-owned task type"; it is sufficient to remove a task type from VibeComfy parity gates, but it is **not** sufficient by itself to delete worker code. Any deletion of an UNUSED task type requires the §8A deletion gate: DB checks for pending/in-progress/recent rows, edge-function and admin/debug emission checks, and owner sign-off.

Authoritative emit surface is `reigh-app/supabase/functions/create-task/resolvers/*.ts` plus the family map at `reigh-app/supabase/functions/create-task/resolvers/registry.ts:16-30`. Family is the public input; the resolver decides which `task_type` is written to the `tasks` table.

Active non-RayWorker routes included in the epic: `video_enhance` / FILM / FlashVSR, `image-upscale`, `animate_character`, and `flux_klein_edit`. Their required work is contract preservation, ownership clarity, cost/completion/output validation, and regression coverage. They are **not** VibeComfy template parity gates unless Sprint 0 explicitly decides to move one into RayWorker.

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
| `video_enhance` | USED-NON-RAYWORKER | `reigh-app/supabase/functions/create-task/resolvers/videoEnhance.ts:159`; UI caller `useVideoEnhance.ts`; AI timeline agent `generation.ts` | FILM interpolation + FlashVSR upscale params | Included in the epic as an active product route, but not a RayWorker/VibeComfy parity gate unless explicitly moved into RayWorker. Preserve cost, completion, output, and UX contract. |
| `image-upscale` | USED-NON-RAYWORKER | `reigh-app/supabase/functions/create-task/resolvers/imageUpscale.ts:72,80`; UI caller `useUpscale.ts` | Hyphenated `task_type: "image-upscale"`; note older underscore metadata exists | Included in the epic as an active product route. Preserve naming, variant metadata, output, and billing/completion behavior. |
| `animate_character` | USED-NON-RAYWORKER | `reigh-app/supabase/functions/create-task/resolvers/characterAnimate.ts:53,59`; frontend `characterAnimate.ts`; AI timeline agent `generation.ts` | Character animation route | Included in the epic as an active product route. Preserve owner, completion/output contract, and canary regression coverage. |
| `flux_klein_edit` | USED-NON-RAYWORKER | `reigh-app/supabase/functions/create-task/resolvers/kleinEdit.ts:97,108`; UI `useMagicEditMode.ts` | Klein edit path; distinct from legacy RayWorker `flux` task type | Included in the epic as an active product route. Do not use legacy RayWorker `flux` cleanup as proof this route is safe. |
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
| `rife_interpolate_images` | UNUSED | No `task_type: "rife_interpolate_images"` literal in `reigh-app/`. | None | RayWorker still has a native RIFE dispatch handler, but current app interpolation is handled outside this RayWorker migration. Keep or delete only through the §8A cleanup gate. |

UNUSED roll-up (cite per row above; aggregate cite: searching `reigh-app/` for `task_type: "<name>"` literal strings returned zero hits for each):

- `hunyuan` (confirmed: `rg -i '\bhunyuan\b|\bhyvid\b' reigh-app/ → 0 hits`)
- `flux`, `t2v`, `t2v_22`, `i2v`, `i2v_22`, `vace`, `vace_21`, `vace_22`, `ltxv`, `ltx2`, `generate_video`, `qwen_image_hires`, `magic_edit`, `inpaint_frames`, `comfy`, `create_visualization`, `extract_frame`, `rife_interpolate_images`

AMBIGUOUS roll-up for **migration parity**: none. Every classification above is a deterministic literal-string match against the current resolver surface; no feature flags, A/B tests, or admin debug surfaces were found in the app emit path. Deletion safety remains a separate cleanup question and must use the §8A deletion gate because old queued rows, direct DB inserts, admin tools, or retry/history paths can exist outside the current resolver surface.

The `USED-NON-RAYWORKER` rows are included in product/regression scope but excluded from RayWorker VibeComfy parity scope. Sprint 0 must name the owning runtime for each and decide whether the epic merely preserves the current Cloud Worker/external route or intentionally moves it into RayWorker. If a route moves into RayWorker, it becomes a new RayWorker migration row and must receive its own template/adapter/canary plan before promotion.

App-side discrepancy: `travelBetweenImages.ts:315` emits `task_type: "wan_2_2_i2v"` when `input.turbo_mode === true`. This task type is **not** in the worker's `TASK_TYPE_TO_MODEL` (`reigh-worker/source/task_handlers/tasks/task_types.py:82-117`) or `task_registry` dispatch map. The UI toggle is commented out, but §8A confirms AI/timeline-agent plumbing can still pass `turbo_mode`; therefore this is an **active pre-kickoff contract risk**, not resolved cleanup. Before Sprint 0 baselines freeze, either remove the AI-agent/schema path or add resolver-side validation/tests proving `turbo_mode: true` is rejected or coerced to the safe `travel_orchestrator` path.

## 1. Current worker contract

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

The full RayWorker dispatch surface is the union of `TASK_TYPE_CATALOG` in `source/task_handlers/tasks/task_types.py:120-138` and the specialized dispatch keys in `source/task_handlers/tasks/task_registry.py:1442-1511`. Friendly names come from `source/core/log/display_names.py:8-45`; `rife_interpolate` is a friendly alias only, while the runtime dispatch key is `rife_interpolate_images`. Do not use `dispatch_manifest.py` as the migration source of truth until it is reconciled with `TaskRegistry.dispatch`; it currently lists only a subset of live specialized handlers.

| task_type | Source of truth | default_model | dispatch_path | Current handler module | Output shape | Alias | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `annotated_image_edit` | `task_types.py:106-110,120-138` | `qwen_image_edit_20B` | Direct queue via `_handle_direct_queue_task` | `task_conversion.py` + `QwenHandler.handle_annotated_image_edit` | Single image path | Annotated Image Edit | Empty prompt allowed; Qwen edit family. |
| `comfy` | `task_registry.py:1507-1510` | N/A | Specialized handler | `source/models/comfy/comfy_handler.py` | First downloaded Comfy output path | ComfyUI | Existing raw-workflow Comfy path; UNUSED per §0A and not migrated; deletion is Sprint 12B / cleanup-gated only. |
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
        travel_segment / join_clips_segment / inpaint_frames
          -> handler-specific media prep
          -> child GenerationTask
          -> HeadlessTaskQueue.submit_task(...)
          -> handler-specific post-processing
     -> Native utility / orchestration handlers
        extract_frame / create_visualization / rife_interpolate_images / stitchers / parent orchestrators
          -> no VibeComfy template; preserve output/completion contract or mark cleanup-gated
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
| RIFE temporal interpolation | `vendor_imports.py:47-55`; `wgp_bridge.py:34,41-42` | Native `rife_interpolate_images` handler. Current exact call sites do not show active travel-orchestrator use. | Not a VibeComfy parity gate because the task type is UNUSED; keep vendored helper until §8A proves dispatch/history/admin paths are safe to remove. |
| Wan2GP `save_video` | `vendor_imports.py:58-73`; `wgp_bridge.py:45-46` | `source/media/structure/{generation.py,compositing.py}` video writing. | Gap: Comfy outputs files, but no callable parity for existing helper. |
| Qwen family handler | `vendor_imports.py:76-78`; `wgp_bridge.py:30` | WGP monkeypatch routes Qwen-family model loading. | Gap: replace with explicit Qwen templates/routes. |
| Shared LoRA utils | `vendor_imports.py:81-83`; `wgp_bridge.py:32` | LoRA multiplier parsing and setup patches. | Gap: VibeComfy needs LoRA widget wiring plus reigh-worker LoRA-file sanitizer pre-processing. |
| Qwen main module | `vendor_imports.py:86-88`; `wgp_bridge.py:31` | Qwen inpainting LoRA patching. | Gap: model-specific Comfy template policy needed. |
| Flow annotator | `vendor_imports.py:91-93`; `wgp_bridge.py:27` | Structure preprocessing. | Gap: pre-process before VibeWorkflow or package as extra nodes. |
| Flow visualization | `vendor_imports.py:96-98`; `wgp_bridge.py:28` | Optical-flow visualization in structure preprocessing. | Gap: no VibeComfy re-export. |
| Canny annotator | `vendor_imports.py:101-103`; `wgp_bridge.py:25` | Control/structure guide creation. | Gap: pre-process before workflow build or add VibeComfy extra. |
| DepthV2 annotator | `vendor_imports.py:106-108`; `wgp_bridge.py:26` | Depth guide creation/download flow. | Gap: pre-process before workflow build or add VibeComfy extra. |
| Pose annotator | `vendor_imports.py:111-113`; `wgp_bridge.py:29` | Pose/DWPose guide creation. | Gap: pre-process before workflow build or add VibeComfy extra. |
| Uni3C cache/controlnet loader | `vendor_imports.py:116-132`; `model_ops.py:234-260` | Cached Uni3C ControlNet loading for guided Wan generation. | Gap: no VibeComfy cache abstraction; likely Comfy ControlNet patch plus cache policy. |

### Existing ComfyUI Integration in reigh-worker

`source/models/comfy/comfy_handler.py` already handles the `comfy` task type, but it is a separate raw-Comfy path rather than a VibeComfy adapter. It imports `ComfyUIManager`, `ComfyUIClient`, `COMFY_PATH`, and `COMFY_PORT` from `source/models/comfy/comfy_utils.py:15`; lazy-starts a `python main.py --listen 0.0.0.0 --port ...` subprocess through `ComfyUIManager` at `comfy_utils.py:25-60`; submits raw workflow JSON to `/prompt` through `ComfyUIClient` at `comfy_utils.py:126-142`; polls `/history/{prompt_id}` and downloads outputs at `comfy_utils.py:144-199`; then writes the first output under `main_output_dir_base / "comfy"` at `comfy_handler.py:164-175`.

The dispatch branch is `source/task_handlers/tasks/task_registry.py:1507-1510`. Dependent tests include `reigh-worker/tests/test_additional_coverage_modules.py:205-219` and coverage imports in `tests/test_wan2gp_direct_coverage_contracts.py:412-413,960-961`. Because §0A confirms raw `comfy` is UNUSED, Section 3 does not preserve raw workflow parity. The handler/util files are cleanup candidates only after the §8A deletion gate; until then they remain WGP/raw-Comfy legacy code and are not part of the VibeComfy adapter.

### Error Paths and Telemetry

WGP errors are not always raised as Python exceptions, so `source/models/wgp/error_extraction.py:13-90` scans captured stdout/stderr for OOM, CUDA, model-loading, and generic Python error patterns. Worker failure handling then classifies retryable errors in `source/runtime/worker/server.py:740-757` and requeues or fails tasks.

Logging suppresses known noisy substrings and third-party loggers, including `mmgp`, in `source/core/log/core.py:57-64` and `core.py:108-113`. The queue performs post-task memory cleanup without unloading models via `source/task_handlers/queue/memory_cleanup.py:16-75`, exposed through `HeadlessTaskQueue._cleanup_memory_after_task` at `task_queue.py:343-345`; that cleanup also clears unused Uni3C cache before CUDA/Python garbage collection at `memory_cleanup.py:41-51`. WGP output telemetry includes `source/models/wgp/generators/output.py:182-208`, which logs RAM and CUDA allocated/reserved/total VRAM. The migration needs Comfy/VibeComfy equivalents for these memory stats, task log anchoring, retry classification, and debug-card breadcrumbs.

### Worker-Orchestrator Coupling

`reigh-worker-orchestrator` has hardcoded Wan2GP startup assumptions:

| Coupling | Source | Migration implication |
| --- | --- | --- |
| Legacy worker directory fallback `Headless-Wan2GP` | `gpu_orchestrator/runpod/worker_startup.template.sh:174` and fallback branch at `179-183` | Keep if required for WGP startup; rename only if it improves dual-stack clarity without breaking WGP. |
| Wan2GP submodule reconciliation | `worker_startup.template.sh:267-292` | Preserve WGP submodule reconciliation while WGP remains a supported executor. Only stale cleanup logic that prevents dual-stack startup should change; `Wan2GP/` itself is retained in this epic. |
| Production profile default | `worker_startup.template.sh:463` | Preserve `--wgp-profile 1` for WGP workers. Add a separate VibeComfy profile flag/env for Comfy workers after profile parity exists; do not rename or remove WGP flags in this migration. |
| Pod disk sizing | `gpu_orchestrator/worker_spawner.py:279-281` and `391-395` | Sprint 0C records the decision to raise the RunPod baseline from the current 50 GB to 200 GB, then validates actual first-pod boot usage. If first boot exceeds 180 GB, raise to 250 GB before Sprint 1. |
| Worker image Dockerfile | `gpu_orchestrator/Dockerfile` | Preserve Wan2GP install steps required by WGP workers; add VibeComfy/custom-node/model assets alongside them for the dual-stack image. |
| `mmgp` runtime dependency | `reigh-worker/pyproject.toml:13` | `mmgp==3.7.6` is WGP-specific and retained while WGP remains supported. Remove only in a separate WGP-retirement epic. |

## 1A. Task-type to VibeComfy template triage

Section 1 enumerates the runtime task surface; Section 2 owns the live ready-template inventory under `vibecomfy/ready_templates/`. This section closes the gap between them by classifying every runtime task type (`source/task_handlers/tasks/task_types.py:120-138` ∪ `source/task_handlers/tasks/task_registry.py:1442-1511`) into one of three dispositions:

- **NATIVE** — a `ready_templates/**` template is the direct execution unit; only parameter wiring (prompt, image inputs, seed, resolution, profile overlay) is required.
- **ADAPT** — an existing template is the closest basis but needs concrete graph edits or patches (added/removed nodes, swapped LoRA loaders, control rails spliced in via `replace_edge`, output shape coercion).
- **NEW** — no usable basis exists in `ready_templates/`; a new ready template must be authored against a named ComfyUI workflow / model family before the cohort can canary.

The `concrete edits required` column lists graph-level deltas only, not parameter wiring. Section 3A pins the recipes for the LoRA, control-rail, travel-continuity, and prompt-expander edits that recur across rows.

Rows marked `NO (UNUSED)` are scope notes, not migration work. They must not create sprint deliverables, template-authoring tasks, owner assignments, or validation gates unless the task type is reintroduced by a separate product decision. If this table is used for implementation planning, filter to `Required by app? = YES` plus USED-INDIRECTLY child routes first; UNUSED rows are cleanup-gated inventory only, even when they contain old template analysis.

| task_type | Required by app? | disposition | target template path or basis | concrete edits required | control rails | LoRA handling | cohort/sprint |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `z_image_turbo` | YES (USED-IN-APP) | NATIVE | `ready_templates/image/z_image.py` | None (prompt is registered via `register_input` per `vibecomfy/docs/authoring.md:164`). | None | None | A / Sprint 2 |
| `z_image_turbo_i2i` | YES (USED-IN-APP) | ADAPT | `ready_templates/image/z_image.py` | Add `LoadImage` + `VAEEncode` and splice the latent into the sampler input that currently feeds from `EmptyLatentImage`; change `register_input` for `image` (Section 3A "i2i input adapter"). | None | None | A / Sprint 2 |
| `qwen_image` | YES (USED-IN-APP) | ADAPT / VERIFY | Non-2512 Qwen image route to be proven in Sprint 5; do not treat `ready_templates/image/qwen_image_2512.py` as a drop-in. | Validate the true WGP-equivalent model/template path for `model: "qwen-image"`; only then wire prompt, seed, resolution, and optional LoRA handling. | None | LoRA optional; use the same validated Qwen LoRA chain/sanitizer pattern as the edit route where applicable. | A / Sprint 5 |
| `qwen_image_2512` | YES (USED-IN-APP) | NATIVE | `ready_templates/image/qwen_image_2512.py` | None | None | None by default | A / Sprint 2 |
| `flux` (all variants: dev, schnell, dev_kontext) | NO (UNUSED) | **OUT OF SCOPE per §0A.** | n/a | n/a | n/a | n/a | If reintroduced, treat as a separate project. |
| `wan_2_2_t2i` | YES (USED-IN-APP — production default for image-gen tool) | ADAPT | `ready_templates/video/wanvideo_wrapper_22_5b_t2v_controlnet.py` (or `wan_t2v.py` after profile fit) | Force `num_frames=1` on the WanVideo sampler/encode nodes; the `forced_video_length=1` flag at `task_types.py:135` must be applied as a small patch over a Wan T2V template since no `wan_2_2_t2i` template exists. | None | Wan templates use `WanVideoLoraSelect` (kj wrapper, `wanvideo_wrapper_21_14b_i2v.py:79-91`), not `LoraLoaderModelOnly`. | A / Sprint 4 |
| `qwen_image_edit` | YES (USED-IN-APP) | NATIVE | `ready_templates/edit/qwen_image_edit.py` | None | None | Built-in `LoraLoaderModelOnly` for Qwen-Image-Edit-Lightning at `edit/qwen_image_edit.py:112-130`; reigh-worker sanitizer pre-process (Section 3A) applies if user LoRAs are stacked on top. | B / Sprint 5 |
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
| `comfy` | NO (UNUSED) | OUT OF SCOPE — cleanup-gated | N/A | Raw workflow submission is not migrated. `comfy_handler.py` and `comfy_utils.py` remain legacy code until the §8A deletion gate passes, then can be deleted in Sprint 12B or a separate cleanup PR. | N/A | N/A | Sprint 12B cleanup candidate |
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

Disposition counts before production filtering are historical planning context only. They are **not** the migration scope.

**Authoritative migration scope after §0A production-usage filter:** 17 task types are in scope, and 19 task types are dropped as UNUSED (see §0A roll-up).

| Scope bucket | Task types | Template implication |
| --- | --- | --- |
| Cohort A direct image/single-frame | `z_image_turbo`, `z_image_turbo_i2i`, `qwen_image`, `qwen_image_2512`, `wan_2_2_t2i` | 2 native routes, 3 adapted routes. Direct `t2v`/`i2v` task types are not scope substitutes. |
| Cohort B edit image | `qwen_image_edit`, `qwen_image_style`, `image_inpaint`, `annotated_image_edit` | Qwen edit template plus prompt/input/mask/annotation/LoRA preprocessing parity. |
| Cohort E orchestration and child video | `travel_orchestrator`, `travel_segment`, `individual_travel_segment`, `travel_stitch`, `join_clips_orchestrator`, `join_clips_segment`, `join_final_stitch`, `edit_video_orchestrator` | Orchestrators/stitchers are no-template routes; `travel_segment`, `individual_travel_segment`, and `join_clips_segment` need the §3A travel/join matrix. Wan-family rows depend on the one NEW Wan 2.2 VACE cocktail template. |

The only NEW template required by the migration is `ready_templates/video/wanvideo_wrapper_22_14b_vace_cocktail.py`, and it is required only for USED indirect Wan-family travel/join segment routes. `hunyuan`, `flux`, direct `t2v`/`i2v`/`vace`, direct LTX task types, raw `comfy`, `rife_interpolate_images`, utility handlers, and other UNUSED rows are cleanup/removal scope, not migration parity scope.

Section 5 is patched downstream to surface the ADAPT/NEW dispositions per cohort so promotion gates check template readiness, not just queue-seam readiness.

## 2. VibeComfy capability summary

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
| ~~No Hunyuan ready template~~ | `find vibecomfy/ready_templates -type f -name '*hunyuan*'` returns zero files. | CLOSED: `hunyuan` is UNUSED per §0A and is not a migration gate. |
| No LoRA-key sanitizer equivalent | Current sanitizer is WGP monkeypatch code in `source/models/wgp/wgp_patches.py:384-483`. | Needed before Qwen/LoRA-heavy cutover; owned as a reigh-worker pre-process, not a VibeComfy graph patch. |
| No Uni3C ControlNet cache | Current cache is in `source/models/wgp/model_ops.py:234-260` via `load_uni3c_controlnet`. | Needed for guided Wan/VACE parity. |
| ~~No RIFE temporal interpolation helper~~ | Current helper is `vendor_imports.py:47-55`. | CLOSED for this migration: `rife_interpolate_images` is UNUSED as a RayWorker migration task type. Keep the native helper/handler until §8A proves no pending/history/admin path still depends on it. |
| No Qwen prompt expander wrapper | Current helper is `vendor_imports.py:32-45`. | Needs pre-processing equivalent if any task depends on WGP expander behavior. |
| No Canny/Depth/Flow/Pose annotator re-exports | Current helpers are `vendor_imports.py:91-113`. | Pre-process before workflow build or expose extras. |
| No Wan2GP `save_video` callable | Current callable is `vendor_imports.py:58-73`. | Existing media helpers need replacement or isolation. |

## 3. Parity gaps and required pre-cutover work

This section turns the current worker contract and VibeComfy capability summary into required pre-cutover work. P0 items block any production canary; P1 items block the cohort that depends on them; P2 items can trail behind dual-run if rollback remains available and output contracts are preserved.

### Parity Gap Matrix

| Capability | Current Wan2GP location | VibeComfy current state | Required work | P-priority | owner-repo | Target sprint |
| --- | --- | --- | --- | --- | --- | --- |
| Five-tier memory profiles and global default profile | `reigh-worker/source/runtime/worker/server.py:556-558,605-609`; prod default in `worker_startup.template.sh:463`; dev defaults in `start_worker.bat:14` and `scripts/live_test/{main,smoke}.py:27` | Lower-level `SessionConfig` knobs only at `vibecomfy/vibecomfy/runtime/session.py:45-53` | Add `vibecomfy.runtime.profile.MemoryProfile` overlay and map profiles 1-5 to `SessionConfig` overrides; baseline prod profile 1 and dev profile 3 | P0 | `vibecomfy` | Sprint 1 |
| Per-call profile override | `reigh-worker/source/models/wgp/generators/wgp_params.py:166,237,374` | No task-level profile field or override semantics | Add `override_profile` handling in the reigh-worker adapter that resolves to `MemoryProfile.to_session_overrides()` before constructing the VibeComfy `SessionConfig` | P0 | `reigh-worker` + `vibecomfy` | Sprint 1-2 |
| Direct task-type routing to templates | USED direct task types from §0A | Ready templates exist for the in-scope image/edit families, but no reigh-worker routing registry | Add `reigh-worker/source/models/comfy/template_routing.py` for USED routes only; unsupported UNUSED task types fail closed under Comfy selection | P0 | `reigh-worker` | Sprint 2 |
| ~~Hunyuan task parity~~ — **REMOVED FROM SCOPE** (per §0A: app emits zero `hunyuan` tasks; `rg -i 'hunyuan\|hyvid' reigh-app/ → 0 hits`) | `hunyuan` in `source/task_handlers/tasks/task_types.py:99-101,120-138` | No `ready_templates/video/hunyuan_*`; live `find ... -name '*hunyuan*'` returns zero template files | ~~Ship Hunyuan ready template~~. Worker handler can stay; no parity work needed since no production traffic exercises this task type. | P3 (defer indefinitely) | — | — |
| Wan/VACE/Uni3C guided-video parity | `vace*`, `t2v*`, `i2v*`; Uni3C cache in `source/models/wgp/model_ops.py:234-260` | Wan and VACE template candidates exist; no Uni3C cache abstraction | Represent Uni3C as VibeComfy patches over Wan 2.2 templates, with explicit cache/model lifecycle policy | P1 | `vibecomfy` + `reigh-worker` | Sprint 4 |
| Qwen image/edit, VLM, and prompt-expander parity | Qwen handlers in direct queue conversion; prompt expander from `source/runtime/wgp_ports/vendor_imports.py:32-45`; travel/join/edit-video VLM service under `source/media/vlm/` | Qwen image/edit template candidates exist; no prompt-expander wrapper or backend-neutral VLM/model-metadata provider | Run Qwen prompt expansion and route-specific VLM prompt generation as reigh-worker pre-processing before workflow build; replace WGP metadata lookups used by orchestration with a backend-neutral provider or frozen table | P1 | `reigh-worker` | Sprint 5-8 |
| LoRA-key sanitizer | `source/models/wgp/wgp_patches.py:384-483`; LoRA setup in `source/models/wgp/lora_setup.py` | No VibeComfy-safe sanitized-file pre-process | Implement `reigh-worker/source/models/comfy/lora_sanitize.py` to sanitize LoRA files before workflow build; VibeComfy receives sanitized filenames only; add golden LoRA corpus tests | P1 | `reigh-worker` | Sprint 5 |
| Canny/Depth/Pose/Flow preprocessing | `source/runtime/wgp_ports/vendor_imports.py:91-113`; flow visualization at `vendor_imports.py:96-98` | No VibeComfy re-exports | Keep annotators as reigh-worker pre-processing before workflow build until moved to a VibeComfy extras package | P1 | `reigh-worker` | Sprint 9 |
| ~~RIFE interpolation task parity~~ | `source/runtime/wgp_ports/vendor_imports.py:47-55`; `source/task_handlers/rife_interpolate.py` | No VibeComfy helper | CLOSED for migration: task type is UNUSED. Keep native RIFE code until the cleanup gate proves there are no pending rows, direct emitters, admin tools, or retry/history paths that can still enqueue it. | P3 | `reigh-worker` | Sprint 12B cleanup candidate |
| ~~Existing raw `comfy` task path~~ | `source/models/comfy/comfy_handler.py`; `source/models/comfy/comfy_utils.py`; dispatch at `task_registry.py:1507-1510` | Separate Comfy subprocess/client stack, not VibeComfy | CLOSED for migration: raw `comfy` is UNUSED per §0A and is not refactored into VibeComfy. Handler/util deletion is Sprint 12B / cleanup-gated only. | P3 | `reigh-worker` | Sprint 12B cleanup candidate |
| Model load/unload lifecycle | `source/models/wgp/model_ops.py`; runtime mutation in `source/runtime/wgp_ports/runtime_registry.py` | `EmbeddedSession` supports `start`, `run`, `flush`, `reconfigure`, `stop`; no WGP-like model-definition loader | Use a long-lived `EmbeddedSession` per worker, explicit profile reconfiguration policy, and build-time frozen template/model definitions pending Q1 | P0 | `reigh-worker` + `vibecomfy` | Sprint 1-2 |
| Queue and child-task adapter seams | Direct seam at `_handle_direct_queue_task`; nested seam via handlers receiving `context["task_queue"]`; direct queue currently converts through WGP-specific `_convert_to_wgp_task` during `submit_task` | No reigh-worker adapter yet | Add a backend-neutral resolved-task boundary before WGP-specific conversion; thread `REIGH_BACKEND` and selector route through both direct conversion and child-task enqueue paths; preserve existing queue statuses/output shapes | P0 | `reigh-worker` | Sprint 2 |
| Observability and debug-card telemetry | Heartbeat/system logs in worker server, WGP memory stats in `source/models/wgp/generators/output.py:182-208`, debug-card path in `source/core/log/debug_card.py` | `RunResult` has `run_id`, `prompt_id`, `outputs`, `metadata_path`, `log_path` | Translate `RunResult` into existing heartbeat logs, `system_logs`, and debug-card breadcrumbs; add backend/template labels and VRAM stats | P0 | `reigh-worker` | Sprint 2-3 |
| RunPod/orchestrator worker-image coupling | `worker_startup.template.sh:174,179-183,267-292,463`; `gpu_orchestrator/runpod/startup_script.py` | VibeComfy has a RunPod CLI path, but reigh-worker will still be orchestrator-provisioned | Propagate backend/profile flags through the existing orchestrator startup path; keep both stacks installed permanently as selectable executors | P1 | `reigh-worker-orchestrator` | Sprint 7-8 |

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
| `5` | `MINIMUM` | `{"vram_policy": "low", "cache_policy": "lru:1", "disable_smart_memory": True, "reserve_vram_gb": 4.0}` (`lru:1` keeps Uni3C-supported profile-5 runs functional with a tiny cache footprint instead of forcing full controlnet reloads every run.) |

`reigh-worker` must mirror WGP `override_profile` semantics: the process default profile is used when no task override is present, and a per-call `override_profile` replaces the default for that single VibeComfy run. The adapter should resolve `override_profile` before workflow execution, not mutate process-global defaults.

Acceptance gates:

- Profile values 1-5 round-trip through `MemoryProfile` into both embedded configuration and managed-server argv tests.
- Profile 1 parity smoke tests use the production baseline from `worker_startup.template.sh:463`.
- Profile 3 parity smoke tests use the development baselines from `start_worker.bat:14` and `scripts/live_test/{main,smoke}.py:27`.
- Sprint 1 smoke coverage is template-level because the worker adapter does not exist yet. Sprint 2 adds worker-route smokes for at least one image path (`z_image_turbo` or `qwen_image_2512`), one direct Wan single-frame path (`wan_2_2_t2i`), and one real video child route (`travel_segment` or `join_clips_segment`), with VRAM peak, wall-clock latency, OOM count, and output-shape checks.
- Before canary, profile coverage includes process default plus per-task `override_profile`, profiles 1 and 3 for every promoted cohort route, profiles 4 and 5 for the heaviest Wan VACE/LTX/Qwen-edit paths, and parent-to-child profile inheritance for Cohort E.

### Task-Type to VibeComfy Template Registry

Add `reigh-worker/source/models/comfy/template_routing.py` as the adapter's registry and keep it as the only genuinely new file under `source/models/comfy/`. Existing imports that need template lookup should call this registry; they should not scatter task-type conditionals across handlers.

The registry must cover the full union task surface from Section 1:

| Task surface | Registry behavior | Gate |
| --- | --- | --- |
| `z_image_turbo`, `z_image_turbo_i2i` | Route to `image/z_image` with i2i-specific input patching where needed | Cohort A |
| `qwen_image_2512` | Route to `image/qwen_image_2512`; preserve output image shape | Cohort A |
| `qwen_image` | Route only after Sprint 5 proves the non-2512 WGP-equivalent model/template path; do not silently reuse the 2512 route | Cohort A |
| ~~`flux`~~ — **UNUSED, skip per §0A** | No route required; worker handler is unreachable from app | — |
| `wan_2_2_t2i` | Route through Wan template with single-frame output contract | Cohort A |
| `qwen_image_edit`, `qwen_image_style`, `image_inpaint`, `annotated_image_edit` | Route to `edit/qwen_image_edit` plus prompt/input wiring, LoRA widget edits, and reigh-worker LoRA-file sanitizer pre-process | Cohort B |
| ~~`qwen_image_hires`~~ — **UNUSED, skip per §0A** (hires-fix is layered as `hires_*` payload params on `qwen_image_edit`, not a separate task type) | — | — |
| ~~`t2v`, `t2v_22`, `i2v`, `i2v_22`, `generate_video`~~ — **UNUSED, skip per §0A** | — | — |
| ~~`ltxv`, `ltx2`~~ — **UNUSED, skip per §0A** (LTX models are reachable through `travel_orchestrator` with `model_name="ltx2_*"`, not as direct task types) | — | — |
| ~~`vace`, `vace_21`, `vace_22`~~ — **UNUSED as direct task types, skip per §0A**; the Wan 2.2 VACE cocktail **model** is still required indirectly via the travel/join segment paths | — | — |
| ~~`hunyuan`~~ — **UNUSED, removed from scope per §0A** | — | — |
| `travel_orchestrator`, `travel_segment`, `individual_travel_segment`, `travel_stitch`, `join_clips_orchestrator`, `join_clips_segment`, `join_final_stitch`, `edit_video_orchestrator` | Preserve specialized handlers; child generation delegates into VibeComfy where applicable | Cohort E |
| ~~`inpaint_frames`, `magic_edit`, `create_visualization`, `extract_frame`, `rife_interpolate_images`, `comfy`~~ — **UNUSED, skip per §0A** | Worker handlers stay installed for backwards compat; no migration work | — |

Any task type missing from `template_routing.py` should fail closed during VibeComfy backend selection with a typed unsupported-template error, not silently fall back to WGP unless the selector explicitly chose WGP before task claim.

### Missing-Template Gates

Only active cohorts have missing-template gates. Removed/UNUSED cohorts are historical context and must not block migration.

| Gap | Affected cohort | Go/no-go rule |
| --- | --- | --- |
| Qwen edit/input variants | Cohort B | No Cohort B promotion until `qwen_image_edit`, `qwen_image_style`, `image_inpaint`, and `annotated_image_edit` each have template/preprocess tests and output-contract assertions. `qwen_image_hires` is not a task-type gate because it is UNUSED. |
| Wan 2.2 VACE cocktail | Cohort E Wan-family travel/join rows | No Wan-family `travel_segment`, `individual_travel_segment`, or `join_clips_segment` promotion until `wanvideo_wrapper_22_14b_vace_cocktail.py` passes Sprint 3.5/4 thresholds. |
| LTX travel rows | Cohort E LTX-family travel rows | No LTX-family travel promotion until the selector can distinguish LTX routes from Wan routes and the §3A LTX rows pass through the current dispatcher. Dispatcher unification is optional. |
| Travel/join matrix | Cohort E | No Cohort E promotion until every non-FALL-BACK §3A matrix row has a passing smoke through the current dispatcher; Sprint 7 consumes this evidence rather than discovering it. |

### Vendor-Utility Shims

Vendor utility ownership should be explicit rather than hidden behind `wgp_bridge.py` compatibility imports:

| Utility | Migration decision | Rationale |
| --- | --- | --- |
| RIFE temporal interpolation | Keep vendored under `reigh-worker/source/media/` and invoke from `rife_interpolate_images` outside VibeComfy. | It is a media post-processing helper, not a workflow-template concern. |
| Uni3C ControlNet | Implement as a VibeComfy patch on Wan 2.2 templates. | It affects workflow graph/control inputs and belongs near template validation. |
| Canny, Depth, Pose, Flow annotators | Run as reigh-worker pre-processing before workflow build. | They transform input media into guide assets that templates consume. |
| Qwen prompt expander | Run as reigh-worker pre-processing before workflow build. | It changes prompt text, not Comfy graph topology. |
| LoRA-key sanitizer | Run as a reigh-worker pre-process that writes sanitized LoRA files and passes sanitized filenames into VibeComfy. | It mutates tensor files, not graph topology; keeping it out of VibeComfy avoids global Comfy loader monkeypatches. |

### Dynamic Model Definitions and Model Lifecycle

Recommendation for Open Question Q1: freeze dynamic Wan2GP model definitions into VibeComfy templates and patches at build time. Wan2GP can load JSON model definitions from `Wan2GP/defaults/*` and `Wan2GP/profiles/*` through `load_missing_model_definition`, but carrying that dynamism into VibeComfy would weaken template validation and make rollback comparisons harder to reproduce.

The cutover design should use a long-lived VibeComfy `EmbeddedSession` as the analogue of the current in-process WGP backend. Model management work before cutover:

- Define which template/model packages are present in the worker image at build time.
- Define when `EmbeddedSession.reconfigure()` is allowed for profile changes, and when the worker must restart instead.
- Preserve queue-visible load/unload behavior even if the implementation becomes "select template and warm session" rather than WGP's `load_model_impl` / `unload_model_impl`.
- Keep `headless_model_management` behavior under review until Q11 decides whether any non-WGP callers require migration rather than deletion.

### Dual-Executor Architecture

Running WGP and VibeComfy from the same worker image is expected and required for rollback. Running both as hot, co-resident executors inside one long-lived Python process is **not supported as a production design**: WGP mutates `sys.path`, monkeypatches vendor modules, stores model/runtime state in globals, and owns CUDA cleanup assumptions; VibeComfy embedded sessions also manage Comfy globals and GPU caches. Keeping both warm in one process would make import order, global patches, memory fragmentation, and cleanup failures hard to diagnose.

Primary architecture:

```text
same dual-stack worker image
  -> wgp worker process/pool:    reigh-worker --backend wgp
  -> comfy worker process/pool:  reigh-worker --backend comfy
  -> task claim reads backend selector and only claims eligible work
```

Implementation shape:

- Add a narrow `Executor` interface in reigh-worker: `supports(route)`, `prepare(task)`, `run(task, profile)`, `cleanup()`, and `health()`.
- Keep selector logic outside both executors. WGP and VibeComfy adapters should receive an already-resolved route and fail closed if they do not support it.
- Backend is chosen at process launch. A worker launched with `--backend wgp` initializes WGP and never initializes VibeComfy; a worker launched with `--backend comfy` initializes VibeComfy and never initializes WGP.
- Prefer scheduler/claim-time eligibility so Comfy workers do not claim WGP-routed tasks and WGP workers do not claim Comfy-routed tasks. If claim-time filtering cannot land immediately, the worker must requeue/fail closed before execution when the selector/backend is incompatible.
- For orchestrators, the parent-selected route is authoritative. Child generation inherits that route unless a child route is explicitly blocked; the parent should fail/requeue before creating mixed-backend artifacts.

Backend switching model:

- To switch a route from WGP to Comfy, update `backend_selector` and ensure Comfy workers are launched/eligible.
- To switch a route from Comfy to WGP, update `backend_selector` and ensure WGP workers are launched/eligible.
- To switch an individual worker process, terminate/drain it and launch a new process with the other `--backend` value.
- Do not hot-switch an already-running process from WGP to VibeComfy or VibeComfy to WGP. If an emergency same-process fallback is ever implemented for local/dev, it must fully stop, unload, and free the active runtime before starting the other backend and should not be used for production canary.

Decision: Sprint 11 canary and the final steady state use launch-time backend selection plus route-level claim eligibility. Same-process backend switching is out of production scope.

### Existing `source/models/comfy/` Decision

The existing raw-Comfy task code path should be deleted, not refactored:

- Treat `source/models/comfy/comfy_handler.py` and `source/models/comfy/comfy_utils.py` as cleanup candidates only; delete them in Sprint 12B or a separate PR after the §8A deletion gate passes.
- Add `source/models/comfy/template_routing.py` for the VibeComfy adapter's USED routes only.
- Migrate or delete tests and coverage imports that currently reference `ComfyUIManager`, `ComfyUIClient`, `COMFY_PATH`, or `COMFY_PORT`.
- Do not preserve the raw `comfy` task first-output contract in the migration. If raw workflow submission is reintroduced later, it should be a separate feature with a new VibeComfy-native contract.

### Observability Shim

The VibeComfy adapter must translate `RunResult` from `vibecomfy/vibecomfy/runtime/session.py:35-42` into existing worker telemetry:

| `RunResult` field | Existing telemetry target | Required behavior |
| --- | --- | --- |
| `run_id` | heartbeat logs and `system_logs` | Emit as `vibecomfy.run_id` on task start, completion, and failure records. |
| `prompt_id` | Comfy/debug logs | Emit as `comfy.prompt_id` and include it in retry/debug breadcrumbs. |
| `outputs` | worker completion path | Normalize to the existing output shape for image, video, and orchestrated child tasks. Raw-Comfy is not migration scope. |
| `metadata_path` | debug-card context | Attach to `source/core/log/debug_card.py` output when present. |
| `log_path` | debug-card and failure diagnostics | Capture and link the VibeComfy/Comfy log path in debug cards and failure system logs. |

The Comfy backend should mirror WGP's memory telemetry from `source/models/wgp/generators/output.py:182-208`: RAM, CUDA allocated/reserved/total VRAM, selected backend, template id, memory profile, and whether the run used embedded or managed-server execution. Error mapping should classify OOM, model-load, schema-validation, prompt-queue, timeout, and output-missing failures so rollback triggers can compare WGP and VibeComfy runs by error class rather than raw exception text.

### Output and Product Acceptance Matrix

Media similarity thresholds in §11 are necessary but insufficient. Dual-run and canary gates must also assert queue-visible and product-visible contracts per USED task type.

| Acceptance dimension | Required assertion |
| --- | --- |
| Create-task input | Resolver payload and worker params match the Sprint 0 WGP baseline for each USED task type. |
| Local artifact | Generated local path exists, has expected extension/container, and matches single-output vs multi-output expectations. |
| Upload/storage | Uploaded destination, metadata, content type, and public/signed URL behavior match WGP. |
| Completion payload | `Complete` payload shape, output field name, status transitions, retry class, and failure shape match WGP. |
| Child tracking | Orchestrated parent/child ids, segment ordering, stitch inputs, and finalization fields match WGP. |
| `complete_task` side effects | Gallery/lightbox insertion, video-editor/timeline insertion, thumbnails, share/history data, and user-visible status changes match current production behavior. |
| Billing/credits | Credit debit/refund behavior is unchanged for success, retry, failure, and partial orchestrator failure. |
| Debug metadata | Debug-card fields, `system_logs`, backend/template/profile labels, `run_id`, `prompt_id`, metadata/log paths, and error classes are populated. |
| Idempotency | Retry or duplicate completion does not create duplicate gallery/timeline artifacts or orphan child completions. |

Sprint 0 owns the baseline contract table. Sprint 3 dual-run asserts the contract for direct image/edit routes and at least one nested child route. Sprint 6 extends it to every USED orchestrated route and every non-FALL-BACK §3A matrix row.

### Artifact Lifecycle

VibeComfy introduces metadata/log outputs and Comfy temp files in addition to final media. The adapter must define:

- Local temp directories for workflow inputs, Comfy outputs, logs, metadata, and sanitized LoRA cache files.
- Cleanup cadence for successful runs, failed runs, retries, and worker shutdown.
- Retention policy for debug artifacts referenced by debug cards.
- Upload parity for final media, thumbnails, and any child segment artifacts consumed by stitch/finalization code.
- Orphan sweeps for local temp files, uploaded-but-uncompleted outputs, and child tasks whose parent rolled back or failed.
- Storage cost monitoring for dual-run/shadow outputs and VibeComfy metadata/log files.

Before Sprint 10 canary readiness, this checklist must become an operational contract, not just design intent:

| Artifact area | Required contract before canary |
| --- | --- |
| Local layout | Named directories for workflow inputs, Comfy outputs, logs, metadata, sanitized LoRA cache, and dual-run scratch data. |
| TTL / cleanup | TTLs for success, failure, retry, shutdown, and abandoned-run paths; cleanup job owner and failure alert. |
| Debug retention | Retention duration and access controls for debug-card-linked logs/metadata; redaction rules for prompts, signed URLs, secrets, and user media paths. |
| Shadow isolation | Separate bucket/path prefix for dual-run and shadow outputs; no completion, billing, gallery/timeline, or user-visible side effects. |
| LoRA cache | Cache key, invalidation on source mtime/hash or module-map version, maximum disk size, and orphan sweep. |
| Upload parity | Final media, thumbnails, child segment artifacts, metadata, content type, and signed/public URL behavior match WGP. |
| Quotas/cost | Storage quota alarms and daily cost visibility for dual-run/shadow artifacts. |

### Observability Operations

Before Sprint 11 canary, §7 labels must be wired into actual operating surfaces:

| Surface | Required before canary |
| --- | --- |
| Dashboards | Per-cohort backend split, latency p50/p95, VRAM peak, OOM count, error class, output-divergence rate, selector version, and worker image version. |
| Alerts | §11 rollback thresholds as alert rules with owner/on-call and debounce/cooldown policy. |
| Synthetic canaries | At least one scheduled smoke per promoted cohort, including one Cohort E parent/child route after Cohort E starts. |
| Runbooks | Emergency selector flip, WGP process/pool fallback, Comfy route unsupported failure, model/custom-node preflight failure, and artifact cleanup. |

### Deployment Preflight

Comfy-capable workers must pass preflight before claiming tasks:

- All templates selectable by `template_routing.py` compile.
- Required custom-node packs are pinned in `vibecomfy/custom_nodes.lock` and checked out at expected revisions.
- Required model files, LoRAs, VAEs, controlnets, and tokenizer/text-encoder assets exist with pinned hashes or recorded provenance.
- Secrets/env vars required by download/upload, Supabase, VLM, RunPod, and VibeComfy runtime are present.
- Cold boot, warm session start, and first run fit the Sprint 0 startup and latency budget.
- Backend selector is reachable, or the worker starts in WGP-safe mode and does not claim Comfy-routed tasks.

Security/privacy preflight before canary:

- Signed URL handling, expiry, and retry behavior match WGP.
- Debug logs and VibeComfy metadata redact secrets, user tokens, signed URLs, and tenant/user identifiers not needed for support.
- Shadow and dual-run artifacts are access-controlled and isolated from user-visible storage paths.
- Model/custom-node download credentials are scoped to read-only artifact access where possible.
- Any prompt/media snippets copied into debug cards follow the existing support/privacy policy.

Capacity/cost preflight before canary:

- Per-cohort expected traffic, shadow-run multiplier, GPU type, pool size, max daily RunPod cost, cache warm strategy, and rollback reserve capacity are recorded.
- Mixed WGP/Comfy pools can absorb rollback traffic without waiting for a new image build.

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
5. Run the reigh-worker LoRA-file sanitizer pre-process for both L1 and L2 filenames before workflow build; point each node at the sanitized filename.
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
- **`structure_videos[]` and legacy `structure_guidance` aliases.** Both fields are accepted by the resolvers (`travelBetweenImages.ts:63-64`, `individualTravelSegment.ts:48-49`) and marked deprecated in `taskTypes.ts:205-211`; the worker contract rejects them when combined with the canonical `travel_guidance` (`travel_guidance.py:221-233`). The TODOs at `taskTypes.ts:185,196,206` confirm three writes-side fields (`chain_segments`, `structure_guidance`, `stitch_config`) are never consumed by the resolver. **Disposition: vestigial; covered by §8A.C "Stale TODOs" — promote those rows to CLEANUP-CANDIDATE once Q-blame check is run.**
- **`travel_guidance.kind = 'ltx_hybrid' | 'ltx_anchor'`.** Both kinds are allowed by `_infer_allowed_kinds` for distilled LTX models (`travel_guidance.py:64-66`) and have full validation paths (`travel_guidance.py:419-438`). Neither is in the LTX-fast `supportedGuidanceModes` array (`modelCapabilities.ts:49,156`), so the app cannot reach them. **Disposition: cleanup-candidate in Sprint 12B only if affected baselines and resolver/worker contract tests are rerun.** Likely dead weight, but not required for migration parity.
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
- Sprint 5 cohort B (Qwen) gates on the pre-processed prompt being byte-equivalent to WGP's expander output for a fixed corpus; this is a reigh-worker-only test, no VibeComfy code change. Byte-equivalence is valid only after pinning the prompt-expander model id, revision SHA, tokenizer/package versions, generation params, seed/determinism settings, and fixture corpus.

This decision aligns with Section 3's "Vendor-Utility Shims" table, which already routes Qwen prompt expansion to reigh-worker pre-processing; Section 3A pins it as the canonical answer.

## 4. Sprint-by-sprint migration plan

Each sprint is a practical delivery increment with a hard two-week maximum. Short verification or readiness sprints are scoped to 3-4 days. The plan stays sequential for execution; repo/workstream ownership is noted inside sprint rows, but implementation is not split into independent tracks.

Critical path:

```text
Sprint 0A -> 0B -> 0C -> 1 -> 2 -> 3 -> 3.5 -> 4 -> 5 -> 6 -> 7 -> 8 -> 9 -> 10 -> 11 -> 12

Optional cleanup/refactor work:
  - Dispatcher unification may replace Sprint 9 only if Sprint 8 is green and the refactor is still worth the risk.
  - Deletion-gated cleanup is Sprint 12B or separate post-canary PRs, not a migration prerequisite.
```

| Sprint | Duration | Goal | Shippable artifacts | Exit criteria | Owner | Main risk | Fallback |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Sprint 0A: Kickoff and contract freeze | 3-4 days | Close kickoff blockers and freeze the project generation contract before adapter work. | Signed §12 checklist; RayWorker-owned USED task inventory; active non-RayWorker route inventory for `video_enhance`, `image-upscale`, `animate_character`, and `flux_klein_edit`; owner/runtime decision for each non-RayWorker row; `turbo_mode: true` resolver safety test/fix; per-USED-RayWorker-task contract skeleton for payload, timeout, polling cadence, output fields, product effects, billing, duplicate completion, and partial-orchestrator failure. | No Sprint 1 implementation starts until `turbo_mode` is safe, each active non-RayWorker row has a named owner/runtime and preserve-vs-move decision, and every USED RayWorker task type has a named baseline owner plus runnable/skipped/blocked status. | `reigh-worker` with `reigh-app` input | A non-RayWorker active route is silently ignored, or a bad historical app payload enters the baseline and later looks like migration drift. | Stop kickoff; fix resolver/API safety/scope classification and rerun affected discovery. |
| Sprint 0B: Thresholds and golden corpus | 1 week | Produce comparison oracles consumed by later sprints. | `migration-thresholds.yaml`; WGP self-repeatability report; route-keyed WGP golden corpus for Cohort A/B and representative Cohort E routes; lightweight product-contract fixtures for `video_enhance`, `image-upscale`, `animate_character`, and `flux_klein_edit`; live-validation doc updated to same route/threshold version. | Threshold YAML is committed and read by a smoke script; WGP self-drift is below thresholds or affected routes are marked WGP-only/pending; corpus is route-keyed, not only task-type-keyed; non-RayWorker active routes have owner-approved contract fixtures or are explicitly deferred with rationale. | `reigh-worker` with owning runtime input | Subjective comparison gates remain possible or active non-RayWorker routes lack regression coverage. | Keep route WGP-only/current-owner-only or widen thresholds only with calibration notes. |
| Sprint 0C: Assets, capacity, and deployment baseline | 3-4 days | Freeze infra and asset assumptions separately from behavioral baselines. | Asset/model/hash manifest; live `ready_templates` inventory; custom-node lock audit; owner/date to change RunPod disk from current 50 GB to 200 GB; first dual-stack pod boot/disk/startup measurement. | 200 GB change is landed or explicitly PENDING; disk usage is measured; if first boot exceeds 180 GB, raise to 250 GB before Sprint 1. | `reigh-worker-orchestrator` + `vibecomfy` | Capacity failure blocks all validation. | Keep WGP-only deployment defaults; do not run dual-stack matrix. |
| Sprint 1: VibeComfy memory-profile MVP | 2 weeks | Implement five-tier VibeComfy memory-profile parity. | `MemoryProfile`; round-trip tests into embedded and managed-server config/argv; representative template profile smokes; process-default plus per-run override tests. | Profiles 1-5 round-trip; profile 1 and 3 have VRAM/wall-clock data; any profile change requiring session restart is documented. | `vibecomfy` | Mapping is syntactic but not operationally close to WGP. | Keep worker defaults on WGP; tune overlay only. |
| Sprint 2: Adapter seam and local selector skeleton | 2 weeks | Add the worker VibeComfy adapter and early route/selector abstraction. | `template_routing.py`; executor/adapter seam; backend-neutral resolved-task object before WGP-specific queue conversion; local `REIGH_BACKEND`; static/local selector map; route support states; direct smokes for `z_image_turbo` and `qwen_image_2512`; one LTX-only or template-independent child smoke; minimal backend/template/profile/error telemetry. `wan_2_2_t2i` is included only if its single-frame patch lands here. | Feature-flagged Comfy path works for included direct routes without entering `_convert_to_wgp_task`; child smoke does not depend on Wan VACE cocktail; unsupported Comfy routes fail closed; local route derivation is test-covered. | `reigh-worker` | Adapter proves only direct tasks or accidentally stays coupled to WGP queue conversion. | Flip `REIGH_BACKEND=wgp`; leave unsupported routes WGP-only. |
| Sprint 3: Dual-run comparison harness | 2 weeks | Build the harness and executable product/billing oracle for routes already landed. | `scripts/dual_run_compare.py`; reports for media similarity, queue contract, product effects, billing/refund/idempotency, latency, VRAM, OOM, error class; no-side-effect shadow artifact isolation; non-RayWorker active-route regression checks that verify they still complete through their current owner. | Harness is green for Sprint-2 routes or marks them RED; not-yet-routed RayWorker rows are pending/fallback/WGP-only; product/billing checks are executable; `video_enhance`, `image-upscale`, `animate_character`, and `flux_klein_edit` are not accidentally broken by shared app/completion/billing changes. | `reigh-worker` with `reigh-app` and owning runtime input | Media success hides completion or billing drift; shared app changes break Cloud Worker/external routes. | Keep production on WGP/current owners; restrict Comfy to local/dev dual-run. |
| Sprint 3.5: Wan 2.2 VACE feasibility dry run | 3-4 days | Test the two-stage HIGH->LOW sampler hypothesis before full Wan template work. | Minimal dry-run workflow/template; one 49-frame comparison; `dry-run-report.md` with PROCEED/FALL-BACK decision. | PROCEED iff §11 video thresholds pass; otherwise Wan-family VACE travel/join routes are WGP-only while the rest continues. | `vibecomfy` + `reigh-worker` | Comfy sampler chain cannot reproduce WGP closely enough. | Mark Wan-family VACE routes WGP-only. |
| Sprint 4: Wan single-frame and cocktail template work | 2 weeks | Resolve Wan template risks without demanding full orchestration parity yet. | Wan 2.2 VACE cocktail template if Sprint 3.5 proceeds; isolated child-route smokes; `wan_2_2_t2i` forced single-frame patch if not already landed. | Cocktail compiles/runs under representative profiles; isolated child smokes pass where applicable; `wan_2_2_t2i` is green or WGP-only/pending. Full parent/child parity waits for Sprint 8. | `vibecomfy` with `reigh-worker` support | Worker-level orchestrated parity is requested before route propagation exists. | Keep affected Wan routes WGP-only; continue direct route work. |
| Sprint 5: Qwen, edit-mode, VLM, and LoRA preprocessing parity | 2 weeks | Finish direct image/edit parity and remove WGP-only preprocessing assumptions needed by later orchestration. | Routes/patches for `qwen_image_2512`, `qwen_image` only after its true non-2512 model path is proven, `qwen_image_edit`, `qwen_image_style`, `image_inpaint`, `annotated_image_edit`; prompt-expander pre-process; backend-neutral VLM/prompt-generation wrapper for travel/join/edit-video callers; LoRA sanitizer; checked-in `module_names_<arch>.json`. | Direct image/edit routes are green or individually WGP-only; `qwen_image` is not treated as equivalent to `qwen_image_2512` unless validated; prompt expansion, VLM prompt fixtures, and LoRA sanitizer pass fixture corpus. | `reigh-worker` + `vibecomfy` | Qwen shortcut, VLM drift, or LoRA sanitation changes outputs. | Keep affected direct routes WGP-only; leave orchestrated routes WGP-only until VLM fixtures pass. |
| Sprint 6: Production selector and claim contract | 2 weeks | Make selector/claim behavior concrete before orchestrated routes depend on it. | Selector schema/namespace; route-key serialization, including direct variants when needed; indexes/RPC/query behavior; cache TTL/rollback SLO; malformed/unauthorized/stale-entry tests; claim-time backend eligibility or pre-execution requeue/fail-closed guard; selector-version logging; child-route snapshot field contract for later parent-created rows. | Missing production route key means WGP/no-claim, never implicit Comfy; mismatched workers cannot claim or execute selected routes; selector unreachable behavior and rollback SLO are tested; the selected backend/selector version can be pinned for child rows created after parent claim. | `reigh-worker` + Supabase owner | Route propagation reimplements selector behavior ad hoc or a worker claims a route it cannot execute. | Keep production selector absent/WGP-only. |
| Sprint 7: Orchestrator image, pools, and artifact contract | 2 weeks | Make deployment and artifact lifecycle canary-ready. | WGP/Comfy startup examples; backend/profile flags; health probes; model/custom-node/template preflight; warm-cache strategy; disk-near-full behavior; drain/kill/restart policy; pool sizing and rollback reserve; artifact paths, prefixes, TTLs, debug retention, redaction, LoRA cache limits, orphan sweeps, quota alerts; concrete telemetry transport for backend/template/profile/run id in heartbeat, structured logs, or both. | WGP and Comfy pools launch from same image; stale workers cannot claim newer routes; artifact cleanup and debug retention are testable; backend/template/profile/run labels are visible in the chosen transport; staged rollback exercise passes. | `reigh-worker-orchestrator` + `reigh-worker` | Hidden platform work fails during canary or telemetry exists only in local logs. | Launch only WGP-default workers; disable Comfy promotion. |
| Sprint 8: Orchestrated route propagation and lifecycle contract | 2 weeks | Route parent/child workflows consistently through selected backend where Comfy support exists. | Propagation for travel/join/edit-video parent and child surfaces; persisted child-row route snapshot (`selected_backend`, selector version, parent route key, and support state); dependency-array/idempotency/cancellation behavior for DB-created child rows; parent/child backend-consistency guards; lifecycle-contract tests; repair/runbook hooks for partial children, uploaded-but-not-completed outputs, duplicate completion, mixed-backend child sets, and parent repair. | Parent rejects Comfy if any required child route is WGP-only, unsupported, fallback, or untested; child rows created after parent claim carry enough route metadata to avoid selector drift; lifecycle contract is green for every USED route intended for canary. | `reigh-worker` | Parent says Comfy while children run WGP, selector changes mid-orchestration, or DB-created child rows bypass adapter assumptions. | Force affected Cohort E routes to WGP; fail closed before child creation. |
| Sprint 9: Control-rail and travel-matrix parity | 2 weeks | Complete Cohort E parity for routes intended for canary. | Canny/Depth/Pose/Flow preprocessing; ffmpeg/ffprobe frame-count/FPS/audio/thumb semantics check around Comfy outputs; full §3A matrix smoke report; LTX control rows verified against a real control-capable template or marked NEW/BLOCKED/WGP-only; continuity smokes; persisted-row compatibility replay. | Every non-FALL-BACK matrix row passes through current dispatcher; native media post-processing preserves frame/audio/output contracts; LTX rows 9-13 no longer rely on an unproven first/last-only seam; replay is green or WGP-only. | `reigh-worker` + `vibecomfy` | Matrix claims coverage for template seams that do not exist or native media semantics drift after generation. | Mark affected route keys WGP-only. |
| Sprint 10: Canary readiness integration | 1 week | Integrate evidence, dashboards, alerts, and rollback runbooks. | Live-validation evidence package; dashboards; §11 alert rules; draft rollback PRs; in-flight rollback exercise; active non-RayWorker route smoke evidence for `video_enhance`, `image-upscale`, `animate_character`, and `flux_klein_edit`. | Soak covers mixed pools, concurrent claims, selector flip with in-flight work, worker kill/restart, cold/warm cache, and disk-near-full behavior; active non-RayWorker routes remain healthy through shared app/completion/billing paths. | `reigh-worker` + `reigh-worker-orchestrator` + owning runtimes | Evidence is too scattered for go/no-go or non-RayWorker regressions are missed. | Keep production WGP-only and leave non-RayWorker route ownership unchanged. |
| Sprint 11: Production canary by route cohort | 2 weeks | Promote RayWorker routes sequentially by selector while monitoring active non-RayWorker routes for shared-contract regressions. | Runtime selector flips; canary runbook; cohort dashboards; shadow/dual-run reports; rollback PRs; smoke/alert watch for `video_enhance`, `image-upscale`, `animate_character`, and `flux_klein_edit`. | Cohort A holds 48h before B, B holds before E; emergency rollback meets SLO; shadow checks have no completion, billing, upload, or user-visible side effects; WGP remains selectable; active non-RayWorker routes remain green or canary pauses. | `reigh-worker` + `reigh-worker-orchestrator` + owning runtimes | Selector promotes a route before all variants are ready or shared changes regress Cloud Worker/external routes. | Flip affected RayWorker route keys back to WGP; leave non-RayWorker routes on their current owner/runtime. |
| Sprint 12: Dual-executor hardening | 1 week | Close the epic as a dual-executor platform with explicit ownership for every active generation route. | Dual-executor runbook; WGP-only/Comfy-only/dual-supported route docs; non-RayWorker active-route ownership docs; staging flip tests; final dashboard/alert review; steady-state ownership matrix; cleanup backlog moved to Sprint 12B/separate PRs. | Both executors boot from same image; supported RayWorker routes can select either backend; WGP runtime code/tests/startup paths remain intact; `video_enhance`, `image-upscale`, `animate_character`, and `flux_klein_edit` have documented owners and regression checks; cleanup-only deletion is not needed for migration closure. | `reigh-worker` + `reigh-worker-orchestrator` + owning runtimes | Teams misread hardening as WGP retirement or forget active non-RayWorker routes. | Keep both pools; set selectors to known-good WGP defaults; leave non-RayWorker routes on current owners. |
| Sprint 12B: Optional cleanup sprint or post-canary PRs | 1-2 weeks, one category at a time | Cleanup only: turbo-mode scaffolding after contract safety, UNUSED-handler deletion after §8A deletion gate, pyproject dedupe, and AMBIGUOUS rows proven dead. | One PR per cleanup category; optional Supabase cleanup migration; DB/admin/debug/direct-emitter proof for handler deletions. | Cleanup lands before Sprint 0 with regenerated baselines or after Sprint 11; if it lands mid-migration, affected baselines and resolver tests rerun before comparison/canary. | `reigh-app` + `reigh-worker` | Cleanup invalidates frozen baselines. | Defer cleanup; keep handlers/scaffolding installed. |

No production canary begins until direct-route parity, selector/claim behavior, orchestrator pool behavior, artifact lifecycle, and orchestrated-route parity are all represented in tests or live-validation evidence.

## 5. Per-task-type cutover order

Cutover is by resolved backend route, not by friendly display name and not always by task type alone. The canary selector reads a server-side route map at task claim time, so rollback can flip a cohort or an individual route back to WGP without changing the queue schema. Direct image/edit tasks can key on `task_type`; orchestrated video routes need more specificity because `travel_segment` / `individual_travel_segment` can resolve to Wan, LTX, guidance, and model-specific paths.

| Cohort | Risk level | Task types | Template readiness (per 1A) | Rationale | Entry gate | Promotion gate | Rollback selector |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Cohort A | Lowest: image-only and comparatively deterministic | `z_image_turbo`, `z_image_turbo_i2i`, `qwen_image`, `qwen_image_2512`, `wan_2_2_t2i` (~~`flux` removed: UNUSED per §0A~~) | NATIVE: `z_image_turbo`, `qwen_image_2512`. ADAPT: `z_image_turbo_i2i` (i2i adapter), `qwen_image` (disable edit branch), `wan_2_2_t2i` (forced `num_frames=1` patch). | These tasks have single-image output shapes, simpler completion paths, and no orchestrated child-task dependency. `wan_2_2_t2i` is included because it is a single-frame output contract even though it routes through Wan-family templates. | Sprint 2 adapter is green for `z_image_turbo`, `qwen_image_2512`, and one single-frame/Wan route; Sprint 5 resolves Qwen-specific gaps before promoting those task types. ADAPT rows must have their patches landed and tested before promotion (not just queue-seam wiring). | 48-hour canary hold with no p95 latency regression beyond threshold, no error-class spike, and output dimensions/format matching baselines. | Set each Cohort A route key in `backend_selector` back to `wgp`. |
| Cohort B | Medium: image edits with prompt/input preprocessing | `qwen_image_edit`, `qwen_image_style`, `image_inpaint`, `annotated_image_edit` (~~`qwen_image_hires` removed: UNUSED per §0A — hires-fix is a payload param on `qwen_image_edit`~~) | NATIVE: `qwen_image_edit`. ADAPT: `qwen_image_style` (LoRA stack + Qwen prompt expander pre-process), `image_inpaint` (mask handling), `annotated_image_edit` (annotation rasterised pre-process). | These are still image outputs, but they depend on edit-mode input handling, empty-prompt allowances, Qwen prompt behavior, masks/annotations, and LoRA/key sanitation. | Sprint 5 Qwen/edit parity is green; preprocessing artifacts and LoRA sanitizer behavior are logged and reproducible. ADAPT rows require Section 3A's reigh-worker LoRA-file sanitizer pre-process to be merged and the Qwen prompt expander pre-process to be byte-stable against WGP. | 48-hour canary hold per task type; compare input mask/annotation handling, output image path shape, retry class, latency, and VRAM. | Set affected edit route keys in `backend_selector` back to `wgp`; leave Cohort A on Comfy if stable. |
| ~~Cohort C~~ | ~~Medium-high: video generation~~ | **REMOVED FROM SCOPE** — `t2v`, `t2v_22`, `i2v`, `i2v_22`, `ltxv`, `ltx2`, `generate_video` are all UNUSED per §0A. App-side video generation routes exclusively through `travel_orchestrator` (Cohort E), not through direct video task types. | — | — | — | — | — |
| ~~Cohort D~~ | ~~High: VACE plus Hunyuan~~ | **REMOVED FROM SCOPE as direct task types** — `vace`, `vace_21`, `vace_22`, `hunyuan` are all UNUSED per §0A. The Wan 2.2 VACE cocktail **template** (Sprint 4 NEW) is still required, but it is consumed indirectly through the Cohort E travel/join paths whose default model is `wan_2_2_vace_lightning_baseline_2_2_2`. | — | — | — | — | — |
| Cohort E | Highest: orchestrated paths (the bulk of remaining migration scope) | `travel_orchestrator`, `travel_segment`, `individual_travel_segment`, `travel_stitch`, `join_clips_orchestrator`, `join_clips_segment`, `join_final_stitch`, `edit_video_orchestrator` (~~`inpaint_frames`, `magic_edit`, `create_visualization`, `extract_frame`, `rife_interpolate_images`, `comfy` removed from migration scope: all UNUSED per §0A~~) | NATIVE (no template): `travel_orchestrator`, `travel_stitch`, `join_clips_orchestrator`, `join_final_stitch`, `edit_video_orchestrator`. ADAPT: `travel_segment` / `individual_travel_segment` (Wan VACE cocktail Sprint 4 NEW template if Sprint 3.5 PROCEEDs, or WGP-only if Sprint 3.5 FALL-BACKs; LTX first-last-frame template, + `video_source` widget patch per Section 3A), `join_clips_segment` (Wan VACE cocktail if PROCEED). | These paths combine parent orchestration, nested child-task enqueueing, and completion semantics that may span several queue rows. With the §0A scope reduction, Cohort E is now the dominant migration cohort: it carries every Wan/VACE/LTX video path that production actually uses (via the `travel_orchestrator`'s `model_name` field). | Sprint 8 proves parent/child backend route propagation and lifecycle contract; Sprint 9 proves control-rail and matrix parity for every promoted route not explicitly marked FALL-BACK/WGP-only. Dispatcher unification is optional and not a canary entry gate. ADAPT rows require the Section 3A travel-continuity patch (`video_source` → `VHS_LoadVideo.video` widget edit), relevant control-rail preprocessing, and the LoRA sanitizer pre-process to be merged. The Sprint 4 NEW Wan 2.2 VACE cocktail template must be live only for Wan-family travel/join paths that are promoted to Comfy. | Parent backend selection and child backend selection agree; lifecycle-contract test is green for every USED task type against Sprint 0 baselines; every **non-FALL-BACK** row of the §3A "Travel-segment configuration matrix" must produce a passing smoke before Cohort E promotion. Smokes must cover all three continuity sub-cases (first-frame-only, first+last, inter-segment `video_source`) for representative non-FALL-BACK Wan/LTX rows, plus one join/edit child smoke for any promoted Wan VACE route. If Sprint 3.5 FALL-BACK marks all Wan-family Cohort E rows WGP-only, Sprint 12's dual-support requirement for Cohort E applies only if at least one LTX/no-template Cohort E route passed Sprint 9. | Force Cohort E parent task types to `wgp`; parent handlers must reject Comfy selection if any child-task route remains WGP-only or untested. |

Adjacent active routes are not promoted by the RayWorker backend selector unless Sprint 0 explicitly moves them into RayWorker. They still remain in epic scope as preservation checks:

| Adjacent route | Current ownership decision | Epic requirement |
| --- | --- | --- |
| `video_enhance` | Current owner/runtime decided in Sprint 0; expected to stay Cloud Worker/external unless explicitly moved. | Preserve FILM/FlashVSR payload, cost, completion, output, and UI contract; smoke during Sprint 3/10/11. |
| `image-upscale` | Current owner/runtime decided in Sprint 0; expected to stay Cloud Worker/external unless explicitly moved. | Preserve hyphenated task type, variant metadata, billing, output path, and completion behavior. |
| `animate_character` | Current owner/runtime decided in Sprint 0; expected to stay Cloud Worker/external unless explicitly moved. | Preserve generation/completion contract and AI-agent/frontend emit paths. |
| `flux_klein_edit` | Current owner/runtime decided in Sprint 0; expected to stay Cloud Worker/external unless explicitly moved. | Preserve Klein edit behavior; do not conflate with unused RayWorker `flux` cleanup. |

The selector contract is:

```text
task claim
  -> derive backend_route:
       direct routes:       (task_type)
       travel/join routes:  (task_type, model_family/model_name, guidance_kind)
  -> read backend_selector[backend_route]
  -> in production: missing selector key => WGP/no-claim, never implicit Comfy
     in local/dev: missing selector key may fall back to process --backend / REIGH_BACKEND
  -> claim only if this worker process/pool is eligible for the selected backend
  -> dispatch through the selected executor
```

For Cohort E, the parent task's resolved backend route is authoritative for child generation unless a child route is explicitly blocked. That prevents mixed WGP/Comfy orchestration where the parent reports Comfy telemetry while the child is silently submitted to WGP. If the parent resolves to Comfy but a child route is WGP-only, unsupported, or FALL-BACK, the parent fails closed or requeues before creating partial/mixed artifacts. Parent-created child rows must carry a route snapshot (`selected_backend`, selector version, parent route key, and support state) because current child creation is persisted through DB rows, not only through an in-memory queue seam.

### Selector Control Plane

The production selector is runtime configuration, not a code PR:

| Requirement | Contract |
| --- | --- |
| Storage | A server-side config table or config-service namespace readable by workers at claim time, with concrete schema/namespace selected in Sprint 6. Direct tasks read this at claim/execution time. Orchestrated parents also persist the selected backend, selector version, and parent route key into child rows or child params when creating children, so child execution cannot drift if selector config changes mid-orchestration. |
| Key shape | Direct: `(task_type)`. Orchestrated video: `(task_type, model_family/model_name, guidance_kind)` plus optional explicit model id where two model ids share a family but have different template readiness. |
| Defaults | Production selector is an explicit allowlist: missing route key means WGP/no-claim, never implicit Comfy. Local/dev may fall back to process `--backend` / `REIGH_BACKEND` for ergonomics. |
| Launch-time backend | Each worker process starts with exactly one backend. `--backend wgp` processes load WGP only; `--backend comfy` processes load VibeComfy only. |
| Claim-time behavior | Worker derives the route before execution and claims only if its launch-time backend matches the selector. Preferred implementation prevents a process/pool from claiming mismatched tasks. Fallback implementation requeues/fails closed before execution. |
| Propagation | Selector updates must take effect within the rollback SLO. Cache TTL must be short enough to meet the SLO, and workers must expose the selector version they used in logs. |
| Permissions | Only the canary owner/on-call role can promote routes to Comfy; malformed, unauthorized, stale-version, or unsupported route entries fail closed and cannot promote Comfy. |
| Audit | Every selector change records actor, old value, new value, reason, timestamp, affected route keys, selector version, and whether the change was emergency rollback or planned promotion. Audit retention is set before Sprint 7. |
| Emergency override | Canary owner can flip a route or cohort to WGP without merge/deploy. Draft PRs are follow-up durability, not the emergency rollback mechanism. |
| Version guard | Selector entries can require a minimum worker image/runtime version; stale workers that cannot satisfy the selected route do not claim the task. |
| Unreachable selector | Fail closed to the process default only for non-canary local/dev. In production canary, selector unreachability blocks Comfy promotion and should prefer WGP-safe claiming. |

## 6. Rollback plan

Rollback remains a permanent operating mode. Every Comfy canary and every steady-state Comfy route is reversible by selector, not by rebuilding an image.

### Rollback Controls

| Control | Scope | Required behavior |
| --- | --- | --- |
| `--backend wgp|comfy` | Worker process | Process-level default set by the worker startup command. This should map to `REIGH_BACKEND={wgp|comfy}` internally. |
| `REIGH_BACKEND={wgp|comfy}` | Worker process / local dev | Environment default used by scripts, live tests, and fallback startup paths. |
| `backend_selector` | Server-side route override | Read at task claim time. A present route value overrides the process default. In production, an absent route key means WGP/no-claim, never implicit Comfy; local/dev may fall back to `--backend` / `REIGH_BACKEND`. Direct routes may key on task type; orchestrated video routes key on task type + model/guidance route. |
| Cohort rollback | Server-side selector update | Flip one cohort, individual task type, or model/guidance route back to `wgp` without changing task payloads, queue rows, or Supabase schema. |
| Worker image rollback | Orchestrator deployment | WGP and VibeComfy both remain in the worker image through canary and steady state, so the orchestrator can launch WGP-default workers immediately. |

The adapter scope for rollback is the same as the adapter scope for migration:

- Direct-queue seam: `_handle_direct_queue_task` -> `db_task_to_generation_task` -> backend queue submission.
- Nested-handler seam: handlers receiving `context["task_queue"]` and enqueueing child generation tasks.

If either seam cannot honor `REIGH_BACKEND` and `backend_selector`, the relevant route remains WGP-only.

### Trigger Conditions

Rollback triggers are defined by §11 thresholds (single source of truth) and Sprint 0 baselines:

| Trigger (concrete threshold per §11) | Action |
| --- | --- |
| p95 latency >1.10× WGP baseline for a cohort, sustained 24h | **Auto-rollback:** flip affected `backend_selector` route entries back to `wgp` by runtime config update; keep collecting Comfy shadow data if possible. |
| Error-class spike for OOM (any non-zero rate), model-load, schema-validation, prompt-queue, timeout, or missing-output (>2× baseline rate) | Roll back affected routes first by runtime config update; roll back full cohort if error classes cross task-family boundaries. |
| Output-divergence rate >1% over a 24h window (per-frame pHash p95 breach rate per §11) | **Auto-rollback only when measured through isolated shadow runs** with no completion, billing, upload, or user-visible side effects. Otherwise stop promotion, restore WGP manually if sampled/offline evidence is severe, and add examples to the dual-run corpus. |
| VRAM peak >1.05× WGP profile-1 or profile-3 baseline | Roll back affected memory profile / task family and retune `MemoryProfile.to_session_overrides()`. |
| Parent/child backend mismatch in orchestrated tasks | Roll back affected Cohort E routes immediately by runtime config update; block further promotion until child-task seam tests pass. |
| Worker startup or health-check regression after orchestrator flag changes | Launch workers with `REIGH_BACKEND=wgp` and revert the startup-template change that passed the Comfy default. |

### In-flight rollback policy

Selector rollback controls future claims; it does not magically unwind tasks already claimed by Comfy workers. Before Sprint 11 canary, each route cohort must have an in-flight policy:

| In-flight state when rollback fires | Default policy | Required guard |
| --- | --- | --- |
| Direct task claimed, generation not started | Requeue or fail closed before execution so a WGP worker can reclaim. | Preserve max-attempt/retry class and do not debit twice. |
| Direct task actively generating | Let current backend finish if upload/completion has not diverged and task is below timeout; otherwise cancel/requeue only when the backend can prove no partial upload/completion side effect happened. | Idempotent completion and orphan-artifact cleanup. |
| Orchestrator parent claimed, children not created | Requeue parent for WGP if the route was rolled back before child creation. | No partial child rows. |
| Orchestrator parent created some children | Freeze parent promotion, allow already-created children to finish on their selected backend only if parent/child backend consistency is still valid; otherwise mark parent for manual repair or WGP retry from a clean checkpoint. | Parent/child tracking and duplicate child prevention. |
| Child generation running | Prefer drain current child, then route subsequent children through WGP only after parent policy says mixed outputs are allowed. If mixed outputs are not allowed, block finalization and repair manually. | Explicit mixed-output policy per Cohort E route. |
| Stitch/finalization running | Let stitch/finalization finish if all inputs are already finalized and output contract is backend-neutral. | No duplicate gallery/timeline insertion. |
| Upload completed but `complete_task` pending | Do not retry blindly. Run idempotency guard first; either complete exactly once or orphan-sweep the uploaded artifact before WGP retry. | Completion idempotency and billing/refund parity. |

### Emergency rollback and durable follow-up

Each cohort canary in Sprint 7 has two rollback layers:

1. **Emergency rollback:** runtime selector config flip, no merge/deploy required, used by the automated triggers above.
2. **Durable follow-up:** pre-prepared draft PR, mergeable after the emergency flip, that makes any needed code/config/documentation revert durable.

| Cohort | Pre-staged rollback PR | Mergeable in |
| --- | --- | --- |
| A (image-only) | Documents and durably codifies selector route revert for Cohort A | < 5 min |
| B (image edits) | Documents and durably codifies selector route revert + Qwen-edit code revert if needed | < 5 min |
| E (orchestrated) | Documents and durably codifies route-level selector revert AND drafts `_handle_via_queue_task` revert to dual-seam | < 10 min (two-PR sequence; second only needed if dispatcher regression) |

PR ownership: Sprint 11 canary owner (named at Sprint 7 kickoff). Drafts open at Sprint 7 setup; one rebase per week to keep them mergeable.

`reigh-worker-orchestrator/gpu_orchestrator/runpod/worker_startup.template.sh` must pass the selected backend/profile through the worker startup command during canary and steady state. The dual-stack worker image continues to contain WGP.

## 7. Telemetry and observability

Telemetry must let operators compare WGP and VibeComfy runs at the same level of detail during shadow, dual-run, and canary. The goal is not a new observability system; it is a compatibility shim that makes Comfy runs show up in existing heartbeat logs, `system_logs`, and debug-card diagnostics.

### Required Labels and Fields

| Field | Applies to | Purpose |
| --- | --- | --- |
| `backend` | All task logs and status updates | Values: `wgp` or `comfy`; required for cohort dashboards and rollback filters. |
| `template_id` | Comfy/VibeComfy runs | VibeComfy ready-template id used by the task. Raw `comfy` workflow routes are not migration scope. |
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
| `RunResult.outputs` | Worker completion output path | Normalize to the existing output shape for image, video, and orchestrated child tasks. Raw-Comfy is not migration scope. |
| `RunResult.run_id` | heartbeat logs and `system_logs` | Emit as `vibecomfy.run_id` consistently across start, success, retry, and failure paths. |
| `RunResult.prompt_id` | debug breadcrumbs and Comfy diagnostics | Emit as `comfy.prompt_id`; include in failure and timeout messages. |
| `RunResult.log_path` | `source/core/log/debug_card.py` | Add a debug-card link or path entry so support can inspect Comfy/VibeComfy logs. |
| VibeComfy validation failures | Worker retry/fail classification | Map to schema-validation or template-routing error class, not generic Python failure. |

Dual-run reports and canary dashboards should group metrics by `task_type`, `backend`, `template_id`, `memory_profile`, error class, and worker image version. Without these labels, rollback decisions will rely on raw exception text and task ids, which is too slow for production canary.

## 8. Dual-executor steady state

Sprint 12 is not Wan2GP removal. The desired end state is a dual-executor worker platform where WGP and VibeComfy are both installed, supported, observable, and selectable by runtime route. VibeComfy becomes available for the routes that pass parity and canary gates; WGP remains a first-class executor for fallback, comparison, and any route where it is still the better or only proven backend.

### Steady-state contract

| Area | Required end state |
| --- | --- |
| Worker image | One dual-stack image includes both WGP and VibeComfy dependencies, models, custom nodes, startup probes, and health checks. |
| Worker pools | Production can run WGP-default and Comfy-default worker processes/pools from the same image. Process/pool isolation remains the preferred production architecture. |
| Selector | `backend_selector` can route by task type for direct image/edit tasks and by `(task_type, model_family/model_name, guidance_kind)` for orchestrated video. |
| Rollback | Any Comfy-promoted route can be flipped back to WGP by runtime selector update, without rebuilding or redeploying the worker image. |
| Observability | Dashboards, logs, debug cards, and alerts distinguish `backend=wgp` from `backend=comfy`, include selector version, and compare latency/VRAM/error/output-divergence by route. |
| Profiles | WGP profile semantics and VibeComfy `MemoryProfile` mapping both remain documented and test-covered. |
| Unsupported routes | If a route selects Comfy but no Comfy route exists, the worker fails closed/requeues before execution. It does not silently fall back to WGP unless the selector chose WGP. |

### Sprint 12 hardening checklist

| Area | Harden / verify | Notes |
| --- | --- | --- |
| WGP executor | Keep WGP runtime packages, model packages, CLI flags, profile handling, root scripts, and WGP tests that prove current behavior. | Do not delete `Wan2GP/`, `source/runtime/wgp_*`, `source/models/wgp/`, or WGP bridge tests as part of this epic. |
| VibeComfy executor | Keep VibeComfy adapter, `template_routing.py`, LoRA sanitizer, profile mapping, telemetry mapper, and route tests. | The adapter should be tested as a peer executor, not as a replacement that makes WGP dead code. |
| Shared executor interface | Ensure both executors implement the same worker-facing contract: `supports(route)`, `prepare(task)`, `run(task, profile)`, `cleanup()`, and `health()`. | Selector logic remains outside both executors. |
| Orchestrator startup | Preserve WGP startup behavior and add Comfy startup behavior. | Startup templates should pass backend/profile flags without removing WGP flags. |
| Claim eligibility | Confirm WGP workers claim WGP-routed tasks and Comfy workers claim Comfy-routed tasks; incompatible workers fail closed before execution. | Prefer claim-time filtering; fallback is pre-execution requeue/fail-closed. |
| Dual-run harness | Keep nightly or scheduled dual-run capability for representative routes. | This remains useful after canary to detect drift in either backend. |
| Documentation | Publish a runbook for choosing WGP vs Comfy per route, flipping the selector, and interpreting backend-specific failures. | This is the actual closure artifact for the epic. |

### UNUSED task-type cleanup

The only deletion bundled with the end-state sprint is deletion of production-unused task-type handlers whose removal does **not** remove WGP as an executor. These are cleanup candidates, not proof that WGP is being retired:

- `magic_edit`
- `inpaint_frames`
- `extract_frame`
- `create_visualization`
- raw `comfy`
- `qwen_image_hires` task-type branch
- `rife_interpolate_images` dispatch wrapper and native RIFE helper, only after the §8A cleanup gate proves no RayWorker dispatch/history/admin path still depends on them

Deleting these rows is optional for the dual-executor conclusion. If cleanup risks delaying dual-executor readiness, defer it to Sprint 12B or separate post-canary PRs.

### Dual-executor exit criteria

- Both WGP and VibeComfy worker processes can boot from the same image.
- Selector can route at least one Cohort A route, one Cohort B route, and, if Sprint 9 produced any dual-supported non-FALL-BACK orchestration route, one Cohort E route to either backend where both are supported. If all Cohort E promoted routes are WGP-only, the selector docs must say so explicitly.
- WGP-only, Comfy-only, and dual-supported routes are explicit in `template_routing.py` / selector docs.
- Runtime selector rollback from Comfy to WGP is tested in staging and production canary.
- Dashboards and debug cards make backend choice obvious for every task.
- No Comfy migration PR removes WGP runtime code, WGP dependencies, WGP tests, or WGP startup paths.

## 8A. Cleanup Scope

Cleanup is deliberately separated from the migration. The epic closes when WGP and VibeComfy are both supported, selectable executors with tested rollback. It does not require deleting production-unused task handlers or old app scaffolding.

Migration-blocking cleanup is limited to contract safety:

- `turbo_mode: true` must be rejected, coerced safely, or removed from active emitters before Sprint 0 baselines freeze because it can produce an unregistered worker task type.
- Server-side validation gaps that can create invalid worker routes, such as invalid `model_type`, may land before Sprint 0 if baselines are regenerated, or after canary as API-hardening work.

Post-canary cleanup candidates belong in Sprint 12B or separate PRs:

- UNUSED task-type handlers such as raw `comfy`, `magic_edit`, `inpaint_frames`, `extract_frame`, `create_visualization`, `qwen_image_hires`, and the `rife_interpolate_images` dispatch wrapper.
- Turbo-mode UI/settings/schema scaffolding and any persisted JSON cleanup.
- Duplicate or unconsumed package metadata such as `[tool.headless_wan2gp.entrypoints]` and `[tool.headless_wan2gp.deprecation]` if still verified unused.
- Ambiguous legacy frontend fields or timeline/prompt markers only after their stated DB or owner checks prove they are dead.

Deletion gate for worker handlers: before deleting code, prove there are zero pending/in-progress/retryable rows, zero recent rows that can be retried through the handler, zero admin/debug/direct-DB emitters, and explicit owner sign-off. If any check fails, keep the handler installed and mark the route WGP-only or unsupported under Comfy.

## 9. Open questions, assumptions, risks, and mitigations

### Open Questions

| ID | Question | Decision needed by | Default stance until answered |
| --- | --- | --- | --- |
| Q1 | Can VibeComfy memory-profile overrides switch per task, or do some changes require session restart? | Sprint 1 exit | Use per-task override only where `EmbeddedSession.reconfigure()` proves safe; otherwise restart session between profile families. |
| Q2 | Does the Wan 2.2 HIGH->LOW two-stage sampler reproduce WGP closely enough? | Sprint 3.5 | If §11 video thresholds fail, keep Wan-family VACE routes WGP-only. |
| Q3 | What is the true VibeComfy route for non-2512 `qwen_image`? | Sprint 5 | Do not promote `qwen_image` through the `qwen_image_2512` template unless equivalence is proven. |
| Q4 | Which control-capable LTX template covers matrix rows 9-13? | Sprint 9 | Mark those rows NEW/BLOCKED/WGP-only until a real first/last+control workflow is verified. |
| Q5 | Should `headless_model_management` stay WGP-specific or become backend-neutral? | Sprint 12 | Keep the WGP-specific command unless a backend-neutral replacement has equivalent WGP coverage. |

### Assumptions

- Queue contracts and Supabase task schema remain unchanged.
- WGP and VibeComfy stay coinstalled in the worker image as the steady-state architecture.
- Worker processes launch with exactly one backend at a time; production does not hot-switch WGP and VibeComfy inside one process.
- Production profile 1 and development profile 3 remain distinct contracts.
- `reigh-worker/`, `reigh-worker-orchestrator/`, and `vibecomfy/` are independent nested repos; closure sweeps must run per repo or by filesystem traversal.

### Key Risks

| Risk | Impact | Mitigation | Status |
| --- | --- | --- | --- |
| Missing memory-profile parity | P0 blocker for cutover. | Sprint 1 `MemoryProfile` overlay plus profile 1/3 smokes and profile 4/5 coverage for heavy routes before canary. | MITIGATED BY PLAN |
| Selector/claim contract too late or too abstract | Workers can claim the wrong backend route. | Sprint 2 local selector skeleton; Sprint 6 production selector/claim contract before orchestrated propagation depends on it. | MITIGATED BY PLAN |
| Product/billing oracle incomplete | Media output passes while app-visible behavior regresses. | Sprint 0A contract skeleton and Sprint 3 executable product/billing checks. | MITIGATED BY PLAN |
| Orchestrator/pool behavior under-specified | Canary fails during startup, health, stale-worker, or rollback scenarios. | Sprint 7 deployment and artifact contract before Cohort E parity and canary. | MITIGATED BY PLAN |
| Wan VACE Comfy template cannot match WGP | Wan-family travel/join cannot safely canary on Comfy. | Sprint 3.5 feasibility gate; fallback keeps Wan-family VACE routes WGP-only. | ACCEPTED FALLBACK |
| LTX control rows are incorrectly mapped | Matrix falsely reports coverage. | Sprint 9 verifies rows 9-13 against a real control-capable template or marks them WGP-only. | OPEN UNTIL SPRINT 9 |
| Cleanup invalidates baselines | Migration comparisons become untrustworthy. | Cleanup is Sprint 12B/post-canary unless it lands before Sprint 0 with regenerated baselines. | MITIGATED BY PLAN |
| WGP is accidentally treated as retired | Rollback and steady-state support break. | Sprint 12 explicitly keeps WGP runtime code, tests, dependencies, and startup paths. | MITIGATED BY PLAN |

## 10. Closure-sweep procedure

This sweep is mandatory before and after Sprint 12. Its purpose is not to prove WGP was removed; it is to prove WGP ownership is intentional and that no Comfy rollout accidentally deleted or orphaned WGP executor surfaces. A workspace-root `git grep` is not sufficient because `reigh-worker/`, `reigh-worker-orchestrator/`, and `vibecomfy/` are independent Git repos nested under the workspace. Running `git grep` from `/Users/peteromalley/Documents/reigh-workspace` can return zero hits while committed files still exist inside the nested repos.

### Option A: Git-Aware Committed-File Sweep

Use this before Sprint 12 hardening to find committed WGP surfaces and classify each as retained executor surface, optional cleanup, or archival documentation. Run both commands from the workspace root:

```bash
git -C reigh-worker grep -lE 'wgp_|headless_wgp|headless_model_management|mmgp|Wan2GP|WanOrchestrator|--wgp-' | sed 's|^|reigh-worker/|'
```

```bash
git -C reigh-worker-orchestrator grep -lE 'wgp_|headless_wgp|headless_model_management|mmgp|Wan2GP|WanOrchestrator|--wgp-' | sed 's|^|reigh-worker-orchestrator/|'
```

Pre-Sprint-12 rule: append any surfaced files not already listed in Section 8 to the retained-executor or cleanup classification before starting hardening. WGP runtime code, dependencies, tests, CLI flags, and startup paths should generally classify as retained executor surface.

### Option B: Filesystem Traversal Sweep

Use this after Sprint 12 to catch untracked files and filesystem residue, then verify retained WGP hits are expected:

```bash
rg -l 'wgp_|headless_wgp|headless_model_management|mmgp|Wan2GP|WanOrchestrator|--wgp-' reigh-worker/ reigh-worker-orchestrator/
```

Post-hardening rule: assert zero **unexpected** hits. Expected hits include WGP executor code, tests, startup paths, model/default evidence, and explicit archive docs. Unexpected hits are stale names in Comfy-only code, selector docs that imply WGP is deleted, or cleanup-only handlers that were supposed to be removed.

If Option B finds code, tests, startup scripts, package metadata, or environment examples, Sprint 12 is not complete until each hit is classified as retained WGP executor surface, Comfy/shared code that needs renaming, optional cleanup, or archival documentation.

## 11. Migration thresholds (single source of truth)

**Status (2026-05-05):** Pinned as starting thresholds, then calibrated in Sprint 0A. These are starting thresholds; Sprint 0B calibrates them against WGP self-drift before they become hard gates. All dual-run scripts (Sprint 3), Sprint 3.5 dry run, and Sprint 11 canary triggers MUST read these values from one artifact: `reigh-worker/scripts/dual_run_compare/migration-thresholds.yaml` (Sprint 0 deliverable, owned by reigh-worker, mirrors the table below plus calibration notes). Changing a threshold requires updating both the YAML and this section in the same PR.

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
| Canary divergence | Output-divergence rate per cohort (per-frame pHash p95 breach rate) | ≤ 1% of shadow/sampled tasks over 24h window | Auto-rollback only if measured through isolated shadow runs with no completion, billing, upload, or user-visible side effects; otherwise mark cohort review-required and stop promotion |

### Sprint 0 deliverables

- `reigh-worker/scripts/dual_run_compare/migration-thresholds.yaml` — machine-readable copy of the table above plus Sprint 0A WGP self-repeatability calibration notes. Calibration runs same backend vs same backend, fixed seed, target GPU/profile combinations, and the selected route-key corpus. If WGP self-drift exceeds a starting threshold, the threshold must be widened with explicit rationale or the route must stay WGP-only until a deterministic comparison method exists.
- `reigh-worker/scripts/dual_run_compare/golden/<route_key>/` — WGP-side golden corpus (reference outputs) for every selector route intended for promotion, not just every task type. Cohort E keys include `(task_type, model_name/model_family, guidance_kind, continuity_case, profile)`; Cohort B keys include edit model variant, mask/annotation/style-reference cases, and relevant profile. Sprint 3 dual-run compares Comfy outputs against this corpus + a fresh WGP run.
- Per-task-type effective timeout, polling cadence, payload shape, and post-completion artifact paths captured into `reigh-worker/docs/migration-baselines.md` per the lifecycle-contract test prerequisites.

### Cross-references

- Sprint 3 exit criteria: "Comparison report fails (red) for landed routes if any threshold above is exceeded; not-yet-routed rows are classified rather than blocking Sprint 3."
- Sprint 3.5 dry-run gate: "Per-frame pHash mean ≤ 0.08 AND p95 ≤ 0.12 on the Wan 2.2 VACE cocktail single-shot dry run; otherwise fall back per §6 (keep Wan VACE on WGP indefinitely; remainder of migration proceeds)."
- Sprint 11 rollback trigger: auto-flip cohort to `wgp` when p95 latency >1.10× baseline sustained 24h OR OOM count >0 over 1h window OR output-divergence rate >1% over 24h from isolated shadow runs. If no safe shadow path exists, output divergence blocks further promotion and is reviewed offline.
- §6 rollback table is patched accordingly.

## 12. Pre-kickoff confidence checklist

Before Sprint 0 starts, the user (or named owner) explicitly checks each of the following. Unchecked items block kickoff.

- [ ] **Threshold values provisionally approved and calibration staffed** (§11) — the numeric thresholds in §11 are accepted as starting values before Sprint 0A; Sprint 0A runs WGP-vs-WGP repeatability calibration, Sprint 0B creates and commits `migration-thresholds.yaml`, and the YAML is readable by all three consumer scripts (Sprint 3 dual-run, Sprint 3.5 dry run, Sprint 11 canary).
- [ ] **Turbo-mode contract risk closed** (§0A / §8A) — `turbo_mode: true` is either rejected/coerced safely by resolver tests or removed from all active emitters, including AI/timeline-agent paths, before baselines freeze.
- [ ] **Per-sprint gates credible** — every Sprint N row in §4 has concrete exit criteria, and predecessor exit criteria are sufficient to start the next sprint.
- [ ] **Pre-Sprint-4 dry run plan staffed** — owner named (VibeComfy maintainer + reigh-worker adapter author per §3A "Wan 2.2 VACE cocktail"); reference output identified; dry-run pod budgeted.
- [ ] **Rollback control plane has an owner** — Sprint 11 canary owner has committed to runtime selector rollback plus draft PRs for durable follow-up before promotion.
- [ ] **Migration-blocking §8A checks identified** — §8A rows are split into migration-blocking vs cleanup-only; only migration-blocking rows can gate Sprint 12 dual-executor hardening.
- [ ] **§9 risk table audited** — every row has a Status column value (OPEN / MITIGATED / ACCEPTED / CLOSED).
- [ ] **Pod disk-size change approved and owned** — Sprint 0C owns the 200 GB disk-size change or an explicit owner/date for it, and measures first dual-stack pod boot/download behavior. If the code change lands before Sprint 0, regenerate affected baselines.
- [ ] **Custom-node lockfile audited** — every template `template_routing.py` can select has its `READY_REQUIREMENTS.custom_nodes` represented in `vibecomfy/custom_nodes.lock`.
- [ ] **Capacity/security owners named for canary readiness** — not a Sprint 1 blocker, but Sprint 10 must have named owners for capacity/cost plan, artifact retention/privacy, selector ACLs, and alert routing.

If any item is unchecked at kickoff, Sprint 0 does not start.
