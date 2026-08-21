# 26 — Task-model recommendations: Reigh on the Astrid kernel

## Executive summary

**Verdict:** deliberately rename capabilities. Use `<authority>.<media>.<operation>[.<variant>]`, with lowercase dotted segments: for example `reigh.image.generate.wan.t2i`, `reigh.video.travel.orchestrate`, and `local.image.generate.parallax`. A capability is a stable executable contract—not a UI family, model commit, `run_type`, WGP/VibeComfy choice, or mutable template. Preserve every functionally-created current `task_type` as an admission alias and in `spec_json.source_task_type`; retain legacy names for compatibility/log correlation. Put contract, template, model, and executor versions in a code-declared registry and immutable task spec. This refines doc 16's safe transitional `reigh.<normalized_task_type>` mapping and doc 20 §19.1 because first-class custom tasks and the observed WGP/VibeComfy dual routing need a stable seam, not normalized legacy spellings. [INFERENCE; Grok §§2–3; docs 14 §2, 16 §§6–9]

V1 should retain travel/join/edit worker-created children exactly in spirit, but admit them through fenced, allowlisted R1 calls with deterministic idempotency keys and kernel dependency edges. The parent remains `running` under a live lease and completes explicitly after its children; do not add a new running→blocked/yield transition during cutover. Custom tasks need a declarative registry plus a generic VibeComfy handler, not arbitrary runtime-code plugins. Wan2GP remains a pinned submodule with its patch/path contract, while executor-build manifests make upgrades safer. All generation is local; `run_type` and Fal/Wavespeed routing disappear. [Grok §§3–6; docs 18 R1/R3–R8, 24 Q3, 25 #7]

## Recommended task/capability model

Identity rules:

- Namespace by owner (`reigh`, `rendering`, `local`), then media/domain and operation. Add a user-visible model/contract variant only when input/output or installability differs materially. Never include executor/backend names or incidental implementation versions.
- One versioned `TaskDefinition` registry drives R1 allowlisting/resolution, UI catalog/forms, availability checks, and exact R3 capability advertisement. No wildcards and no `task_types` table authority.
- Each definition binds capability contract, aliases, family/resolver, schemas/ports, output policy, allowed origins, requirements, and one deterministic executor binding. Multiple bindings may be installed, but admission pins one; there is no silent fallback after claim. [INFERENCE]

### Full functional mapping

| Today's `task_type` | New capability | Family | Local executor binding |
|---|---|---|---|
| `wan_2_2_t2i` | `reigh.image.generate.wan.t2i` | `image_generation` | WGP `t2v_2_2` or VibeComfy Wan t2i |
| `qwen_image` | `reigh.image.generate.qwen` | `image_generation` | local Qwen / VC Qwen image |
| `qwen_image_style` | `reigh.image.generate.qwen.style` | `image_generation` | local Qwen / VC Qwen edit |
| `qwen_image_2512` | `reigh.image.generate.qwen.2512` | `image_generation` | local Qwen / VC Qwen 2512 |
| `z_image_turbo` | `reigh.image.generate.z_image` | `image_generation` | VC `image/z_image` |
| `image-upscale` | `reigh.image.upscale` | `image_upscale` | VC `image/basic_image_upscale` |
| `z_image_turbo_i2i` | `reigh.image.transform.z_image` | `z_image_turbo_i2i` | VC `image/z_image_img2img` |
| `qwen_image_edit` | `reigh.image.edit.qwen` | `magic_edit` | local Qwen / VC Qwen edit |
| `image_inpaint` | `reigh.image.inpaint.qwen` | `masked_edit` | local Qwen / VC Qwen edit |
| `annotated_image_edit` | `reigh.image.edit.annotated.qwen` | `masked_edit` | local Qwen / VC Qwen edit |
| `flux_klein_edit` | `reigh.image.edit.flux.klein` | `klein_edit` | VC Flux Klein |
| `video_enhance` | `reigh.video.enhance` | `video_enhance` | VC basic video enhance |
| `wan_2_2_i2v` | `reigh.video.generate.wan.i2v` | `travel_between_images` turbo | VC Wan i2v |
| `animate_character` | `reigh.video.animate.character` | `character_animate` | VC Wan animate |
| `individual_travel_segment` | `reigh.video.travel.segment.individual` | `individual_travel_segment` | specialized WGP/VC travel binding |
| `travel_segment` | `reigh.video.travel.segment` | child allowlist | specialized WGP/VC travel binding |
| `travel_stitch` | `reigh.video.travel.stitch` | `crossfade_join` / child | local stitch, optional upscale child |
| `travel_orchestrator` | `reigh.video.travel.orchestrate` | `travel_between_images` | local orchestrator |
| `join_clips_segment` | `reigh.video.join.transition` | child allowlist | WGP VACE or VC binding |
| `join_final_stitch` | `reigh.video.join.finalize` | child allowlist | local ffmpeg/stitch handler |
| `join_clips_orchestrator` | `reigh.video.join.orchestrate` | `join_clips` / child | local orchestrator |
| `edit_video_orchestrator` | `reigh.video.edit.orchestrate` | same | local orchestrator using join chain |
| `edit_video_segment` | `reigh.video.edit.segment` | compatibility only | disabled until a writer/handler exists |
| `banodoco_render_timeline` | alias to `rendering.timeline_visualize` | `render_export` | Astrid Remotion |
| `banodoco_timeline_generate` | `reigh.timeline.generate.themed` | legacy | hidden until a fully local executor exists |

The first 22 rows cover every type emitted by the 13 resolvers or current child writers (Grok §§1,4; doc 16 §§2,6). Active resolver-less legacy rows (`edit_travel_flux`, `image_edit`, underscore `image_upscale`, `magic_edit`, `single_image`) remain compatibility/log aliases, not admissions; `wan_lora_training` stays deferred. Inactive rows are rejected. Worker catalog keys (`vace*`, `t2v*`, `i2v*`, `flux`, `hunyuan`, `ltxv/ltx2`, `generate_video`, `qwen_image_hires`) and legacy specialized keys (`comfy`, `extract_frame`, `inpaint_frames`, `rife_interpolate_images`, `create_visualization`) remain private handler/profile identifiers until given a declared contract. This preserves functioning paths without turning database drift into public API. [Grok §§1,5; docs 16 §5, 20 §16.1]

## Orchestrators

Ratify worker-created children for v1 (doc 20 §16.7), with this protocol:

1. Initial R1 admission creates an orchestrator parent and run; its immutable spec contains the versioned orchestration contract. R3/R4 starts a 300-second fenced attempt.
2. The executor admits each allowed child through R1 with `Idempotency-Key: reigh.orch:v1:<parent-ulid>:<plan-version>:<role>:<index>`. An internal-only child envelope supplies `parent_task_id`, `run_id`, and deterministic `run_ordinal`, validated against the caller's live parent fence. [INFERENCE]
3. Kernel ULIDs are authoritative. Retain today's pregenerated UUID as `logical_task_id`; cache the R1 UUID→ULID response and reconstruct it by replay after a crash. Rewrite sequential and fan-in `dependant_on` references to ULIDs and hard `task_dependencies`. Thus join chains, parallel segments/final stitch, and travel chains map directly from Grok §4.
4. Keep the parent `running` under a `LeaseKeeper`; it need not occupy the GPU execution slot. R5 carries only bounded progress `{schema_version,phase,completed,total,percent,message?,eta_seconds?,metrics?}` and updates the fence—never status or output paths (docs 18 R5, 19 §5.3, 20 §19.7).
5. Replace `checkOrchestratorCompletion` with an executor coordinator: read child/run state; after all required children succeed, R7-complete the parent once; on terminal child failure, R8-fail it; cancellation covers all nonterminal run members. The keeper serializes R5 with R7/R8. This explicit `orch-complete` is preferable to blocked-on-children because Astrid has no documented yield-and-resume attempt primitive. [INFERENCE]

Structural runs follow later: first materialize all statically knowable nodes atomically from the same orchestration contract; retain executor continuation only where child specs depend on produced media; then replace those with output-activated continuation nodes family by family. Existing capabilities/specs need no rename. [Docs 14 §2, 20 §16.8]

## Custom task authoring

An author adds one declarative `TaskDefinition`: `{id/version, capability/contract_version, aliases, input_schema, port_map, resolver_id, executor_binding_id, template_ref?, requirements, output_contract/policy, allowed_origins, availability_probe, setup_hint}`. A `StaticRegistryProvider` is enough for v1; a future manifest/package loader implements the same provider interface, so no kernel or route schema changes. Do not load arbitrary task code at runtime in v1. [INFERENCE; docs 14 §2, 20 §08.3]

For a Comfy task: author a VibeComfy scratchpad with typed ports; promote it to an immutable template or snapshot it at admission; register, for example, `local.image.generate.parallax` with a pinned `template_id`, version, and digest. R1 validates ports, resolves project inputs to `media_id`s, pins definition/template/binding versions in `spec_json`, and admits the task/run. R3 claims the exact capability. The worker's `TaskRegistry` dispatches `{capability, contract_version}` to one generic VibeComfy handler, which materializes inputs and runs `vibecomfy run` against the pinned workflow. R5 reports progress; R6 stages outputs; R7 atomically commits managed media plus generation/variant lineage and any internal asset-registry visibility merge—never document-native placement. [Grok §§2,5–6; docs 18 R1/R3/R5–R7, 24 Q1]

Version and record: registry digest; task-definition and capability-contract versions; template version/digest and port schema; executor protocol/handler ABI; selected implementation; VibeComfy/ComfyUI/node/model versions and hashes. Startup must fail closed on bridge/worker registry-digest disagreement.

## Wan2GP update contract

Keep the `banodoco/Wan2GP` submodule, reviewed SHA, fixed `reigh-worker/Wan2GP/` mount, in-process cwd/sys.path boundary, `wgp_bridge.py`, `wgp_patches.py`, defaults/finetunes/ckpts paths, and fork-rebase→submodule-bump runbook. Current evidence pins `181bb71a21008032e4771e11663f33e4489c4512`; boot rewrites only `wgp_config.json` (Grok §3; rebase runbook §§1–7).

Add an executor-build manifest `{wan2gp_sha, upstream_base, patchset_hash, worker_contract_version, preset/model/checkpoint hashes}`. Make path, import, patch-lifecycle, conversion-fixture, and representative capability smokes promotion gates; drain queued tasks before changing the pinned implementation and retain the prior manifest for rollback. Admissions record the selected implementation; capability IDs do not change unless the public contract breaks. WGP and VibeComfy are deterministic bindings behind the same semantic capability, never meanings of `task_type` or `run_type`; no post-claim fallback. [INFERENCE]

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

- **Phase 0:** freeze child graphs/payloads, legacy aliases, Wan contracts, and the local availability matrix. **Phase 1:** atomic output/media/generation boundary and registry-merge command. **Phase 2:** prove non-orchestrated Wan t2i plus missing-model, replay, fence, crash, and render cases. **Phase 3:** ship registry-driven R1/R3, custom-definition seam, batches/runs, child admission, cancellation, expiry, and media resolution. **Phase 4:** port all local handlers/orchestrators, Wan/Vibe bindings, intermediate media IDs, and parent completion. **Phase 5:** task catalog/setup/custom-template UX and two-second progress. **Phase 6:** clean-install acceptance. **Phase 7:** remove Supabase, provider, `run_type`, legacy status, and old `checkOrchestratorCompletion` paths. [Doc 22 §3, amended by doc 24]

Top risks are orchestrator parity (golden graph/replay/crash/cancellation fixtures), Wan rebase drift (manifested, gated, rollbackable updates), and custom-author ergonomics/security (one scaffold/linter; immutable workflow digests; bounded schemas/ports; templates cannot mutate the database). Also reject registry drift at startup and never let claimed work silently switch bindings.

Owner decisions:

1. Ratify semantic capability names above, reserving `reigh.*` for shipped definitions and `local.*` for user definitions.
2. Ratify explicit long-lived leased parents for v1, rather than adding a yield/block/resume kernel transition.
3. Permit multiple installed bindings per capability with one admission-pinned default and no automatic fallback (recommended).
4. Allow both promoted templates and scratchpads snapshotted by digest (recommended), or promoted templates only.
5. Confirm source-controlled/declarative custom definitions for v1; defer arbitrary runtime-code loaders (recommended).
6. Confirm resolver-less/inactive historical types remain aliases/private handlers rather than admitted public capabilities.
