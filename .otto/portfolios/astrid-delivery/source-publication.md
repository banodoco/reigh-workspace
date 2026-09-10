# Published source and custody

Selected source and skills were published normally and remote refs verified on September 10, 2026. These are preservation inputs, not proof that the six projects or their combined composition are complete.

| Repository | Published ref | Exact commit |
|---|---|---|
| peteromallet/Astrid | main | `b33b1593fa7b89c6600a3b14fc7b8a5641b494ad` |
| banodoco/banodoco-workspace-runtime | main | `c38590a07f1ca3ec9d28cb018fddd7760f9be6ce` |
| peteromallet/poms-skills | handover/astrid-portfolio-20260910 | `d849898cd0c191cffc5ababbb5ea7d2c188e8ed0` |

The control package is published separately in public banodoco/reigh-workspace, branch `handover/astrid-portfolio-20260910`, based on main `b1993c35a0000833f1990589c9cc280884ef322d`. Its exact commit is supplied in the preparer's final delivery message and verified with `git rev-parse HEAD` in the fetched checkout. Do not substitute the dirty workspace recovery branch: its 38 additional commits are not part of this publication.

## What was preserved

**Latest publication supersedes the earlier source pins below:** both main refs in the table were independently verified after normal pushes. Read [the latest publication and validation receipt](latest-source-publication.md). It includes Astrid's SDK/CLI and later host/assets snapshot, Runtime's feature/main/dirty composition and bounded integration corrections, plus proof limitations. The original JSON and paragraphs below are historical preservation records, not the current main baseline.

[source-publication.json](source-publication.json) records all **44 Astrid** and **15 Runtime** selected paths, Git blob identities, parent/tree/commit SHAs, exclusions and post-publication observations. Astrid's parent is `82d09bb91c8a4621695c1d8b6966652cad941ef4`; Runtime's is `afccb430e2a983c968b6a8a96fd630ba3a6262fc`. [CPU validation](analysis/source-validation.md) records the bounded 276 + 31 passing tests on audited dirty inputs. Those tests are not P7 or portfolio acceptance.

Source snapshots used isolated Git indexes and commit-tree. **Active local HEADs, indexes and dirty files were intentionally preserved**, even though remote Astrid main advanced. Do not run an unexamined pull/reset in those active checkouts or apply an old dirty patch on top of already-published contents. Fetch refs, compare selected blobs and current owner state, and integrate in the agreed continuation custody.

Concurrent work continued after the snapshot: Astrid acquired additional status entries; Runtime's tracked patch changed and an additional boundary test appeared. Published snapshots are unaffected, but do **not** include every later local edit. Capture and reconcile that delta with its owner at the P7 handoff. Publication does not freeze another manager's work.

Runtime was initially preserved on a handover branch only. The user's subsequent explicit publication instruction superseded that decision: the latest validated source composition is now on main at the table's pin. This does not migrate live data or certify GPU/portfolio completion. The orchestrator still coordinates the destination GPU candidate plus latest main at its verified checkpoint.

## Exclusions and other inputs

Excluded: assessment/eval/pitfall corpora, generated outputs, caches, logs, archives, credentials, unrelated control state, non-allowlisted local edits and other repositories' dirty source. The Reigh orchestrator has separate unresolved conflict/operational work and was not swept into publication. Preserve it; do not repair or publish it by implication.

Read-only baseline observations, to refresh before integration: Reigh app `3d3e088653c4b7ff00eca2ecfd9c23859ca0f9f7`; Reigh worker remote main `d8fb28875f78bd189dc4046369ee34dcf50e2c1a` (local main was seven commits behind); VibeComfy main `898c4e63cb60a31fe1af9ce5a1fbaa62762d465d`. Existing VibeComfy handover refs remain separate inputs, not automatically selected main: `handover/unified-workflow-integrity-20260909` at `a5489db88a0052d2ec35ed4702983fee0fbc5869`, `handover/canonical-workflow-integrity-20260908` at `cb130f1b737c6e2043a93089c24b3fcbac166b69`, and `handover-main-integration-20260909` at `6bd8290a081d1b93b3403db6d5d9dcf82f043900`. The UE manager supplies the actual selected cross-repository candidate.

## Skills and recipient setup

[Dependency setup](dependencies/README.md) names the exact published skills revision and required receiving-machine local-only sync. The new skills commit includes inspected dirty Megado content and user-renamed wakeup-loop; parent `f129603...` alone is not the runnable setup. [Provenance](dependencies/provenance.json) distinguishes original and exported content. No installed aliases, global instructions or cloud agents were changed during preparation.
