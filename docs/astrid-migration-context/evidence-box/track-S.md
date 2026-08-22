# ORACLE VERDICT — track-S (shots-pack v2 + generation repository + registry merge)

**Verdict: PASS**

Reviewed: `dd1bbe3a..track-S` (8 commits, 20 files) in `/workspace/reigh-phase-a-20260822/exec-track-S`.

## Acceptance evidence

1. **Pack v2 migration — PASS.**
   - `astrid/packs/shots/migrations/0002_generations.sql`: DDL transcribed from doc 17 §2 (doc-24 amendment honored: no `shot_generation_items`). Column-for-column and index-for-index identical to the doc.
   - One-primary partial unique index `generation_one_primary ... WHERE is_primary = 1`; `UNIQUE (generation_id, media_id)`; soft delete via `generations.deleted_at` (variants/bytes survive); `media_id ... ON DELETE RESTRICT`.
   - Fresh tmp DB via `compose_standard_application`: exactly **22 tables**; `schema_migrations` contains `('shots', 2, 'generations', ...)`. `schema-pack.yaml` version 1→2 with migration entry declaring both tables.

2. **Frozen-count bumps — PASS, all eight homes verified in diff.**
   - `m4_gate.py` (FROZEN_TABLE_COUNT = 22; latent bug fixed at ~:568: `manifest.migrations[0].tables` → iterate **all** migrations' tables — the v2 second migration would otherwise be invisible to composition drift checks); `authority_lint._declared_tables` same fix; `check_pack_factoring.py` shots tuple extended.
   - Tests: `test_registry.py` (STANDARD_TABLE_COUNT = 22), `test_m6_gate.py`, `test_reference_lifecycle.py:824`, `test_m8_installed_contract.py` (rewritten to derive every pack migration from manifests, not just migration[0]), `test_shot_repository.py:1846`, `test_standard_application.py`, plus `test_catalog_migrations.py` and `test_m7_hardening.py` (4→5 schema_migrations rows).
   - `artifacts/m4/finalizer-admission.json` regenerated post-v2 (`pack_tables` grouped by pack incl. generations/generation_variants, total_table_count 22). Note below on its recorded exit.

3. **GenerationRepository — PASS.**
   - Receipt-free and event-free per heartbeat precedent; module docstring and code confirm: never constructs a writer, every command takes the caller's `UnitOfWork`, fences (project exists → task succeeded-with-winner same-project → type vocabulary → media same-project → duplicate id) all evaluate **before any write**, so a rejection changes zero rows.
   - `record_completion(uow, ...)`: inserts generation + one original variant `is_primary = 1` inside the caller transaction; no commit anywhere in the repository. Verified by reading the full method body.
   - `set_primary`: demote-then-promote inside one UoW; writer serialization (BEGIN IMMEDIATE) forbids interleaving and the partial unique index backstops even a hypothetical non-serialized writer. Already-primary is a typed `GenerationPrimaryError(already_primary)`.
   - Soft delete idempotent; RESTRICT honored (test `test_variant_pins_media_through_on_delete_restrict` passes); reads transaction-free on `read_only_connection`.

4. **timeline.registry_merged — PASS.**
   - Kind registered in-tree (`schema-pack.yaml` event_kinds; constant `TIMELINE_REGISTRY_MERGED_EVENT_KIND`), no migration.
   - `TimelineRepository.merge_registry`: head read from stream row → additive upsert into `asset_registry_json` (existing keys never clobbered; zero-added-keys returns current head appending nothing) → hash-chained append carrying `{assets, added_keys, base_head}` with internal `expected_head_seq=base_head` CAS as defense-in-depth. No caller `expected_version`. Archive fence derived from stream events before any change. `document_json` untouched (only `asset_registry_json` + `updated_at`) — byte-identity asserted by test.

## Verification runs

- Batch 1 (six named suites): **119 passed** in 16.9s.
- Batch 2 (`pytest tests -k "generation or merge"`): 81 passed, 5 skipped, **3 failed — all three reproduce identically on base dd1bbe3a** (verified in a clean worktree): timeline-snapshot fingerprint test and two remotion-registry tests failing on environment drift (missing real local effects / stale snapshot fixture), not on any track-S surface.
- Fresh DB composition: 22 tables, shots|2 migration row (see §1).

## Notes (non-blocking)

- The committed refreshed `artifacts/m4/finalizer-admission.json` records a gate run with `exit: 1` and two CLI-surface drift violations ("excluded-from-census set drift", "product timeline verbs") plus absent feasibility admission. These violations reproduce **at base dd1bbe3a unchanged** — pre-existing workspace/environment drift in `_check_cli_surface` (frozen `{"serve","doctor","run"}` vs live `{'backup','doctor','serve'}`; AST verb scan finds no `_PRODUCT_TIMELINE_VERBS` in this checkout's domain_product). Not introduced or worsened by track-S; the schema-composition check it exists to evidence passes cleanly against the live tree. Flag for whoever owns the m4 gate freeze constants.
