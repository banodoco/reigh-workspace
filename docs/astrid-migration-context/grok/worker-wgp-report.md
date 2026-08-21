Working...
# Reigh task system → Astrid kernel (forensic)

Grounded in repo files. `run_type` on live rows is from the 2026-08-21 probe in `docs/astrid-migration-context/16-capability-map.md` §5.

---

## 1. Task-type inventory

Creation: **resolver** = `create-task` named family; **child** = worker `add_task_to_db` → same edge, family = `task_types.name` via `createWorkerPassthroughResolver`. GPU vs API is `task_types.run_type`, not a column on `tasks`. Worker always claims `run_type:"gpu"` (`task_claim.poll_next_task`); API orchestrator always `"api"`.

| task_type | family | GPU handler | run_type | created | output |
|---|---|---|---|---|---|
| `wan_2_2_t2i` | image_generation | DIRECT_QUEUE → WGP or VibeComfy `video/wanvideo_wrapper_22_14b_t2i` | api | resolver (batch) | generation |
| `qwen_image` / `_style` / `_2512` | image_generation | DIRECT_QUEUE → VibeComfy `image/qwen_image_2512` or `edit/qwen_image_edit` | api | resolver (batch) | generation |
| `z_image_turbo` | image_generation | DIRECT_QUEUE → VibeComfy `image/z_image` | api | resolver (batch) | generation |
| `image-upscale` | image_upscale | DIRECT_QUEUE → VibeComfy `image/basic_image_upscale` | api | resolver | generation (based_on) |
| `individual_travel_segment` | individual_travel_segment | specialized: `handle_travel_segment_via_queue` standalone | gpu | resolver | generation |
| `join_clips_orchestrator` | join_clips | `handle_join_clips_orchestrator_task` | gpu | resolver **or child** (travel stitch_config) | none (orch) |
| `video_enhance` | video_enhance | DIRECT_QUEUE → VibeComfy `video/basic_video_enhance` | api | resolver | generation (variant) |
| `z_image_turbo_i2i` | z_image_turbo_i2i | DIRECT_QUEUE → VibeComfy `image/z_image_img2img` | api | resolver (batch) | variant/gen |
| `qwen_image_edit` | magic_edit | DIRECT_QUEUE → VibeComfy `edit/qwen_image_edit` | api | resolver (batch) | variant/gen |
| `image_inpaint` / `annotated_image_edit` | masked_edit | DIRECT_QUEUE → VibeComfy `edit/qwen_image_edit` | api | resolver (batch) | generation |
| `travel_orchestrator` | travel_between_images | `handle_travel_orchestrator_task` | gpu | resolver | none (orch) |
| `wan_2_2_i2v` | travel_between_images (turbo) | DIRECT_QUEUE → VibeComfy `video/wanvideo_wrapper_22_14b_i2v_kijai` | api | resolver | generation |
| `travel_stitch` | crossfade_join | `handle_travel_stitch_task` | gpu | resolver **or child** | generation |
| `edit_video_orchestrator` | edit_video_orchestrator | `handle_edit_video_orchestrator_task` | gpu | resolver | none (orch) |
| `animate_character` | character_animate | DIRECT_QUEUE → VibeComfy `video/wan22_animate_native_first_stage` | api | resolver | generation |
| `flux_klein_edit` | klein_edit | DIRECT_QUEUE → VibeComfy `edit/flux2_klein_4b_image_edit_distilled` | api | resolver (batch ≤4) | variant/gen |
| `join_clips_segment` | *(passthrough)* | `_handle_join_clips_segment_task` → WGP VACE | gpu | child | processing (skip_generation) |
| `join_final_stitch` | *(passthrough)* | `handle_join_final_stitch` | gpu | child | generation |
| `travel_segment` | *(passthrough)* | `handle_travel_segment_via_queue` | gpu | child | processing |
| `comfy` / `extract_frame` / `inpaint_frames` / `rife_interpolate_images` / `create_visualization` | none | specialized GPU handlers | — | unused/legacy | — |
| `vace`/`t2v`/`i2v`/`ltx2`/… | none | DIRECT_QUEUE WGP | gpu | catalog-only | — |
| `banodoco_timeline_generate` / `banodoco_render_timeline` | none | API TASK_HANDLERS (pool `banodoco`) | — | not in 13 families | render |

API `TASK_HANDLERS` (`api_orchestrator/task_handlers.py`): fal (`image-upscale`, `qwen_image`/`_2512`, `z_image_turbo`, `z_image_turbo_i2i`, `video_enhance`, `flux_klein_edit`), wavespeed (`qwen_image_edit`/`_style`, `wan_2_2_t2i`/`i2v`, `animate_character`), image (`image_inpaint`, `annotated_image_edit`). No replicate handlers. Doc 24 Q3 cuts this path.

`edit_video_segment`: live `task_types` row, **no current worker writer** — `edit_video_orchestrator` reuses the join chain (`join_clips_segment` + `join_final_stitch`).

Placement: `complete_task/handler.ts` → `createGenerationFromTask` → `executePlacement` if `placement_intent`; orchestrators skip generation (`category=orchestration` / `skip_generation`).

---

## 2. Dispatch / registry

No `register_handler`. Static:

1. `server.process_single_task` → `TaskRegistry.dispatch(task_type, context)` (`server.py:177`).
2. If `task_type ∈ DIRECT_QUEUE_TASK_TYPES` (`task_types.py` catalog): `resolve_task_route` (`template_routing.py`) then `execute_resolved_direct_task` (`task_execution.py`).
   - `WorkerBackend.WGP` → `HeadlessTaskQueue.submit_task` → poll `get_task_status` (in-process).
   - `VIBECOMFY` + `VIBECOMFY_SUPPORTED` → `handle_vibecomfy_resolved_task` → `subprocess.run([python, -m, vibecomfy.cli, run, …])`.
3. Else specialized dict (`task_registry.py:1569`): travel/join/edit orch, segments, stitch, extract_frame, inpaint_frames, create_visualization, rife, comfy.
4. Else fallthrough to direct queue if `task_queue` exists; else `ValueError`.

Lazy imports: `dispatch_manifest.HANDLER_IMPORT_SPECS` only for `travel_orchestrator`, `extract_frame`, `travel_segment`, `individual_travel_segment`.

Claim: GPU `poll_next_task` POSTs `claim-next-task` `{worker_id, run_type:"gpu", worker_backend, worker_profile, selector_*}`. RPC `claim_next_task_service_role` filters `get_task_run_type`. PAT path ignores run_type. Route guard `_claim_route_guard` is fail-closed vs `REIGH_BACKEND`.

Status: leaf Complete → `complete_task` (base64 <2MB / signed PUT ≥2MB). Intermediate: `storage.upload_intermediate_file_to_storage` (`artifact_class:"intermediate"`). Final location is local-path passthrough until complete_task.

Guardian: 20s `func_worker_heartbeat_with_logs`; PID death → `status="crashed"`. No lease TTL.

---

## 3. Wan2GP

Git submodule `reigh-worker/.gitmodules`: `https://github.com/banodoco/Wan2GP.git` branch `reigh-sprint-3`, SHA **`181bb71a21008032e4771e11663f33e4489c4512`**. Not pip. Fork of deepbeepmeep/WanGP (v10.9874 in README).

Drive (in-process, cwd must be `Wan2GP/`):

`execute_resolved_direct_task` → `HeadlessTaskQueue.submit_task` → `process_task_impl` → `WanOrchestrator.generate` → `wgp.generate_video` / `wgp.load_models`. Boundary: `runtime_paths.ensure_wan2gp_on_path` + `wgp_bridge.py`. Models: `Wan2GP/defaults/<key>.json` + `finetunes/`; weights `Wan2GP/ckpts/` auto-download. `TASK_TYPE_TO_MODEL` maps Reigh types (`wan_2_2_t2i`→`t2v_2_2`, join segment→`wan_2_2_vace_lightning_baseline_2_2_2`). I/O: prompt, image_refs (PIL, not paths), `video_length` (t2i forced 1), output under `main_output_dir`.

Update: rebase fork, bump submodule, revalidate `wgp_patches.py` + path contract (`docs/wan2gp-rebase-runbook.md`). Drift CI is report-only. Worker boot rewrites `Wan2GP/wgp_config.json`.

Pose: `decord` is the video reader (`wgp.py`, VACE preprocessor). `smplfitter` is a **SCAIL/NLFPose** dep (`Wan2GP/models/wan/scail/nlf/eager.py`); Reigh travel uses **DWPose** (`media/structure/preprocessors.ensure_dwpose_models`), not SMPL. Local stubs `reigh-worker/smplfitter/` and `decord/` paper over missing wheels. Darwin-arm64 `decord==0.6.0` wheel gap is a known test hazard.

Risks: in-process import + cwd contract; monkeypatches vs upstream; ckpts disk; dual WGP/VibeComfy for the same `task_type`.

---

## 4. Dynamic orchestrator (children mid-run)

**Sole INSERT** is still `create-task`. Worker `add_task_to_db` (`task_completion.py`) POSTs `{family: task_type_str, project_id, input: {…payload, task_id: pregenerated UUID, dependant_on: list}}`. Unknown family + active `task_types.name` → passthrough (`index.ts:469-487`). Honors `input.task_id` so sibling `dependant_on` matches.

**Join** (`join/task_builder.py`):
- Chain: N−1 `join_clips_segment` (`dependant_on` previous), then `join_final_stitch` on last. Payload: `orchestrator_task_id_ref`, `join_index`, `starting_video_path`/`ending_video_path`, `skip_generation:true`, `orchestrator_details`.
- Parallel: segments `dependant_on=None`; stitch `dependant_on=transition_task_ids[]`.

**Travel** (`travel/orchestrator.py`): sequential `travel_segment` (`dependant_on` previous); then either `travel_stitch` on last, or `join_clips_orchestrator` depending on **all** segment ids (`stitch_config`). Optional later upscale child from `travel/stitch.py` (`task_type_str=upscaler_engine_to_use`).

**Edit video**: preprocess keepers, then `create_join_chain_tasks` (same join children). No `edit_video_segment`.

**Progress**: orch types `{travel,join_clips,edit_video}_orchestrator` on success stay **In Progress** (`server.py:907-932`) with `output_location` = progress string / `[ORCHESTRATOR_COMPLETE]{json}`. Parent Complete is `complete_task/orchestrator.ts` `checkOrchestratorCompletion` when children (and `join_final_stitch` wait-gate) finish. Claim will not re-claim an In Progress parent; `_orchestrator_has_incomplete_children` is claim-adjacent.

Route snapshots: children inherit parent `route_contract` via `parent_derived_child_route_snapshot_fields` / `_route_snapshot_for_join_child`.

---

## 5. Add a task type today

| # | Seam | Difficulty |
|---|---|---|
| 1 | `resolvers/registry.ts` + new resolver; family ≠ `tasks.task_type` (`image_upscale`→`image-upscale`) | medium |
| 2 | `task_types` seed (`20260413000000_add_flux_klein_edit…` shape: `run_type`, `category`, `billing_type`, `unit_cost`, `tool_type`, `content_type`). FK `tasks.task_type→task_types.name` (`20260213000000_…fkey.sql`) | **hard** — live 37 rows vs repo seeds; hyphen vs underscore |
| 3 | GPU: `DIRECT_QUEUE`/`TASK_TYPE_TO_MODEL` and/or specialized dict; API: `TASK_HANDLERS` | medium |
| 4 | `template_routing.SPRINT_2_SELECTOR_MAP` + `template_id`; VibeComfy scratchpad in `vibecomfy_adapter._workflow_reference_for_resolved_task`; dimensional `SECTION3A_ROUTE_SUPPORT_MAP` for travel | **hard** |
| 5 | `stampTaskRouteContract` (`routeContract.ts`); NULL `route_key` fails claim except `*_orchestrator` | **hard** |
| 6 | Frontend `createTask.ts` `{family, project_id, input, idempotency_key, materialized_inputs?}` + `TOOL_IDS` | medium |
| 7 | `complete_task`: `createGenerationFromTask` routing (`variant_on_child→parent→child→standalone`); `executePlacement`; trigger `create_generation_on_task_complete` if `category=generation` | **hard** |
| 8 | Worker children: only need active `task_types` row + GPU handler (no named family) | easier, still FK+route |

Unsafe: billing columns (cut in migration), live/repo drift, `image-upscale` hyphen, passthrough gated on DB not code.

---

## 6. Gaps vs Astrid fenced tasks

**Maps cleanly:** 13 families → `reigh.<task_type>` capabilities (doc 16); batch → `runs` + `run_ordinal`; `dependant_on` → hard `task_dependencies`; claim poll → R3 capability allowlist; VibeComfy subprocess and WGP in-process stay as executors; complete_task generation/placement → atomic R7 (doc 24: no relational placement, document-native).

**Breaks:**
- **Worker-created children after claim.** Kernel `spec_json` is immutable at admission (doc 14 §2). Today the parent mutates the queue mid-run. v1 keep: allowlist passthrough via R1 from the executor (doc 14: “keep orchestrator contracts inside immutable specs; structural runs later”). Need executor-initiated admission with `Idempotency-Key`, and map worker UUIDs → kernel ULIDs so `dependant_on` still wires.
- **Parent stays In Progress** with progress in `output_location`. Astrid heartbeat is **non-event** and bumps `status_version` (R5). Progress must ride heartbeat `progress` JSON, not a status rewrite. Parent must not `complete` until children succeed — either kernel `blocked` on children, or explicit orch-complete after last child (today’s `checkOrchestratorCompletion`).
- **Mid-run continuation** (SVI latent tails, `upload_intermediate_file_to_storage` URLs). R6 quarantine is attempt-scoped; cross-task intermediates need media_ids at child admission, not public `image_uploads` URLs.
- **run_type gpu/api + API orchestrator.** Doc 24 Q3: fully local; fal/wavespeed/banodoco handlers are cut. Same `task_type` currently dual-pathed (WGP *or* VibeComfy *or* API). Capability allowlist must encode **local backend**, not `task_types.run_type`.
- **No lease today** vs 300s fence + serialized heartbeat/complete (`LeaseKeeper`, doc 19). Orchestrator In-Progress-without-lease will look like a lost attempt if the worker returns to the claim loop after enqueueing children.
- **gpu_orchestrator** (RunPod spawn from `task-counts`) is retired; local executor is one process + optional VibeComfy subprocess.

**Genuinely new:** capability-gated claim; receipted child admission; atomic complete (bytes + media + generation, **no** shot_generation_items); heartbeat-as-progress; local model/node availability (`422 capability_unavailable`) instead of API fallback; Comfy wrap = new `reigh.*` capability + `template_id` + VibeComfy scratchpad, not a `task_types` row.
[launch_hermes_agent] done in 334.2s (exit=0)
0
