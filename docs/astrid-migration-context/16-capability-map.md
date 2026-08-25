# 16 — Reigh Task Capability Map (for `ReighTaskBridgeAdapter`)

> **SUPERSEDED by `27-build-spec.md` (Grok review, judged ADOPT).** Historical payload and resolver evidence only; it is not a working build contract.
>
> **(Amended: Grok review — judged ADOPT.)** Kernel ULIDs are the only task IDs; there is no worker UUID/logical-ID cache or dependency rewrite. Worker-child families are admitted only through R1 by the live fenced parent executor using deterministic `reigh.orch:v1:<parent>:<role>:<index>` keys; browser admission is forbidden. Day-one coverage is one production-shaped `wan_2_2_t2i` slice plus missing-model, admission/completion replay, fence, crash/expiry, poisoned-output, and cancellation cases; join/travel fixtures move to Phase B. Placement is timeline-document CAS state, thumbnails are later work, and the `shots` pack is dormant as a Reigh authority. `[INFERENCE]` Repository search found no handler reads of `orchestration_contract`, `task_view_contract`, or `family_contract`, so those legacy contract blocks are not part of the surviving build contract; retain `orchestrator_details`, which handlers do read.

**(Amended doc 26/Grok)** Naming ratified: flat `reigh.<normalized>` IDs are final; semantic taxonomy as capability naming is rejected and remains catalog metadata only per Grok's second opinion and doc 26.

**Phase-1 design spec — READ-ONLY research; no implementation. Prepared 2026-08-21.**

**Summary.** This is the complete capability map for the bridge's `ReighTaskBridgeAdapter` (doc 14 §2): every one of the 13 resolver families in `reigh-app/supabase/functions/create-task/resolvers/` is enumerated with its source `task_type` strings (including the `image-upscale` hyphenation oddity), its canonical kernel `capability` name (`reigh.<normalized>`), its full input payload contract (field / type / required), its kernel `output_policy`, its dependency edges, priority, batch/orchestrator shape, and the worker pipeline it maps to (doc 03). Also included: the live `task_types` DB ↔ resolver gap table (37 live rows, 8 inactive, probed 2026-08-21), a code-declared passthrough allowlist proposal replacing the `task_types` lookup, a golden-test fixture list (one per payload shape, with expected kernel rows), and open questions. An engineer can implement the adapter resolver layer from this document alone.

**Key facts**
- `create-task` is the sole INSERT path into Reigh `tasks`; 13 named families in `resolvers/registry.ts` + a `task_types`-backed passthrough for worker-created children. [10 §3, `registry.ts`]
- Every family maps to exactly one `reigh.<normalized>` capability; the only hyphenated source `task_type` is `image-upscale` → `reigh.image_upscale`. [14 §2, `imageUpscale.ts`]
- Kernel admission contract (doc 14 §2): `capability`, `spec_json` (with `output_policy`), `input_manifest_json` (media_ids resolved at admission), `priority`, `available_at=now`, `max_attempts=3`, `status=queued|blocked`, one hard `task_dependencies` edge per `dependant_on` entry; batch families admitted atomically as a `run` with ordered children (`run_ordinal`).
- Live `task_types` has **37 rows (29 active / 8 inactive)** — doc 01's "28 rows" and the repo's 26 seed names are both stale; 13 live rows have no repo seed. The DB is **not migrated** (doc 14 §2); the passthrough becomes a code-declared allowlist.
- Every one of the 19 `task_type` strings the resolvers can write exists as an active live row (verified 2026-08-21) — the FK `tasks.task_type → task_types(name)` is satisfiable today for all families, but the adapter must not depend on that FK.
- Batch families (fan-out >1 row per request): `image_generation` (prompts×imagesPerPrompt ≤16), `magic_edit` (≤16), `masked_edit` (≤16), `klein_edit` (≤4), `z_image_turbo_i2i` (≤16). Orchestrator families: `join_clips`, `travel_between_images`, `edit_video_orchestrator` (worker creates children via the passthrough path). [10 §3.3, resolver files]
- Two resolvers (`individual_travel_segment`, `crossfade_join`, `travel_between_images`) branch on `orchestrator_task_id_ref`: worker-created tasks pass through raw, frontend-created tasks get full validation. [resolver files]

---

## 1. Adapter architecture (context, from doc 14 §2)

```text
Reigh UI
  → createTask() (reigh-app/src/shared/lib/taskCreation/createTask.ts)
  → AstridLocalClient.createTask()
  → POST /projects/{project_slug}/tasks            ← new bridge route
  → ReighTaskBridgeAdapter
  → ported family resolver (this map)
  → TasksService.create / RunRepository.create (SDK; [BUILD] RunsService.create facade)
  → kernel tasks + task_dependencies + runs + receipt/event
```

Request body (unchanged contract, doc 14 §2):

```json
{
  "family": "image_generation",
  "input": { "...": "existing family payload" },
  "materialized_inputs": [
    {"generation_id": "...", "kind": "file", "target": "source_image"}
  ]
}
```

- `Idempotency-Key` header required; `201` admission / `200` replay / `409 idempotency_mismatch` on same key + different bytes.
- Batch requests (>1 task) with a request key derive per-task keys `sha256(baseKey:index)` (ported from `create-task/index.ts` `deriveBatchIdempotencyKey`); adapter maps these onto kernel `command_receipts`.
- Ownership check (projects.user_id == caller) and aspect-ratio lookup become bridge-side same-project assertions (no auth, doc 15).
- The ported resolvers are **pure** (validation + param building). Their Supabase-specific side effects must be re-plumbed: `ensure_shot_parent_generation` / generation lookups → content pack queries; route-contract stamping (`derive_route_key` RPC) is **dropped** (route control plane is cut, doc 13 §10.Q14 / doc 15).
- `tasks_assert_claimable` trigger and `params.route_contract` are not recreated; `spec_json` keeps the resolved worker payload verbatim so existing `reigh-worker` handlers keep working against the claim adapter. [14 §2: "keep existing orchestrator contracts inside immutable task specs"]

### 1.1 Kernel row mapping (exact)

| Kernel table | Reigh source | Notes |
|---|---|---|
| `tasks` | `tasks` row via resolver | `capability` = `reigh.<normalized task_type>`; `spec_json` = doc-14 envelope below; `input_manifest_json` = media entries; `status` = `queued` (no deps) or `blocked` (deps) |
| `task_dependencies` | `dependant_on[]` (worker passthrough lifts it; all frontend families write `null`) | one `kind='hard'` edge per entry |
| `runs` | batch families & orchestrator fan-outs | `kind` = family name; `title` = family; `input_json` = request input |
| `command_receipts` | `idempotency_key` (+ batch-derived keys) | receipt = admission result |
| `media` / `media_locations` | `materialized_inputs[].generation_id` → its media row | resolved during admission; `input_manifest_json` entries carry `media_id` |
| `projects` | `project_id` | bridge route is project-scoped |

`spec_json` envelope (doc 14 §2, exact):

```json
{
  "schema_version": 1,
  "family": "<resolver family>",
  "source_task_type": "<original task_type string, hyphenation preserved>",
  "params": { "...": "<resolved worker payload, verbatim>" },
  "output_policy": {
    "create_generation": true,
    "shot_id": "<uuid or null>",
    "based_on_generation_id": "<uuid or null>",
    "timeline_placement": { "timeline_id": "...", "source_clip_id": "...", "target_track": "...", "insertion_time": 3.5, "intent": "after_source" } | null,
    "placement_intent": { "timeline_id": "...", "anchor_clip_id": "...", "relation": "after", ... } | null,
    "variant": { "source_variant_id": "<uuid or null>", "create_as_generation": false, "is_primary": false, "make_primary_variant": false }
  }
}
```

`input_manifest_json` (one entry per input media; roles = `materialized_inputs[].target`, plus generation-backed params such as `based_on` when a media_id is resolvable):

```json
[
  {"role": "source_image", "media_id": "<kernel media ULID>", "kind": "file"},
  {"role": "style_reference_image", "media_id": "<...>", "kind": "remote"}
]
```

Admission rules carried over from `create-task/index.ts`: unknown family → allowlist lookup (was `task_types` + `createWorkerPassthroughResolver`, §6 below); resolver output must be a non-empty task array. The legacy path returned `400 unknown_task_family` / `400 validation_error`; the ratified bridge returns `422 unsupported_family` for unknown UI families and `422 unsupported_capability` for unknown/inactive/dead derived children (doc 18 §2.3/R1). Batch idempotency recovery returns the existing ids with `deduplicated: true` for singles / `task_ids[]` for batches. **(Amended doc 26/Grok)**

**Priority:** every resolver writes no priority; kernel default `0` everywhere (`join_clips` has an input `priority` that only lands in `params`). [resolver files, doc 04 §3.7]

**max_attempts:** `3` for all admissions (doc 14 §2). Reigh's `tasks.attempts` cap is also 3 — same value, different ledger (kernel `execution_attempts`, doc 13 §2.1.Q).

---

## 2. Family capability table (13 families + passthrough)

Columns: resolver file | source `task_type`(s) | capability | tasks/request | batch/orchestrator | output_policy core | deps | priority | worker pipeline (doc 03 §3.1–3.4).

| family (registry key) | resolver file | task_type(s) written | capability | tasks/request | shape | create_generation | deps | worker pipeline |
|---|---|---|---|---|---|---|---|---|
| `image_generation` | `resolvers/imageGeneration.ts` | `wan_2_2_t2i` (default), `qwen_image`, `qwen_image_style`, `qwen_image_2512`, `z_image_turbo` (model_name switch) | `reigh.wan_2_2_t2i`, `reigh.qwen_image`, `reigh.qwen_image_style`, `reigh.qwen_image_2512`, `reigh.z_image_turbo` | `prompts.length × imagesPerPrompt` (≤16) | **batch** (run fan-out) | true | null | WGP direct (t2i→t2v family); QwenHandler for qwen_*; z_image; VibeComfy routes exist for wan_2_2_t2i/z_image_turbo/qwen_image_2512 |
| `image_upscale` | `resolvers/imageUpscale.ts` | `image-upscale` (**hyphen**) | `reigh.image_upscale` | 1 | single | true (is_primary when based_on) | null | VibeComfy (`image_upscale` scratchpad); api run_type |
| `individual_travel_segment` | `resolvers/individualTravelSegment.ts` | `individual_travel_segment` | `reigh.individual_travel_segment` | 1 (or passthrough when `orchestrator_task_id_ref`) | single | true (variant_on_child/parent) | null (frontend) | WGP direct — `travel.segments.segment_queue` (VACE, SVI latent tails, Uni3C) |
| `join_clips` | `resolvers/joinClips.ts` | `join_clips_orchestrator` | `reigh.join_clips_orchestrator` | 1 | **orchestrator** (children `join_clips_segment` ×N-1 + `join_final_stitch` via passthrough) | false (children generate) | null | WGP — `join.orchestrator`; segments VibeComfy-allowed |
| `video_enhance` | `resolvers/videoEnhance.ts` | `video_enhance` | `reigh.video_enhance` | 1 | single | true (variant on `based_on`) | null | VibeComfy (`video_enhance` scratchpad); api (fal FILM/FlashVSR) |
| `z_image_turbo_i2i` | `resolvers/zImageTurboI2I.ts` | `z_image_turbo_i2i` | `reigh.z_image_turbo_i2i` | `numImages` (1–16) | **batch** (run fan-out) | from `create_as_generation` | null | VibeComfy (`z_image_turbo` scratchpad); api |
| `magic_edit` | `resolvers/magicEdit.ts` | `qwen_image_edit` | `reigh.qwen_image_edit` | `numImages` (1–16) | **batch** (run fan-out) | from `create_as_generation` | null | VibeComfy (`qwen_image_edit` scratchpad) + QwenHandler; api |
| `masked_edit` | `resolvers/maskedEdit.ts` | `image_inpaint` (default) / `annotated_image_edit` | `reigh.image_inpaint`, `reigh.annotated_image_edit` | `num_generations` (1–16) | **batch** (run fan-out; rows identical params) | true | null | QwenHandler image_inpaint/annotated_image_edit; api |
| `travel_between_images` | `resolvers/travelBetweenImages.ts` | `travel_orchestrator` (default) / `wan_2_2_i2v` (`turbo_mode`) | `reigh.travel_orchestrator`, `reigh.wan_2_2_i2v` | 1 | **orchestrator** (children `travel_segment` ×N-1 + `travel_stitch` + optional `join_clips_orchestrator`) or direct when turbo | false (orch) / true (turbo) | null | WGP — `travel.orchestrator` |
| `crossfade_join` | `resolvers/crossfadeJoin.ts` | `travel_stitch` | `reigh.travel_stitch` | 1 (or passthrough when `orchestrator_task_id_ref`) | single | true (stitched video) | null | WGP — `travel_stitch` handler (stitch + upscale) |
| `edit_video_orchestrator` | `resolvers/editVideoOrchestrator.ts` | `edit_video_orchestrator` | `reigh.edit_video_orchestrator` | 1 | **orchestrator** (reuses join chain: `join_clips_segment` + `join_final_stitch`) | false | null | WGP — `edit_video_orchestrator` handler |
| `character_animate` | `resolvers/characterAnimate.ts` | `animate_character` | `reigh.animate_character` | 1 | single | true | null | VibeComfy (`animate_character` scratchpad); api |
| `klein_edit` | `resolvers/kleinEdit.ts` | `flux_klein_edit` | `reigh.flux_klein_edit` | `numImages` (1–4) | **batch** (run fan-out) | from `create_as_generation` | null | VibeComfy (`flux_klein_edit` scratchpad); api |
| *(passthrough)* | `resolvers/workerPassthrough.ts` | allowlist entry name (e.g. `join_clips_segment`, `travel_segment`, `join_final_stitch`, `travel_stitch`) | `reigh.<normalized name>` | 1 | single (worker child) | category-driven (§6) | lifts `input.dependant_on` | per-entry specialized handler (doc 03 §3.1). **(Amended doc 26/Grok: dead `edit_video_segment` removed.)** |

---

## 3. Per-family resolver detail (implementation contract)

Input tables list **field | type | required** (R = required, O = optional) with defaults in parentheses. `output_policy` bullets state the exact kernel projection. All params land in `spec_json.params` **verbatim** (workers depend on exact keys, doc 03 §2.5 whitelist).

### 3.1 `image_generation` → `wan_2_2_t2i` | `qwen_image` | `qwen_image_style` | `qwen_image_2512` | `z_image_turbo` (`imageGeneration.ts`)

| input field | type | req | notes |
|---|---|---|---|
| `prompts` | `{id, fullPrompt, shortPrompt?}[]` | R | ≥1; per-prompt seed ordering `baseSeed + taskIndex` |
| `imagesPerPrompt` | number | R | 1–16; total = prompts×imagesPerPrompt ≤ 16 |
| `model_name` | string | O | switch: `qwen-image`→qwen_image(+style if style_reference_image), `qwen-image-2512`→qwen_image_2512, `z-image`→z_image_turbo, default→wan_2_2_t2i |
| `resolution`, `resolution_scale`, `resolution_mode` (`project`\|`custom`), `custom_aspect_ratio` | string/number | O | resolved via `resolveImageGenerationResolution` against project aspect_ratio |
| `seed` | number | O | 32-bit; random when absent |
| `steps` | number | O | default 12 |
| `negative_prompt` | string | O | |
| `shot_id`, `timeline_placement` | string/object | O | lineage fields |
| `loras` | `{path, strength}[]` | O | strength 0–2 → `additional_loras` record |
| `style_reference_image`, `subject_reference_image`, `style_reference_strength`, `subject_strength`, `subject_description`, `in_this_scene`, `in_this_scene_strength`, `reference_mode` (`style`\|`subject`\|`style-character`\|`scene`\|`custom`) | mixed | O | only for qwen*/z-image models; mode-filtered; scene adds IN_SCENE_LORA URL |
| `hires_scale`, `hires_steps`, `hires_denoise`, `additional_loras` (record) | mixed | O | hires override merged into params |
| `lightning_lora_strength_phase_1/2` | number | O | |

Params written per task: `task_id` (generated `wan_2_2_t2i_<ts>_<rand6>`), `model`, `prompt`, `resolution`, `seed`, `steps`, `add_in_position:false`, optional `negative_prompt`/`additional_loras`/references/hires/lightning, `shot_id` via lineage, `timeline_placement` via lineage. Output type: image (t2i forces `video_length=1`, doc 03 §3.4).

`output_policy`: `create_generation: true`; `shot_id` from params; `based_on_generation_id: null`; `timeline_placement` from params; no variant block. **Batch:** run fan-out, `run_ordinal = taskIndex` (0-based, deterministic by prompt order then per-prompt index).

### 3.2 `image_upscale` → `image-upscale` (hyphen; `imageUpscale.ts`)

| input field | type | req | notes |
|---|---|---|---|
| `image_url` | string (URL) | R | validated |
| `generation_id` | string | O | becomes `based_on` + `parent_generation_id`; `is_primary: true` when present (`markPrimaryWhenBasedOn`) |
| `source_variant_id` | string | O | variant linkage |
| `scale_factor` | number | O | 1–8, default 2 |
| `noise_scale` | number | O | default 0.1 |
| `output_format` | string | O | default `jpeg` |
| `shot_id`, `placement_intent` | string/object | O | lineage |

Params: `image`, `scale_factor`, `noise_scale`, `output_format`, optional `generation_id`, lineage (`shot_id`, `based_on`, `parent_generation_id`, `source_variant_id`, `is_primary`, `placement_intent`).

`output_policy`: `create_generation: true`; `based_on_generation_id = generation_id`; `shot_id`; `timeline_placement` from `placement_intent`; `variant: {source_variant_id, create_as_generation: false, is_primary: true}`. **Capability normalization example:** `image-upscale` → `reigh.image_upscale` (hyphen→underscore), source string preserved in `spec_json.source_task_type`.

### 3.3 `individual_travel_segment` (`individualTravelSegment.ts`) — largest payload

| input field | type | req | notes |
|---|---|---|---|
| `parent_generation_id` or `shot_id` | string | R (one of) | if only shot_id: adapter must call `ensure_shot_parent_generation` equivalent (content-pack parent-generation row) |
| `segment_index` | number | R | ≥0; `is_first_segment = index===0` |
| `start_image_url` | string | R | |
| `end_image_url` | string | O | presence → 2 input images |
| `child_generation_id` | string | O | validated: must belong to parent + pair slot; else pair lookup, else child_order lookup |
| `pair_shot_generation_id`, `start_image_generation_id`, `end_image_generation_id`, `start_image_variant_id`, `end_image_variant_id` | string | O | pair/lineage resolution |
| `model_name` | string | O | default `wan_2_2_i2v_lightning_baseline_2_2_2` |
| `model_type` | `"i2v"`\|`"vace"` | O | |
| `base_prompt`, `enhanced_prompt`, `negative_prompt` | string | O | `base_prompt` default `""` |
| `num_frames` | number | O | default 49, `min(.,81)` |
| `frame_overlap_from_previous` | number | O | |
| `continuation_config` | object | O | sets `chain_segments: true` |
| `seed`, `random_seed` | number/bool | O | fallback seed 789 |
| `amount_of_motion` | number | O | default 0.5 |
| `advanced_mode`, `motion_mode` (`basic`\|`presets`\|`advanced`), `phase_config`, `selected_phase_preset_id` | mixed | O | phase_config drives guidance/steps/lora_multipliers |
| `loras` | `{path,strength}[]` | O | → `additional_loras` |
| `travel_guidance`, `structure_guidance`, `structure_videos` | object/array | O | |
| `generation_name`, `make_primary_variant` (default true), `is_last_segment` | mixed | O | |
| `parsed_resolution_wh`, `num_inference_steps` (default 6), `guidance_scale` (default 1), `guidance2_scale`, `guidance_phases` (2) | mixed | O | |
| `originalParams` | object | O | retry envelope; `orchestrator_details` seed + `stitched_start_frame`/`guidance_start_frame` fallback |
| `orchestrator_task_id_ref` | string | O | **passthrough branch**: entire input → params, no validation |

Side effects to port: (1) ensure/get parent generation; (2) child-generation resolution (validate given id → pair lookup ordered `created_at DESC` → `child_order=segment_index` fallback); (3) sibling-layout query (`segment_frames_expanded`/`frame_overlap_expanded`/`stitched_start_frame`/`guidance_start_frame` from sibling `individual_travel_segment` tasks with same `parent_generation_id`, status Complete/In Progress, newest first) — in the kernel this reads `tasks.spec_json` (family=individual_travel_segment, params.segment_index/num_frames/frame_overlap_from_previous) + content-pack generation rows.

Params: flat ~40-key payload (top-level `flow_shift`, `lora_names:[]`, `model_name`, `project_id`, `shot_id`, `base_prompt`, `fps_helpers:16`, `seed_to_use`, `cfg_zero_step:-1`, `sample_solver`, `segment_index`, `guidance_scale`, `cfg_star_switch:0`, `guidance2_scale`, `guidance_phases`, `is_last_segment`, `negative_prompt`, `is_first_segment`, `additional_loras`, `lora_multipliers`, `model_switch_phase`, `num_inference_steps`, `parsed_resolution_wh`, `num_frames`, optional `frame_overlap_from_previous`/`stitched_start_frame`/`guidance_start_frame`, `amount_of_motion`, `orchestrator_details`, `parent_generation_id`, optional `child_generation_id`, `input_image_paths_resolved`, `after_first_post_generation_saturation:1`, `after_first_post_generation_brightness:0`, `motion_mode`, optional `enhanced_prompt`/`continuation_config`/`travel_guidance`/generation ids/pair id/`generation_name`, `make_primary_variant:true`, `individual_segment_params` mirror) + four contract blocks (`contract_version:1`, `task_family`, `orchestrator_details`, `orchestration_contract` v3, `task_view_contract` v1, `family_contract` v1).

`output_policy`: `create_generation: true`; `based_on_generation_id = parent_generation_id`; `shot_id`; `variant: {make_primary_variant: true}`; child routing (`variant_on_child` when `child_generation_id` present, else `variant_on_parent` for stitch tasks, else child_generation, else standalone — port of `complete_task/generation.ts` routing).

### 3.4 `join_clips` → `join_clips_orchestrator` (`joinClips.ts`)

| input field | type | req | notes |
|---|---|---|---|
| `clip_source` | `{kind:"clips", clips:[{url, name?}]}` | R | ≥2 clips |
| `mode` | `"multi_clip"`\|`"video_edit"` | R | `video_edit` requires `video_edit` |
| `video_edit` | `{source_video_url, source_video_fps?, source_video_duration?, source_video_total_frames?, portions_to_regenerate?[]}` | O | |
| `shot_id`, `parent_generation_id`, `based_on` | string | O | |
| `run_id` | string | O | else generated |
| `prompt` (""), `context_frame_count` (15), `gap_frame_count` (23), `replace_mode` (true), `keep_bridging_images`, `enhance_prompt` (false), `model` (`wan_2_2_vace_lightning_baseline_2_2_2`), `num_inference_steps` (6), `guidance_scale` (3.0), `seed` (-1), `negative_prompt` (""), `priority` (0) | mixed | O | defaults table `TASK_DEFAULTS` |
| `resolution` `[w,h]`, `fps` | array/number | O | |
| `loras` `{path,strength}[]`, `phase_config` (3-phase VACE default with HF LoRA URLs), `motion_mode` (`basic`\|`advanced`), `selected_phase_preset_id` (`__builtin_vace_default__`) | mixed | O | user loras merged into each phase |
| `per_join_settings` `{prompt?, gap_frame_count?, context_frame_count?, replace_mode?, model?, num_inference_steps?, guidance_scale?, seed?, negative_prompt?, priority?, resolution?, fps?, loras?}[]` | array | O | length ≤ joins count |
| `tool_type`, `audio_url`, `use_input_video_resolution`, `use_input_video_fps`, `vid2vid_init_strength`, `loop_first_clip` | mixed | O | |

Params: `orchestrator_details` (orchestrator_task_id generated `join_clips_orchestrator_<ts>_<rand6>`, `clip_list`, `run_id`, `shot_id`, defaults, `phase_config`, `advanced_mode:true`, `per_join_settings?`, video_edit fields, `based_on`?) + 4 contract blocks (`family_contract.mode` = `multi_clip_join`\|`video_edit_join`).

`output_policy`: `create_generation: false` (orchestration); `shot_id` preserved (children inherit); `based_on_generation_id` from `based_on`. Children (`join_clips_segment` ×N-1, `join_final_stitch` ×1) created by the worker through the passthrough path; the adapter admits only the orchestrator row.

### 3.5 `video_enhance` (`videoEnhance.ts`)

| input field | type | req | notes |
|---|---|---|---|
| `video_url` | string (URL) | R | |
| `enable_interpolation`, `enable_upscale` | boolean | R | ≥1 must be true |
| `interpolation` | `{num_frames (1–4), use_calculated_fps, fps, use_scene_detection, loop, video_quality (low\|medium\|high\|maximum), video_write_mode (fast\|balanced\|small)}` | O | defaults num_frames 1, use_calculated_fps true, quality high |
| `upscale` | `{upscale_factor (1–4), acceleration, quality, color_fix, output_format (X264/VP9/PRORES4444/GIF), output_quality, output_write_mode, preserve_audio}` | O | defaults factor 2, color_fix true, quality high |
| `shot_id`, `based_on`, `source_variant_id` | string | O | `based_on` → `parent_generation_id` + `is_primary:true` |

Params: `tool_type:"video-enhance"`, `video_url`, `enable_interpolation`, `enable_upscale`, `interpolation{...}`, `upscale{...}`, `shot_id?`, `based_on?`+`parent_generation_id`+`is_primary`, `source_variant_id?`.

`output_policy`: `create_generation: true`; `based_on_generation_id = based_on`; `shot_id`; `variant: {source_variant_id, is_primary: true}`.

### 3.6 `z_image_turbo_i2i` (`zImageTurboI2I.ts`)

| input field | type | req | notes |
|---|---|---|---|
| `image_url` | string (URL) | R | |
| `prompt` | string | O | default `""` |
| `strength` | number | O | 0–1, default 0.6 |
| `enable_prompt_expansion` | boolean | O | default false |
| `seed` | number | O | baseSeed + index per task |
| `numImages` | number | O | 1–16 |
| `loras` | `{path, scale?}` | O | scale default 1.0; `acceleration` = `none` with loras else `high` |
| `shot_id`, `based_on`, `source_variant_id`, `create_as_generation`, `tool_type`, `timeline_placement`, `placement_intent` | mixed | O | lineage |

Params: `image_url`, `prompt`, `strength`, `enable_prompt_expansion`, `num_images:1`, `image_size:"auto"`, `num_inference_steps:8`, `output_format:"png"`, `enable_safety_checker:true`, `add_in_position:false`, `seed?`, `loras?`, `acceleration`, + lineage.

`output_policy`: `create_generation` from `create_as_generation` (default false → variant); `based_on_generation_id = based_on`; `shot_id`; `timeline_placement`; `variant: {source_variant_id, create_as_generation}`. **Batch:** numImages tasks, run fan-out.

### 3.7 `magic_edit` → `qwen_image_edit` (`magicEdit.ts`)

| input field | type | req | notes |
|---|---|---|---|
| `prompt`, `image_url` | string | R | URL validated |
| `negative_prompt`, `in_scene`, `resolution` | mixed | O | resolution from project aspect_ratio fallback |
| `seed` | number | O | baseSeed + index |
| `numImages` | number | O | 1–16 |
| `output_format` | string | O | default `jpeg` |
| `enable_sync_mode` (false), `max_wait_seconds` (300, ≥1), `enable_base64_output` (false) | mixed | O | |
| `qwen_edit_model` | `"qwen-edit"`\|`"qwen-edit-2509"`\|`"qwen-edit-2511"` | O | default `qwen-edit` |
| `loras` `{url,strength}[]`, `hires_fix` (via `buildHiresFixParams`) | mixed | O | |
| `shot_id`, `tool_type`, `based_on`, `source_variant_id`, `create_as_generation`, `timeline_placement`, `placement_intent` | mixed | O | lineage |

Params: `seed`, `image`, `prompt`, `output_format`, `qwen_edit_model`, `enable_sync_mode`, `max_wait_seconds`, `enable_base64_output`, optional `negative_prompt`/`in_scene`/`resolution`/`loras`/hires_*, `add_in_position:false`, + lineage.

`output_policy`: `create_generation` from `create_as_generation`; `based_on_generation_id = based_on`; `shot_id`; `timeline_placement`; `variant: {source_variant_id, create_as_generation}`. **Batch:** numImages tasks, run fan-out.

### 3.8 `masked_edit` (`maskedEdit.ts`)

| input field | type | req | notes |
|---|---|---|---|
| `image_url`, `mask_url`, `prompt` | string | R | URLs validated non-empty |
| `num_generations` | number | R | 1–16; **all rows get identical params** (no seed variation — ported behavior) |
| `task_type` | `"image_inpaint"`\|`"annotated_image_edit"` | O | default `image_inpaint` |
| `generation_id` | string | O | → `based_on` + `parent_generation_id` |
| `shot_id`, `tool_type`, `loras` `{url,strength}[]`, `create_as_generation`, `source_variant_id`, `qwen_edit_model`, `hires_fix` | mixed | O | |

Params: `image_url`, `mask_url`, `prompt`, `num_generations:1`, `generation_id`, `based_on`, `parent_generation_id`, optional lineage + hires.

`output_policy`: `create_generation: true`; `based_on_generation_id = generation_id`; `shot_id`; `variant: {source_variant_id, create_as_generation}`. **Batch:** num_generations tasks, run fan-out (identical specs — the run is the fan-out primitive).

### 3.9 `travel_between_images` (`travelBetweenImages.ts`)

| input field | type | req | notes |
|---|---|---|---|
| `image_urls` | string[] | R | N images → N-1 segments |
| `base_prompts`, `segment_frames`, `frame_overlap` | arrays | R | expanded to segment count (singletons broadcast) |
| `negative_prompts`, `enhanced_prompts` | string[] | O | |
| `base_prompt`, `enhance_prompt` (false), `text_before_prompts`, `text_after_prompts` | mixed | O | |
| `model_name` (default `wan_2_2_i2v_lightning_baseline_2_2_2`), `model_type` (`i2v`\|`vace`) | mixed | O | |
| `seed` (fallback 789), `random_seed`, `steps` (20), `num_inference_steps`, `guidance_scale` | mixed | O | |
| `turbo_mode` | boolean | O | true → task_type `wan_2_2_i2v` (direct), false → `travel_orchestrator` |
| `amount_of_motion` (0.5), `motion_mode`, `advanced_mode`, `phase_config`, `selected_phase_preset_id` | mixed | O | |
| `pair_phase_configs`, `pair_loras`, `pair_motion_settings` | `(obj\|null)[]` | O | per-segment overrides → `phase_configs_expanded`/`loras_per_segment_expanded`/`motion_settings_expanded` |
| `loras` `{path,strength}[]` | array | O | → `additional_loras` |
| `continuation_config`, `travel_guidance`, `structure_guidance`, `structure_videos`, `stitch_config` | object/array | O | |
| `shot_id`, `parent_generation_id`, `image_generation_ids[]`, `pair_shot_generation_ids[]` | mixed | O | parent ensured via shot if absent |
| `resolution`, `dimension_source` (`project`\|`firstImage`\|`custom`), `generation_mode` (`batch`\|`timeline`\|`by-pair`), `main_output_dir_for_run`, `show_input_images` (true), `generation_name`, `independent_segments` (true), `after_first_post_generation_saturation` (1), `after_first_post_generation_brightness` (0), `debug` (false) | mixed | O | |

Params: `tool_type:"travel-between-images"`, `orchestrator_details` (generation_source `batch`, orchestrator_task_id `sm_travel_orchestrator_<ts>_<rand6>`, run_id, expanded arrays, `num_new_segments_to_generate`, resolution, model, seed_base, defaults…), optional `parent_generation_id`/`generation_name`, + 4 contract blocks (`family_contract.read_contract`).

`output_policy`: orchestrator → `create_generation: false` (children `travel_segment` create); turbo `wan_2_2_i2v` → `create_generation: true`; `based_on_generation_id = parent_generation_id`; `shot_id`.

### 3.10 `crossfade_join` → `travel_stitch` (`crossfadeJoin.ts`)

| input field | type | req | notes |
|---|---|---|---|
| `clip_urls` | string[] | R (frontend branch) | ≥2 |
| `frame_overlap_settings_expanded` | number[] | R (frontend branch) | length = clip_urls−1, all >0 |
| `shot_id`, `parent_generation_id` | string | O | |
| `audio_url`, `tool_type` | string | O | |
| `orchestrator_task_id_ref` | string | O | **passthrough branch** (worker-created stitch): raw input → params |

Params (frontend): `shot_id`, `parent_generation_id`, `clip_urls`, `frame_overlap_settings_expanded`, `full_orchestrator_payload` (run_id generated, mirrors top-level), `orchestration_contract` (taskFamily `join_clips`, runId, parentGenerationId, shotId), optional `audio_url`/`tool_type`.

`output_policy`: `create_generation: true` (stitched final video); `based_on_generation_id = parent_generation_id`; `shot_id`.

### 3.11 `edit_video_orchestrator` (`editVideoOrchestrator.ts`)

| input field | type | req | notes |
|---|---|---|---|
| `orchestrator_details` | object | R | passthrough verbatim |
| `tool_type`, `parent_generation_id`, `based_on` | string | O | |

Params: `orchestrator_details` (verbatim) + optionals. `output_policy`: `create_generation: false` (orchestration; worker reuses the join chain — children `join_clips_segment` + `join_final_stitch` — per `reigh-worker/source/task_handlers/edit_video_orchestrator.py` and doc 03 §3.1).

### 3.12 `character_animate` → `animate_character` (`characterAnimate.ts`)

| input field | type | req | notes |
|---|---|---|---|
| `character_image_url`, `motion_video_url` | string | R | |
| `mode` | `"replace"`\|`"animate"` | R | |
| `resolution` | `"480p"`\|`"720p"` | R | |
| `prompt` | string | O | default `"natural expression; preserve outfit details"` |
| `seed` | number | O | default 111111 |
| `random_seed` | boolean | O | default true → random 32-bit |

Params: `orchestrator_task_id` (generated `character_animate_<ts>_<rand6>`), `run_id` (generated), `character_image_url`, `motion_video_url`, `prompt`, `mode`, `resolution`, `seed`. `output_policy`: `create_generation: true`; no shot/based_on (standalone).

### 3.13 `klein_edit` → `flux_klein_edit` (`kleinEdit.ts`)

| input field | type | req | notes |
|---|---|---|---|
| `prompt`, `image_url` | string | R | URL validated |
| `klein_model` | `"flux-klein-4b"`\|`"flux-klein-9b"` | R | |
| `negative_prompt`, `seed`, `strength` (0.6), `num_inference_steps` (8), `output_format` (`png`) | mixed | O | |
| `numImages` | number | O | 1–4 |
| `shot_id`, `tool_type`, `based_on`, `source_variant_id`, `create_as_generation`, `timeline_placement`, `placement_intent` | mixed | O | lineage |

Params: `seed` (baseSeed+index), `image`, `prompt`, `klein_model`, `strength`, `num_inference_steps`, `output_format`, optional `negative_prompt`, + lineage.

`output_policy`: `create_generation` from `create_as_generation`; `based_on_generation_id = based_on`; `shot_id`; `timeline_placement`; `variant: {source_variant_id, create_as_generation}`. **Batch:** numImages tasks, run fan-out.

### 3.14 Worker passthrough (`workerPassthrough.ts`) — allowlist-backed

> **(Amended: Grok review — judged ADOPT.)** The table below records the old payload. In the surviving contract the worker uses the kernel ULID returned by R1 as the task ID and puts kernel ULIDs directly in `dependant_on`; there is no pre-generated UUID, logical-ID cache, alias, or rewrite map.

| input field | type | req | notes |
|---|---|---|---|
| `task_id` | string | O | worker pre-generated id; must be honored as the **logical** task id so sibling `dependant_on` references resolve; adapter maps to the kernel ULID after admission |
| `dependant_on` | string[] | O | lifted → hard `task_dependencies` edges |
| everything else | arbitrary | – | dumped into `params` unmodified |

`output_policy`: category-driven from the allowlist entry (§6): `generation` → `create_generation: true`; `processing`/`orchestration` → `false`. `spec_json.source_task_type = family` as-is.

---

## 4. Lineage / completion routing (shared, ported from `shared/lineage.ts` + `complete_task`)

`setTaskLineageFields` writes: `shot_id`, `based_on` **and** `parent_generation_id` (same value), `source_variant_id`, `create_as_generation`, `tool_type`, `is_primary` (`markPrimaryWhenBasedOn`), `timeline_placement` (`{timeline_id, source_clip_id, target_track, insertion_time, intent:"after_source"|"replace"}`), `placement_intent` (`{timeline_id, anchor_clip_id, anchor_generation_id?, anchor_variant_id?, relation:"after", preferred_track_id, fallback_at, fallback_track_id}`). [lineage.ts:raw]

The kernel completion service (doc 14 §3) must port `complete_task`'s generation routing: `variant_on_child` (child_generation_id) → `variant_on_parent` (parent_generation_id, stitch tasks) → `child_generation` (parent exists) → `standalone`; skip when `spec_json.params.skip_generation === true` or capability is orchestration-category; shot placement via `add_generation_to_shot` equivalent (content pack `shot_generation_items`), timeline placement via `upsert_asset_registry_entry`/`update_timeline_config_versioned` equivalents (bridge timeline pack). [10 §3.4, 14 §3]

---

## 5. Capability ↔ live `task_types` DB gap table

Live probe 2026-08-21 (`SELECT name, run_type, category, is_active, tool_type FROM task_types ORDER BY name` via psql, read-only): **37 rows — 29 active, 8 inactive**. Doc 01's "28 rows" (reltuples) and the repo's 26 seed names are both stale. Resolver coverage: all 19 resolver-writable task_types exist as **active** rows.

| `task_types.name` (live) | run_type | category | active | resolver family | capability | disposition |
|---|---|---|---|---|---|---|
| `animate_character` | api | generation | t | `character_animate` | `reigh.animate_character` | ported |
| `annotated_image_edit` | api | generation | t | `masked_edit` (task_type override) | `reigh.annotated_image_edit` | ported |
| `api_query` | api | generation | f | — | — | inactive → reject |
| `different_perspective_orchestrator` | api | generation | f | — | — | inactive → reject |
| `edit_travel_flux` | gpu | generation | t | — | — | reject; dead type, no alias **(Amended doc 26/Grok)** |
| `edit_video_orchestrator` | gpu | orchestration | t | `edit_video_orchestrator` | `reigh.edit_video_orchestrator` | ported |
| `edit_video_segment` | gpu | processing | t | — (no current writer) | — | reject; absent from child allowlist **(Amended doc 26/Grok)** |
| `extract_frame` | api | generation | f | — | — | inactive → reject |
| `flux_klein_edit` | api | generation | t | `klein_edit` | `reigh.flux_klein_edit` | ported |
| `generate_openpose` | api | generation | f | — | — | inactive → reject |
| `i2v_22` | api | generation | f | — | — | inactive → reject |
| `image_edit` | gpu | generation | t | — (legacy; superseded by `qwen_image_edit`) | — | reject; dead type, no alias **(Amended doc 26/Grok)** |
| `image_inpaint` | api | generation | t | `masked_edit` | `reigh.image_inpaint` | ported |
| `image_upscale` | gpu | generation | t | — (legacy underscore row; resolver writes `image-upscale`) | — | reject; dead type, no alias **(Amended doc 26/Grok)** |
| `image-upscale` | api | upscale | t | `image_upscale` (hyphen) | `reigh.image_upscale` | ported — hyphen row is the FK target |
| `individual_travel_segment` | gpu | generation | t | `individual_travel_segment` | `reigh.individual_travel_segment` | ported |
| `join_clips_orchestrator` | gpu | orchestration | t | `join_clips` | `reigh.join_clips_orchestrator` | ported |
| `join_clips_segment` | gpu | processing | t | passthrough (worker child) | `reigh.join_clips_segment` | allowlist (worker-created) |
| `join_final_stitch` | gpu | generation | t | passthrough (worker child) | `reigh.join_final_stitch` | allowlist (worker-created) |
| `magic_edit` | gpu | generation | t | — (legacy row; current resolver writes `qwen_image_edit`) | — | reject; dead type, no alias **(Amended doc 26/Grok)** |
| `qwen_image` | api | generation | t | `image_generation` (model_name=`qwen-image`) | `reigh.qwen_image` | ported |
| `qwen_image_2512` | api | generation | t | `image_generation` (model_name=`qwen-image-2512`) | `reigh.qwen_image_2512` | ported |
| `qwen_image_edit` | api | generation | t | `magic_edit` | `reigh.qwen_image_edit` | ported |
| `qwen_image_style` | api | generation | t | `image_generation` (model_name=`qwen-image` + style ref) | `reigh.qwen_image_style` | ported |
| `rife_interpolate_images` | api | generation | f | — | — | inactive → reject |
| `single_image` | gpu | generation | t | — (legacy direct-queue) | — | reject; dead type, no alias **(Amended doc 26/Grok)** |
| `test` | api | generation | f | — | — | inactive → reject (dev artifact) |
| `travel_orchestrator` | gpu | orchestration | t | `travel_between_images` | `reigh.travel_orchestrator` | ported |
| `travel_segment` | gpu | processing | t | passthrough (worker child) | `reigh.travel_segment` | allowlist (worker-created) |
| `travel_stitch` | gpu | generation | t | `crossfade_join` (+ passthrough worker stitch) | `reigh.travel_stitch` | ported |
| `video_enhance` | api | processing | t | `video_enhance` | `reigh.video_enhance` | ported |
| `wan_2_2_i2v` | api | generation | t | `travel_between_images` (turbo_mode) | `reigh.wan_2_2_i2v` | ported |
| `wan_2_2_t2i` | api | generation | t | `image_generation` (default) | `reigh.wan_2_2_t2i` | ported |
| `wan_lora_training` | gpu | training | t | — | — | **cut** (training product deferred, doc 15 Q5) |
| `wgp` | api | generation | f | — | — | inactive → reject |
| `z_image_turbo` | api | generation | t | `image_generation` (model_name=`z-image`) | `reigh.z_image_turbo` | ported |
| `z_image_turbo_i2i` | api | generation | t | `z_image_turbo_i2i` | `reigh.z_image_turbo_i2i` | ported |

**Repo↔live drift:** repo-seeded but **not live**: `edit_travel_kontext`, `lora_training` (replaced live by `wan_lora_training`). Live but no repo seed found (out-of-band): `image-upscale`, `magic_edit`, `qwen_image_edit`, `wan_2_2_t2i`, `wan_lora_training`, `api_query`, `different_perspective_orchestrator`, `extract_frame`, `generate_openpose`, `i2v_22`, `rife_interpolate_images`, `test`, `wgp`. [grep of 466 migrations vs probe]

**Ratified disposition (Amended doc 26/Grok):** active resolver-less types `edit_travel_flux`, `image_edit`, `image_upscale` (underscore), `magic_edit`, `single_image`, and unwritten `edit_video_segment` are rejected outright—no aliases and no child-allowlist entries. `wan_lora_training` remains rejected per doc 15 Q5.

---

## 6. Unknown-family passthrough → code-declared allowlist (proposal)

> **(Amended: Grok review — judged ADOPT.)** This is an executor-child allowlist, not a public fallback. R1 accepts these families only with a live leased-running parent, matching executor/attempt/lease/fence, and deterministic `reigh.orch:v1:<parent>:<role>:<index>` key; browser/frontend requests are forbidden before any row is written.

Doc 14 §2: "Unknown-family passthrough becomes a code-declared capability allowlist; the current `task_types` database is not migrated." Today the index falls back to `SELECT name FROM task_types WHERE name = family AND is_active = true` then `createWorkerPassthroughResolver(family)` (create-task/index.ts). Proposal — a frozen constant in the adapter, per entry: `{ task_type, capability, category, run_type }`:

| allowlist entry (task_type = family) | capability | category (output_policy driver) | origin / writer |
|---|---|---|---|
| `join_clips_segment` | `reigh.join_clips_segment` | processing (`create_generation: false`) | `reigh-worker/source/task_handlers/join/task_builder.py` (add_task_to_db, task_type_str="join_clips_segment") |
| `join_final_stitch` | `reigh.join_final_stitch` | generation (`true`) | same file (`"join_final_stitch"`) |
| `travel_segment` | `reigh.travel_segment` | processing | `reigh-worker/source/task_handlers/travel/orchestrator.py` |
| `travel_stitch` | `reigh.travel_stitch` | generation | same file (also covered by `crossfade_join` when frontend-created) |
| `join_clips_orchestrator` | `reigh.join_clips_orchestrator` | orchestration | same file (travel orchestrator spawns it) |

All five worker-created child types observed live in `add_task_to_db` calls: `join_clips_segment`, `join_final_stitch`, `travel_segment`, `travel_stitch`, `join_clips_orchestrator` (grep of reigh-worker/source). `edit_video_segment` is rejected because it has no current writer. Behavior on admission: honor `input.task_id` as logical id (map to the kernel task ULID for dependency edges), lift `input.dependant_on` → hard edges, dump input into `params`, category drives `output_policy.create_generation`. Reject an unknown UI family with `422 unsupported_family`; reject an unknown/inactive/dead derived child capability with `422 unsupported_capability` (doc 18 §2.3/R1). Inactive live rows (`is_active=false`) are **not** allowlisted. **(Amended doc 26/Grok)**

---

## 7. Golden-test fixture list (one per payload shape, expected kernel rows)

> **(Amended: Grok review — judged ADOPT.)** The A–N table is historical coverage inventory. Phase A runs only one production-shaped `wan_2_2_t2i` slice plus missing-model, replay/lost-ack, fence, crash/expiry, poisoned-output, and cancellation evidence; join/travel fixtures C/D/E/I/M move to Phase B. `[INFERENCE]` Drop `orchestration_contract`, `task_view_contract`, and `family_contract` from active fixtures because repository search found no handler reads; retain handler-read `orchestrator_details`.

Shapes A–I correspond to doc 10 §3.3 examples A–I; J–N cover the remaining families. Each fixture = request → expected kernel rows. `project_id` is a kernel project ULID; ids are ULIDs; `spec_json.params` shown summarized (must match §3 exactly). All tasks: `priority=0`, `max_attempts=3`, `available_at=now`, status `queued` (deps) / `blocked` (with deps).

| # | shape | family | request input (essential) | expected kernel rows |
|---|---|---|---|---|
| A | `image_generation` batch | `image_generation` | `prompts:[{id:"p1",fullPrompt:"a woman walking…"}], imagesPerPrompt:2, model_name:"wan_2_2_t2i", resolution:"832x480", steps:12, seed:123456789, shot_id:"<uuid>", style_reference_image:"https://…"` + `materialized_inputs:[{generation_id:"g1",kind:"file",target:"style_reference_image"}]` | **run** (kind=`image_generation`, status running, input_json=request input); **2 tasks** `reigh.wan_2_2_t2i` run_ordinal 0,1; `spec_json={schema_version:1, family:"image_generation", source_task_type:"wan_2_2_t2i", params:{task_id,model:"optimised-t2i",prompt,resolution,seed:123456789 & 123456790,steps,add_in_position:false,shot_id,style_reference_image}, output_policy:{create_generation:true,shot_id,based_on_generation_id:null,timeline_placement:null}}`; `input_manifest_json=[{role:"style_reference_image",media_id:"<ulid>",kind:"file"}]`; 0 deps |
| B | `character_animate` | `character_animate` | `character_image_url:"https://…/char.png", motion_video_url:"https://…/motion.mp4", mode:"animate", resolution:"480p"` | **1 task** `reigh.animate_character`; params `{orchestrator_task_id:"character_animate_…", run_id, character_image_url, motion_video_url, prompt:"natural expression; preserve outfit details", mode:"animate", resolution:"480p", seed:<32-bit>}`; output_policy `{create_generation:true, shot_id:null, based_on_generation_id:null, timeline_placement:null}`; 0 deps; no run |
| C | `individual_travel_segment` | `individual_travel_segment` | `parent_generation_id:"g0", segment_index:1, start_image_url:"https://…/a.png", end_image_url:"https://…/b.png", num_frames:49, shot_id:"<uuid>"` | **1 task** `reigh.individual_travel_segment`; flat ~40-key params + 4 contract blocks; `output_policy:{create_generation:true, based_on_generation_id:"g0", shot_id, variant:{make_primary_variant:true}}`; 0 deps; sibling-layout query reads prior segment tasks |
| D | `join_clips` orchestrator | `join_clips` | `clip_source:{kind:"clips",clips:[{url:u1},{url:u2}]}, mode:"multi_clip"` | **1 task** `reigh.join_clips_orchestrator`; params `{orchestrator_details:{orchestrator_task_id,clip_list,run_id,…}, orchestration_contract:{contract_version:3,task_family:"join_clips",…}, task_view_contract, family_contract:{mode:"multi_clip_join"}}`; output_policy `{create_generation:false, shot_id:null,…}`; 0 deps; no run (children admitted later by worker via passthrough) |
| E | `travel_between_images` orchestrator | `travel_between_images` | `image_urls:[u1,u2,u3], base_prompts:["p1","p2"], segment_frames:[49,49], frame_overlap:[8], shot_id:"<uuid>"` | **1 task** `reigh.travel_orchestrator`; `tool_type:"travel-between-images"`, `orchestrator_details` with `num_new_segments_to_generate:2` + expanded arrays + 4 contract blocks; output_policy `{create_generation:false, shot_id, based_on_generation_id:<ensured parent>}`; turbo variant: `turbo_mode:true` → 1 task `reigh.wan_2_2_i2v`, `create_generation:true` |
| F | `magic_edit` batch | `magic_edit` | `prompt:"make it rainy", image_url:"https://…/a.png", numImages:2, shot_id:"<uuid>"` | **run** (kind=`magic_edit`); **2 tasks** `reigh.qwen_image_edit` run_ordinal 0,1; params `{seed:base & base+1, image, prompt, output_format:"jpeg", qwen_edit_model:"qwen-edit", enable_sync_mode:false, max_wait_seconds:300, enable_base64_output:false, add_in_position:false, shot_id}`; output_policy `{create_generation:false, based_on_generation_id:null, shot_id, variant:{create_as_generation:false}}` |
| G | `video_enhance` | `video_enhance` | `video_url:"https://…/v.mp4", enable_interpolation:true, enable_upscale:true, based_on:"g5", shot_id:"<uuid>"` | **1 task** `reigh.video_enhance`; params `{tool_type:"video-enhance", video_url, enable_interpolation, enable_upscale, interpolation:{num_frames:1,use_calculated_fps:true,video_quality:"high"}, upscale:{upscale_factor:2,color_fix:true,output_quality:"high"}, based_on:"g5", parent_generation_id:"g5", is_primary:true, shot_id}`; output_policy `{create_generation:true, based_on_generation_id:"g5", shot_id, variant:{is_primary:true}}` |
| H | `klein_edit` batch | `klein_edit` | `prompt:"red dress", image_url:"https://…/a.png", klein_model:"flux-klein-4b", numImages:2, shot_id:"<uuid>"` | **run** (kind=`klein_edit`); **2 tasks** `reigh.flux_klein_edit`; params `{seed:base,base+1, image, prompt, klein_model, strength:0.6, num_inference_steps:8, output_format:"png", shot_id}`; output_policy `{create_generation:false, shot_id, variant:{create_as_generation:false}}` |
| I | worker passthrough | `join_clips_segment` (allowlist) | `task_id:"<worker-uuid>", dependant_on:["<worker-uuid-sibling>"], prompt:"transition", gap_frame_count:23, …` | **1 task** `reigh.join_clips_segment`; `spec_json={schema_version:1, family:"join_clips_segment", source_task_type:"join_clips_segment", params:<input verbatim>, output_policy:{create_generation:false,…}}`; **1 hard edge** `task_dependencies(task→sibling kernel ULID)`; status `blocked` (deps) |
| J | `image_upscale` (hyphen) | `image_upscale` | `image_url:"https://…/a.png", generation_id:"g9", shot_id:"<uuid>", scale_factor:4` | **1 task** `reigh.image_upscale`; `spec_json.source_task_type:"image-upscale"` (**hyphen preserved**); params `{image, scale_factor:4, noise_scale:0.1, output_format:"jpeg", generation_id:"g9", based_on:"g9", parent_generation_id:"g9", is_primary:true, shot_id}`; output_policy `{create_generation:true, based_on_generation_id:"g9", shot_id, variant:{is_primary:true}}` |
| K | `z_image_turbo_i2i` batch | `z_image_turbo_i2i` | `image_url:"https://…/a.png", numImages:2, seed:42, shot_id:"<uuid>"` | **run** (kind=`z_image_turbo_i2i`); **2 tasks** `reigh.z_image_turbo_i2i`; params `{image_url, prompt:"", strength:0.6, enable_prompt_expansion:false, num_images:1, image_size:"auto", num_inference_steps:8, output_format:"png", enable_safety_checker:true, add_in_position:false, seed:42,43, acceleration:"high", shot_id}` |
| L | `masked_edit` batch | `masked_edit` | `image_url:"…/a.png", mask_url:"…/m.png", prompt:"repaint", num_generations:2` | **run** (kind=`masked_edit`); **2 tasks** `reigh.image_inpaint` with **identical** params `{image_url, mask_url, prompt, num_generations:1, generation_id:null, based_on:null, parent_generation_id:null}`; `create_generation:true`; `task_type:"annotated_image_edit"` variant → `reigh.annotated_image_edit` |
| M | `crossfade_join` (frontend stitch) | `crossfade_join` | `clip_urls:[u1,u2], frame_overlap_settings_expanded:[6], shot_id:"<uuid>", parent_generation_id:"g0"` | **1 task** `reigh.travel_stitch`; params `{shot_id, parent_generation_id, clip_urls, frame_overlap_settings_expanded, full_orchestrator_payload:{run_id,…}, orchestration_contract:{contract_version:3,task_family:"join_clips",run_id,parent_generation_id,shot_id}}`; `create_generation:true, based_on_generation_id:"g0"` |
| N | `edit_video_orchestrator` | `edit_video_orchestrator` | `orchestrator_details:{source_video_url:"…", portions_to_regenerate:[…]}` | **1 task** `reigh.edit_video_orchestrator`; params `{orchestrator_details:<verbatim>}`; output_policy `{create_generation:false,…}`; 0 deps |

Fixture harness expectations: each fixture runs the ported resolver against a mocked adapter context (project, aspect_ratio, content-pack parent-generation stub, sibling-task reader); asserts (1) validation errors match, (2) task count & capability, (3) `spec_json` exact-ish (params key set + output_policy), (4) run fan-out ordinals for batch fixtures, (5) dependency edges for fixture I, (6) idempotency replay (same key → same ULIDs, no new rows; changed bytes → `409 idempotency_mismatch`), (7) `image-upscale` capability normalization. Port the existing `__tests__/dispatch.test.ts` + `placement.test.ts` cases into the adapter test suite.

---

## 8. Cross-family summary

| Dimension | Value |
|---|---|
| Families | 13 resolvers + 1 passthrough path (allowlist) |
| Distinct capabilities | 19 (`reigh.wan_2_2_t2i`, `reigh.qwen_image`, `reigh.qwen_image_style`, `reigh.qwen_image_2512`, `reigh.z_image_turbo`, `reigh.image_upscale`, `reigh.individual_travel_segment`, `reigh.join_clips_orchestrator`, `reigh.video_enhance`, `reigh.z_image_turbo_i2i`, `reigh.qwen_image_edit`, `reigh.image_inpaint`, `reigh.annotated_image_edit`, `reigh.travel_orchestrator`, `reigh.wan_2_2_i2v`, `reigh.travel_stitch`, `reigh.edit_video_orchestrator`, `reigh.animate_character`, `reigh.flux_klein_edit` + allowlist `reigh.*`) |
| Batch → run | `image_generation`, `magic_edit`, `masked_edit`, `klein_edit`, `z_image_turbo_i2i` |
| Orchestrator (create_generation=false) | `join_clips`, `travel_between_images` (non-turbo), `edit_video_orchestrator` |
| Single generation | `image_upscale`, `video_enhance`, `character_animate`, `crossfade_join`, `individual_travel_segment`, `travel_between_images` (turbo), passthrough generation-category |
| Dependencies at admission | only worker passthrough (`dependant_on` lift); frontend families all `null` |
| run_type split (worker) | api: qwen_*, z_image_*, image-upscale, animate_character, video_enhance, flux_klein_edit; gpu: wan_* / travel / join / edit orchestrators |
| Dropped at port | route-contract stamping (`derive_route_key` RPC + `params.route_contract`), `tasks_assert_claimable` trigger, `task_types` FK, billing columns (`base_cost_per_second` etc.), `attempts`/`slot` machinery |

---

## 9. Open questions

1. **RESOLVED (doc 26/Grok):** legacy active task types (`single_image`, `image_edit`, `magic_edit`, `edit_travel_flux`, `image_upscale` underscore row) and unwritten `edit_video_segment` are rejected outright; no alias admission and nothing dead on the child allowlist.
2. **`ensure_shot_parent_generation` port**: the content pack v2 DDL (doc 14 §4) has `generations.parent_generation_id` but no ensure-parent RPC; should the adapter auto-create a parent generation row (as Reigh does) or require the caller to supply `parent_generation_id`?
3. **Worker-supplied `task_id`**: kernel ids are ULIDs, worker passthrough pre-generates UUIDs for sibling `dependant_on` references. Adapter maps logical id → ULID and rewrites dependency edges; must the claim adapter also expose the mapping (so worker logs keep the original id), or is the ULID authoritative end-to-end?
4. **`masked_edit` identical batch rows**: port faithfully (N identical specs in one run) or per-index seed variation (behavior change)?
5. **RESOLVED (doc 26/Grok):** `travel_between_images.turbo_mode` retains the ratified flat capability `reigh.wan_2_2_i2v`; semantic taxonomy is catalog metadata, not an ID rewrite.
6. **`input_manifest_json` coverage**: resolve only `materialized_inputs` to media_ids, or also generation-backed params (`based_on`, `style_reference_image`, `clip_urls`...) when their media rows exist? Doc 14 says "Input media should resolve to Astrid media_ids during admission" — exact rule needed.
7. **RESOLVED (doc 26/Grok):** retain worker-created child admission for v1 behind the hard internal R1 gate (live parent fence + matching executor + deterministic key); structural fan-out remains deferred.
8. **Run scoping**: are batch families (A/F/H/K/L) the only run fan-outs, or should orchestrator parents also open a run so children inherit `run_id`?
9. **`priority`**: all families write 0; `join_clips` has a `priority` input that only reaches `params`. Should the adapter promote `params.priority` to kernel `tasks.priority` (behavior change)?
10. **Live task_types drift**: 13 live rows have no repo seed and `image-upscale` (hyphen) is the real FK target while `image_upscale` (underscore) is legacy-active. Confirmed by probe; no further action unless decision rows in §5 are admitted.
