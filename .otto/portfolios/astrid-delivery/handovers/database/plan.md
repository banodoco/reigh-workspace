> Frozen reference snapshot. Current state and receiving authority are governed by the package START-HERE and authority.md; preserve the existing live run. Paths below are source references, not missing package requirements.

# Delivery plan

The first useful outcome is a fresh realm that is created explicitly, verified before writable open and served through the existing domain API. Existing constraints, receipts, CAS, worker fencing and generated clients must keep working. Complete delivery additionally provides verified immutable snapshots and replacement recovery, not merely a fresh-schema prototype.

The source document states there are no users or supported production realms. Treat that as the planning premise; inventory actual development data and consumer closure at delivery start. Valuable existing roots/backups are preservation inputs, never test fixtures or targets for upgrade. No shipping migration subsystem is needed.

Implementation approach amended by the user following GPT-6 Astra medium's assessment: retain all C1–C8 and deliver through consolidation. Use a thin enforced lifecycle boundary over existing mechanisms. Avoid a manager framework, moving every SQL method, domain rewrites and rebuilding existing safety tests. Callers must not bypass admission. Reuse was already required; the revised estimate rests on specific retained mechanisms and gaps documented in [astra-assessment.md](astra-assessment.md).

1. Start with a half-day read-only reuse/gap map: resolve runtime/Astrid source custody, trace existing replacement orchestration, and map each C1–C8 criterion to retained code, an existing fixture or a concrete gap. Preserve dirty inputs. Define canonical format and bounded fixture matrix. Reconcile the estimate before implementation; unresolved source custody can extend this step.
2. Consolidate schema/identity initialization and read-only verification. Reuse existing SQLite backup, CAS hashing, ownership and durable publication helpers wherever they meet the contract; one manager should consolidate orchestration rather than add a parallel service.
3. Retain existing admission/transaction locking, CAS-journal reconciliation and atomic receipts; consolidate entry points and close bypasses. Tighten exact schema/identity enforcement and refuse missing roots before owner-lock directory creation. Prove refusal and race behavior using retained/adapted fixtures. The foundation review is the only intermediate gate.
4. Reuse SQLite backup and CAS-copy machinery; verify the completed candidate before snapshot publication. Complete inactive-realm restore with owner shutdown, catalog switching, credential renewal and interruption recovery. Establish freshness against the superseded live instance, not merely an increment of the snapshot's old epoch. In parallel where file ownership permits, serialize catalog registration and selection over the full read-modify-write operation and retain admission-based readiness.
5. Route server, CLI, Astrid and packs through the canonical runtime contract; remove obsolete migration/compatibility paths and regenerate clients once after the contract settles. Retain behavior-focused tests while deleting obsolete compatibility expectations.
6. Run the complete corruption/concurrency/crash/HTTP fixture matrix, broad affected suites and final integrated review. Document explicit fresh-realm provisioning and unsupported legacy inputs.

Keep the architecture decision from the source plan. Exact format identifier, schema inventory and manager placement are T1/T2 implementation details. Any proposal that changes safety properties, consumer behavior beyond legacy rejection, or source authority needs oracle judgment. Decompose difficult concurrency questions into fixture-backed tasks before XHARD escalation.

Estimate: **6–9 focused engineering days** for the complete conversion: T1 0.5 day, T2–T3 1.5–2.5, T4–T5 2–3, T6 1–1.5, T7 1–1.5. This includes fixture adaptation, integration and review corrections; it is not an agent elapsed-time prediction. **10–15 days is a contingency** if replacement integration, source custody or consumer closure reveals deeper gaps. T1 must establish whether the lower range holds. Inspected test definitions are not passing evidence.

A **3–5-day smaller milestone** could deliver canonical create/open, consolidated admission, catalog/bootstrap fixes and focused checks. It excludes complete snapshot/replacement guarantees, full compatibility removal and consumer closure. This is not the selected scope and does not complete this run. There is a meaningful reduction in churn, but no evidence for a literal 90:10 effort reduction.

Preserve publication-race coverage when adapting tests that import migration code slated for deletion. Existing generated-operation/digest parity is insufficient for C7; add focused success and typed-error behavior checks, reusing the rest of the suite.

Validation uses isolated temporary roots and catalogs, never the corrupt realm. Required scenarios are specified in implementation-criteria.md. No tests have run during setup.
