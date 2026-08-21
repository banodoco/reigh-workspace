## 08 — Unified-model prior art §5

### Strategic/prior-art

1. **Q:** When is a second agent real? **Recommendation:** Defer until it has a funded owner and two end-to-end journeys; irrelevant to this migration. **Rationale:** v10 generalizes only from demonstrated sameness. Reigh remains Astrid’s first composition [08 §4–5]. **Affects:** Kernel extraction, loaders. **Confidence:** High—explicit rule.

2. **Q:** Publish the kernel? **Recommendation:** Keep it internal until two shipped products consume it. **Rationale:** Reigh will still expose undiscovered seams. Publishing now prematurely freezes APIs [08 §2, §5]. **Affects:** Packaging, versioning. **Confidence:** High.

3. **Q:** Add a dynamic pack loader? **Recommendation:** No; retain explicit application-declared composition. **Rationale:** v10 specifies fixed registration and rejects discovery/hot-loading. The migration needs known in-tree packs [08 §2]. **Affects:** Startup, security. **Confidence:** High.

4. **Q:** Future identity/tenancy location? **Recommendation:** App shell or external service, never the kernel; materially confirms no identity port. **Rationale:** Accounts and tenancy are forbidden kernel concepts. Local scope cuts auth/RLS/PATs [13 §3; 14 §1]. **Affects:** Schema, future remote access. **Confidence:** High.

5. **Q:** Keep media in the kernel? **Recommendation:** Yes; scale bytes through location realms. **Rationale:** SHA-256 media identity is a kernel currency. Tasks, imports, and completion all depend on it [08 §2; 14 §2–3]. **Affects:** Storage, outputs, dedupe. **Confidence:** High.

6. **Q:** Permanent term “media”? **Recommendation:** Keep `media` in code/schema; permit “asset” in UI copy. **Rationale:** The schema vocabulary is established. Renaming offers no semantic benefit [08 §2]. **Affects:** Naming only. **Confidence:** High.

7. **Q:** Generalize the references pack? **Recommendation:** Keep it Astrid-specific until another product proves reuse. **Rationale:** Anticipatory generalization contradicts the master-plan rule. Reigh may use existing semantics without broadening them [08 §4]. **Affects:** Pack APIs. **Confidence:** High.

8. **Q:** Which aggregates get streams/CAS? **Recommendation:** Give timelines and generations aggregate streams; keep shots/references on project streams. **Rationale:** Timelines need document CAS; generations have independent primary/star/delete lifecycles. Other local mutations lack demonstrated concurrency needs [09; 17 §4]. **Affects:** Events, repositories. **Confidence:** Medium-high.

9. **Q:** Pack disable/uninstall behavior? **Recommendation:** Fixed composition, forward-only upgrades, no destructive uninstall. **Rationale:** Imported pack data cannot safely disappear. Rollback belongs to database restore [08 §2; 11]. **Affects:** Migration runner, recovery. **Confidence:** High.

10. **Q:** Manifest stability? **Recommendation:** Freeze an internal v1; promise public compatibility only after extraction. **Rationale:** Deterministic registration matters now. Public stability does not [08 §5]. **Affects:** Conformance tests. **Confidence:** High.

11. **Q:** CLI/bridge mount ownership? **Recommendation:** Composition-owned mounts; preserve eight CLI families and use explicit Reigh domain routes. **Rationale:** This avoids generic table APIs and preserves frozen timeline routes [08 §2; 14 §1]. **Affects:** Routing, contracts. **Confidence:** High.

12. **Q:** Cross-pack dependencies? **Recommendation:** Permit manifest ordering, but exchange through kernel IDs; avoid cross-pack foreign keys. **Rationale:** That is a plugin law. Keeping generation and placement tables together avoids violating it [08 §2.3]. **Affects:** Doc-17 DDL. **Confidence:** High.

13. **Q:** When may the kernel evolve? **Recommendation:** Only for a primitive shared by two real compositions. **Rationale:** Reigh generations and gallery state belong in packs. Kernel additions would be speculative generalization [08 §5; 14 §4]. **Affects:** Kernel stability. **Confidence:** High.

### v10 implementation choices

14. **Q:** Media-root/staging policy? **Recommendation:** `.astrid/media`, managed copies by default, explicit `external_local` opt-in, attempt quarantine before completion. **Rationale:** Generated outputs must remain authoritative if source paths disappear. Staging enables atomic verification [04 §5; 14 §3]. **Affects:** Import, uploads, backup. **Confidence:** High.

15. **Q:** Fan-out bound? **Recommendation:** Kernel ceiling 256 children per command with receipt-linked continuation; resolver limits remain ≤16. **Rationale:** Doc 13 already maps the kernel envelope to 256. Reigh’s narrower limits remain enforced at admission [13 §4.3; 16 §1]. **Affects:** RunsService, receipts. **Confidence:** Medium.

16. **Q:** Closed vocabularies? **Recommendation:** Freeze existing kernel vocabularies; put Reigh-specific terms in pack registries or metadata. **Rationale:** No demonstrated Reigh gap requires widening kernel enums [08 §2; 17 §4]. **Affects:** Registries, completion. **Confidence:** High.

17. **Q:** Supported platform matrix? **Recommendation:** Ubuntu 24.04 x86-64/NVIDIA as canonical all-in-one host; current Chromium; versions pinned by lockfiles. `[INFERENCE]` **Rationale:** Same-host CUDA workers make Linux/NVIDIA the genuine production path. Exact support versions are otherwise absent [03; 15 Q3]. **Affects:** CI, packaging. **Confidence:** Medium.

### Sprint-review questions

18. **Q:** Six-sprint plan? **Recommendation:** Demote it to a theoretical lower bound; retain eight dependency-safe sprints. **Rationale:** The review found unresolved gate inversions. Reigh migration adds further work [08 §4]. **Affects:** Forecast only. **Confidence:** High.

19. **Q:** Three-engineer forecast? **Recommendation:** Use 11–13 sprints and delete the 10–12 headline. **Rationale:** The former is dependency-derived; the latter is inconsistent [08 §4]. **Affects:** Staffing communication. **Confidence:** High.

20. **Q:** Backup receipt conformance? **Recommendation:** Exempt backup/restore from domain receipts; require checksummed manifests, atomic replacement, and restore verification. **Rationale:** Recording a restore receipt inside the restored authority is circular. Doc 11’s operational guards are the appropriate model. **Affects:** Cutover, rollback tests. **Confidence:** High.

## 13 — Migration context §10

1. **Q:** Full migration or hybrid? **Recommendation:** Full Reigh-on-Astrid; no hybrid runtime authority. **Rationale:** That is the stated goal. Supabase is rollback-only after cutover [14 §1, phase 6–7]. **Affects:** Entire build. **Confidence:** High.

2. **Q:** Worker disposition? **Recommendation:** Port GPU worker and API orchestrator to the bridge; retire cloud GPU scaling/capacity reconcilers. **Rationale:** Docs 14 and 19 specify this split. Local executors replace the Supabase fleet. **Affects:** Worker repos, deployment. **Confidence:** High.

3. **Q:** Billing? **Recommendation:** Cut it; archive ledger and Stripe identifiers only. **Rationale:** Billing is explicitly out of scope and forbidden in the kernel [04 §2.4; 14; 15 Q5]. **Affects:** UI, claims, completion. **Confidence:** High.

4. **Q:** Tenancy? **Recommendation:** One user per projects root. **Rationale:** Loopback trust can replace RLS only under single-user ownership [14 §1; 15]. **Affects:** Security, root layout. **Confidence:** High.

5. **Q:** Slot-first attempts? **Recommendation:** Snapshot live DDL/functions and export rows, then archive—not import. **Rationale:** Their writers and provenance are unknown. They are not kernel execution attempts [12 §3.1; 15 Q1]. **Affects:** Export audit. **Confidence:** High.

6. **Q:** Timeline history? **Recommendation:** Import latest documents; retain immutable event JSONL. **Rationale:** Replaying foreign events would fabricate Astrid provenance. The bridge operates on latest-state CAS [09; 11]. **Affects:** Import, history UX. **Confidence:** High.

7. **Q:** Cross-device sync? **Recommendation:** Cut it for v1. **Rationale:** A single local writer makes bookmarks and keep-both divergence unnecessary [08; 14 §1]. **Affects:** IndexedDB sync, divergence UI. **Confidence:** High.

8. **Q:** Media scope? **Recommendation:** Import referenced bytes only; cold-archive everything else with a verified manifest. **Rationale:** v10 omitted roughly 8.5 GB of unreferenced bytes. Content hashing permits later recovery [11 §6; 15 Q4]. **Affects:** Export, storage, retirement. **Confidence:** High.

9. **Q:** Public surfaces? **Recommendation:** Drop sharing, referrals, and anonymous/public semantics; locally import referenced or user-owned presets only. **Rationale:** Hosted public authority has no local equivalent. Useful project inputs should still survive [14 §1; 15 Q5]. **Affects:** Routes, UI, importer. **Confidence:** High.

10. **Q:** Historical task parity? **Recommendation:** Preserve current-project gallery state and only terminal tasks needed for provenance; cut ledger pages and full task history. **Rationale:** Fresh content would lose useful work, while operational history adds little value [14 §4; 15 Q2]. **Affects:** Export filters, screens. **Confidence:** High.

11. **Q:** Realtime? **Recommendation:** Poll: 1–2 seconds active, 5–10 idle, 30 seconds timeline; no SSE. **Rationale:** This matches the local-first default and avoids a new realtime subsystem [09; 15 Q7]. **Affects:** React Query, load tests. **Confidence:** High.

12. **Q:** Recover live drift? **Recommendation:** Yes—snapshot all prod-only migrations and slot DDL before finalizing the exporter. **Rationale:** Live production, not repo migrations, is authoritative [07 §4; 13 §9]. **Affects:** Schema freeze, verification. **Confidence:** High.

13. **Q:** Credit balances/refunds? **Recommendation:** Freeze balances and ledger metadata in the archive; neither recompute nor import them. **Rationale:** Fractional accounting matters only for audit once billing is cut [02 §7; 10 §4]. **Affects:** Retirement audit. **Confidence:** High.

14. **Q:** Route control plane? **Recommendation:** Drop it; use enumerated code-declared capabilities. **Rationale:** Live claims ignore its decisions. Docs 14/16 already define the replacement [12 §5.2; 16 §6]. **Affects:** Claims, worker config. **Confidence:** High.

15. **Q:** Agent/effect/extension surfaces? **Recommendation:** Cut hosted sessions, AI routes, and extension persistence for v1; preserve referenced effect data only inside migrated timeline state. **Rationale:** Runtime Supabase authority is prohibited. Future AI must use local proxies and external secrets [14 §1, §4; 15 Q5]. **Affects:** Feature flags, edge functions. **Confidence:** Medium-high.

## 14 — Codex migration design owner questions

1. **Q:** Import slot attempts? **Recommendation:** Archive, don’t import. **Rationale:** They are unmodeled media history, not retries. Kernel attempts become authoritative [12 §3.1; 15 Q1]. **Affects:** Importer. **Confidence:** High.

2. **Q:** Import all history? **Recommendation:** Active projects and latest content; terminal tasks only where needed for provenance. **Rationale:** This preserves useful work without replaying leases or the operational tail [14 §4; 15 Q2]. **Affects:** Import filters. **Confidence:** High.

3. **Q:** Worker locality? **Recommendation:** Require both worker processes on the `astrid serve` host. **Rationale:** Loopback/no-auth transport depends on it [14 risks; 15 Q3]. **Affects:** Installer, deployment. **Confidence:** High.

4. **Q:** Import every storage object? **Recommendation:** No—referenced objects only; cold-archive the rest. **Rationale:** This matches content-addressed import precedent while preventing irreversible loss [11 §6; 15 Q4]. **Affects:** Storage exporter. **Confidence:** High.

5. **Q:** Remove public/cloud features? **Recommendation:** Yes, including timeline-agent history. **Rationale:** They require tenancy or hosted infrastructure excluded from v1 [14 §1; 15 Q5]. **Affects:** Feature cut list. **Confidence:** High.

6. **Q:** Latest-state timeline migration? **Recommendation:** Yes, with immutable raw event export. **Rationale:** Foreign history must not become fabricated Astrid events [09; 11]. **Affects:** Import, audit. **Confidence:** High.

7. **Q:** Polling or SSE? **Recommendation:** Poll; defer SSE. **Rationale:** Local single-user operation does not justify push infrastructure [09 §3; 15 Q7]. **Affects:** Client invalidation. **Confidence:** High.

## 15 — Owner defaults: still open

1. **Q:** Cutover date/rollback length? **Recommendation:** Cut over only after phase-6 gates; then retain a 14-day read-only rollback window. `[INFERENCE]` **Rationale:** No calendar evidence exists. Two weeks permits workflow validation without indefinite dual authority [14 phases 6–7]. **Affects:** Operations, retirement date. **Confidence:** Low—duration is judgment.

2. **Q:** Are both worker repos colocated? **Recommendation:** Yes; make it a release invariant. **Rationale:** Unauthenticated loopback routes are safe only on the same host [14 risk; 18 §2]. **Affects:** Process supervision. **Confidence:** High.

3. **Q:** Freeze or destroy Supabase? **Recommendation:** Freeze for 14 days, then destroy after verified offline DB/storage/DDL exports. `[INFERENCE]` **Rationale:** Indefinite freeze contradicts full migration; immediate destruction weakens rollback. **Affects:** Secrets, cloud cost, recovery. **Confidence:** Medium.

## 16 — Capability map §9

1. **Q:** Admit legacy resolver-less task types? **Recommendation:** Reject them; archive rows only. **Rationale:** No current writer creates them. Database drift must not become API surface [16 §5–6; 15 Q2]. **Affects:** Allowlist, negative tests. **Confidence:** High.

2. **Q:** Auto-create parent generations? **Recommendation:** Yes, deterministically and transactionally server-side. **Rationale:** Existing callers may provide only `shot_id`. Requiring projection IDs breaks resolver parity [16 §3]. **Affects:** Admission, repositories. **Confidence:** High.

3. **Q:** Preserve worker UUID task IDs? **Recommendation:** Make ULIDs authoritative; retain logical IDs in `spec_json` and claim/log DTOs, without an alias table. **Rationale:** This preserves correlation without creating legacy authority [14 §4; 16 §6]. **Affects:** DTOs, logs. **Confidence:** High.

4. **Q:** Vary seeds for identical `masked_edit` rows? **Recommendation:** No; port identical rows faithfully. **Rationale:** Seed variation is an unrequested behavior change. Change it later under a versioned contract [16 §3.8, fixture L]. **Affects:** Fixtures, hashes. **Confidence:** High.

5. **Q:** Rename turbo-travel capability? **Recommendation:** Keep `reigh.wan_2_2_i2v`; distinguish intent through `family` and `tool_type`. **Rationale:** Capability describes executor ability, not UI intent [16 §1, §3.9]. **Affects:** Worker allowlists. **Confidence:** High.

6. **Q:** Input-manifest coverage? **Recommendation:** Resolve every project-owned media input; reject dangling internal IDs, retain genuine external URLs in params. **Rationale:** Manifests should be authoritative for local bytes [14 §2; 16]. **Affects:** Admission, lineage. **Confidence:** High.

7. **Q:** Who creates orchestrator children? **Recommendation:** Keep allowlisted worker-created admission in v1. **Rationale:** Structural server orchestration is explicitly deferred. Rewriting it during transport cutover increases parity risk [14 §2; 16 §6]. **Affects:** Worker adapter. **Confidence:** High.

8. **Q:** Give orchestrators runs? **Recommendation:** Yes; parent opens a run and dynamic children inherit it with deterministic ordinals. **Rationale:** Runs provide structural grouping without replacing current dynamic creation [08 §2; 16 §1]. **Affects:** RunsService, cancellation. **Confidence:** Medium.

9. **Q:** Promote `params.priority`? **Recommendation:** No; keep kernel priority zero. **Rationale:** Current resolvers do not schedule by it. Promotion would silently alter behavior [16 §1, §8]. **Affects:** Claim order. **Confidence:** High.

10. **Q:** Act on live `task_types` drift? **Recommendation:** Snapshot it as evidence, but make code and fixtures authoritative. **Rationale:** Catalog, seeds, and resolver reality disagree. Importing the table adds no executable capability [16 §5–6]. **Affects:** Export manifest. **Confidence:** High.

## 17 — Pack v2 DDL

1. **Q:** `shots` v2 or new `content` pack? **Recommendation:** Keep `shots` and ship v2 there. **Rationale:** The tables share the shot/composition lifecycle. A new pack adds dependency complexity without an independent lifecycle [17 §1]. **Affects:** Manifest, repositories. **Confidence:** High.

2. **Q:** Model paired shot generations? **Recommendation:** Add nullable `shot_generation_items.pair_item_id` now, with same-shot/distinct-item guards. **Rationale:** Travel and pair operations actively depend on it [06 §3.2; 16 §3.3]. **Affects:** DDL, importer, resolver parity. **Confidence:** High.

3. **Q:** One generation task or join table? **Recommendation:** Keep one producing `task_id`; archive anomalous legacy arrays. **Rationale:** Current completion is singular, while runs/dependencies model orchestration [10 §3; 14 §2]. **Affects:** Provenance queries. **Confidence:** Medium-high.

4. **Q:** Freeze generation vocabularies now? **Recommendation:** No; use repository validation until live distinct values are exported. **Rationale:** Production vocabulary is unverified. Premature CHECKs risk rejecting valid imports [07; 17 §2]. **Affects:** Export probe, later v3. **Confidence:** High.

5. **Q:** Deletion semantics? **Recommendation:** Soft-delete only; no hard delete or media GC in v1. **Rationale:** Astrid lacks safe GC precedent, and variants RESTRICT-pin bytes [17 §2]. **Affects:** Reads, retention. **Confidence:** High.

6. **Q:** Whole-shot reorder? **Recommendation:** Add one atomic permutation command. **Rationale:** Reigh actively uses normalized full-list reorder. Multiple position writes expose intermediate invalid order [06 §3.2; 17 §4]. **Affects:** SDK, bridge, events. **Confidence:** High.

7. **Q:** Atomic completion or reconciliation? **Recommendation:** One composite receipt and one writer transaction. **Rationale:** Partial task/media/generation/placement success is a critical forbidden state [14 §3; 17 §5]. **Affects:** Completion service, retries. **Confidence:** High.

8. **Q:** Dedicated variant-star command? **Recommendation:** No; use `update_variant`. **Rationale:** Starring has no unique invariant or lifecycle. A separate verb adds needless surface [17 §4]. **Affects:** API vocabulary. **Confidence:** Medium-high.

## 18 — Bridge route schemas §17

1. **Q:** Receipt no-work claims? **Recommendation:** No; re-query. **Rationale:** No mutation occurred, and replaying “nothing at T0” could suppress later work [18 §2, §6]. **Affects:** Claim keys, tests. **Confidence:** High.

2. **Q:** Event for staged outputs? **Recommendation:** No event; use a receipt-backed operational staging record. **Rationale:** Quarantine is ephemeral, not project truth. Completion emits durable facts [18 §9–10]. **Affects:** Event registry, GC. **Confidence:** High.

3. **Q:** Where does `aspect_ratio` live? **Recommendation:** `projects.settings_json.aspect_ratio`; surface only known settings plus `default_timeline_id`. **Rationale:** Admission needs aspect ratio, but no new kernel column is justified [10 §2; 18 §13]. **Affects:** Importer, project DTO. **Confidence:** High.

4. **Q:** Keep starvation/model-affinity logic? **Recommendation:** No; use kernel priority/availability ordering. **Rationale:** Explicit capabilities replace model affinity. The old escape hatch has no local purpose [13 §4; 16]. **Affects:** Claim schema. **Confidence:** High.

5. **Q:** Timeline registry update during completion? **Recommendation:** Add an internal registry-merge command that reads the current head, appends an event, and advances `config_version` inside the completion UoW. **Rationale:** Public whole-document save risks clobbering; silent mutation breaks CAS visibility [09; 14 §3]. **Affects:** Timeline repository, editor conflicts. **Confidence:** Medium.

6. **Q:** Freeze cancel and queue-summary routes now? **Recommendation:** Make cancellation normative now; defer queue summary. **Rationale:** Cancellation is functional parity. Summary is an optimization after scaling is cut [14 §4; 18 §15]. **Affects:** App controls, contracts. **Confidence:** High.

7. **Q:** Freeze upload/quota constants? **Recommendation:** Use 2 GiB/request, 64 GiB/attempt, 60-second sweep as configurable defaults—not wire constants. **Rationale:** Lease cadence supports the sweep, but artifact-size evidence is absent [18 §14]. **Affects:** Configuration, 413 tests. **Confidence:** Low-medium.

8. **Q:** App polling cadence? **Recommendation:** Two seconds active, ten seconds idle, thirty seconds for timelines; defer push. **Rationale:** This stays within doc 15 while keeping reads bounded [15 Q7; 18 §2]. **Affects:** React Query. **Confidence:** High.

9. **Q:** Cross-project claim order? **Recommendation:** Use one global query ordered by priority, availability, creation time, then task ID. `[INFERENCE]` **Rationale:** Project iteration can starve later projects. Single-writer atomic selection makes global ordering deterministic [04 §2.4; 14 §3]. **Affects:** Claim repository, fairness tests. **Confidence:** Medium-high.

## 19 — Worker diff §9

1. **Q:** Capability strings/wildcards? **Recommendation:** Enumerate doc-16 `reigh.<normalized_task_type>` strings; no wildcards or backend names. **Rationale:** Enumeration prevents unsupported claims and makes eligibility auditable [16 §5–6]. **Affects:** Worker configuration. **Confidence:** High.

2. **Q:** Bridge port/listener? **Recommendation:** Standardize loopback port 17333 and serve all routes on one listener. **Rationale:** The editor/Vite contract already uses 17333. Port zero is test construction only [09; 18 §1]. **Affects:** CLI, `ASTRID_BRIDGE_URL`. **Confidence:** High.

3. **Q:** Multi-repository completion UoW? **Recommendation:** Make it mandatory; refactor repositories if necessary. **Rationale:** Follow-on projections violate strict completion atomicity [04 §2.4; 14 §3]. **Affects:** Composition root, tests. **Confidence:** High.

4. **Q:** Worker timeline-registry mutation? **Recommendation:** Use the internal evented registry merge from doc-18 Q5, never public full-document save. **Rationale:** It preserves atomic requested placement without clobbering editor state [09; 19 §6]. **Affects:** Completion B4. **Confidence:** Medium.

5. **Q:** Staging transport? **Recommendation:** Streaming `multipart/form-data`, attempt-scoped quotas, GC on terminal/expiry plus periodic orphan cleanup. **Rationale:** It supports metadata and large files while hashing during streaming [18 §9; 19 §5]. **Affects:** Client, disk management. **Confidence:** Medium-high.

6. **Q:** Executor observability? **Recommendation:** No worker table or separate executor heartbeat; use attempt heartbeat/progress and local logs. **Rationale:** Lease liveness already exists, and fleet management is cut [14 §3–4]. **Affects:** Guardian, dashboards. **Confidence:** High.

7. **Q:** `progress_json` shape? **Recommendation:** `{schema_version, phase, completed, total, percent, message?, eta_seconds?, metrics?}`; never store output locations. `[INFERENCE]` **Rationale:** A versioned bounded shape replaces overloaded status writes while keeping outputs authoritative elsewhere [04 §3.9; 19 §3]. **Affects:** App cards, heartbeat DTO. **Confidence:** Medium.

8. **Q:** Shared bridge client? **Recommendation:** One local workspace package for both worker repos; retain `shadow_side_effects` as its conformance harness. `[INFERENCE]` **Rationale:** Duplicating fencing and retry logic invites protocol drift [14 §3; 19 §5]. **Affects:** Packaging, CI. **Confidence:** Medium.

9. **Q:** Preserve `max_task_wait_minutes`? **Recommendation:** Drop it. **Rationale:** The removed model-affinity system was its purpose. Kernel ordering plus capabilities is sufficient [13 §4; 18 Q4]. **Affects:** Claim DTO, worker env. **Confidence:** High.

10. **Q:** Keep cloud-API task types? **Recommendation:** Keep active resolver-mapped Fal/Wavespeed capabilities in the local API orchestrator. **Rationale:** Local-only constrains persistence and worker placement, not outbound provider calls; secrets remain external [14 §1, §3; 16 §5]. **Affects:** Allowlist, credentials, tests. **Confidence:** High.

Implementation correction: doc 18’s normative attempt-number routes and opaque `staging_key` should override doc 19’s pseudocode that exposes `attempt_id`/`staging_txn_id`.

## Highest-leverage decisions

1. **Strict atomic completion** (17.7, 18.5, 19.3–4): determines repository boundaries and whether task success is trustworthy.
2. **Same-host worker cutover with no hybrid authority** (13.1–2, 14.3, 15.2): fixes transport, security, and deployment architecture.
3. **Selective migration plus immutable cold archive** (13.5, 13.8, 14.1–4): controls migration complexity and irreversible-loss risk.
4. **Enumerated capability admission with dynamic worker children retained for v1** (16.1, 16.7–8, 19.1): controls resolver and worker parity.
5. **Live-schema freeze before exporter implementation** (13.12): prevents repo/prod drift from corrupting the migration.

## Overrides of doc 15

One explicit override/refinement: doc 15 Q4 leaves unreferenced bytes in old Supabase buckets. Keep them there only during rollback; before destroying Supabase, copy them into a verified offline cold archive. Astrid still imports referenced bytes only.

No other recommendation contradicts doc 15.
