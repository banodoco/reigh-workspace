**Bias: simplicity.** Doc 16 + Codex already closed most of this. Doc 26 adds taxonomy, a binding selector, and a promotion story the local product does not need.

---

### D1. Capability naming — **DISAGREE**

Keep the already-ratified flat IDs: `reigh.wan_2_2_t2i`, `reigh.image_upscale`, `reigh.travel_orchestrator`. Doc 16 mapped all 19 writable types that way; Codex §19.1 said enumerate those strings, no wildcards, no backend names. The worker, VibeComfy scratchpads, WGP `TASK_TYPE_TO_MODEL`, child passthrough, and golden fixtures all key off the flat `task_type`. A 5-segment taxonomy (`reigh.image.generate.wan.t2i`) is catalog cosmetics paid for in every claim allowlist and fixture. It also fails its own rule: `qwen.2512` and `flux.klein` are model versions in the ID. Family/tool_type already group the UI.

**Simplest:** `reigh.<normalized_task_type>` for shipped, `local.<slug>` for user defs, `spec_json.source_task_type` for the old string. Taxonomy lives in catalog metadata, not the capability id. Contract breaks → new id or `contract_version`, same as today.

### D2. Orchestrator parent model — **AGREE**

Do not add a kernel yield/block-on-children machine during cutover. Codex §16.7 already kept allowlisted worker-created children for v1; Astrid has no documented yield-and-resume. Kernel `blocked` already means *hard deps on siblings* (doc 16) — that is the children, not the parent. Parent stays `running` under `LeaseKeeper`, children admit via fenced R1 with deterministic idempotency keys, executor R7/R8s the parent. That is today's `checkOrchestratorCompletion` with a lease.

One operational footgun to treat as part of this decision, not a later surprise: an orch parent can hold a 300s fence for minutes/hours without occupying the GPU. Heartbeat-as-progress (R5) plus crash-replay of receipted child admissions is load-bearing, not polish.

### D3. Bindings per capability — **DISAGREE**

One binding per capability in the running registry. This is a single-user box with one pinned Wan2GP SHA (`181bb71a…`) and a code-declared map of ~19 entries (doc 22: capabilities enumerated in code). “Switching Wan builds requires registry surgery” is editing one line and restarting — which you already do for a submodule bump + drain. Multi-binding + admission-time pin is a cloud A/B selector. You will not run WGP build A and B concurrently.

WGP vs VibeComfy for the same type is a real *today* dual path (Grok §3). For v1, hard-pick: WGP for the Wan/travel/join family that already lives there, VibeComfy for the rest. Record what ran as provenance on completion. No post-claim fallback — that part of doc 26 is right, and one binding makes it automatic.

### D4. Custom workflow entry — **REFINE** (snapshots, not a promotion system)

User custom = workflow bytes hashed at admission, digest pinned in `spec_json`. Shipped `reigh.*` = in-repo VibeComfy ready_templates referenced by the code registry. That is two directories, not two runtime objects. “Promote a scratchpad to a template” is `cp` + a YAML file + restart, i.e. git. Building promotion/curation machinery for v1 is how you get a second `task_types` table.

### D5. Custom task definitions — **AGREE** (trim the schema)

Declarative files + one generic VibeComfy handler. No runtime code plugins — Codex §08.3 already rejected dynamic loaders. The owner’s “wrap a Comfy workflow” story is exactly this.

Do not ship the full doc-26 `TaskDefinition` blob to users. User-facing v1: `{id, input ports, workflow path/digest, output policy}`. `availability_probe`, `allowed_origins`, `resolver_id`, `executor_binding_id`, ABI versions belong on shipped entries only. A future manifest loader can implement the same provider interface later; v1 is a directory of YAML.

### D6. Legacy dead types — **AGREE** (harsher)

Reject, do not alias. Codex §16.1 + fresh start (doc 24/25 #8): no historical rows to serve. `edit_travel_flux`, `magic_edit`, `single_image`, underscore `image_upscale`, `image_edit` have no writer. `edit_video_segment` is a live row with no current writer — do not even put it on the child allowlist. WGP catalog keys (`vace*`, `t2v*`, …) and dead specialized handlers (`comfy`, `extract_frame`, …) stay private. Ported types already carry `source_task_type` (`qwen_image_edit`, not `magic_edit`).

---

### Simplest end-state that still hits the owner goals

A code-declared table of the 19 live capabilities as `reigh.<normalized_task_type>` (plus `rendering.timeline_visualize`), each with input schema, output policy, **one** local executor, and a workflow digest when Comfy. Frontend still posts `{family, input}`; the adapter derives the capability. Travel/join/edit keep worker-created children through the same R1 allowlist, parent leased-running, explicit complete/fail. Custom tasks: drop YAML + a workflow into a local dir → `local.<slug>` → generic VibeComfy handler; admission pins the digest. Missing models → `422 capability_unavailable` with a setup hint, never a fallback. No dotted taxonomy, no binding picker, no promotion service, no plugin loader, no kernel yield, no dead-type aliases.

### Missed

1. **One generic `local.workflow.run` vs N `local.*` names.** Easiest custom UX may be *one* capability parameterized by digest + ports. Named `local.*` entries are optional sugar, not the mechanism. Otherwise you rebuild `task_types`.
2. **Who may admit children.** Internal-only child envelope (live parent fence, `parent_task_id`, deterministic key) must be a hard gate. If the browser can R1 `travel_segment`, the allowlist leaks. Not named as a decision.
3. **Orch lease lifetime.** Parent-as-long-lived-attempt vs today’s “In Progress, never re-claimed” is the real cutover risk; design the keeper/crash-replay now.
4. **Model acquisition / availability matrix** (doc 24 P0) is more load-bearing than naming. Advertise only what is installed.
5. **Thumbnails** (doc 24 P0) — cheap local capability, not a generation column. Not in these six.
6. **Pin fewer versions in `spec_json`.** Workflow digest + definition version + model hash change outputs. Pinning ComfyUI/node/ABI/everything on every task is spec bloat; keep the rest on the process manifest.
7. **`family` remains the UI/admission key.** Do not make the editor speak capability strings.

`[INFERENCE]` Structural runs (materialize the whole orch graph at admission) stay deferred — don’t let them leak into v1 contracts.
