## P0 — must-have before direction is trustworthy

1. **[Evidence + Artifact] Reproducible live-authority snapshot** → The corpus omits full bodies for 202 functions, complete views/policies, out-of-band slot/referral/agent-node DDL, deployed edge-function versions, and several environment-controlled behaviors. Repo and production already disagree on claim gating. Without this, the design may preserve dead behavior or omit live behavior. → Export `pg_get_functiondef`, `pg_get_viewdef`, `pg_get_triggerdef`, `pg_policies`, constraints, publication membership, `cron.job`, `storage.buckets`, and `supabase_migrations.schema_migrations`; record `supabase functions list --project-ref wczysqzxlwdndgxitrvc`. Prioritize `claim_next_task_*`, `complete_task_with_timing`, generation triggers, timeline RPCs, and every `slot_first_*` object. Write a dated, secret-free schema/deployment manifest and correct doc 07’s false “no reverse drift” claim.

2. **[Evidence] Actual deployed task-completion path** → `CREATE_GENERATION_IN_EDGE` decides whether completion materializes generations in edge code or through `create_generation_on_task_complete`; claim responses may also omit fields workers expect. These change what must be ported. → Capture sanitized deployed environment-name/value-class evidence, edge bundle commit hashes, and live trigger definitions. Replay a disposable completion while tracing `tasks`, `generations`, `generation_variants`, `shot_generations`, storage, and timeline changes. Verify whether deployed `claim-next-task` returns `attempts`, `claimed_backend`, `selected_backend`, and `claim_decision_reason`.

3. **[Context + NEW decision] Retained local-v1 capability contract** → “Local-only” does not say whether only authority/workers are local or whether outbound Fal, Wavespeed, Fireworks, Anthropic, Groq, Banodoco, and similar services are forbidden. Nor does doc 15 decide whether AI prompt/effect/sequence functionality survives. This determines most of the supported product. → Read:

   - `reigh-app/supabase/functions/{ai-prompt,ai-generate-effect,ai-generate-sequence,ai-generate-sequence-component,ai-timeline-agent}/`
   - `ai-timeline-agent/tools/delegateToBanodocoAgent.ts`
   - `reigh-worker-orchestrator/api_orchestrator/{task_handlers.py,handlers/,fal_utils.py,wavespeed_utils.py}`

   Owner decision: **local authority with selected outbound providers** versus **fully local compute**, followed by a versioned capability/model matrix. This is new beyond doc 14’s seven questions.

4. **[Context + NEW decision] User-visible generation/editor authority model** → The corpus inventories relational shots/generations and the JSON video-editor timeline, but does not explain their synchronization during generate, variant selection, drag/reorder, render, agent edits, and worker completion. Archiving slot history is unsafe until its role in current primary/lineage selection is understood. → Produce action-level call graphs from `complete_task`, generation/shot hooks, `renderRouter.ts`, timeline queries, `effects/`, `sequences/`, and the external append service. Decide whether the relational shot timeline and JSON timeline are both authorities or whether one becomes a projection.

5. **[Decision + Process] Atomic completion and timeline-CAS strategy** → Docs 17–19 leave two architecture-critical questions open: whether task completion, media rows, generation projection, placement, and events can share one `BEGIN IMMEDIATE`; and whether worker completion mutates the timeline through full-document CAS, a registry-only command, or leaves it to the editor. Partial commits or a background save could corrupt or clobber editor state. → Spike a cross-repository command using Astrid’s writer/UoW; inject failure after every stage. Then test simultaneous editor save and worker completion. Record an ADR covering filesystem staging, DB commit, cleanup/reconciliation, and timeline visibility.

6. **[Evidence + NEW decision] Cutover corpus and in-flight-work policy** → “Current/active projects,” “terminal tasks only,” and “referenced media” are not executable selection rules. Queued/running tasks, missing objects, failed/cancelled generations, slug collisions, unresolved URLs, and source-ID retention remain unspecified. → Run exact counts, `tasks.status` distributions, FK/orphan checks, distinct generation/variant types, and a storage reachability/size inventory. Decide: drain/cancel/resume in-flight work; abort/placeholder/skip missing media; UUID→ULID/source-ID policy; and exact project inclusion predicate.

7. **[Artifact + Process] Executable parity proof** → Doc 16 lists 14 fixture designs and doc 19 lists T1–T12, but no fixture corpus, exporter, or end-to-end run exists. → Capture sanitized production-shaped requests/responses for every resolver family and representative gallery/timeline operations. Build a comparison harness for current resolver output versus Astrid task/run rows. Run vertical slices for one WGP, one VibeComfy, and one API task, including lost acknowledgements, stale fences, expiry, cancellation, poisoned output, dependency unblocking, and duplicate completion.

## P1 — should-have before build starts

8. **[Context] Full worker, model, and deployment topology** → RunPod provisioning, model download/cache selection, Railway services, Vite production configuration, Banodoco enqueue, and API-provider output handling are only summarized. → Read `gpu_orchestrator/runpod/`, both `railway.json` files, Docker/startup scripts, worker `TaskRegistry`, model/profile manifests, and `renderRouter.ts`; write one deployment/dataflow and secrets-boundary document.

9. **[Artifact + Process] Production-shaped exporter dry run** → No Postgres/storage exporter or tested Reigh replay exists; even the older v10 importer has not demonstrated a real `--apply` plus `verify.py`. → Build deterministic JSONL/source-hash manifests, storage manifests, and UUID maps; replay one anonymized but complex project into a disposable DB. Report counts, hashes, FKs, lineage, primary variants, receipt replay, event chains, and representative UI-query parity.

10. **[NEW decision] Queue/orchestration contract** → Capability names, dynamic worker-created children versus structural runs, UUID visibility, cross-project fairness, starvation/model affinity, progress schema, cancellation guarantees, and no-work claim receipts remain open across docs 16–19. → Trace `add_task_to_db` and current cancel/progress consumers; freeze a versioned identity/capability/queue contract before implementing bridge clients.

11. **[Process] Capacity, contention, and recovery evidence** → Aggressive polling, heartbeats, large uploads, hashing, backups, and one writer may interact badly. → Soak-test realistic queue/gallery polling, large video staging, lease expiry, writer crash, disk-full cleanup, backup/restore, and concurrent claims. Set measurable latency, throughput, disk, and recovery gates.

12. **[Artifact] Decision and contradiction ledger** → Doc 15 defaults remain merely proposed; docs also retain known contradictions and the now-obsolete claim that the implementation-decisions file is absent. → Ratify defaults, add provenance/status/verification per decision, and maintain a supersession ledger covering docs 01–19 and [Astrid’s existing decision artifact](/Users/peteromalley/Documents/reigh-workspace/Astrid/docs/astrid-v10-implementation-decisions.md).

## P2 — useful completeness

13. **[Context] Deferred cloud/history dossiers** → Even if cut from v1, cross-device sync, RunPod provisioning, public sharing, referrals, agent-session history, and Railway scaling need concise disposition records so “deferred” is not mistaken for “irrelevant.” → Document dependencies, retained exports, and conditions for reintroduction.

14. **[Evidence cleanup] Secondary unknowns** → Verify the 8.5 GB estimate, 210 unresolved references, collision paths, dead refund/thumbnail/status code, FSA and legacy Supabase module deadness, `timelines copy`, and render/understanding E2E behavior.

If you could only obtain three things, they would be…

1. A complete, reproducible live schema/deployment/runtime snapshot.
2. A signed retained-capability decision plus generation/editor authority call graph.
3. A production-shaped Postgres→Astrid dry run with end-to-end worker and parity evidence.
