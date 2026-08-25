# 25 — Ten Bold End-State Statements

1. **The finished product has no login because it is a single-user tool trusted on loopback, not a cloud tenancy system with local mode bolted on.**

   Grounded in: docs 15 Q5 and §Binding decisions, 20 §13.4/§13.9, 22 §2.
   Consequence: Accounts, JWTs, RLS, PATs, sharing, and billing disappear from the supported runtime rather than being reimplemented in SQLite.

2. **The shot editor is a focused view mode of the video editor, with the same document, save path, and undo history—not a second editor.**

   Grounded in: docs 23 §3/§6 and 24 Q1.
   Consequence: Shot-focused UX can remain rich, but it cannot introduce another persistence model or synchronization boundary.

3. **The timeline document is the shot database: shot groups, pools, timing, ordering, and boundary overrides live in `timelines.document_json` and its asset registry inside SQLite.**

   Grounded in: docs 09 §5, 23 §3, 24 Q1.
   Consequence: There are no relational placement rows to normalize, reorder, mirror, or reconcile with the editor document.

4. **Generations are rows; placement is document structure: `generations` and `generation_variants` remain relational while group membership and clip position do not.**

   Grounded in: docs 17, 23 §3/§5, 24 Q1.
   Consequence: Gallery and provenance queries use stable relational identities without creating a second authority for where media appears in the edit.

5. **One Astrid SQLite file is the only database in the end state; the managed media tree stores bytes, not competing structured truth.**

   Grounded in: docs 09, 20 §13.1/§08.5, 22 §1–2.
   Consequence: Neither Supabase, a placement store, nor a worker-owned database may remain on any supported read or write path.

6. **Polling is the realtime model: roughly two seconds while work is active is the promised experience, and SSE or WebSockets are not hidden prerequisites.**

   Grounded in: docs 15 Q7, 20 §13.11, 23 §2, 24 Q6.
   Consequence: Correctness comes from receipts, fences, and timeline CAS; polling changes visibility latency only.

7. **Your machine is the data center: every generation and render executes locally, and no supported capability sends work to Fal, Wavespeed, RunPod, or another outbound provider.**

   Grounded in: docs 15 Q3, 20 §19.10 as superseded, 22 §2/§4, 24 Q3.
   Consequence: A capability without verified local models and nodes is disabled with setup guidance instead of silently falling back to the cloud.

8. **Fresh start means the old Supabase data is gone from the new product by decision, not queued for a later migration.**

   Grounded in: docs 09, 22 Phases 6–7 as superseded, 23 §1/§6, 24 status and remaining consideration 7.
   Consequence: No exporter, replay layer, rollback authority, or historical-data compatibility path belongs in the supported release.

9. **Export is a task, not a browser download trick: Astrid runs Remotion locally, commits an MP4 to managed media, and the browser plays it through the bridge.**

   Grounded in: docs 22, 23 §4/§6, 24 Q4.
   Consequence: Render progress, cancellation, retry, provenance, storage, and playback all use the same task and media contracts as generation outputs.

10. **A thousand-item gallery is a browser delivery problem, not a reason to rebuild shot placement as relational tables.**

    Grounded in: docs 17, 23 §2–3, 24 remaining considerations 2–3.
    Consequence: Solve scale with bounded generation reads, local thumbnail tasks, and measured document-size limits while keeping placement document-native.
