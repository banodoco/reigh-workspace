# Reigh + Astrid: one authority, one bridge

The proposed end-state is right. I would sharpen it with one rule:

> Astrid SQLite is the only authority for structured state and identity; Astrid’s managed media tree is the authoritative byte store referenced by that schema; `astrid serve` is the only runtime boundary.

A timeline registry entry references a generation/media identity—it is not another generation record. Supabase may temporarily remain read-only for rollback, but after cutover it is neither queried nor written by any supported workflow. The 87 ratified recommendations are commitments, not questions to reopen (docs 15, 20).

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
     │ Same-host workers            │
     │ WGP │ VibeComfy │ API worker │
     └──────────────────────────────┘
```

A typical day, in ten lines:

1. The user opens a project; Reigh reads projects, shots, gallery, and timeline through `astrid serve`.
2. Every project, shot, generation, variant, task, and media identity is an Astrid identity.
3. The user requests a generation; the editor submits an enumerated capability with an idempotency key.
4. The bridge resolver admits a task—or an atomic run of tasks—into the kernel queue.
5. A same-host worker claims only work matching its declared capabilities.
6. It executes through WGP, VibeComfy, or a retained outbound provider while heartbeating its fenced lease.
7. Outputs stream into attempt-scoped quarantine and are hash-verified.
8. Completion atomically records success, media, generation/variant, placement, events, and the timeline registry merge.
9. The next poll shows the same generation row in the gallery and its placement in the timeline.
10. Editor saves still use whole-document CAS; worker completion cannot overwrite the editor’s current configuration.

## 2. Guiding principles

- **One authority; no hybrid runtime.** Supabase becomes rollback-only after cutover, then disappears. There is no mirror or sync layer (docs 14 §1, 20 §13.1).

- **One bridge.** Browser and workers use explicit domain routes on the same listener. There is no generic PostgREST replacement and no direct SQLite access (docs 14 §1, 18).

- **Same-host workers are a release invariant.** Loopback/no-auth trust is valid only while both worker processes run beside `astrid serve`. Remote workers require a later authenticated transport design (docs 15 Q3, 20 §14.3).

- **Completion is indivisible.** A task cannot be successful unless its outputs, media, generation, variant, placement, events, and required timeline visibility are committed together (docs 17 §5, 19 §6, 20 §17.7).

- **Capabilities are enumerated in code.** Port the 13 resolver families and allowlisted dynamic children; do not migrate `task_types` or the route control plane as runtime authorities (docs 16, 20 §16/§19).

- **Import selectively; archive immutably.** Import active projects, useful terminal provenance, latest timeline state, and referenced bytes. Archive slot-first history, foreign timeline events, billing records, rejected history, complete live DDL, and all unreferenced bytes (docs 15, 20 §13.8 and Q4 refinement).

- **Polling, not push.** Two seconds while active, ten seconds idle, thirty seconds for timelines. SSE is deferred (docs 15 Q7, 20 §18.8).

- **Keep Reigh concepts out of the kernel.** Generations, variants, and placements belong in shots pack v2. Identity, billing, tenancy, and worker registries do not (doc 20 §08/§17).

## 3. The roadmap

### Phase 0 — Freeze production truth and retained scope

**Goal:** prevent the build from encoding assumptions contradicted by production.

**Major work:** Close doc 21’s live-authority snapshot and deployed-completion-path gaps. Capture deployed functions, triggers, cron, policies, storage inventory, slot objects, edge versions, environment-controlled behavior, claim responses, and actual completion side effects.

Ratification resolves the policy direction for the retained-capability gap: local authority and same-host workers may still call active resolver-mapped providers such as Fal/Wavespeed, while hosted prompt/effect/agent-session surfaces are cut. This must now become a signed, versioned capability/model matrix. Also freeze the generation/editor authority call graph and executable definitions of “active project,” “referenced media,” and in-flight-work handling (docs 20 §19.10, 21 P0).

**Exit:** dated secret-free production manifest; traced completion path; signed capability matrix and cut list; exact migration predicates; contradiction/supersession ledger.

**Size:** Medium `[INFERENCE]`.

### Phase 1 — Establish the shared schema and atomic boundary

**Goal:** make Astrid capable of representing Reigh content without another store.

**Major work:** Consume doc 17’s shots-pack-v2 specification: generations, variants, shot placements, events, receipts, primary invariants, pair-item refinement, soft deletion, and atomic whole-shot reorder. Establish the cross-repository unit of work and the internal evented timeline-registry merge ratified in doc 20.

This is where doc 21’s atomic-completion P0 gap must close—not during worker rollout.

**Exit:** deterministic migration/replay; schema invariants pass; failure injection after every completion stage produces either the entire result or no result; simultaneous editor save and worker registry merge cannot clobber editor configuration.

**Size:** Large `[INFERENCE]`.

### Phase 2 — Prove the early vertical slice

**Goal:** prove the architecture before expanding it.

Use one production-shaped, non-orchestrated capability—`wan_2_2_t2i` is the strongest candidate because doc 16 maps it to existing worker paths—through the minimum doc-18 routes and a real same-host worker:

```text
editor → admission → claim → execute → stage → atomic complete
       → gallery + shot + timeline visibility
```

Run this against a disposable Astrid root, not production. It is an architectural proof, not a temporary hybrid mode.

**What it proves:** real payload compatibility; one identity across queue/gallery/timeline; receipt replay after lost acknowledgement; stale-fence rejection; coherent media publication; editor CAS coexistence; two-second polling visibility; and no Supabase dependency for this journey.

**Exit:** repeatable demo plus duplicate admission, crash/expiry, stale fence, poisoned output, cancellation, and concurrent-editor-save tests. This also begins doc 21’s executable parity proof.

**Size:** Medium `[INFERENCE]`.

### Phase 3 — Complete the bridge and admission surface

**Goal:** make `astrid serve` the complete supported boundary.

**Major work:** Consume doc 18’s R1–R12 contracts and doc 16’s capability map: all project/shot/gallery/media reads, task admission and cancellation, capability-aware queue operations, attempt lifecycle, media serving, typed errors, request limits, polling, and the expiry loop. Port all 13 resolver families, atomic batch-to-run admission, input-media resolution, and allowlisted worker-created children.

Existing timeline routes and CAS remain frozen.

**Exit:** doc 16’s 14 golden fixtures match current resolver behavior; unknown capabilities are rejected; batch admission is atomic; receipt, fence, cancellation, expiry, Range/ETag, and contract-compatibility tests pass; every mutation reaches the one writer queue.

**Size:** Large `[INFERENCE]`.

### Phase 4 — Port the full worker surface

**Goal:** make both worker repositories bridge-native.

**Major work:** Consume doc 19’s per-file cutover, shared bridge client, serialized `LeaseKeeper`, staging flow, keep/delete lists, atomic completion service, and T1–T12 suite. Preserve WGP, VibeComfy, API handlers, and ratified dynamic orchestration. Remove Supabase transports, retry counters, phantom-claim recovery, route selectors, worker-table heartbeats, and cloud fleet scaling.

**Exit:** representative WGP, VibeComfy, API, batch, orchestration, dependency, retry, crash, cancellation, lost-ack, and fence-race cases pass. Neither worker repository needs Supabase credentials or endpoints. Deployment refuses to start unless workers and `astrid serve` satisfy the same-host invariant.

**Size:** Large `[INFERENCE]`.

### Phase 5 — Cut the application over

**Goal:** make every retained Reigh workflow Astrid-backed.

**Major work:** Replace remaining PostgREST, RPC, storage, realtime, and edge-function calls with domain clients. Adopt the ratified polling cadence. Remove excluded account, billing, public, training, agent-session, and cloud-fleet surfaces.

**Exit:** supported workflows pass with Supabase networking blocked; browser traffic goes only to `astrid serve`; generation selection, shot ordering, timeline edits, task progress, cancellation, gallery reads, two-tab CAS, and polling-load gates pass.

**Size:** Large `[INFERENCE]`.

### Phase 6 — Rehearse migration, migrate, and cut over

**Goal:** carry useful production state into the new authority without importing obsolete authority.

**Major work:** Use live production—not repository migrations—as source truth. Reuse doc 11’s operator-only patterns: deterministic JSONL, hashes, UUID→ULID maps, receipt-keyed SDK replay, empty-target guard, exclusive lock, backup, and verification.

Drain or resolve in-flight work. Import active projects, referenced media, useful terminal provenance, generations, variants, placements, and latest timeline documents. Preserve immutable archives for slot tables, raw timeline events, billing/Stripe metadata, excluded history, full schema/runtime evidence, and unreferenced storage bytes.

**Exit:** production-shaped rehearsal and final replay pass counts, hashes, FKs, lineage, primary uniqueness, receipt replay, event chains, media reachability, and representative UI queries. Supabase becomes read-only rollback only.

**Size:** Large `[INFERENCE]`.

### Phase 7 — Retire the legacy authority

**Goal:** make the one-authority posture operationally final.

After the ratified 14-day rollback window, remove Supabase adapters, credentials, edge/worker paths, cron, scaling components, and deployment dependencies. Before destruction, restore-sample the offline DB/DDL/storage archives, including the Q4 cold archive.

**Exit:** the product starts and passes acceptance with no Supabase secret, URL, or network access; Astrid backup recovery succeeds; cold-archive sampling succeeds.

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

Credits, balances, Stripe and refunds; Supabase auth/RLS/PATs and multi-user tenancy; public sharing and referrals; training-data management; hosted AI prompt/effect/sequence routes and agent-session history; cross-device sync/bookmarks/divergence; remote/RunPod workers and autoscaling; SSE/websockets; full task, timeline, or slot-history import; `task_types` and route-control-plane tables; worker registry/dashboards; hard deletion/media GC; generic table APIs; and a product-facing importer.

Selected outbound generation providers remain allowed through the same-host API worker (doc 20 §19.10).

## 6. Top journey risks

| Risk | Mitigation and owner |
|---|---|
| Production differs from the repository | Phase 0 owns the live snapshot and completion trace. |
| Retained capability or authority boundaries remain ambiguous | Phase 0 owns the signed matrix and action-level authority map. |
| Cross-pack completion or registry merge is not truly atomic | Phase 1 blocks further rollout until fault injection and concurrent-save tests pass. |
| Resolver/payload drift breaks real generations | Phases 2–4 own production-shaped fixtures and parity tests. |
| Lease races create duplicate or lost work | Phase 4 owns `LeaseKeeper`, fence, crash, and expiry testing. |
| Polling, uploads, or hashing overload the single writer/disk | Phases 2 and 5 own contention, disk-full, cleanup, backup, and recovery tests. |
| Migration predicates omit state or media | Phase 0 owns inventory/rules; Phase 6 owns deterministic handling and manifests. |
| Retirement makes missing data irreversible | Phase 6 keeps rollback read-only; Phase 7 requires cold-archive verification and restore sampling. |

## 7. The first three actions next week

1. **Capture production truth and trace one deployed completion.** Owner-visible outcome: one dated manifest showing exactly what production executes and which generation, media, shot, and timeline changes completion currently makes.

2. **Sign the local-v1 capability and authority contract.** Owner-visible outcome: a versioned retained-capability/provider matrix plus a one-page map naming the authority for generation, variant, shot, and timeline mutations.

3. **Run the atomic-completion vertical-slice spike.** Owner-visible outcome: a recorded end-to-end demo and failure matrix proving one real generation can travel from editor to worker to gallery and timeline—with no Supabase, reconciliation, stale-fence write, or editor clobbering.
