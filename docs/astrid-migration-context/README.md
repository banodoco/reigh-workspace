# Astrid Migration Context — dossier index

> **(Amended: Grok review — judged ADOPT; Amended: engineering-answers judgment.)** This directory separates binding decisions and current build authority from historical evidence. The migration is a fresh-start local product journey; legacy production/import material remains useful forensic context but is not implementation work.

## Current authority and reading order

**(Amended: Grok review — judged ADOPT/MODIFY; Amended: engineering-answers judgment.)** Read in this order:

1. `15-owner-decisions-defaults.md`, `24-owner-decisions-round2.md`, `25-end-state-bold-statements.md`, and `grok/second-opinion-decisions.md` — the ratified constitution.
2. `grok/simplicity-review.md` — the over-complication review; its item-by-item judgments are recorded in doc 22.
3. `28-engineering-answers-judgment.md` — head-to-head judgment of the two ten-question responses and the adopted `[INFERENCE]` amendments.
4. `27-build-spec.md` — the sole current working build contract, amended with the adopted mechanisms.
5. `22-codex-roadmap.md` — the current A/B/C journey plan and verdict tables.
6. Docs 01–14, 16–21, 23, and 26 only when implementation needs their historical evidence or forensic detail.

No lower-authority document may override the constitution. Where historical specs 16–19 conflict with doc 27, doc 27 controls.

## Index

**(Amended: Grok review — judged ADOPT.)**

| # | Status | Doc | Purpose |
|---|---|---|---|
| 01 | Evidence | `01-reigh-postgres-schema.md` | Repository/live Postgres schema inventory and drift. |
| 02 | Evidence | `02-reigh-task-pipeline.md` | Legacy task lifecycle, retries, billing, sweeps, and realtime. |
| 03 | Evidence | `03-reigh-worker-execution.md` | Legacy GPU worker execution and artifact flow. |
| 04 | Evidence | `04-astrid-sqlite-schema.md` | Astrid v10 kernel, packs, writer, events, receipts, and media. |
| 05 | Evidence | `05-astrid-package-semantics.md` | Astrid CLI/SDK and implemented/planned semantics. |
| 06 | Evidence | `06-reigh-app-data-usage.md` | Frontend data-contract inventory. |
| 07 | Evidence | `07-live-db-schema.md` | Read-only live database probe and drift ledger. |
| 08 | Evidence | `08-unified-model-prior-art.md` | Prior decisions leading to the fresh-start posture. |
| 09 | Frozen base contract | `09-astrid-bridge.md` | Existing timeline/discovery/media bridge behavior; doc 27 adds the task surface without renaming frozen timeline errors. |
| 10 | Evidence | `10-reigh-edge-functions.md` | Legacy edge-function and resolver inventory. |
| 11 | Historical evidence | `11-astrid-v10-migration.md` | Existing operator migration scripts; not journey work or product authority. |
| 12 | Evidence | `12-reigh-task-internals.md` | Legacy claim/retry/slot machinery. |
| 13 | Historical synthesis | `13-migration-context.md` | Broad dossier synthesis; migration §§8–11 are evidence, not journey work. |
| 14 | Historical design | `14-codex-migration-design.md` | First bridge-extension design, superseded where doc 27 differs. |
| 15 | **Binding constitution** | `15-owner-decisions-defaults.md` | Ratified owner defaults, interpreted through later fresh-start decisions. |
| 16 | **Historical — superseded by 27** | `16-capability-map.md` | Resolver/payload/capability evidence; broad fixture plan is not a day-one gate. |
| 17 | **Historical — superseded by 27** | `17-pack-v2-ddl.md` | Two-table DDL evidence; event-sourced generation design is cut. |
| 18 | **Historical — superseded by 27** | `18-bridge-route-schemas.md` | Earlier route encyclopedia; surviving routes are in doc 27. |
| 19 | **Historical — superseded by 27** | `19-worker-diff.md` | Legacy transport/per-file inventory; surviving worker client is in doc 27. |
| 20 | Historical consultation | `20-codex-recommendations.md` | Broad recommendations; only outcomes carried into constitution/doc 27 remain current. |
| 21 | Historical consultation | `21-codex-knowledge-gaps.md` | Earlier gap list; archaeology/exporter/every-family gates are cut. |
| 22 | **Current journey plan** | `22-codex-roadmap.md` | Grok verdicts and the Phase A/B/C plan. |
| 23 | Historical consultation | `23-openrouter-followup-report.md` | Supporting polling/document-native/fresh-start analysis; decisions are ratified in doc 24. |
| 24 | **Binding constitution** | `24-owner-decisions-round2.md` | Document-native placement, deep copy, local compute, Astrid render, copy-only media, polling. |
| 25 | **Binding constitution** | `25-end-state-bold-statements.md` | Ten contradiction-testing end-state claims. |
| 26 | Historical consultation | `26-task-model-recommendations.md` | Ratified task-model outcomes are carried into doc 27; old dual-ID/staging/phases are not. |
| 27 | **Current build contract** | `27-build-spec.md` | Consolidated routes, two-table DDL, capability registry, worker client, vertical slice, custom path, and release criteria. |
| 28 | **Judged engineering consultation** | `28-engineering-answers-judgment.md` | Per-question A/B comparison, decisive winner, adoption decisions, contradictions, and amendments carried into docs 27/22. |
| G1 | Binding task-model decision | `grok/second-opinion-decisions.md` | Flat names, one binding, snapshots/templates, trimmed definitions, no aliases/plugins, leased parents. |
| G2 | Judged review | `grok/simplicity-review.md` | Ten-item simplicity review; verdicts are in doc 22 §1. |
| 31 | **Forward map** | `31-forward-map.md` | Phases B and C in full: B-1 VibeComfy binding → B-2 capability fan-out → B-3 orchestrator children → B-4 Wan2GP gates → B-5 model acquisition → B-6 conformance; C-0 cutover inventory → C-1 domain clients → C-2 shot mode → C-3 render UX → C-4 ops surfaces → C-5 acceptance; Phase D release mechanics. |

## Current product facts

**(Amended: Grok review — judged ADOPT/MODIFY; Amended: engineering-answers judgment.)**

- One Astrid SQLite file is the only structured authority; the managed SHA-256 tree is authoritative for bytes.
- The browser and one same-host worker use the loopback bridge; workers never open SQLite.
- Fresh start means no production importer, exporter, replay, archive, rollback authority, or historical compatibility path in the supported release.
- Capabilities use flat `reigh.<normalized>` names with one local binding; `family` remains the frontend key.
- Workers may admit allowlisted children only while holding the live parent fence; kernel ULIDs are the IDs.
- Generations/variants are relational; placement lives only in the CAS-versioned timeline document.
- Completion is atomic across task/attempt/output/media and optional generation/variant plus required registry visibility.
- Verified bytes publish durably into CAS before the receipt-bearing SQLite transaction; Phase A fault-injects every crash window and permits only invisible byte orphans.
- Render is an Astrid task producing a managed MP4; media is copy-only.
- Model acquisition uses a separate resumable setup journal and is the only setup-only outbound-network exception; execution remains fully local and network-blocked.
- Local trust adds a per-boot request capability, Host/custom-header checks, restrictive data permissions, bounded hostile-input handling, and a Comfy node allowlist—without accounts or tenancy.
- The timeline envelope carries `doc_format`; representation changes and registry pruning remain measurement-gated behind one logical document/version/save route.
- Capability conformance, Wan rollback, orchestrator interleavings, two hardware tiers, writer occupancy, and `refuse/degrade/queue` are explicit phase gates or measured policies.
- Polling is 2s active, 10s idle, and 30s timeline; SSE is deferred.
- The current implementation sequence is Phase A vertical slice, Phase B remaining local capabilities/orchestrators, Phase C app cutover/release.
