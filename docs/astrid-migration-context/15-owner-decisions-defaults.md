# Owner Decisions — Proposed Defaults for Codex's 7 Questions

Status: **PROPOSED** — owner veto overrides any item. These defaults were drafted to unblock the phase-1 design artifacts (docs 16–19). Rationale cites evidence docs.

Source: doc 14 §"Open questions for the owner". Decision rule used throughout: *local-first, minimal build, no data loss via retained raw exports.*

---

| # | Question | Proposed default | Rationale |
|---|---|---|---|
| Q1 | Are `attempts`/`shot_slots` authoritative product history, or may they be archived rather than imported? | **Archive, do not import.** Keep a read-only JSONL export of `attempts`, `shot_slots`, `slot_first_migration_map` as an audit artifact. Do not map them to kernel `execution_attempts`. | Doc 12 §3.2: the `attempts` TABLE is slot-first *media* attempt history with **no repo migration and no schema_migrations entry** — writers unknown. Importing unmodeled DDL into the kernel fabricates authority. `execution_attempts` becomes the live attempt ledger going forward. |
| Q2 | Should production migration include all historical tasks/generations or only current projects and referenced media? | **Current/active projects only; all referenced media bytes; tasks in terminal states only.** Historical tasks/generations import as latest-state (no `In Progress`). | Local-first tool values current work. Full history multiplies replay risk (45k+ tasks, 84k attempts) for near-zero local value. Live leases cannot be replayed (doc 14: "never import an In Progress task as a live lease"). |
| Q3 | Are all workers guaranteed to run on the same machine for the local release? | **Yes — local-only workers on the same host as `astrid serve`.** Remote/RunPod workers are deferred to a later authenticated/TLS transport phase. | Bridge is localhost + CORS (doc 09); localhost trust cannot serve cloud workers (doc 14 risk). This is the fork that keeps the build small. If this is wrong, stop and redesign transport before anything else. |
| Q4 | Should storage migration import only referenced objects, or every object in `image_uploads`, `timeline-assets`, `render-outputs`? | **Referenced objects only.** Unreferenced bytes stay in the old buckets, cataloged in a manifest, not imported. | v10 migration precedent: 6,793 unreferenced files (~8.5 GB) cataloged-but-dropped (doc 11). SHA-256 content-addressed dedupe re-imports shared bytes cheaply if they later become referenced. |
| Q5 | May public sharing, referrals, training-data management, and timeline-agent session history be explicitly removed from the local product? | **Yes — cut: public/anonymous sharing, referrals, training-data management, timeline-agent session history, credits/Stripe, PATs, Supabase auth/RLS, cloud worker scaling.** | Owner already cut credits (local-only). Everything else on this list is cloud-tenant surface with no local single-user value. `timeline_agent_sessions` is the only borderline item: cut for v1, revisit if the AI timeline agent returns. |
| Q6 | Is latest-state-only timeline migration acceptable if the full Postgres event export is retained separately? | **Yes.** Import latest timeline document (config + registry); retain raw `timeline_events` export as an immutable JSONL audit artifact. Do not forge Astrid events from Postgres events. | Matches doc 14 stance and the bridge's whole-document CAS model (doc 09). Postgres `timeline_events` have ULID ids + their own semantics; replaying them as Astrid events would fabricate history. |
| Q7 | Is 1–2 second active polling acceptable, or is SSE required before cutover? | **Polling: 1–2s while work is active, 5–10s idle, 30s timeline.** SSE deferred. | Local single user, single writer; the bridge already polls at 30s/3s (doc 09). Push adds a realtime channel the single-writer kernel doesn't need yet. |

---

## Binding decisions implied by the defaults

1. **No product importer.** Migration lives under `Astrid/scripts/`, operator-run (v10 pattern, doc 11). Product stays greenfield.
2. **No new auth surface.** Localhost binding + strict CORS + request validation replaces JWT/RLS for the local release. Provider secrets via environment/keychain, never SQLite.
3. **Kernel `execution_attempts` is the only attempt ledger.** The live slot system is archived, not mapped.
4. **`capability` naming normalizes task types** (`image-upscale` → `reigh.image_upscale`), original strings preserved in `spec_json` (doc 14).
5. **Supabase becomes read-only rollback only after cutover**, then retired (doc 14 phase 7).

## Still open (not answerable by defaults)

- Exact cutover date / rollback window length.
- Whether `reigh-worker` and `reigh-worker-orchestrator` both live on the same box as `serve` (Q3 says yes — confirm).
- Retention of old Supabase project after retirement (freeze vs destroy).
