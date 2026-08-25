# 29 — Ground-truth sense-check of the Reigh→Astrid plan

> **Status: VERIFICATION REPORT (2026-08-22).** Independent adversarial audit of docs 15/24/25/grok-decisions (constitution), 27 (build contract), 22 (roadmap), and 16–19/26/28 (historical/consultative) against actual code (`Astrid/`, `reigh-app/`, `reigh-worker/`, `reigh-worker-orchestrator/`), the live kernel SQLite (`Astrid/projects/.astrid/astrid.sqlite3`, read-only), and the live production Postgres (read-only, `SELECT`-only, `statement_timeout=30s`). Read-only everywhere except this file.

## 1. Summary verdict

**The plan is well-grounded.** Every load-bearing kernel primitive claimed by doc 27 exists and behaves as described in `Astrid/astrid/core/`; the "20-table kernel" and migration-state claims are exactly right; the capability/dead-type analysis matches live production data; the Wan2GP pin matches. Found **6 corrections** (none fatal), **9 residual contradictions** between historical docs and doc 27 (4 dangerous-if-implemented), **5 unverified** items. The single most important nuance: **doc 27 §5's completion ordering is an amendment to be built, not a description of current kernel behavior** — the current kernel publishes bytes *inside* the writer transaction.

## 2. A. Kernel + build spec (doc 27) vs Astrid code

| Claim | Expected | Found | Verdict |
|---|---|---|---|
| Single-writer queue, one `BEGIN IMMEDIATE` per command, strict FIFO | doc 27 §1/§5 | `Astrid/astrid/core/conformance/kit.py:31-35,1052` ("one writer thread… exactly one BEGIN IMMEDIATE… strict FIFO") | PASS |
| Command receipts inside commit | doc 27 §5 step 8 | `Astrid/astrid/core/receipts/service.py:3-6` ("runs **inside** the kernel unit of work — same BEGIN IMMEDIATE"); table `command_receipts` exists in live DB | PASS |
| Idempotency keys / receipt replay+mismatch before mutation | doc 27 §5 step 1 | `repositories/tasks.py:3628-3638` (receipt gate first); `events/service.py:132-146` (`UNIQUE(stream_id,idempotency_key)`) | PASS |
| Hash-chained events | doc 27 §10 "untouched" | `events/service.py:740-758` (`hash_prepended` sha256 chain); SD2 envelope chain inside `payload_json`; note: no `prev_hash` column by design (`events/__init__.py:13-15`) | PASS (nuance) |
| Fenced attempts: `lease_id`, `status_version`, `DEFAULT_LEASE_SECONDS=300` | doc 27 §4.2–4.3 | `repositories/tasks.py:118` (=300); DDL `migrations/sql/core/0001_initial.sql:156-161`; fence rechecks `tasks.py:3644-3697` | PASS |
| `TaskRepository.claim/expire_overdue/complete` signatures | doc 27 §4.2/§4.5 | `claim` tasks.py:1745-1756 (executor_id, lease_seconds=300); `expire_overdue` :2358 (budget-driven requeue/fail :2470-2472); `complete` :3517 (fenced, one receipt) | PASS |
| Claim creates leased `running` attempt directly, hash-chained claimed event | doc 27 §4.2 | tasks.py:1765-1768,1870-1887 (claimed attempt, status_version 1, ULID lease_id, `core.task.claimed`) | PASS |
| `capability` column; `spec_json`/`input_manifest_json` columns | doc 27 §2.1 | INSERT tasks.py:1423-1436; read model :391-395; validation :1269-1295 | PASS |
| Media SHA-256 identity + `media_locations` | README:59 | media identity is byte SHA-256 alone (tasks.py:3608-3611); realm vocabulary frozen `io/media_import.py:542-545`; bridge verifies SHA before streaming (`integrations/reigh/local_bridge_server.py:316-321`) | PASS |
| Timelines: `document_json`+`asset_registry_json`, CAS 409 carrying head, `config_version`=stream head | doc 27 §4/§7.1 | `packs/timeline/repository.py:32-34,246-248,315-328,751-754,876-881` | PASS |
| **§5 ordering: bytes published BEFORE `BEGIN IMMEDIATE`, O(stat) in-lock** | doc 27 §5 | **NOT current behavior.** Kernel publishes via in-UoW `materialize_prepared` INSIDE the completion transaction: `media.py:744-754` ("published through the in-UoW media helper … at the short materialization boundary"), `media.py:1603`, `tasks.py:3535-3546`, `io/media_import.py:528-533`. Receipt-inside-commit part matches. Doc 22:187 confirms it is Phase-A build step 3 ("pre-transaction CAS publication"). **Verdict: doc 27 §5 = amendment/change requirement.** | PASS-as-spec / FAIL-as-description |
| Frozen bridge routes: GET /health, /projects, timelines, save, assets Range/ETag | doc 27 §4 preamble | `local_bridge_server.py:776-830` (health :780, projects :785, timeline list :792, load :804, assets GET/HEAD :820-845); POST save :870-921; Range grammar + stat-derived ETag + 304 :54-57,444,592-607. No task routes exist yet (POST 404s :923) | PASS |
| "20-table kernel"; schema_migrations core/references/shots/timeline @ v1 | user prompt / doc 04 | Live sqlite_master: exactly **20 tables** (list incl. `command_receipts`,`event_streams`,`task_dependencies`); migrations rows `core|1, references|1, shots|1, timeline|1`; catalog `CORE_MIGRATION_VERSION=1` (`migrations/catalog.py:26`) | PASS |

## 3. B. Capability/task model vs code

| Claim | Expected | Found | Verdict |
|---|---|---|---|
| Flat `reigh.<normalized>` names | doc 15:26, G1, 27:14 | **Plan-only.** No `reigh.` capability construction anywhere in reigh-app; client POSTs `{family,…}` (`src/shared/lib/taskCreation/createTask.ts`); only unrelated hit is reserved command IDs in `src/tools/video-editor/runtime/commandRegistry.ts`. Correct as design; would be wrong if read as existing behavior | PASS-as-design |
| 13 resolver families + passthrough | doc 16:11-17 | Confirmed: `create-task/resolvers/registry.ts` `TASK_FAMILY_RESOLVERS` = 13 named families; passthrough `resolvers/workerPassthrough.ts`; unknown family → live `task_types.is_active` lookup → passthrough or 400 `unknown_task_family` (`create-task/index.ts`) | PASS |
| Dead types rejected: `edit_video_segment`, `edit_travel_flux`, `image_edit`, underscore `image_upscale`, `magic_edit`, `single_image` | 27:107 | All six verified **active** in prod `task_types` today (probe below); resolver-less/dormant (`edit_video_segment`: active row, 0 tasks using it). Rejection is designed, not yet coded (no admission layer exists) | PASS |
| Retained capabilities exist as live prod types | 27 §3.1 table | All 19 retained source strings (+3 child types `join_clips_segment`,`join_final_stitch`,`travel_segment`) present in prod active list, incl. hyphen `image-upscale` | PASS |
| Worker TaskRegistry dispatch, DIRECT_QUEUE_TASK_TYPES, VibeComfy subprocess, add_task_to_db children, heartbeat | doc 19/27 §6 | Static registry, no register_handler (`reigh-worker/source/task_handlers/tasks/task_registry.py`); `DIRECT_QUEUE_TASK_TYPES` literal then catalog-derived reassignment (`task_types.py`); VibeComfy subprocess `python3.11 -m vibecomfy.cli run` with cwd pin and **no timeout** (`models/comfy/vibecomfy_adapter.py`); children created via POST create-task edge → status Queued (`core/db/task_completion.py`); heartbeat 20s RPC `func_worker_heartbeat_with_logs` + crash detection (`runtime/worker/guardian.py`) | PASS |
| Wan2GP submodule SHA `181bb71a…` | grok/worker-wgp-report.md:68 | Pinned SHA `181bb71a21008032e4771e11663f33e4489c4512`, branch `reigh-sprint-3` (`reigh-worker/.gitmodules`, `.git/modules/Wan2GP/refs/heads/reigh-sprint-3`) | PASS |
| Zero Astrid references in worker/orchestrator | repeated plan claim | Case-insensitive search across `reigh-worker/source/` and `reigh-worker-orchestrator/`: **zero hits** | PASS |

## 4. C. Constitution vs code reality

| Claim | Constitution | Ground truth | Classification |
|---|---|---|---|
| Fully local execution, no outbound generation providers | 24 Q3, 25 #7, 27 §6/§10, 22:50 | **Still-active today:** fal+wavespeed poller is the live API path (`reigh-worker-orchestrator/api_orchestrator/task_handlers.py`, `fal_utils.py`, `wavespeed_utils.py`, `handlers/{fal,wavespeed,image}.py`); RunPod GPU spawner active (`gpu_orchestrator/worker_spawner.py`, injects REPLICATE token); Replicate call in worker `task_handlers/magic_edit.py`; edge fns call Replicate (`trim-video`) + LLM providers Fireworks/OpenAI/Groq/Anthropic (`ai-prompt`, `ai-timeline-agent`, `ai-generate-effect`, `ai-voice-prompt`). **Cut-in-plan, not yet cut** (27 §6 deletes them; 22 #7 calls the path dead-once-local). Luma/Minimax/ElevenLabs/Suno/OpenAI-images: NOT FOUND | Consistent-as-target |
| Astrid-side cloud backends | 25 #7 spirit | Astrid core itself ships `FalBackend`/`WavespeedBackend`/`CodexBackend` registered cloud descriptors (`core/generation/backends/__init__.py:8-12`, `registry.py:189-211`) plus direct `fal_client` use in packs (`packs/media/executors/speech_repair_lavasr/run.py:20`, `packs/rendering/executors/sprite_sheet/upscale.py:164`, `packs/video_editing/orchestrators/animate_image/run.py:28`). Doc 27 is silent on their disposition in the shipped product; OS-level provider blocking (Phase-A criterion 13) is the only guard | Gap (minor) |
| Copy-only media; no importers; reject dead types | 24 Q5, 25 #8, 27 §1 | Kernel default realm `managed_local`, `external_local` explicit opt-in only (`io/media_import.py:543-545,958-962`); no importer/exporter code on any product path; admission layer not built yet so rejection is forward-looking | PASS |

## 5. D. Corpus internal consistency

Residual contradictions 16–19 vs 27 (from systematic sweep; severity-ranked):

**Dangerous (could be mistakenly implemented):**
1. **start/outputs/staging protocol** — 18:23,141-143,321-352,381-409 and 19:27-28,52-57,135-139,251-261 still specify `start`→`outputs`(+`staging_txn_id`) despite inline "route removed" notes; 27:174,182,196-200 abolish them. Highest-risk residue: the two route encyclopedias are the docs an implementer would copy.
2. **Fal/cloud keep-lists** — 16:108,112 dual WGP/VibeComfy-or-fal bindings; 19:197,437,518-520 keep-list questions; 27:91-104,262 delete Fal/Wavespeed and api_orchestrator outright.
3. **`shot_generation_items`** — 16:370 and 19:401 still require it; 27:80: "does not exist" (17:72-73,424 already cut it). Prod check: `to_regclass('public.shot_generation_items')` = NULL — table doesn't exist even in Postgres.
4. **Auth posture** — 18:29,111 "no tokens, no RLS" vs 27:218-226 per-boot request token + Host/custom-header gate.
5. **Dual-ID mapping** — 16:488 logical-id→ULID rewrite vs 27:131 "no logical_task_id cache or alias table".
6. **Claim idempotency key + starvation fields** — 18:140, 19:135 require claim key; 18 body + 19:215 keep `max_task_wait_minutes` vs 27:174 (claim keyless) and 27:188 (field abolished).
7. **Orch child key shape** — 18 §4.1 includes `<plan-version>` vs 27:141 `reigh.orch:v1:<parent>:<role>:<index>`.
8. **Generation event stream** — 17:15,43,81 specify `generation.generation` + 9 event kinds vs 27:75 "no generation.generation event stream".

**Harmless-history (banners supersede):** dead-type rejection (16:420 ≡ 27:107 — aligned, not contradictory); plugin-law mentions in 17 are kernel pack FK laws; render/variant extra routes (18:20,147-148) clearly superseded by 27:182.

**Doc 28 adoption spot-checks (6):** CAS-before-COMMIT (28:33→27:231-236), `doc_format` envelope (28:34→27:291), change taxonomy (28:34→27:154-163), setup journal (28:35→27:268-279), local-trust controls (28:37→27:218-228), refuse/degrade/queue + occupancy (28:38→27:307,317) — all present. **One adoption not landed:** 28:36 "four-fact recovery" has no named counterpart in 27 (only implied by §9 Phase-B machinery).

## 6. E. Live DB spot-checks

Kernel SQLite (read-only): 20 tables; migrations `core|1,references|1,shots|1,timeline|1`; **all domain row counts = 0** (projects, timelines, tasks, execution_attempts, media, events, event_streams, command_receipts, runs, shots, shot_items, media_locations, task_outputs, task_dependencies) — fresh-start baseline confirmed.

Prod Postgres (reachable; SELECT-only) vs doc 07 §3.13 estimates:

| Table | doc 07 est. | Live exact (2026-08-22) | Drift |
|---|---|---|---|
| tasks | 45,946 | 46,024 | +78 (~1 day activity) |
| generations | 38,465 | 39,026 | +561 |
| generation_variants | 40,037 | 41,474 | +1,437 |
| projects | 478 | 478 | 0 |
| task_types | 28 (est.) | **37** (29 active / 8 inactive) | est. stale; matches doc 16:17's probe exactly |

Tasks status distribution: Complete 27,392 / Cancelled 14,678 / Failed 3,939 / Queued 15. Active types confirm every retained capability string and all six dead-type names; inactive set (`api_query`, `wgp`, `test`, …) matches doc 16 §5 dispositions.

## 7. Corrections list

1. **(major, README:66)** "Verified bytes publish durably into CAS **before** the receipt-bearing SQLite transaction" is listed under *Current product facts* but describes a Phase-A requirement; current kernel publishes in-lock (`media.py:744-754`, `tasks.py:3535-3546`). Reword to "will publish" or move to doc 27 reference.
2. **(minor, doc 27 §3.1)** Rejected-names enumeration omits `wan_lora_training` — an *active* prod type whose cut lives only in historical 16:413,420 + 15 Q5. Add it to the explicit reject list.
3. **(minor, doc 16:16)** Historical "max_attempts=3" admission contract vs kernel default 1 (`tasks.py:1232`) — doc 27 §10 intentionally leaves it configurable; ensure implementation doesn't inherit 3 from doc 16.
4. **(minor, docs 28:36/27)** "Four-fact recovery" adoption claimed but absent from doc 27 text; land it in §9 or annotate as subsumed.
5. **(info, doc 07 §3.13)** Small-table `reltuples` estimates unreliable (`task_types` 28 vs 37 exact); doc 16's corrected numbers stand.
6. **(info, grok/worker-wgp-report.md)** Heartbeat cadence stated 10 s (§1 table) vs 20 s loop (§2); ground truth is a 20 s guardian loop (`guardian.py`). Cosmetic.
7. **(info, gap)** Astrid-native cloud backends (`FalBackend`/`WavespeedBackend`/`fal_client` pack executors) are unaddressed by doc 27's deletion list; acceptable only because acceptance blocks provider networking at OS level — consider stating their non-binding explicitly.

## 8. Unverified

- Deep read of `engineering-answers/A.rtf` + `message.txt` originals (judged via doc 28 + sweep cross-check only).
- Wan2GP working-tree drift beyond the pinned SHA (dirty-submodule check not run).
- Full doc 07 §4 drift ledger re-verification (spot-checked headline counts only).
- Whether `api_orchestrator`/`gpu_orchestrator` are *currently scheduled* in prod ops (code paths active; runtime deployment inferred `[INFERENCE]`).
- Doc 22 audited at skim depth (verdict table + phase gates), not line-by-line.

## 9. Top 10 findings

1. Plan's kernel claims are real: every cited primitive (leases=300s, fenced attempts, receipts-in-commit, hash chains, CAS timelines, 20 tables, v1×4 migrations, empty domain rows) verified in code and live DB.
2. Doc 27 §5 completion ordering is an **amendment**, not current behavior — biggest implementation surprise available in the corpus (kernel today publishes bytes under the writer lock).
3. `reigh.*` capability strings exist nowhere in running code; they are the G1/27 design. Live reigh-app speaks `family` + 13 resolvers + DB-gated passthrough.
4. "Fully local" is end-state: fal/wavespeed/Replicate/RunPod/LLM-edge paths are all still live code, correctly slated for deletion by 27 §6 / 22 #7.
5. Docs 18/19 remain the most dangerous historical corpus: their start/outputs/staging route bodies could be implemented verbatim by anyone skipping the banners.
6. Prod data validates the capability plan exactly: 37 task_types (29/8), all retained types live, all six dead names live-and-active, `wan_lora_training` active-but-cut, hyphen `image-upscale` real.
7. Worker ground truth matches the grok forensic report, including Wan2GP pin `181bb71a21008032e4771e11663f33e4489c4512` and zero Astrid coupling.
8. Prod drifted only trivially since doc 07's day-old dump (+0.2% tasks, +1.4% variants) — doc 07 remains trustworthy evidence.
9. One doc-28 adoption (four-fact recovery) didn't land in 27; everything else spot-checked did.
10. Minor completeness gaps worth 10 minutes each: add `wan_lora_training` to 27's reject list; fix README fact #66 tense; note Astrid-native cloud backends' non-binding status.
