# `.oracle/tasklist.md` — Phase-A frozen-ready batches

Grounding: `.oracle/plan.md` STABLE v3 (incl. §v3 deltas), `.oracle/northstar.md`, `.oracle/agent_goal.md` done criteria 1–7. All paths relative to `/Users/peteromalley/Documents/Astrid-oracle` unless noted. Validation commands use repo-root `tests/` per plan §3-OQ1 (documented erratum vs immutable `agent_goal.md`). Each batch ends at a natural seam and commits both repos' `oracle-run` branches at its checkpoint (agent-goal authorization; never merge to main).

---

## Batch B1 — Kernel amendment + crash-proof foundation (T1 + harness skeleton)

**Tasks**
| Task | Classification |
|---|---|
| **T1-spike** — one-week APFS crash-test spike (doc 30 risk 1): prove bytes durable before `BEGIN IMMEDIATE`; extend `tests/v10/test_crash_atomicity.py` lanes | `[XHARD]` |
| **T1** — §5 kernel amendment: pre-transaction CAS publication, clean cutover of BOTH seams — hoist publish at `materialize_prepared` (`core/repositories/media.py:1794–1800`) above `BEGIN IMMEDIATE`; same for `_insert` (:2156–2164 via `import_prepared`); expose prepare→publish-then-commit API in `core/io/media_import.py` | `[XHARD]` |
| **Harness skeleton** — scaffold `tests/v10/test_phase_a_fault_matrix.py` infrastructure only (E7 shape: `UnitOfWork(writer, on_statement=observer):690`, child re-exec + `os._exit(137)`, fresh byte-identical DB copy per boundary); no Phase-A labeled points yet | normal |

**[XHARD] evidence (T1/T1-spike):** doc 30 names this risk #1; it reorders publication vs transaction inside the kernel's hottest write path (`materialize_prepared`, `_insert`) — a mistake corrupts the bytes-before-rows invariant silently across every consumer. Requires crash-injection judgment under APFS fsync semantics, not mechanical edits. Mitigation already priced in: E1 confirmed both sites are behavior-neutral duplicates falling through verify-reuse (:908–917) either side of the transaction; old-or-complete rename invariant independent of transaction timing.

**Checkpoint acceptance criteria (oracle verifies exactly)**
1. Spike report exists under `.oracle/evidence/t1_spike/` with crash-test results proving bytes-on-disk precede `BEGIN IMMEDIATE` on APFS.
2. Both publication sites reordered; zero code changes required at the five `import_prepared` callers (`core/conformance/kit.py:712,732`, `packs/references/conformance.py:158`, `packs/shots/conformance.py:171`, `sdk/media.py:134,195`) — verified untouched by diff.
3. Extended `tests/v10/test_crash_atomicity.py` lanes green; all existing kernel completion tests green.
4. Harness skeleton runs (0 labeled points, infrastructure proven: observer → child re-exec → exit 137 → fresh-copy replay).
5. Both repos committed to `oracle-run`.

**Agent-goal criteria advanced:** 2 (partially — lanes laid), 7 (kernel untouched regressions).

**North Star:** *One authority* (committed row never precedes durable bytes); *Correctness by primitives* (CAS publication keeps its named crash test); *Invisible failure* (crash leaves orphans/replays, never partial authority). Anti-patterns avoided: partial scoping leaving dual crash-window conventions (rejected in plan §3-OQ2).

**Validation commands**
```
cd /Users/peteromalley/Documents/Astrid-oracle && python3 -m pytest tests/v10/test_crash_atomicity.py -x -q
cd /Users/peteromalley/Documents/Astrid-oracle && python3 -m pytest tests/v10 -x -q
cd /Users/peteromalley/Documents/Astrid-oracle && python3 -m pytest tests -x -q   # full regression at checkpoint
```

**Traceability:** plan.md §1 T1 (+§2-E1 resolution, §3-OQ2), agent_goal done 2/7; harness skeleton feeds T13 (plan §1 T13, delta N3 wall-clock measurement lands here as instrumentation stub).

---

## Batch B2 — Pack v2 schema + generation repository + registry-merge event (T2 + T3)

**Tasks**
| Task | Classification |
|---|---|
| **T2** — shots-pack v2 migration: new `astrid/packs/shots/migrations/0002_generations.sql` (exact DDL doc 27 §2.2 + doc 17 indexes, NO `shot_generation_items`); `schema-pack.yaml` `migrations[1]`, tables `[generations, generation_variants]`, vocabularies unchanged; bump frozen-20 count in **eight-plus homes** (`scripts/reshape/m4_gate.py:583-584` + `FROZEN_PACK_TABLES`:96-102, `tests/v10/test_registry.py:63,168,1154`, `tests/v10/test_m6_gate.py:47(+159,175)`, `tests/v10/test_reference_lifecycle.py:828`, `tests/v10/test_m8_installed_contract.py:319-324` + migration row `("shots", 2)`, **plus `tests/v10/test_shot_repository.py:1849` and `tests/v10/test_standard_application.py:67` (`EXPECTED_TABLE_COUNT = 20`, asserted :302)**; also check `artifacts/m4/finalizer-admission.json:118` total_table_count if any gate compares regenerated evidence); fix latent bug `m4_gate.py:568` reading only `migrations[0].tables` — iterate all descriptors | normal |
| **T3** — `astrid/packs/shots/generation_repository.py` mirroring ShotRepository command discipline (no events, no receipt of its own — heartbeat precedent `tasks.py:2202-2226`); add ONE event kind `timeline.registry_merged` to `packs/timeline/schema-pack.yaml:24-28` (in-tree, forward-only, no migration); `TimelineRepository.merge_registry(uow, *, project_id, timeline_id, entries) -> int` — head read + additive upsert + hash-chained append `{assets, added_keys, base_head}` via `_events.append(expected_head_seq=current_head)`; `document_json` byte-identical; archive fence :997-1005 honored; NO caller-supplied `expected_version` | normal |

**Checkpoint acceptance criteria (oracle verifies exactly)**
1. Fresh tmp DB → `apply_pending_migrations` → exactly 22 tables; `schema_migrations` shows `shots|2`.
2. Catalog/probe tests pass; m4 gate sees v2 tables — negative test included (revert DDL → gate red).
3. GenerationRepository unit tests: one-primary invariant enforced, soft delete, `ON DELETE RESTRICT` honored.
4. Completion UoW creates generation + merged registry atomically; `document_json` byte-identical after merge (asserted in test).
5. Save-storm fixture green: N editor saves interleaved with M completions — zero silent registry loss, every loser receives 409 carrying new head.
6. Per v3 delta N1: merge-skipped completion yields a valid, replayable receipt (completion UoWs unconditionally append `core.task.completed` + ≥1 `core.media.imported`; merge conditional).
7. Both repos committed to `oracle-run`.

**Agent-goal criteria advanced:** 1 (done), 3 groundwork, 6 groundwork.

**North Star:** *One authority* (merge mutates `asset_registry_json` inside the same writer-serialized UoW with head-CAS — explicitly NOT a second placement authority; `timeline.saved` reuse rejected for breaking event-log reconstructability); *Growth by declaration* (event-less generations legal per E4; single new event kind exists because reconstructability + conflict proof demand it — no ceremony); *Correctness by primitives* (save-storm is a named primitive test; no LWW, no layered CAS objects).

**Validation commands**
```
cd /Users/peteromalley/Documents/Astrid-oracle && python3 -m pytest tests/v10/test_registry.py tests/v10/test_m6_gate.py tests/v10/test_reference_lifecycle.py tests/v10/test_m8_installed_contract.py -x -q
cd /Users/peteromalley/Documents/Astrid-oracle && python3 -m pytest tests/packs/shots tests/packs/timeline -x -q
cd /Users/peteromalley/Documents/Astrid-oracle && python3 -m pytest tests -x -q   # checkpoint regression
python3 scripts/reshape/m4_gate.py   # drift gate green post-fix
```

**Traceability:** plan.md §1 T2/T3 (+E4, E5 resolutions; v3 delta N1 edit sites), agent_goal done 1, 3, 6; constitution event-log reconstructability rule.

---

## Batch B3 — Capability registry + admission + trust perimeter (T4 → T5 → T8 → T9)

Dependency order inside batch: T4 first; T5, T9 parallel after T4/T5 respectively; T8 after T5.

**Tasks**
| Task | Classification |
|---|---|
| **T4** — capability registry: `core/integrations/reigh/capabilities.py` typed entries (id, family, input validator/resolver, output policy, ONE binding, availability probe, optional template digest — doc 27 §3.2, nothing more); 19 retained flat IDs + `rendering.timeline_visualize`; child allowlist (5 IDs incl. `reigh.join_clips_orchestrator`); dead-type reject list incl. `wan_lora_training` | normal |
| **T5** — R1 admission route: POST branch in `local_bridge_server.py` do_POST :866-923; DTOs + error categories in `bridge_service.py` (`invalid_body/not_found/conflict/capability_unavailable/payload_too_large`); Idempotency-Key semantics | normal |
| **T8** — executor-only child-admission hard gate: envelope validation in R1 handler + `capabilities.py` (parent ULID, attempt_no, executor_id, lease_id, fence; parent = caller's live leased attempt; deterministic key `reigh.orch:v1:<parent>:<role>:<index>`; hard deps kernel ULIDs; child inherits project/run) | normal |
| **T9** — local-trust gate (mechanics pinned by E2): guard top of overridden `parse_request`:188-192 after `super()` — fail-closed Host-vs-loopback, boot-token via `hmac.compare_digest`, required custom header; `_send_error(403,…)` + `return False` before any body byte; OPTIONS exempt (:856-860); custom header appended to `_ALLOWED_HEADERS`:252-263; token threaded as kwarg through `make_local_bridge_handler(*,…):171-174` from `_dispatch_serve` (`gateway/dispatch.py:128`, stdout echo once at boot); enforce 0700 on projects_root (+ media root) right after `compose_standard_bridge`:190, typed failure exit 1 | normal |

**Checkpoint acceptance criteria (oracle verifies exactly)**
1. Registry unit tests: unknown/dead type → `capability_unavailable`; duplicate-family bindings impossible by construction (type-level, not test-convention).
2. R1 route tests: valid family → 201 + ULID; replayed Idempotency-Key → 200 stored result; changed payload same key → 409; browser request for child family → `child_admission_forbidden`.
3. Child-gate tests: browser-origin child admit rejected even when type exists; forged/stale envelope rejected; valid envelope admitted with correct deterministic key.
4. Trust fixtures under `tests/integrations/reigh/`: hostile page rebinding/no-cors POST fails preflight; missing/wrong token → 403-class rejection BEFORE body read; Host spoof rejected; frozen GET routes unaffected; OPTIONS preflight still 204.
5. Serve boot enforces 0700 (negative: permissive dir → typed failure exit 1).
6. Both repos committed to `oracle-run`.

**Agent-goal criteria advanced:** 3 (R1 half), 4 (done), 5 (done).

**North Star:** *Growth by declaration* (capabilities stay flat declarative entries, one binding each — duplicate-family impossible by construction, not by lint); *Anti-patterns avoided:* no bridge middleware/route-table layer invented (single parse_request guard suffices — E2); no secret-file token handoff protocol (in-process injection; dissolved multi-process problem Phase A doesn't have); ceremony without consumer rejected (registry fields limited to doc 27 §3.2 list).

**Validation commands**
```
cd /Users/peteromalley/Documents/Astrid-oracle && python3 -m pytest tests/integrations/reigh -x -q
cd /Users/peteromalley/Documents/Astrid-oracle && python3 -m pytest tests -x -q   # checkpoint regression
```

**Traceability:** plan.md §1 T4/T5/T8/T9 (+E2 resolution, §3-OQ3), agent_goal done 3 (partial: R1), 4, 5.

---

## Batch B4 — Task lifecycle routes + liveness sweeper (T6 + T7)

Order: T6 first (sweeper is a liveness prerequisite T12/T13 prove); T7 depends on T1+B2 repository work.

**Tasks**
| Task | Classification |
|---|---|
| **T6** — claim / heartbeat / cancel routes over `TaskRepository.claim`:1745-1756 + existing cancellation service; global deterministic claim ordering (priority, availability, creation time, ULID); claim+heartbeat keyless, no receipts; **task-read routes (doc 27 §4.1, BC1 lens-A fix): `GET /projects/:slug/tasks` (bounded summary page) + `GET /projects/:slug/tasks/:task_id` (progress/output read) — exit criterion 11 polling visibility**. Sweeper (E6 blocking fix): daemon maintenance thread in `compose_standard_bridge` (`packs/__init__.py:199`, immediately after `run_startup_staging_gc`:234), ~15 s tick, read-only project enumeration, `expire_overdue` sweeps via `writer.submit`, loop-until-None per project, stop before writer close; EVERY sweep invocation gets a fresh ULID idempotency key (expiry's request hash empty :2409-2409ff — repeated key would replay stored receipt and expire nothing) | normal |
| **T7** — complete/fail routes: new `core/integrations/reigh/multipart.py` hand-rolled ~150-line bounded streaming parser (reject bad/absent Content-Length vs total cap pre-read; no chunked; single pass splitting on boundary; text fields buffered under strict per-field cap; file parts stream to mkstemp under existing `media_import.staging_path` with inline SHA-256 `digest.update(chunk)`; abort ⇒ unlink; require terminating `--boundary--`; truncated = failure + cleanup). REUSE existing frozen per-txn quarantine `.astrid/media/.staging/<txn_id>` with re-hash-before-publish + startup GC (`media_import.py:506-515`) — NO parallel quarantine dir. Server verifies size/type → T1 prepare→publish → one receipt-bearing UoW; fail carries `{code,message,retryable}`, `max_attempts` = kernel default 1 | normal |

**Checkpoint acceptance criteria (oracle verifies exactly)**
1. Claim returns leased `running` attempt with lease_id/expiry/fence (`DEFAULT_LEASE_SECONDS=300`); empty queue → 204; global ordering deterministic under concurrent claims.
2. Named liveness test: crashed executor mid-attempt + clock advance + sweeper tick → task back to queued, next claim succeeds.
3. Heartbeat extends lease, returns next fence, appends nothing; heartbeat-vs-expiry race-free under FIFO serialization — BOTH orders tested.
4. Complete happy path commits atomically (bytes in tree + rows in DB, single UoW); poisoned/truncated bytes → failure with ZERO authoritative rows.
5. Lost-ack replay returns stored result (exactly-once per Idempotency-Key); wrong fence → 409 carrying only attempt/expiry/current fence.
6. Parser unit tests: oversize field/file/body, bad boundary, missing terminator, max part count — all fail closed with cleanup (no staging residue beyond GC-recoverable).
7. Receipt validity holds on every completion path (N1 resolution: unconditional `core.task.completed` + ≥1 `core.media.imported` appends satisfy `ReceiptService.record`'s `first_project_seq` requirement — asserted, not assumed).
8. Task-read routes: bounded summary page + single-task progress/output read return correct rows over the bridge (exit criterion 11 polling visibility); retry-budget named test: retryable fail with attempts<max → `queued` (requeued), budget exhausted → terminal `failed` (BC1 lens-A fix).
9. Both repos committed to `oracle-run`. **BC2 BIG sense-check fires here if this is the 3rd passed batch or any prior gate failed.**

**Agent-goal criteria advanced:** 3 (claim/heartbeat/complete/fail halves — done criterion 3 fully satisfiable at this checkpoint).

**North Star:** *Invisible failure* (E6's wedge was invisible-failure incarnate — sweeper closes it; fresh-ULID sweep keys are receipt-primitive correctness); *Honest latency* (polling claim/heartbeat/sweeper over promised budgets; no SSE; correctness never transport-dependent); *Correctness by primitives* (fences carry their named wrong-fence test; receipts exactly-once). Anti-patterns avoided: lazy on-claim expiry entangling claim's receipt contract (rejected); third-party multipart dep for a loopback bridge (rejected); parallel quarantine beside existing frozen staging discipline (rejected).

**Validation commands**
```
cd /Users/peteromalley/Documents/Astrid-oracle && python3 -m pytest tests/integrations/reigh tests/core/integrations/reigh -x -q
cd /Users/peteromalley/Documents/Astrid-oracle && python3 -m pytest tests -k "lease or sweeper or multipart or complete or fail" -x -q
cd /Users/peteromalley/Documents/Astrid-oracle && python3 -m pytest tests -x -q   # checkpoint regression
```

**Traceability:** plan.md §1 T6/T7 (+E6 blocking finding, E3 verdict, v3 deltas N1/N2-record-only), agent_goal done 2 (receipt replay groundwork), 3 (complete).

---

## Batch C5 — Proofs: fixtures, journeys, fault matrix, regression (T10 → T11 → T12 → T13 → T14)

Order: T10/T11 parallel; T12 needs T3–T11 all landed; T13 needs T1+T7 (landed earlier) but shares wall-clock instrumentation from B1 skeleton; T14 last.

**Tasks**
| Task | Classification |
|---|---|
| **T10** — deterministic TEST executor binding + t2i conformance fixture: `capabilities.py` binding seam + fixture emitting fixed deterministic bytes honoring output policy; representative `wan_2_2_t2i` fixture (accepted input, manifest shape, provenance naming boot-manifest hash, truthful unavailability) per doc 27 §3.6. No real CUDA anywhere (non-goal) | normal |
| **T11** — gallery reads: GET `/projects/:slug/generations` (bounded page + primary-variant summary) + `/:generation_id` detail; paged queries in `generation_repository.py` | normal |
| **T12** — journey harness: `tests/integrations/reigh/test_journey_phase_a.py` (+conftest reusing `tmp_bridge_root`:100, `repository_server`:219 pattern, port 0, in-process): admit→claim→heartbeat→complete→CAS bytes in tree→media rows→gallery row→timeline registry visible; duplicate-admission replay; poisoned-output rejection; cancel queued+running; wedged-executor recovery via sweeper; **merge-skipped-completion replayable-receipt scenario (v3 N1 named test)** | normal |
| **T13** — crash-point fault-injection matrix (≥100 crashes): fill B1 skeleton with labeled points across upload/hash/publish/transaction/commit/response + `SQLITE_IOERR`, `SQLITE_FULL`, fs exhaustion, replay, concurrent identical-byte publication, **lease-death-via-sweeper**; asserts DB→tree totality, exactly-once per key, no partial rows, orphan report (orphans reported, RETAINED); evidence table → `.oracle/evidence/`; measure subprocess-per-boundary wall-clock vs 900 s CI lane FIRST (delta N3), timeout-mark if needed | `[XHARD]` |
| **T14** — full-suite regression + checkpoint commits | normal |

**[XHARD] evidence (T13):** crash-boundary selection requires reasoning about which statement boundaries can leave DB/tree disagreement — mislabeled points produce vacuous green; the matrix must distinguish orphan-acceptable from corruption states across seven crash classes including SQLite error injection and fs exhaustion. Subprocess-per-boundary × ≥100 crashes has a real CI-budget engineering constraint (900 s lane) needing measured scaling decisions. Highest blast radius: this matrix is THE proof of done criterion 2.

1. T10 fixture green; networking irrelevant; unavailability probe flips advertisement off (asserted both directions); `capability_unavailable` body carries the setup-hint payload (one runnable next action — BC1 lens-A note).
2. Gallery route tests: paging bounds enforced, primary summary present, deleted generation excluded; **media content route confirmed media_id-addressable** (one-line check vs frozen asset route :820–845 — assign explicitly if not; BC1 lens-A note).
3. Journey harness green end-to-end with test binding, INCLUDING duplicate-admission replay and poisoned-output rejection (agent_goal done 6 verbatim).
4. Fault matrix runner green: ≥100 injected crashes, ZERO DB/tree disagreement, receipt replay exactly-once, evidence table written under `.oracle/evidence/` (agent_goal done 2 verbatim); stays inside 900 s CI lane or carries explicit timeout mark with measurement recorded; **in-lock completion work asserted O(stat)-only (no byte copies inside the writer transaction — BC1 lens-A note)**.
5. `python3 -m pytest tests -x -q` fully green, no regressions (agent_goal done 7).
6. All seven agent-goal done criteria re-verified against final state; both repos committed to `oracle-run` and pushed to `origin` remotes at Phase-6 completion; NEVER merged to main.

**Agent-goal criteria advanced:** 1, 2, 3, 4, 5, 6, 7 — all seven close here.

**North Star:** *One authority* (journey asserts CAS bytes↔rows totality; gallery reads derive solely from SQLite); *Invisible failure* (matrix makes every crash point visible; orphans reported AND retained — no silent cleanup); *Growth by declaration* (TEST binding proves the declarative seam without runtime plugins); *Honest latency* (journey runs over real polling budgets). Anti-patterns avoided: silent executor swaps (binding is declared, probed truthfully); speculative cloud/multi-user machinery (none built).

**Validation commands**
```
cd /Users/peteromalley/Documents/Astrid-oracle && python3 -m pytest tests/integrations/reigh -k journey -x -q
cd /Users/peteromalley/Documents/Astrid-oracle && python3 -m pytest tests/v10/test_phase_a_fault_matrix.py -x -q
cd /Users/peteromalley/Documents/Astrid-oracle && python3 -m pytest tests -x -q
ls .oracle/evidence/   # fault-matrix + T13 evidence table present (host-side check)
```

**Traceability:** plan.md §1 T10–T14 (+v3 deltas N1 named test, N3 measurement), agent_goal done 1–7 verbatim; BC3 BIG sense-check (≥5 passes incl. operations/performance lens) gates final completion per sense-check cadence.

---

## Cross-batch notes

- **BC cadence:** BC1 already passed (post-plan). BC2 triggers after every 3 passed batches or immediately after any gate failure (earliest: end of C5 if B1–B4 pass clean — fire it at C5 start regardless since batch count reaches threshold mid-batch). BC3 before declaring done.
- **Model policy:** every class pinned `stealth/ox-alpha`; classification labels above affect review depth only, never routing.
- **Recorded deferrals carried forward:** N2 (child fan-out on parent requeue — record decision in code comment/docs when T8 lands, do not build); N4 (`NON_EXECUTABLE_COMMAND_KINDS` fix only if T10 touches kit specs).
- **Erratum standing:** all validation uses `tests/` (repo root), superseding `astrid/tests` in immutable `agent_goal.md` — owner confirmation requested at next check-in.
[launch_hermes_agent] done in 160.4s (exit=0)
0
