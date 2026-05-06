# Sprint 11A VibeComfy Endpoint Inventory

Generated: 2026-05-06

Scope: agent-owned inventory for Sprint 11A batch T1. This artifact enumerates app-used create-task and AI-agent generation surfaces that can be route-stamped before any VibeComfy selector promotion or production patch.

## Baseline

- Selector contract version: `WORKER_ROUTE_CONTRACT_VERSION = 1`.
- App route stamping source: `reigh-app/supabase/functions/create-task/routeContract.ts` via `stampTaskRouteContract`.
- App selector map source: `reigh-app/supabase/functions/_shared/selectedRoute.ts`.
- Worker route contract source: `reigh-worker/source/task_handlers/tasks/template_routing.py`.
- Default create-task behavior: if no `route_selection_candidate` is supplied, create-task stamps `selected_backend: "wgp"`.
- Candidate behavior: create-task accepts `route_selection_candidate.backend` values `wgp` and `vibecomfy`; the worker still fail-closes any explicit VibeComfy task whose route is not `vibecomfy_supported` with a template.
- Current restrictive baseline: `z_image_turbo` is the only route with `support_state: vibecomfy_supported`.

## Profile Behavior

The app and worker derive `selected_profile` from `params.profile`, then `params.wgp_profile`, then `params.override_profile`, then `default`, unless create-task receives `route_selection_candidate.profile`. Worker-local `memory_profile` is separately extracted from `params.override_profile`.

Dimensional child routes derive route keys from:

`<task_type>__model-<model_family>__guidance-<guidance_key>__continuity-<continuity_case>__profile-<profile>`

This applies to `travel_segment`, `individual_travel_segment`, and `join_clips_segment`.

## Route Inventory

| App-used surface | Create-task family or agent task type | Stamped task type | Route key | Support state | Selected template ID | Selected profile behavior | Can request VibeComfy today | Ownership surface | Shared completion/billing exposure | Promotion status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Image generation form, modal, AI agent text-to-image with `model: z-image` | `image_generation`, `text-to-image` | `z_image_turbo` | `z_image_turbo` | `vibecomfy_supported` | `image/z_image` | Candidate profile or params profile fallback; usually `default` | Yes. This is the only route that can execute on VibeComfy today when explicitly selected. | App create-task resolver plus AI agent mapper; worker direct route | Image completion, generation variant creation, task cost/billing for image generation | Candidate for first promotion only after route-specific live RunPod proof, Reigh-shaped queue proof, telemetry, billing metadata where relevant, and WGP rollback rerun |
| Image generation form, modal, AI agent text-to-image default or `model: qwen-image` | `image_generation`, `text-to-image`, transfer modes defaulting to Qwen | `qwen_image` | `qwen_image` | `wgp_only` | `null` | Candidate profile or params profile fallback; usually `default` | Request can be stamped, but worker must not execute VibeComfy; explicit VibeComfy fail-closes | App create-task resolver plus AI agent mapper; worker direct route | Image completion, generation variant creation, task cost/billing | Unpromoted; WGP-only |
| Image generation form, modal, AI agent text-to-image with `model: qwen-image-2512` | `image_generation`, `text-to-image` | `qwen_image_2512` | `qwen_image_2512` | `wgp_only` | `null` | Candidate profile or params profile fallback; usually `default` | Request can be stamped, but worker must not execute VibeComfy; explicit VibeComfy fail-closes | App create-task resolver plus AI agent mapper; worker direct route | Image completion, generation variant creation, task cost/billing | Unpromoted; WGP-only |
| Image generation transfer tasks with Qwen reference image | `image_generation`, `style-transfer`, `subject-transfer`, `style-character-transfer`, `scene-transfer` | `qwen_image_style` | `qwen_image_style` | `wgp_only` | `null` | Candidate profile or params profile fallback; usually `default` | Request can be stamped, but worker must not execute VibeComfy; explicit VibeComfy fail-closes | App create-task resolver plus AI agent mapper; worker direct route | Image completion, generation variant creation, task cost/billing | Unpromoted; WGP-only |
| Image generation form with WAN fallback/default model | `image_generation` | `wan_2_2_t2i` | `wan_2_2_t2i` | `wgp_only` | `null` | Candidate profile or params profile fallback; usually `default` | Request can be stamped, but worker must not execute VibeComfy; explicit VibeComfy fail-closes | App create-task resolver; worker direct route alias from `optimised_t2i`/`wan_2_2_t2i` | Image completion, generation variant creation, task cost/billing | Unpromoted; WGP-only |
| Media lightbox image-to-image, AI agent image-to-image | `z_image_turbo_i2i`, `image-to-image` | `z_image_turbo_i2i` | `z_image_turbo_i2i` | `wgp_only` | `null` | Candidate profile or params profile fallback; usually `default` | Request can be stamped, but worker must not execute VibeComfy; explicit VibeComfy fail-closes | App create-task resolver plus AI agent mapper; worker direct route | Image completion, source variant lineage, generation variant creation, task cost/billing | Unpromoted; WGP-only |
| Magic edit hooks, AI agent magic-edit | `magic_edit`, `magic-edit` | `qwen_image_edit` | `qwen_image_edit` | `wgp_only` | `null` | Candidate profile or params profile fallback; usually `default` | Request can be stamped, but worker must not execute VibeComfy; explicit VibeComfy fail-closes | App create-task resolver plus AI agent mapper; worker direct route | Image completion, source variant lineage, generation variant creation, task cost/billing | Unpromoted; WGP-only |
| Klein edit hook | `klein_edit` | `flux_klein_edit` | `flux_klein_edit` | `vibecomfy_unsupported` by missing selector entry | `null` | Candidate profile or params profile fallback; usually `default` | Request can be stamped, but worker must not execute VibeComfy; explicit VibeComfy fail-closes as no selector entry | App create-task resolver; worker direct route fallback | Image completion, source variant lineage, generation variant creation, task cost/billing | Unpromoted; unsupported |
| Inpainting workflows | `masked_edit` | `image_inpaint` | `image_inpaint` | `wgp_only` | `null` | Candidate profile or params profile fallback; usually `default` | Request can be stamped, but worker must not execute VibeComfy; explicit VibeComfy fail-closes | App create-task resolver; worker direct route | Image completion, source variant lineage, generation variant creation, task cost/billing | Unpromoted; WGP-only |
| Annotated/masked edit workflows | `masked_edit` with `task_type: annotated_image_edit` | `annotated_image_edit` | `annotated_image_edit` | `wgp_only` | `null` | Candidate profile or params profile fallback; usually `default` | Request can be stamped, but worker must not execute VibeComfy; explicit VibeComfy fail-closes | App create-task resolver; worker direct route | Image completion, source variant lineage, generation variant creation, task cost/billing | Unpromoted; WGP-only |
| Image upscale hooks, AI agent image-upscale | `image_upscale`, `image-upscale` | `image-upscale` | `image-upscale` | `vibecomfy_unsupported` by missing selector entry | `null` | Candidate profile or params profile fallback; usually `default` | Request can be stamped, but worker must not execute VibeComfy; explicit VibeComfy fail-closes as no selector entry | App create-task resolver plus AI agent mapper; worker direct route fallback | Image completion, source variant lineage, generation variant creation, task cost/billing | Unpromoted; unsupported |
| Video enhance hooks, AI agent video-enhance | `video_enhance`, `video-enhance` | `video_enhance` | `video_enhance` | `vibecomfy_unsupported` by missing selector entry | `null` | Candidate profile or params profile fallback; usually `default` | Request can be stamped, but worker must not execute VibeComfy; explicit VibeComfy fail-closes as no selector entry | App create-task resolver plus AI agent mapper; worker direct route fallback | Video completion, source lineage, generation variant creation, task cost/billing | Unpromoted; unsupported |
| Character animate tool, AI agent character-animate | `character_animate`, `character-animate` | `animate_character` | `animate_character` | `vibecomfy_unsupported` by missing selector entry | `null` | Candidate profile or params profile fallback; usually `default` | Request can be stamped, but worker must not execute VibeComfy; explicit VibeComfy fail-closes as no selector entry | App create-task resolver plus AI agent mapper; worker direct route fallback | Video completion, generation variant creation, task cost/billing | Unpromoted; unsupported |
| Travel Between Images batch/timeline generation, AI agent image-to-video | `travel_between_images`, `image-to-video` | `travel_orchestrator` | `travel_orchestrator` | `wgp_only` | `null` | Candidate profile or params profile fallback; child routes derive their own profile from child params | Request can be stamped, but parent VibeComfy selection is blocked before insert when required child/control routes have blockers | App orchestrator resolver plus AI agent mapper; worker/orchestrator child creation | Shared orchestrator completion, child task completion, stitch completion, billing ownership across child tasks | Unpromoted; WGP-only parent with blocked child/control requirements |
| Travel Between Images child segment created by orchestrator | Worker-created or passthrough child | `travel_segment` | `travel_segment__...` dimensional route or generic `travel_segment` | `vibecomfy_unsupported` | `null` | Derived from child params `profile`/`wgp_profile`/`override_profile`; usually `default` | Request can be stamped only through parent/worker paths; explicit VibeComfy child fails closed | Worker child task creation and app passthrough resolver | Child generation completion, orchestrator aggregation, task cost/billing | Unpromoted; unsupported |
| Individual segment regeneration UI | `individual_travel_segment` | `individual_travel_segment` | `individual_travel_segment__...` dimensional route or generic `individual_travel_segment` | `vibecomfy_unsupported` | `null` | Derived from segment params `profile`/`wgp_profile`/`override_profile`; usually `default` | Request can be stamped, but worker must not execute VibeComfy; explicit VibeComfy fail-closes | App create-task resolver and worker segment route | Child generation completion, orchestrator linkage when present, task cost/billing | Unpromoted; unsupported |
| Join clips tool and gallery join actions | `join_clips` | `join_clips_orchestrator` | `join_clips_orchestrator` | `wgp_only` | `null` | Candidate profile or params profile fallback; child routes derive their own profile from child params | Request can be stamped, but parent VibeComfy selection is blocked before insert when required child/control routes have blockers | App orchestrator resolver; worker/orchestrator child creation | Shared orchestrator completion, join child completion, final stitch, billing ownership across child tasks | Unpromoted; WGP-only parent with blocked child/control requirements |
| Join clips segment created by orchestrator | Worker-created child | `join_clips_segment` | `join_clips_segment__...` dimensional route or generic `join_clips_segment` | `vibecomfy_unsupported` | `null` | Derived from child params `profile`/`wgp_profile`/`override_profile`; usually `default` | Request can be stamped only through parent/worker paths; explicit VibeComfy child fails closed | Worker child task creation and app passthrough resolver | Child generation completion, orchestrator aggregation, task cost/billing | Unpromoted; unsupported |
| Join final stitch created by orchestrator | Worker-created control task | `join_final_stitch` | `join_final_stitch` | `wgp_only` | `null` | Candidate profile or params profile fallback; usually `default` | Request can be stamped, but worker must not execute VibeComfy; explicit VibeComfy fail-closes | Worker control task creation and app passthrough resolver | Final stitch completion, orchestrator completion, task cost/billing | Unpromoted; WGP-only |
| Crossfade join actions | `crossfade_join` | `travel_stitch` | `travel_stitch` | `wgp_only` | `null` | Candidate profile or params profile fallback; usually `default` | Request can be stamped, but worker must not execute VibeComfy; explicit VibeComfy fail-closes | App create-task resolver; worker stitch route | Stitch completion, generation variant creation, task cost/billing | Unpromoted; WGP-only |
| Travel stitch control task created by orchestrator | Worker-created control task | `travel_stitch` | `travel_stitch` | `wgp_only` | `null` | Candidate profile or params profile fallback; usually `default` | Request can be stamped, but worker must not execute VibeComfy; explicit VibeComfy fail-closes | Worker control task creation and app passthrough resolver | Stitch completion, orchestrator completion, task cost/billing | Unpromoted; WGP-only |
| Edit video replace mode and video editing mode | `edit_video_orchestrator` | `edit_video_orchestrator` | `edit_video_orchestrator` | `wgp_only` | `null` | Candidate profile or params profile fallback; child routes derive their own profile from child params | Request can be stamped, but parent VibeComfy selection is blocked before insert when required child/control routes have blockers | App orchestrator resolver; worker/orchestrator child creation | Shared orchestrator completion, join child completion, final stitch, billing ownership across child tasks | Unpromoted; WGP-only parent with blocked child/control requirements |
| Worker/service-role passthrough for active DB task types without explicit resolver | Unknown family fallback | Original family name | Direct alias when known, otherwise original family name | Selector map entry when present, else `vibecomfy_unsupported` | Selector map template when present, else `null` | Candidate profile or params profile fallback; usually `default` | Request can be stamped, but only `z_image_turbo` can execute on VibeComfy today | App create-task passthrough for worker-created processing tasks and internal callers | Depends on task type; can touch shared completion/billing if inserted task completes through app edge functions | Unpromoted except `z_image_turbo` when used as the direct route with full proof |

## AI-Agent Generation Mapping

The AI timeline agent uses two create-task tools:

- `executeCreateTask` supports user-facing `task_type` values `text-to-image`, `style-transfer`, `subject-transfer`, `style-character-transfer`, `scene-transfer`, `image-to-video`, `image-to-image`, `magic-edit`, `image-upscale`, `video-enhance`, and `character-animate`.
- `createGenerationTask` maps those values to create-task families: `image_generation`, `travel_between_images`, `z_image_turbo_i2i`, `magic_edit`, `image_upscale`, `video_enhance`, and `character_animate`.

Therefore the AI-agent generation surface is covered by the same inventory rows as the app create-task families above. The only AI-agent path that can currently execute on VibeComfy is text-to-image with `model: z-image`, which maps to `image_generation` and stamps `z_image_turbo`.

## Orchestrated Parent Requirements

The app blocks explicit VibeComfy parent selection before insert when required child/control routes are blocked:

| Parent route key | Required routes | Current blockers |
| --- | --- | --- |
| `travel_orchestrator` | `travel_segment`, `travel_stitch`, `join_clips_orchestrator` | `travel_segment` is `vibecomfy_unsupported`; `travel_stitch` and `join_clips_orchestrator` are `wgp_only` |
| `join_clips_orchestrator` | `join_clips_segment`, `join_final_stitch` | `join_clips_segment` is `vibecomfy_unsupported`; `join_final_stitch` is `wgp_only` |
| `edit_video_orchestrator` | `join_clips_segment`, `join_final_stitch` | `join_clips_segment` is `vibecomfy_unsupported`; `join_final_stitch` is `wgp_only` |

## Section 3A Worker-Only Dimensional Rows

`SECTION3A_ROUTE_SUPPORT_MAP` currently records only `vibecomfy_unsupported` dimensional `travel_segment__...` rows. Some rows have disposition labels such as `NEW` or `BLOCKED`, but those are report metadata, not runtime support states. They do not alter the baseline that `z_image_turbo` is the only `vibecomfy_supported` route.

## Sources Inspected

- `reigh-app/supabase/functions/create-task/index.ts`
- `reigh-app/supabase/functions/create-task/routeContract.ts`
- `reigh-app/supabase/functions/create-task/resolvers/registry.ts`
- `reigh-app/supabase/functions/create-task/resolvers/*.ts`
- `reigh-app/supabase/functions/_shared/selectedRoute.ts`
- `reigh-app/src/shared/lib/taskCreation/createTask.ts`
- `reigh-app/supabase/functions/ai-timeline-agent/tools/create-task.ts`
- `reigh-app/supabase/functions/ai-timeline-agent/tools/generation.ts`
- `reigh-worker/source/task_handlers/tasks/template_routing.py`

