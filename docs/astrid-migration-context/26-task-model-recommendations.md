# 26 — Task-model recommendations: Reigh on the Astrid kernel

**Status: RATIFIED 2026-08-21 as refined by Grok second opinion (`grok/second-opinion-decisions.md`).**

## Executive summary

**Ratified verdict (revised):** retain doc 16's flat shipped IDs, `reigh.<normalized_task_type>`; semantic taxonomy is catalog metadata and never the capability ID. User definitions use `local.<slug>` as optional named sugar over the generic `local.workflow.run` custom-task mechanism. Preserve a ported source string only in `spec_json.source_task_type`; reject dead types rather than admitting aliases. The code-declared registry has exactly one local executor binding per capability: WGP for the Wan/travel/join family already resident there, VibeComfy for the rest, and no post-claim fallback. [Amended doc 26/Grok; docs 16 §§6–9, 20 §19.1; `grok/second-opinion-decisions.md`]

V1 should retain travel/join/edit worker-created children exactly in spirit, but admit them through fenced, allowlisted R1 calls with deterministic idempotency keys and kernel dependency edges. The parent remains `running` under a live lease and completes explicitly after its children; do not add a new running→blocked/yield transition during cutover. Custom tasks need a declarative registry plus a generic VibeComfy handler, not arbitrary runtime-code plugins. Wan2GP remains a pinned submodule with its patch/path contract, while executor-build manifests make upgrades safer. All generation is local; `run_type` and Fal/Wavespeed routing disappear. [Grok §§3–6; docs 18 R1/R3–R8, 24 Q3, 25 #7]

## D1 — Capability naming (REVISED: flat IDs retained)

Identity rules:

- Shipped IDs use the already-ratified doc-16 scheme: `reigh.<normalized_task_type>`; `image-upscale` remains the one source spelling normalized to `reigh.image_upscale`. Semantic media/operation/model taxonomy belongs in catalog metadata, never in the capability ID. [Amended doc 26/Grok]
- User definitions use `local.<slug>` when a stable name helps; `local.workflow.run` is the generic parameterized custom-workflow capability (§D4–D5). The frontend continues to post `{family, input}` and never speaks capability strings.
- `spec_json.source_task_type` retains the old string for ported live types. It is provenance, not an alias-admission mechanism.
- One code-declared registry drives R1 allowlisting/resolution, catalog/forms, availability checks, and exact R3 capability advertisement. No wildcards and no `task_types` table authority.
- Each shipped entry binds its contract, catalog metadata, family/resolver, schemas/ports, output policy, requirements, allowed origins, availability probe, and exactly one executor. [Amended doc 26/Grok]

### Full functional mapping

| Source `task_type` | Ratified capability | Family / origin | One local executor binding |
|---|---|---|---|
| `wan_2_2_t2i` | `reigh.wan_2_2_t2i` | `image_generation` | WGP `t2v_2_2` |
| `qwen_image` | `reigh.qwen_image` | `image_generation` | VibeComfy Qwen image |
| `qwen_image_style` | `reigh.qwen_image_style` | `image_generation` | VibeComfy Qwen edit |
| `qwen_image_2512` | `reigh.qwen_image_2512` | `image_generation` | VibeComfy Qwen 2512 |
| `z_image_turbo` | `reigh.z_image_turbo` | `image_generation` | VibeComfy `image/z_image` |
| `image-upscale` | `reigh.image_upscale` | `image_upscale` | VibeComfy `image/basic_image_upscale` |
| `individual_travel_segment` | `reigh.individual_travel_segment` | `individual_travel_segment` | WGP travel segment |
| `join_clips_orchestrator` | `reigh.join_clips_orchestrator` | `join_clips` | WGP join orchestrator |
| `video_enhance` | `reigh.video_enhance` | `video_enhance` | VibeComfy video enhance |
| `z_image_turbo_i2i` | `reigh.z_image_turbo_i2i` | `z_image_turbo_i2i` | VibeComfy `image/z_image_img2img` |
| `qwen_image_edit` | `reigh.qwen_image_edit` | `magic_edit` | VibeComfy Qwen edit |
| `image_inpaint` | `reigh.image_inpaint` | `masked_edit` | VibeComfy Qwen edit |
| `annotated_image_edit` | `reigh.annotated_image_edit` | `masked_edit` | VibeComfy Qwen edit |
| `travel_orchestrator` | `reigh.travel_orchestrator` | `travel_between_images` | WGP travel orchestrator |
| `wan_2_2_i2v` | `reigh.wan_2_2_i2v` | `travel_between_images` turbo | WGP Wan i2v |
| `travel_stitch` | `reigh.travel_stitch` | `crossfade_join` / internal child | WGP travel stitch |
| `edit_video_orchestrator` | `reigh.edit_video_orchestrator` | `edit_video_orchestrator` | WGP join-chain orchestrator |
| `animate_character` | `reigh.animate_character` | `character_animate` | VibeComfy Wan animate |
| `flux_klein_edit` | `reigh.flux_klein_edit` | `klein_edit` | VibeComfy Flux Klein |
| `travel_segment` | `reigh.travel_segment` | internal child only | WGP travel segment |
| `join_clips_segment` | `reigh.join_clips_segment` | internal child only | WGP VACE join segment |
| `join_final_stitch` | `reigh.join_final_stitch` | internal child only | WGP join stitch handler |
| `timeline_visualize` | `rendering.timeline_visualize` | `render_export` | Astrid Remotion |

The first 19 rows are doc 16's live resolver capabilities; the next three are executor-only child capabilities, and render retains Astrid's native ID. Catalog taxonomy can group them without changing these contract strings. Missing prerequisites suppress advertisement and produce `422 capability_unavailable` with setup guidance on direct admission. [Amended doc 26/Grok; Grok §§1,4; docs 16 §§2,6, 18 R1]

## D2 — Orchestrator parent model (RATIFIED)

Ratify worker-created children for v1 (doc 20 §16.7), with this protocol:

1. Initial R1 admission creates an orchestrator parent and run; its immutable spec contains the versioned orchestration contract. R3/R4 starts a 300-second fenced attempt.
2. The executor admits each allowed child through R1 with `Idempotency-Key: reigh.orch:v1:<parent-ulid>:<plan-version>:<role>:<index>`. This is a hard internal gate: the child envelope supplies `parent_task_id`, `run_id`, `run_ordinal`, `executor_id`, and the parent fence; admission requires the same executor that owns the live fence and a `running` parent. Browser/user origins cannot admit child capabilities. [Amended doc 26/Grok; INFERENCE]
3. Kernel ULIDs are authoritative. Retain today's pregenerated UUID as `logical_task_id`; cache the R1 UUID→ULID response and reconstruct it by replay after a crash. Rewrite sequential and fan-in `dependant_on` references to ULIDs and hard `task_dependencies`. Thus join chains, parallel segments/final stitch, and travel chains map directly from Grok §4.
4. Keep the parent `running` under a `LeaseKeeper`; it need not occupy the GPU execution slot. R5 carries only bounded progress `{schema_version,phase,completed,total,percent,message?,eta_seconds?,metrics?}` and updates the fence—never status or output paths (docs 18 R5, 19 §5.3, 20 §19.7). The long-lived parent fence, heartbeat-as-progress visibility, and crash-replay of receipted child admissions are load-bearing cutover requirements, not polish. [Amended doc 26/Grok]
5. Replace `checkOrchestratorCompletion` with an executor coordinator: read child/run state; after all required children succeed, R7-complete the parent once; on terminal child failure, R8-fail it; cancellation covers all nonterminal run members. The keeper serializes R5 with R7/R8. This explicit `orch-complete` is preferable to blocked-on-children because Astrid has no documented yield-and-resume attempt primitive. [INFERENCE]

Structural runs follow later: first materialize all statically knowable nodes atomically from the same orchestration contract; retain executor continuation only where child specs depend on produced media; then replace those with output-activated continuation nodes family by family. Existing capabilities/specs need no rename. [Docs 14 §2, 20 §16.8]

## D3 — Executor binding (REVISED: one per capability)

The running v1 registry has **one binding per capability**. Hard-pick WGP for the Wan/travel/join family that already lives there and VibeComfy for every remaining generation capability; `rendering.timeline_visualize` stays on Astrid Remotion. Switching an implementation is a reviewed registry edit plus restart/drain, not an admission-time picker. Record the process/build manifest as completion provenance. There is no post-claim fallback. [Amended doc 26/Grok; Grok §3]

## D4 — Custom workflow entry (REVISED: snapshots and ready_templates only)

User workflows are immutable snapshots: hash the workflow bytes at admission and pin the digest in `spec_json`. Shipped `reigh.*` Comfy workflows are in-repo VibeComfy `ready_templates` referenced by the code registry. Promotion is git—`cp` the workflow, add/update its YAML/registry entry, review, and restart. V1 has no promotion service, curation database, or second runtime object model. [Amended doc 26/Grok]

## D5 — Custom task definitions (REVISED: trimmed user schema)

The user-facing declarative `TaskDefinition` is only `{id, input ports, workflow path/digest, output policy}`. Shipped registry entries additionally own `availability_probe`, `allowed_origins`, `resolver_id`, `executor_binding_id`, and ABI/process requirements; those are not user-facing fields. V1 loads declarative YAML and routes every custom workflow through one generic VibeComfy handler. No runtime code plugins or dynamic code loader. [Amended doc 26/Grok; docs 14 §2, 20 §08.3]

The custom-task mechanism is the single `local.workflow.run` capability parameterized by immutable workflow digest and typed ports. Named `local.<slug>` definitions are optional catalog/UX sugar over that mechanism, not a rebuilt `task_types` authority. R1 validates ports, resolves project inputs to `media_id`s, pins the definition version and workflow digest, and admits the task/run. R3 claims the exact capability; R5 reports progress; R6 stages outputs; R7 atomically commits managed media plus generation/variant lineage and any internal asset-registry visibility merge—never document-native placement. [Amended doc 26/Grok; Grok §§2,5–6; docs 18 R1/R3/R5–R7, 24 Q1]

Of the version/provenance fields, pin only the output-determinative ones in `spec_json`: workflow digest, definition version, and model hash. ComfyUI, node, executor protocol, handler ABI, and other environment versions belong on the process/build manifest and completion provenance, not on every task. Startup still fails closed on bridge/worker registry-digest disagreement. [Amended doc 26/Grok]

## D6 — Legacy dead types (REVISED: reject outright)

Dead types are rejected, never aliased, and never placed on the child allowlist. This includes `edit_travel_flux`, `magic_edit`, `single_image`, underscore `image_upscale`, `image_edit`, and `edit_video_segment` (a live row with no current writer), plus inactive rows such as `banodoco_timeline_generate`. Worker catalog keys (`vace*`, `t2v*`, `i2v*`, `flux`, `hunyuan`, `ltxv/ltx2`, `generate_video`, `qwen_image_hires`) and dead specialized handlers (`comfy`, `extract_frame`, `inpaint_frames`, `rife_interpolate_images`, `create_visualization`) remain private implementation identifiers. Ported live types retain their exact old spelling only in `spec_json.source_task_type`. [Amended doc 26/Grok; docs 16 §5, 20 §16.1, 24/25 #8]

## Grok second opinion (baked in)

> A code-declared table of the 19 live capabilities as `reigh.<normalized_task_type>` (plus `rendering.timeline_visualize`), each with input schema, output policy, **one** local executor, and a workflow digest when Comfy. Frontend still posts `{family, input}`; the adapter derives the capability. Travel/join/edit keep worker-created children through the same R1 allowlist, parent leased-running, explicit complete/fail. Custom tasks: drop YAML + a workflow into a local dir → `local.<slug>` → generic VibeComfy handler; admission pins the digest. Missing models → `422 capability_unavailable` with a setup hint, never a fallback. No dotted taxonomy, no binding picker, no promotion service, no plugin loader, no kernel yield, no dead-type aliases.

Decision-worthy consequences (Amended doc 26/Grok):

1. `local.workflow.run`, parameterized by digest and typed ports, is the one custom-task mechanism; named `local.*` entries are optional sugar.
2. Child admission is a hard internal gate: browser/user origins cannot admit child types; only the executor holding the live `running` parent fence may do so, with `executor_id` matching the claiming executor and deterministic idempotency keys.
3. The long-lived orchestrator lease keeper plus crash-replay of receipted child admissions is the real cutover risk and must be designed now.
4. The model acquisition/availability matrix is more load-bearing than naming: advertise only installed, preflighted capabilities; otherwise return `422 capability_unavailable` with a setup hint.
5. Thumbnails are a cheap local capability, not a generation column; include them in the local availability/product journey.
6. `spec_json` pins only workflow digest, definition version, and model hash; ComfyUI/node/ABI versions live on the process manifest.
7. `family` remains the frontend UI/admission key; the editor never submits capability strings.

Structural runs—materializing a whole orchestrator graph at admission—remain deferred and must not leak into v1 contracts. [INFERENCE; `grok/second-opinion-decisions.md`]

## Wan2GP update contract

Keep the `banodoco/Wan2GP` submodule, reviewed SHA, fixed `reigh-worker/Wan2GP/` mount, in-process cwd/sys.path boundary, `wgp_bridge.py`, `wgp_patches.py`, defaults/finetunes/ckpts paths, and fork-rebase→submodule-bump runbook. Current evidence pins `181bb71a21008032e4771e11663f33e4489c4512`; boot rewrites only `wgp_config.json` (Grok §3; rebase runbook §§1–7).

Add an executor-build manifest `{wan2gp_sha, upstream_base, patchset_hash, worker_contract_version, preset/model/checkpoint hashes}`. Make path, import, patch-lifecycle, conversion-fixture, and representative capability smokes release gates; drain queued tasks before changing the pinned implementation and retain the prior manifest for rollback. Completion provenance records the manifest that ran; capability IDs do not change unless the public contract breaks. Each capability has one registry-selected executor, never an admission-time WGP/VibeComfy choice, and no post-claim fallback. [Amended doc 26/Grok; INFERENCE]

## `run_type` and API tasks

Delete the `gpu|api` scheduling axis and Fal/Wavespeed/API-provider handlers. Former API types with local VibeComfy/Qwen paths retain the capabilities above. Provider-only combinations are hidden until a local binding exists. The registry advertises a capability only after its model, nodes, binaries, template, disk, and hashes pass preflight; a direct R1 request returns `422 capability_unavailable` with `missing_prerequisites` and `setup_hint`, never cloud fallback. Executor kind remains provenance, not schema or capability identity. [Grok §§1,6; docs 18 §2.3/R1, 24 Q3, 25 #7]

## Grok §6 gap resolutions

| Gap | Resolution |
|---|---|
| Immutable spec vs mid-run children | Parent stays immutable; fenced, allowlisted R1 creates separate immutable children with stable keys, run membership, and hard dependencies. |
| Heartbeat as progress | R5 `progress` JSON only; 30-second serialized beats refresh the 300-second lease and fence. |
| Intermediates | Prefer producing-child R7 media outputs; otherwise publish through project media import, obtain a `media_id`, then use it in child R1. Never pass storage URLs/local paths; R6 quarantine is attempt-local. [INFERENCE] |
| Parent In Progress | Kernel `running` with a live attempt; child state is authoritative; explicit parent R7/R8 after aggregation. |
| No lease | `LeaseKeeper` + expiry loop; a crash requeues, and receipted child admissions replay without duplicates. |
| `run_type` | Exact local capabilities and prerequisite probes replace API/GPU routing; unavailable means disabled with setup guidance. |

## Phased plan, risks, and owner decisions

- **Phase 0:** freeze child graphs/payloads, dead-type rejection, Wan contracts, and the local availability matrix. **Phase 1:** atomic output/media/generation boundary and registry-merge command. **Phase 2:** prove non-orchestrated Wan t2i plus missing-model, replay, fence, crash, and render cases. **Phase 3:** ship registry-driven R1/R3, custom-definition seam, batches/runs, hard-gated child admission, cancellation, expiry, and media resolution. **Phase 4:** port all local handlers/orchestrators, the single Wan/Vibe binding per capability, intermediate media IDs, and parent completion. **Phase 5:** task catalog/setup/custom-workflow UX and two-second progress. **Phase 6:** clean-install acceptance. **Phase 7:** remove Supabase, provider, `run_type`, legacy status, and old `checkOrchestratorCompletion` paths. [Amended doc 26/Grok; Doc 22 §3, amended by doc 24]

Top risk is orchestrator lease lifetime: the parent holds a live fence for minutes or hours without occupying GPU, so keeper liveness, heartbeat-as-progress, receipted child-admission replay, crash, and cancellation fixtures are cutover gates. Next are Wan rebase drift (manifested, gated, rollbackable updates), the installed-model availability matrix, and custom-author ergonomics/security (one scaffold/linter; immutable workflow digests; bounded schemas/ports; templates cannot mutate the database). Reject registry drift at startup. [Amended doc 26/Grok]

Owner decisions — **RATIFIED 2026-08-21 as refined by Grok**:

1. Retain flat `reigh.<normalized_task_type>` IDs; semantic taxonomy is catalog metadata; `local.<slug>` is optional sugar; source strings live only in `spec_json.source_task_type`.
2. Use explicit long-lived leased parents for v1, with R5 progress and replay-safe fenced child admission; add no yield/block/resume kernel transition.
3. Use one binding per capability: WGP for Wan/travel/join, VibeComfy for the rest, and no post-claim fallback.
4. Use admission-pinned snapshots for custom workflows and in-repo VibeComfy `ready_templates` for shipped workflows; promotion is git, with no promotion machinery.
5. Use declarative custom definitions trimmed to `{id, input ports, workflow path/digest, output policy}` and one generic VibeComfy handler; no runtime code plugins.
6. Reject dead historical types outright; do not admit aliases and put nothing dead on the child allowlist.
