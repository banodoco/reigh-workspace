**Verdict:** the end-state is right (one SQLite, loopback, local compute, document-native shots, polling). The *plan* still designs a cloud executor, a data-migration program, and a second kernel. Ceremony that protects crash-safe completion stays. Ceremony that protects a future we cut goes.

---

### 1. **Cut** — Phase 0 live-prod archaeology + importer/rollback as journey work
**Where:** 22 Phase 0/6–7 (even after “superseded”), 14 §4 “Production-data migration”, 15 Q1–Q2/Q4/Q6, 20 highest-leverage #3/#5, 21 P0.1/P0.2/P0.6/P1.9, 13 §8–11, 11 v10 scripts as product-adjacent.

Fresh start is ratified (24 remaining §7, 25 #8, 23 §6.1). Then the roadmap still opens with “dated secret-free production manifest,” “traced completion path,” live function/trigger/cron dumps, and cold-archive of unreferenced bytes before destroying Supabase. That is a different product.

**Simplest:** freeze 24+25 as constitution. Phase 0 = local availability matrix + one completion-behavior note from *code* (what `complete_task` actually writes). Operator dump of prod, if anyone wants it, lives outside the product. No exporter, no JSONL audit artifacts, no 14-day rollback, no `reigh-import:v1:*` keys.

**Saves:** a research program before any local t2i works. [INFERENCE] weeks.

---

### 2. **Simplify** — six-step fenced attempt protocol → claim / heartbeat / complete
**Where:** 18 R3–R8, 14 §3, 19 §2/§5, kernel `claimed→running` plus `status_version` on every beat.

Today’s Reigh claim is a status flip with no TTL; three cloud sweeps recover it (12). Astrid already has 300s leases. The plan then adds: claim → start (allocates staging URL) → heartbeat (bumps version, no receipt) → outputs (quarantine, receipted) → complete/fail, every mutation carrying `lease_id` + `status_version`, plus `LeaseKeeper` so heartbeat cannot race complete.

On **one same-host worker**, the real failures are: process death, poisoned bytes, lost HTTP ack on complete. They do not require a two-state attempt (`claimed` vs `running`) or a version counter that exists so a concurrent heartbeat can invalidate completion.

**Simplest:** `POST /queue/claim` creates a leased attempt (`running` immediately). Heartbeat extends the lease and may carry `progress`. `POST …/complete` is multipart: files + fence; server hashes, then one `BEGIN IMMEDIATE` (task + media + generation). `POST …/fail`. Expiry loop already requeues. Keep a mutex around heartbeat vs complete — that is ~30 lines, not a protocol.

**Keep:** lease + expiry (crash), receipt on **admission and complete** (lost ack), atomic complete (14’s actual critical risk).

**Saves:** R4 and R6 as routes; `staging_txn_id` / `upload_url` indirection; fence-error encyclopedia (`stale_status_version`, `lease_mismatch`, `attempt_not_live`, `lease_expired`, `task_terminal`, `attempt_budget_exhausted`). T3/T4/T8 become one crash-expiry test.

---

### 3. **Cut** — Doc 26 taxonomy / TaskDefinition blob / aliases / multi-binding
**Where:** 26 §§Identity/Custom/Owner 1,3; conflicts with 16, 20 §19.1, and grok/second-opinion-decisions D1/D3/D4/D5.

Already ratified: flat `reigh.<normalized_task_type>`, one binding, no wildcards, no plugin loader. Doc 26 then proposes `reigh.image.generate.wan.t2i`, aliases, `contract_version`, promotion, “multiple installed bindings, admission pins one,” and a user-facing `{availability_probe, allowed_origins, resolver_id, executor_binding_id, ABI…}` blob. That is a cloud catalog. Grok already rejected it.

**Simplest:** code table of the ~19 live types + `rendering.timeline_visualize`. Custom = YAML `{id, ports, workflow path, digest}` → `local.<slug>` or one `local.workflow.run`. Pin digest + model hash in `spec_json`. Process-level Wan SHA / Comfy nodes live in a boot manifest, not every task. Dead types (`edit_video_segment`, underscore `image_upscale`, …): reject, do not alias (fresh start).

**Saves:** a naming migration across claim allowlists, fixtures, and UI; a second `task_types` table.

---

### 4. **Shrink** — 26-doc living corpus + 8-phase gated journey
**Where:** README reading order, 22 Phases 0–7, 20 (87 recs), 21 (P0–P2), 23 swarm, 26 restating 16.

The constitution is three short docs: 15, 24, 25. Everything else is evidence, a first design, or a consultation. Specs 16–19 still contain `shot_generation_items`, Fal/Wavespeed keep-lists, B3 placement, import keys — with “Amended (doc 24)” stickers rather than a rewrite. Phase 3 “complete the bridge” and Phase 4 “port the full worker” are the same cutover, sequenced as if a fleet were rolling out.

**Simplest:** one working spec (~15 pages): routes that survive item 2, generations DDL, capability table, worker client, vertical-slice exit. Archive 01–13. Rewrite 16–19 or mark them historical. 20/21/26 are not authorities. Phases: (A) t2i + render slice, (B) remaining local caps + orch children, (C) app cutover. Stop writing supersession ledgers.

**Saves:** the next agent re-deriving the product from 26 files.

---

### 5. **Simplify** — generation pack as event-sourced aggregate
**Where:** 17 §3: stream `generation.generation`, 9 event kinds, 10 command kinds, receipt on star/unstar; 20 §08.8 “generations get streams/CAS.”

Gallery needs rows, one-primary, lineage, soft-delete, and **one** completion command in the task txn. Star/viewed_at do not need hash-chained events or their own stream. Kernel events/receipts are inherited discipline for *kernel* commands (timeline CAS, task complete). Copying that onto every `generation.starred` is plugin-law cosplay.

**Simplest:** two tables + `record_completion` inside the task UoW. Star/primary/delete = small pack commands *or* even SQL in that same writer callback. No per-generation stream until a second writer exists (it won’t).

**Keep:** one-primary unique index, media RESTRICT, completion atomicity.

**Saves:** registry wiring, m4_gate 20→22 theater, 9× event fixtures.

---

### 6. **Shrink** — idempotency + typed errors on every executor hop
**Where:** 18 §2.3–2.4 (≈20 new error codes), 19 keys on claim/start/outputs/complete/fail.

Admission receipts and complete receipts earn their keep (editor double-click; worker lost ack). Claim-with-no-work correctly writes **no** receipt (20 §18.1). Heartbeat correctly has none. Then start/outputs still demand keys, and 409 extras return the full attempt model so a *fleet* can resync.

**Simplest:** `Idempotency-Key` on R1 and complete/fail only. Claim is “get work or 204.” Errors: `invalid_body`, `not_found`, `conflict` (CAS/lease), `capability_unavailable`, `payload_too_large`. Map the rest internally.

**Saves:** zod surface in 18 §17, fence-resync protocol, claim-key replay rules.

---

### 7. **Cut** — `api_orchestrator` port, executor heartbeat, queue/summary as v1 surface
**Where:** 19 §3.4/§7 keep-list (`TASK_HANDLERS`, fal/wavespeed), optional `POST /executors/{id}/heartbeat`, `GET /queue/summary`; 18 reserved routes.

Doc 24 Q3 deleted outbound providers. Porting the API orchestrator “with handlers unchanged” is shipping a corpse. Worker registry was correctly refused (14 §4); the optional heartbeat puts it back. Queue summary replaced `task-counts` for **autoscaling**. One local process does not need it; R2 + 2s poll is the badge.

**Simplest:** one worker process beside `serve`. Same-host invariant = supervisor/boot check, not a wire protocol. Logs = files.

**Saves:** a second BridgeClient, phantom-claim deletion work that is already unnecessary, T11-as-API-path.

---

### 8. **Simplify** — orchestrator identity + child admission
**Where:** 26 Orchestrators; 16 §6 passthrough; 19 T11.

Keep: leased parent, allowlisted child R1, deterministic keys `reigh.orch:v1:<parent>:<role>:<index>`, hard deps, explicit parent complete. That *is* today’s `checkOrchestratorCompletion` plus a lease (Grok D2 — correct).

**Cut:** dual UUID/ULID (`logical_task_id` + cache + rewrite `dependant_on`). Kernel ULID is the id; worker stops pre-generating UUIDs. **Cut** four “contract blocks” on join/travel params (16 fixtures D/E/M) unless a handler still reads them — [INFERENCE] most are route-control leftovers. **Gate** child families so the browser cannot admit `travel_segment` (Grok missed-item 2 — load-bearing).

Structural runs stay deferred. Do not leak them into v1 schemas.

---

### 9. **Shrink** — day-1 fixture/test matrix
**Where:** 16 §7 A–N (14 fixtures), 19 T1–T12, 21 P0.7 “executable parity proof.”

Resolver parity for **live** families matters. Fourteen golden kernel-row hashes plus a 12-case fence matrix plus 50× keeper races is how you postpone the slice.

**Simplest:** one production-shaped `wan_2_2_t2i` (admit, crash, lost-ack complete, poisoned output, missing model). Add join/travel graphs when those handlers move. Cancel when the app needs Cancel.

---

### 10. **Cut / merge** — leftover product surfaces
| Item | Verdict | Why |
|---|---|---|
| R13 render routes | **Merge into R1/R2** | 18 already says R13 is a facade over `rendering.timeline_visualize`. Extra DTO is chrome. |
| R12 `GET /variants` | **Defer** | Gallery is generations + primary; variants on detail. |
| Shots pack v1 + `shot_items` as Reigh authority | **Leave dormant** | 23/24: do not mirror document groups. |
| References pack / evidence / understanding | **Don’t touch** | Not the local editor. |
| Conformance kit table-count, plugin laws, dynamic pack loader | **Ignore** | 20 already said no dynamic loader. Don’t bump frozen-20 as a gate. |
| Hash-chained events, ULIDs, single-writer UoW | **Keep as-is** | Inherited; rewriting the kernel is a larger project than Reigh. Don’t *extend* it. |
| 64 GiB attempt quota / 2 GiB request / 60s sweep constants | **Don’t freeze** | 18 §18.7 already low-confidence. Pick boring defaults in code. |
| Thumbnails as Phase 1 schema | **Cheap local task later** | Not a column (24). Not a blocker for t2i. |
| Document size paging | **Measure, don’t design** | 24 P1. |

---

### Keep (not ceremony)
- One writer queue; workers never open SQLite (14).
- Timeline whole-document CAS; worker must not save the editor document (20 §18.5 — internal registry merge only).
- SHA-256 managed media; always-copy (24 Q5).
- Atomic complete: bytes + media + generation + optional registry visibility, or nothing.
- Polling 2s/10s/30s (24 Q6).
- Code-declared capabilities; `422 capability_unavailable` with setup hint; no cloud fallback.

---

If I cut only three things, they would be…

1. **The import/Phase-0/rollback program** — it contradicts the ratified fresh start and delays the only proof that matters (local t2i).
2. **Claim/start/outputs/complete as a cloud fence machine** — collapse to claim + heartbeat + atomic complete; keep leases and two receipts.
3. **Doc 26’s catalog (taxonomy, aliases, multi-binding, TaskDefinition blob) plus treating 16–22 as living law** — one flat table, one rewritten spec, then build the slice.
