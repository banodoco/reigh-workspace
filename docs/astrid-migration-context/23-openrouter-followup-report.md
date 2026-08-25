# 23 — OpenRouter follow-up: realtime, shot editing, and local-product gaps

**Status:** investigation report, 2026-08-21. The five-agent DeepSeek V4 Flash fan completed 5/5 without timeout (`/tmp/swarm-results/_report.json`). B1 and B2 produced uncaptured first responses and were rerun once as required; citations below use the complete reruns. Swarm sources: [B1 realtime](/tmp/swarm-results/B1_realtime.rerun.txt), [B2 shot features](/tmp/swarm-results/B2_shot_features.rerun.txt), [B3 shot abstraction](/tmp/swarm-results/B3_shot_abstraction.txt), [B4 remaining gaps](/tmp/swarm-results/B4_what_else.txt), [B5 slots review](/tmp/swarm-results/B5_slots_review.txt). Corpus citations use dossier document numbers.

## 1. Executive summary

**F1 — Realtime: keep polling; make it intentional.** Do not add SSE or WebSockets for local v1. The timeline already has the right correctness mechanism: immediate optimistic local state, whole-document CAS save, explicit `409` conflict/lost-ack recovery, and a 30-second safety poll. Task/generation freshness should use React Query at 2 seconds while work is active, 10 seconds when idle, and immediate invalidation when an admission, cancellation, or completion response is observed. Bridge discovery remains 3 seconds only while down/empty. Astrid SDK `subscribe_events` is not reusable realtime infrastructure: it is a synchronous Python iterator that polls legacy run files, not kernel SQLite events and not a browser API (`Astrid/astrid/sdk/events.py`; `core/events/stream.py`; B1). [INFERENCE] A cursor route over kernel `project_seq` is a later load optimization, not an MVP dependency.

**F2 — Shot editor: one editor, one document-native placement model.** Keep generations, variants, media identity, provenance, and the one-primary invariant in SQLite. Move shot grouping, positioned/unpositioned membership, timing, pair/segment overrides, and ordering into the same timeline document and asset registry used by the video editor. “Shot editor” becomes a focused mode/view of that editor, not a child editor and not a second persistence system. This deletes the normalization RPC/trigger family instead of porting it. The swarm split here: B2/B5 retain doc 17's `shot_generation_items`; B3 removes it. The macro verdict follows the owner's simplification goal and chooses B3's placement boundary, while retaining B2/B5's normalized generation/variant authority. [INFERENCE]

**F3 — The remaining risk is product integration, not another schema abstraction.** A shippable local product still needs a production local-mode boot path, task/generation bridge routes and same-host execution, media import/output lifecycle, render/export, provider/model setup, useful error UX, and exposed backup/restore. Astrid already supplies strong primitives for media hashing, fenced tasks, rendering, events, health, and backup; most gaps are bridge/app/installer integration (B4; docs 04–05, 18–22). The owner's fresh-start decision supersedes doc 22's migration/import work: do not build an exporter, replay layer, or rollback archive.

## 2. F1 — Realtime recommendation

### Experience and mechanism

| Surface | Required experience | Mechanism and cadence |
|---|---|---|
| Editor's own timeline changes | Immediate; never wait for transport | Existing optimistic state + debounced bridge save + CAS response. No poll involved. |
| Timeline changes from task completion/another tab | Prompt, conflict-safe | Invalidate timeline/registry immediately when a task becomes terminal; retain 30 s safety poll, refetch on focus/reconnect. A stale save remains `409`, never silent merge. |
| Active tasks/runs/generation outputs | Progress feels live | Poll task/status/progress every 2 s while any task is queued/running; invalidate task, gallery, shot-group and timeline queries on state transition. |
| Idle gallery/status | Fresh without churn | 10 s status, 30 s gallery; pause nonessential background-tab polls and refetch on focus. |
| Bridge startup/recovery | Clear recovery | Existing 3 s health/discovery poll only while the bridge is down or selectors are empty; one full refetch after recovery. |

Today Supabase pushes changes for `tasks`, `generations`, `shot_generations`, `generation_variants`, and `timelines`, while hard polls already cover pending work at 3–5 seconds and timelines at 30 seconds (doc 06 §3.10; `reigh-app/src/shared/realtime/RealtimeConnection.ts`, `shared/hooks/useSmartPolling.ts`, `tools/video-editor/hooks/useTimelineQueries.ts`). The local bridge is polling-only and already exposes strict CAS semantics (doc 09 §§4–6). Docs 15 Q7, 20 §13.11, and 22 §2 ratify polling/no push.

Reuse React Query keys, `DataFreshnessManager`/`useSmartPolling`, bridge health discovery, timeline draft recovery, poll-adoption guards, and `AstridBridgeDataProvider` conflict handling (B1). Replace the Supabase channel with a small local invalidation coordinator driven by task responses and bridge health. Keep IndexedDB timeline drafts; remove `sync_bookmarks`, cross-device “keep both,” and hub/spoke divergence behavior because cross-device sync is cut (doc 20 §13.7; `useEditorSync.ts` already disables it for the Astrid provider).

Build the doc-18 task/content reads and bounded list responses. Do **not** expose SDK `subscribe_events`. [INFERENCE] If polling later becomes measurably expensive, add `GET /projects/:slug/events?after_seq=` over the kernel's gap-free `events.project_seq`; only after that proves insufficient should the bridge stream the same cursor via SSE. WebSockets have no current bidirectional use case.

## 3. F2 — Shot editor inventory and abstraction

### What must survive

B2 found these product capabilities, which align with doc 06 §§3.2–3.3:

- Shot create/name/delete/reorder/duplicate, focused navigation, aspect ratio, and derived counts.
- A per-shot media pool with positioned and unpositioned images; drag, multi-drag, reorder, remove, and frame/contiguity behavior across desktop/mobile.
- Generation families and variants: primary selection, original protection, star/view state, lineage, trim, reposition, and task progress/output.
- Boundary/segment behavior: pair prompts, guidance/model settings, enhanced prompts, segment children/outputs, and travel-between-images.
- Switching a group between source images and a final video, plus optimistic edits and recovery.

The complexity to eliminate is not those features; it is their persistence machinery: `batch_update_timeline_frames`, `reorder_normalized`, `delete_and_normalize`, `unposition_and_normalize`, `demote_orphaned_video_variants`, trigger-synchronized `shot_data`/primary pointers, direct-write fallbacks, and mutable workflow metadata inside placement rows (B2; doc 06 §3.2; `shared/hooks/timeline/`, `shared/hooks/segments/`, `shared/hooks/shots/`).

### Recommended structure

Use one timeline document and one focused shot mode:

```json
{
  "shotGroups": [{
    "id": "shot-local-id",
    "name": "Shot 1",
    "clipIds": ["clip-a", "clip-b"],
    "poolGenerationIds": ["gen-1", "gen-2"],
    "mode": "images",
    "finalVideoAssetKey": null,
    "boundaries": [{"leftClipId": "clip-a", "rightClipId": "clip-b", "overrides": {}}]
  }]
}
```

- The document owns group order, placed `clipIds`, unpositioned `poolGenerationIds`, timing, transitions, and editable boundary overrides. Promote the existing `pinnedShotGroups`/shot-group commands into this stable model rather than inventing another editor (`tools/video-editor/lib/shot-group-commands.ts`, `timeline-domain.ts`). [INFERENCE]
- The asset registry maps each clip asset to `media_id`, `generationId`, and optional `variantId`; selected bytes are explicit and renderable (doc 09 §5; B3/B5).
- SQLite owns `generations` and `generation_variants`, task/media provenance, lineage, stars/viewed state, and atomic primary switching. Task `spec_json` records the immutable submitted pair/travel inputs; the document retains later editable overrides. `generation.record_completion` atomically commits task/output/media/generation/variant, then performs the already-required internal timeline registry/document merge without overwriting editor state (docs 17 §5, 20 §18.5, 22 §§1–4).
- Stats are queries/projections. Duplicate/reorder/unposition are document commands. A “shot editor” is a filtered viewport over one group; it has no separate save, undo stack, or database rows.

This changes doc 17: keep `generations`, `generation_variants`, their events/receipts, primary index, and atomic completion; remove `shot_generation_items` plus placement normalization commands/events. Update docs 18 and 22 so shot writes are timeline saves/internal merges, not relational placement routes. [INFERENCE] Stop using existing `shots`/`shot_items` as Reigh authorities; decide their eventual pack disposition separately rather than mirroring document groups into them.

## 4. F3 — Remaining local-product considerations

| Priority | Gap and minimum outcome | Existing foundation |
|---|---|---|
| **P0** | Production local boot: no required Supabase env/session; one launcher supervises SPA, `astrid serve`, and same-host workers; health/prerequisite screen. | Bridge health/discovery; current local mode is DEV-only (B4). |
| **P0** | Task journey: admission, cancel/read, claim/start/heartbeat/stage/complete/fail, lease expiry, and one real capability end to end. | Kernel fenced tasks; docs 16, 18, 19; roadmap Phase 2. |
| **P0** | Media lifecycle: import by copy (default), explicit link-in-place option, hash/dedupe/probe/thumbnails, staged outputs, broken-link handling, and disk-full behavior. | Managed SHA-256 tree/staging (`Astrid/astrid/core/io/media_import.py`; docs 04–05). |
| **P0** | Render/export: choose and prove one supported MP4 path with progress, cancel, destination selection, and failure recovery. | Astrid `RenderService`/Remotion and Reigh browser render router (B4). |
| **P0** | Retained provider/model contract and secrets setup: local compute versus selected outbound APIs, keychain/env resolution, redaction, model/node checks. | Astrid secrets utilities/model catalog; doc 21 P0.3. |
| **P1** | Error/recovery UX for bridge down, worker unavailable, missing model/media, CAS conflict, lease failure, and disk full; provide doctor output. | Typed bridge errors, draft/409 recovery, `astrid doctor`. |
| **P1** | Backup/restore and project portability exposed in UI/docs; test restore of DB + managed media and clarify credentials are excluded. | Atomic checked backup/restore (doc 04 §5). |
| **P1** | Effects/templates/transition registry audit: retain bundled local entries; hide hosted AI/catalog persistence paths. | Existing video-editor registries; cut list in docs 20/22. |
| **P1** | Polling/upload/render soak tests and explicit CPU/RAM/disk/latency envelope. | Read-only SQLite connections and one writer; doc 21 P1.11. |
| **P2** | Managed-media garbage collection, updater/version UX, diagnostic bundle, and broader platform support. | Staging GC and doctor exist; hard delete/media GC is deliberately deferred (doc 22 §5). |

Append-service replacement is not a new gap: the Astrid bridge already replaces timeline append semantics. Timeline event history, CAS, client undo, backup/restore primitives, asset Range/ETag serving, and built-in effects are also present; they need product wiring and verification, not parallel subsystems (B4; docs 04, 05, 09).

## 5. Slots verdict

**DEFER PACK.** For v1, shot pools and placement are document-only; generation candidacy remains `generation_variants` with one primary. Do not build generic `slots`/`slot_candidates`, do not treat `pool_id` as a server-side candidacy API, and do not map the archived production `shot_slots`/`attempts` system (B5; docs 15 Q1, 17, 20 §17.1). Promotion trigger: a second shipped workflow needs a candidate container that is not a generation family, or a real cross-timeline/project candidate query cannot be served from generation rows plus documents. [INFERENCE]

## 6. How to implement and integrate

1. **Roadmap Phase 0:** ratify the authority map above; freeze the retained capability/provider matrix; amend doc 17/18/22 before implementation. Replace doc 22 Phases 6–7 with a fresh-start release/legacy-removal gate—no exporter, replay, historical archive, or rollback authority.
2. **Phase 1:** implement generations/variants and atomic completion, but remove relational shot placement from doc 17. Formalize `shotGroups`, boundary overrides, registry references, and document commands; fault-test completion versus concurrent editor save.
3. **Phase 2:** prove one task vertical slice including 2-second active polling, media import/output, generation/variant creation, pool/clip visibility, CAS coexistence, crash/expiry, and duplicate acknowledgement.
4. **Phase 3:** finish typed bridge task/content/media routes, cancellation, bounded polling reads, recovery errors, and the local invalidation coordinator. Keep timeline bridge routes compatible.
5. **Phase 4:** port/supervise retained same-host worker paths and model/provider prerequisites; remove Supabase transports and cloud fleet behavior.
6. **Phase 5:** ship bridge-only app boot, focused shot mode, local render/export, secrets setup, backup/restore, onboarding, diagnostics, and Supabase-blocked acceptance tests.

## 7. Open decisions for the owner

1. Ratify document-native shot placement/pools and removal of `shot_generation_items` from doc 17, or retain relational placement and accept two placement authorities.
2. For a group duplicate, should v1 copy only the document structure/media references, or also enqueue/copy generated final-video assets?
3. Which outbound providers remain allowed in “local,” and which capability families are hidden until fully local models/nodes are installed?
4. Choose the supported v1 export path: Astrid Remotion, browser WebCodecs, or both with one explicitly secondary.
5. Default media policy: managed copy for durability with an opt-in external link, or always-copy with no link mode?
6. Is a timeline completion-triggered refresh within roughly 2 seconds sufficient, with SSE explicitly deferred until measured evidence says otherwise?
