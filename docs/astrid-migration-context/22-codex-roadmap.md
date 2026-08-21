# Reigh + Astrid: one authority, one bridge

The proposed end-state is right. I would sharpen it with one rule:

> Astrid SQLite is the only authority for structured state and identity; Astrid’s managed media tree is the authoritative byte store referenced by that schema; `astrid serve` is the only runtime boundary.

A timeline registry entry references a generation/media identity—it is not another generation record. **Amended (doc 24 supersessions; doc 23 §6.1):** the ratified fresh start has no Supabase rollback or data-import phase; Supabase is neither queried nor written by any supported workflow. Earlier recommendations remain commitments except where doc 24 explicitly supersedes them (docs 15, 20, 24).

## 1. The end-state in one picture

```text
┌───────────────────────┐
│ Reigh browser/editor  │
│ content, tasks, CAS   │
│ polling               │
└───────────┬───────────┘
            │ HTTP only
            ▼
┌────────────────────────────────────────────────────────┐
│ astrid serve — one loopback listener                   │
│                                                        │
│ Timeline adapter │ Content adapter │ Task/worker routes│
│                                                        │
│      every mutation → ONE ordered writer queue         │
└───────────────────────┬────────────────────────────────┘
                        │
              ┌─────────┴──────────┐
              ▼                    ▼
     ┌─────────────────┐   ┌────────────────────┐
     │ Astrid SQLite   │   │ Managed media tree │
     │ kernel + packs  │◀─▶│ SHA-256 addressed │
     │ one shared      │   │ authoritative bytes│
     │ schema/identity │   └────────────────────┘
     └─────────────────┘
              ▲
              │ claim/start/heartbeat/stage/
              │ complete/fail with fences
     ┌────────┴─────────────────────┐
     │ Same-host local executors    │
     │ WGP │ VibeComfy │ render     │
     └──────────────────────────────┘
```

A typical day, in ten lines:

**Amended (doc 24 Q1/Q3/Q4):** placement is timeline-document state, generation compute is fully local, and render/export is task-backed.

1. The user opens a project; Reigh reads projects, the timeline document and its shot groups, and the relational gallery through `astrid serve`.
2. Every project, generation, variant, task, and media identity is an Astrid identity; shot groups are document-local structures stored in `timelines.document_json`.
3. The user requests a generation; the editor submits an enumerated capability with an idempotency key.
4. The bridge resolver admits a task—or an atomic run of tasks—into the kernel queue.
5. A same-host worker claims only work matching its declared capabilities.
6. It executes entirely on the machine through an installed WGP/VibeComfy model and node stack while heartbeating its fenced lease.
7. Outputs stream into attempt-scoped quarantine and are hash-verified.
8. Completion atomically records success, media, generation/variant state, events, and the timeline registry merge; it creates no relational placement row.
9. The next poll shows the generation row in the gallery and any pool/clip reference in the timeline document.
10. Editor saves still use whole-document CAS; worker completion cannot overwrite the editor’s current configuration.

## 2. Guiding principles

- **Amended (doc 24 supersessions; doc 23 §6.1): One authority; no hybrid or rollback runtime.** The fresh-start product has no Supabase import, mirror, sync, or rollback authority (docs 14 §1, 20 §13.1).

- **One bridge.** Browser and workers use explicit domain routes on the same listener. There is no generic PostgREST replacement and no direct SQLite access (docs 14 §1, 18).

- **Same-host workers are a release invariant.** Loopback/no-auth trust is valid only while both worker processes run beside `astrid serve`. Remote workers require a later authenticated transport design (docs 15 Q3, 20 §14.3).

- **Amended (doc 24 Q1): Completion is indivisible.** A task cannot be successful unless its outputs, media, generation, variant, events, and required timeline-registry visibility are committed together; relational placement is not part of the transaction because it no longer exists (docs 17 §5, 19 §6, 20 §17.7).

- **Capabilities are enumerated in code.** Port the 13 resolver families and allowlisted dynamic children; do not migrate `task_types` or the route control plane as runtime authorities (docs 16, 20 §16/§19).

- **Amended (doc 24 supersessions; doc 23 §6.1): Start fresh.** Do not build an exporter, replay/import layer, historical archive, or rollback authority; old production data is not carried into the new product.

- **Polling, not push.** Two seconds while active, ten seconds idle, thirty seconds for timelines. SSE is deferred (docs 15 Q7, 20 §18.8).

- **Amended (doc 24 Q1): Keep Reigh concepts out of the kernel.** Generations and variants belong in shots pack v2; shot groups, pools, timing, ordering, and boundary overrides belong in the timeline document. Identity, billing, tenancy, and worker registries do not enter the shots pack (doc 20 §08/§17).

## 3. The roadmap

### Phase 0 — Freeze production truth and retained scope

**Goal:** prevent the build from encoding assumptions contradicted by production.

**Major work:** Close doc 21’s live-authority snapshot and deployed-completion-path gaps. Capture deployed functions, triggers, cron, policies, storage inventory, slot objects, edge versions, environment-controlled behavior, claim responses, and actual completion side effects.

**Amended (doc 24 Q3):** the signed matrix is a **local availability matrix**, not a provider matrix. Every retained capability must map to installed local models, nodes, and executors; Fal/Wavespeed and all other outbound generation providers are cut. Also freeze the generation/editor authority call graph and the completion behaviors that must be ported faithfully (docs 20 §19.10, 21 P0).

**Exit:** dated secret-free production manifest; traced completion path; signed local availability matrix and cut list; contradiction/supersession ledger. Fresh-start means the evidence verifies behavior, not migration predicates (doc 24 supersessions and considerations §7).

**Size:** Medium `[INFERENCE]`.

### Phase 1 — Establish the shared schema and atomic boundary

**Goal:** make Astrid capable of representing Reigh content without another store.

**Amended (doc 24 Q1):** consume only doc 17’s relational generation/variant scope: `generations`, `generation_variants`, events, receipts, the one-primary and unique-media invariants, soft deletion, and atomic completion. Do not implement `shot_generation_items`, relational pair items, shot placement, or relational whole-shot reorder. Shot groups, pools, timing, ordering, and boundary overrides are timeline-document commands saved through CAS. Establish the cross-repository unit of work and internal evented timeline-registry merge ratified in doc 20.

**Amended (doc 24 considerations §2):** decide and, if accepted for Phase 1, implement thumbnails as a separate cheap local task/capability; thumbnails are not generation or placement columns.

This is where doc 21’s atomic-completion P0 gap must close—not during worker rollout.

**Exit:** deterministic schema/bootstrap; generation/variant invariants pass; failure injection after every completion stage produces either the entire result or no result; simultaneous editor save and worker registry merge cannot clobber editor configuration; the thumbnail scope decision is recorded.

**Size:** Large `[INFERENCE]`.

### Phase 2 — Prove the early vertical slice

**Goal:** prove the architecture before expanding it.

Use one production-shaped, non-orchestrated capability—`wan_2_2_t2i` is the strongest candidate because doc 16 maps it to existing worker paths—through the minimum doc-18 routes and a real same-host worker:

```text
editor → admission → claim → execute → stage → atomic complete
       → gallery row + timeline-document pool/clip visibility
editor → render admission → Astrid render task → managed MP4
       → bridge media Range/ETag → browser <video>
```

**Amended (doc 24 Q3/Q4):** run this against a disposable Astrid root, not production. Before generation, prove model/node acquisition, verification, update handling, local-availability gating, and disk-space preflight. Before render, prove the Reigh timeline-document-to-Remotion compatibility layer plus local Node/ffmpeg prerequisites. Use Astrid’s `rendering.render` / `rendering.timeline_visualize` capability path; there is no outbound fallback. This is an architectural proof, not a temporary hybrid mode.

**What it proves:** real payload compatibility; one identity across queue/gallery/timeline; receipt replay after lost acknowledgement; stale-fence rejection; coherent media publication; editor CAS coexistence; two-second polling visibility; managed-MP4 browser playback; prerequisite/setup failure behavior; and no Supabase or outbound-provider dependency for this journey.

**Exit:** repeatable generation and render demos plus duplicate admission, crash/expiry, stale fence, poisoned output, cancellation, concurrent-editor-save, missing-model/node/ffmpeg, and insufficient-disk cases. This also begins doc 21’s executable parity proof.

**Size:** Medium `[INFERENCE]`.

### Phase 3 — Complete the bridge and admission surface

**Goal:** make `astrid serve` the complete supported boundary.

**Amended (doc 24 Q1/Q4):** consume doc 18’s amended R1–R13 contracts and doc 16’s capability map: project and timeline-document reads, relational generation/variant gallery reads, task admission and cancellation, capability-aware queue operations, attempt lifecycle, media serving, typed errors, request limits, polling, and the expiry loop. Shot groups are loaded and saved only through the existing timeline-document CAS routes—there are no shot-placement routes. The task-based render/export family submits a render task, exposes status/cancellation through kernel task routes, then serves the resulting managed MP4 through the existing Range/ETag media-content route. Port retained resolver families, atomic batch-to-run admission, input-media resolution, and allowlisted worker-created children.

Existing timeline load/save CAS semantics remain frozen; only the document model carried through them gains the ratified shot-group structure.

**Exit:** retained doc 16 fixtures match required resolver behavior; unknown or locally unavailable capabilities are rejected with setup guidance; batch and render admission are atomic; receipt, fence, cancellation, expiry, Range/ETag, timeline-CAS, and contract-compatibility tests pass; every mutation reaches the one writer queue.

**Size:** Large `[INFERENCE]`.

### Phase 4 — Port the full worker surface

**Goal:** make both worker repositories bridge-native.

**Amended (doc 24 Q3):** consume doc 19’s per-file cutover, shared bridge client, serialized `LeaseKeeper`, staging flow, keep/delete lists, atomic completion service, and T1–T12 suite. Preserve WGP, VibeComfy, and ratified dynamic orchestration only where execution is fully local. Delete outbound-provider handlers, credentials, routing, retries, and fallbacks. Make model-weight acquisition/verification and required ComfyUI/VibeComfy nodes explicit worker prerequisites alongside the local availability matrix. Remove Supabase transports, retry counters, phantom-claim recovery, route selectors, worker-table heartbeats, and cloud fleet scaling.

**Exit:** representative local WGP, VibeComfy, batch, orchestration, dependency, retry, crash, cancellation, lost-ack, and fence-race cases pass. Neither worker repository contains or needs Supabase or outbound-provider credentials/endpoints. Deployment refuses to start unless workers, installed model/node prerequisites, and `astrid serve` satisfy the same-host invariant.

**Size:** Large `[INFERENCE]`.

### Phase 5 — Cut the application over

**Goal:** make every retained Reigh workflow Astrid-backed.

**Amended (doc 24 Q3/Q4/Q5):** replace remaining PostgREST, RPC, storage, realtime, and edge-function calls with domain clients. Adopt the ratified polling cadence. Ship focused document-native shot mode, local render/export with task progress and managed-MP4 playback, model/node setup and local-availability UX, disk preflight, and always-copy media import with no link-in-place option. Remove excluded account, billing, public, training, agent-session, outbound-provider, and cloud-fleet surfaces.

**Exit:** supported workflows pass with Supabase and outbound-provider networking blocked; browser traffic goes only to `astrid serve`; generation selection, document-native shot ordering, timeline edits, task progress, cancellation, gallery reads, local render/export, managed-media copying, model setup, two-tab CAS, and polling-load gates pass.

**Size:** Large `[INFERENCE]`.

### Phase 6 — Fresh-start release gate

**Amended (doc 24 supersessions; doc 23 §6.1): SUPERSEDED.** The former migration/replay phase is removed.

**Goal:** prove the fresh local product starts and operates without old production data or authority.

**Major work:** exercise clean install, first-run model/node/media setup, project creation, generation, document-native shot editing, render/export, backup/restore, and upgrade paths from an empty local authority. Do not build an exporter, replay layer, historical archive, rollback import, or production-data carryover.

**Exit:** clean-install acceptance passes with Supabase and outbound-provider networking blocked, no legacy credentials, and no old-data dependency.

**Size:** Medium `[INFERENCE]`.

### Phase 7 — Remove legacy product paths

**Amended (doc 24 supersessions; doc 23 §6.1):** this is code-path retirement after fresh-start acceptance, not a rollback-window or data-destruction phase.

Remove Supabase adapters, credentials, edge/worker paths, cron, scaling components, deployment dependencies, outbound-provider code, and any dormant migration/import UI. Retain only the local product’s Astrid backup/restore path.

**Exit:** the product starts and passes acceptance with no Supabase or outbound-provider secret, URL, code path, or network access; Astrid backup recovery succeeds.

**Size:** Medium `[INFERENCE]`.

## 4. How “smooth” is engineered

- The **single writer queue** serializes editor, worker, SDK, and maintenance mutations. Reads use read-only connections.
- **Command receipts** turn lost acknowledgements and duplicate requests into exact replay; changed input under the same key returns `409 idempotency_mismatch`.
- **Leases and fences** ensure only the current attempt can mutate work. Worker death leads to expiry and bounded requeue; an old worker receives a typed conflict and changes nothing.
- The worker’s **`LeaseKeeper`** serializes heartbeat with complete/fail, preventing self-inflicted stale fences.
- Public editor saves use **whole-document CAS**. Completion uses the internal evented registry merge against the current head, preserving editor configuration.
- Bytes are staged and verified before the writer lock. **Atomic completion** commits all authoritative state together; any failure rolls back the transaction and leaves quarantine eligible for cleanup.
- Bridge loss leaves work queued or lease-recoverable. Disk/hash errors cannot create media rows. Polling delay affects freshness, not correctness. Conflicts become explicit retries, never silent overwrites.

## 5. Explicitly out of scope for v1

**Amended (doc 24 Q3/Q5 and supersessions):** credits, balances, Stripe and refunds; Supabase auth/RLS/PATs and multi-user tenancy; public sharing and referrals; training-data management; hosted AI prompt/effect/sequence routes and agent-session history; **all outbound generation providers**; provider-secret setup; cross-device sync/bookmarks/divergence; remote/RunPod workers and autoscaling; link-in-place media; SSE/websockets; all historical data import/replay/archive/rollback work; `task_types` and route-control-plane tables; worker registry/dashboards; hard deletion/media GC; generic table APIs; and a product-facing importer.

There is no outbound-provider exception: fully local compute is a v1 release condition (doc 24 Q3, superseding doc 20 §19.10).

## 6. Top journey risks

**Amended (doc 24 Q1/Q3 considerations):** add local model/disk readiness and timeline-document growth as explicit delivery risks.

| Risk | Mitigation and owner |
|---|---|
| Production differs from the repository | Phase 0 owns the live snapshot and completion trace. |
| Retained capability or authority boundaries remain ambiguous | Phase 0 owns the signed local availability matrix and action-level authority map. |
| Cross-pack completion or registry merge is not truly atomic | Phase 1 blocks further rollout until fault injection and concurrent-save tests pass. |
| Resolver/payload drift breaks real generations | Phases 2–4 own production-shaped fixtures and parity tests. |
| Lease races create duplicate or lost work | Phase 4 owns `LeaseKeeper`, fence, crash, and expiry testing. |
| Model acquisition, node installation, or disk capacity makes a fresh machine unusable | Phases 2, 4, and 5 own download/verify/update, prerequisite checks, disk-space preflight, setup UX, and insufficient-disk recovery (doc 24 Q3 considerations). |
| Shot groups and `poolGenerationIds` push the timeline document toward the 1 MiB input / 4 MiB output bounds | Phase 2 measures realistic large projects; Phase 5 owns a release envelope, with paging/laziness deferred until evidence requires it (doc 24 Q1 considerations). |
| Polling, uploads, hashing, thumbnailing, or rendering overload the single writer/disk | Phases 2 and 5 own contention, disk-full, cleanup, backup, render, and recovery tests. |
| Legacy migration or rollback assumptions leak into the fresh-start product | Phases 5–7 own Supabase-blocked acceptance and removal of import/replay/archive paths (doc 24 supersessions). |

## 7. The first three actions next week

1. **Capture production truth and trace one deployed completion.** Owner-visible outcome: one dated manifest showing exactly what production executes and which generation, media, shot, and timeline changes completion currently makes.

2. **Amended (doc 24 Q1/Q3): Sign the local-v1 capability and authority contract.** Owner-visible outcome: a versioned local availability matrix plus a one-page map naming relational generation/variant authority and timeline-document shot-group authority.

3. **Run the atomic-completion vertical-slice spike.** Owner-visible outcome: a recorded end-to-end demo and failure matrix proving one real generation can travel from editor to worker to gallery and timeline—with no Supabase, reconciliation, stale-fence write, or editor clobbering.
