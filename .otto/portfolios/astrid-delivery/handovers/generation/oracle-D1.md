> Frozen reference snapshot. Current state and receiving authority are governed by the package START-HERE and authority.md; preserve the existing live run. Paths below are source references, not missing package requirements.

# D1 oracle ruling — proceed

Configured oracle: gpt-5.6-sol, high; native /root/publication_oracle; call 1/3. Planning direction, not implementation certification.

Extend existing fenced Runtime settlement transaction to publish canonical generation/variant rows. Do not use a continuation calling independently committing public create APIs. Reuse internal validation/persistence primitives shared with public commands.

Use one versioned envelope: immutable admitted intent (project, logical groups, modality, permitted selectors, ordering, partial policy), winning-attempt completion provenance/output mappings, and Runtime resolution to canonical verified objects. Executors cannot supply arbitrary project/task/generation/variant/object identities. Keep publication orthogonal to existing project.update effect; no generalized effect framework.

After managed output publication, write domain rows before task/run completion inside the same database transaction. A publication error rolls back domain rows and completion. Content-addressed byte staging can precede this transaction; committed associations and completion must remain atomic.

IDs are task-scoped: generation = task + declared logical group key; variant = generation + original declared output ordinal/key. Attempt/fence are provenance only. Multiple prompts/jobs have explicit groups; never infer groups from file enumeration. Exclude manifests, diagnostics, references and incidental bundle members. Vibe workflows require explicit generative admission; RunPod remains substrate.

Partial success must be admitted explicitly. Publish only successful deliverables with original ordinals and record omitted/failed members in settled result. No empty successful generation. Missing required output, zero successful required groups, failed/cancelled task, stale fence, ownership mismatch or invalid publication means no generation/variant rows. Identical post-commit replay returns existing receipt; changed replay conflicts.

Reuse task.completed event and attempt.settle receipt, adding generation/variant/object mapping to settled result. No dedicated generation-event subsystem unless an actual consumer requires it.

T1–T6 remain normal: T1 defines envelope/identity/partial rules and clients (source: admission/settlement protocol and capability declarations; evidence: grouped multimodal fixtures and rejected mappings); T2 implements atomic shared primitives (source: runtime service/store; evidence: all-or-nothing/replay/crash/stale/failure and preserved effects); T3 host/SDK mapping and managed results (evidence: sync/async caller exit, stable media and explicit timeline); T4/T5 normalize retained adapters with explicit groups and controls after T3; T6 integrated failure and authorized live evidence after T4/T5. Scope/dependencies in tasklist.md remain valid, including declared review gates.

Return only if transaction cannot bind objects/domain rows atomically, task-scoped groups cannot represent retained behavior without schema change, partial policy conflicts with public behavior, orthogonal publication cannot preserve another effect, or provider-resume/GPU migration is proposed as required scope. Otherwise apply ruling. Estimate 5–8 focused engineer-days. No execution/testing/provider authority now.
