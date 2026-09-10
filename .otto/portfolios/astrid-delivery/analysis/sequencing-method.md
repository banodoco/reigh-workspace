> Frozen reference snapshot. Current state and receiving authority are governed by the package START-HERE and authority.md; preserve the existing live run. Paths below are source references, not missing package requirements.

# Lightweight project sequencing

Use one small dependency ledger alongside existing project plans. Keep original task IDs, acceptance criteria and evidence; do not create a second task scheduler or duplicate tasklists.

## 1. Describe the boundary, not just the project name

For each project record: intended user outcome; authoritative planning root and current candidate; contracts/state it owns; contracts it consumes; files it may change; explicit exclusions; remaining acceptance gates. Distinguish planned, implemented, reviewed, integrated and live-proven. A reviewed isolated branch is not automatically the baseline of another project.

## 2. Classify each interaction

| Relationship | Meaning | Scheduling rule |
|---|---|---|
| Contract prerequisite | B needs an accepted behavior/interface from A | A's named handoff gates B's dependent task, not automatically all of B |
| File collision | Tasks write the same source | One writer at a time; record source handoff, even if semantically independent |
| Duplicate responsibility | Two plans implement the same authority or operation | Choose one implementation owner; retain both acceptance obligations |
| Candidate/integration prerequisite | B must use A's accepted source composition | Freeze and reconcile exact source; rerun affected evidence on combined candidate |
| Validation/rollout prerequisite | B can be developed independently but cannot claim completion or ship | Allow bounded implementation; gate acceptance/rollout explicitly |
| No material overlap | Different files, authority and prerequisites | Run concurrently within available capacity |

Same-file overlap is not proof of a semantic prerequisite. Different files are not proof of independence. Cyclic prerequisites indicate that a contract must be designed jointly and then implemented by one owner.

## 3. Keep one row per meaningful handoff

| Producer milestone | Consumer task | Relationship | Exact handoff and evidence | Source/contract revision | Owner | State |
|---|---|---|---|---|---|---|
| Example: DB foundation | GEN settlement | Contract prerequisite | Reviewed admission/transaction/verifier contract and retained safety fixtures | Frozen candidate + schema revision | Runtime owner | Pending |

Every actual row needs a concrete producer milestone and consumer task, not “project A before project B.” States are pending, ready, accepted, or invalidated, with evidence links and observation time. Keep live project status in its own authoritative ledger; this table references it.

## 4. Dispatch from the ready set

A task is ready when its prerequisite handoffs are accepted for the source it will consume, source custody is resolved, its write set is available, and the action falls within existing authorization. Read-only investigation and fixture design may be ready before implementation. Implementation may be ready before integration or live validation.

Prefer finishing an in-flight shared foundation to starting a competing rewrite. Meanwhile, release disjoint work. “Finish the older project first” is appropriate only when its whole acceptance boundary is actually required, its remaining work is inseparable from the shared interface, or concurrent work would have prohibitive reconciliation cost.

## 5. Re-evaluate at handoffs

At each accepted milestone or material scope change: update exact source/contract identity; check downstream assumptions; invalidate only evidence affected by a change; recompute the ready set. Do not rerun every suite or reset review budgets merely because a new plan is added.

For a newly discovered predecessor or follow-up, check whether it changes the assumed source baseline before preserving an earlier sequencing recommendation. Add its edges to the existing plan and state what changed. Do not silently alter active run instructions or interrupt its workers.

The deliverable is a boundary summary, a handoff table, an ownership map, and the next ready tranche. The [portfolio plan](portfolio-plan.md) is the initial application; the GPU follow-up assessment adds the newly discovered upstream context.
