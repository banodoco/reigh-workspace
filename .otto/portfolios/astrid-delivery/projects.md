# Projects and handovers

Workspace-relative active roots below are the same-machine source of live status. Bundled handovers are frozen planning inputs, not replacement ledgers. Record each actual manager thread/session and current source in the local status when taking over; do not publish private transcript IDs.

| ID | Project and frozen handover | Existing active/local root | First useful assignment |
|---|---|---|---|
| unified-execution | [Ratified v3](handovers/unified-execution/UNIFIED-PLAN-v3.md), [captured idea](handovers/unified-execution/idea-snapshot.md), [current-state note](handovers/unified-execution/CURRENT.md) | Current `megado-unified-v3` handoff must be located through the existing UE manager; historical location `c12-safety-snapshot-20260908/megado-unified-v3` is absent here | Continue P7 CPU closure; obtain exact candidate/contracts/counters and remaining acceptance |
| database | [Goal](handovers/database/agent_goal.md), [plan](handovers/database/plan.md), [criteria](handovers/database/implementation-criteria.md), [tasks](handovers/database/tasklist.md), [roles](handovers/database/run.yaml) | `Astrid/.otto/runs/runtime-database-clean-break-20260910` | Reconcile Runtime source; align GEN and E2 schema requirements; preserve safety fixtures |
| generation | [Goal](handovers/generation/agent_goal.md), [plan](handovers/generation/plan.md), [D1](handovers/generation/oracle-D1.md), [tasks](handovers/generation/tasklist.md), [roles](handovers/generation/run.yaml) | `.otto/runs/astrid-generation-path-alignment-20260910` | Define publication intent/identity, consume accepted UE session/output contracts |
| visualization | [Goal](handovers/visualization/agent_goal.md), [plan](handovers/visualization/plan.md), [criteria](handovers/visualization/implementation-criteria.md), [tasks](handovers/visualization/tasklist.md), [roles](handovers/visualization/run.yaml), [UX fixture](handovers/visualization/test-project.md) | `Astrid/.otto/runs/timeline-visualization-fixes-20260910` | Preserve current dirty implementation; parser/clock/coverage/fixture work; E2 migration stays downstream |
| render | [Goal](handovers/render/agent_goal.md), [plan](handovers/render/plan.md), [criteria](handovers/render/implementation-criteria.md), [tasks](handovers/render/tasklist.md), [roles](handovers/render/run.yaml) | `Astrid/.otto/runs/runtime-render-path-reliability-20260910` | Scoped resolution and filename trace; DB owns shared recovery truth |
| ephemeral | [Goal](handovers/ephemeral/agent_goal.md), [plan](handovers/ephemeral/plan.md), [criteria](handovers/ephemeral/implementation-criteria.md), [tasks](handovers/ephemeral/tasklist.md), [roles](handovers/ephemeral/run.yaml), [adopted shared decision](handovers/ephemeral/shared-decision.md) | `Astrid/.otto/runs/ephemeral-derived-artifact-lifecycle-20260910` | Output intent and lifecycle schema design with DB/GEN; synthetic producer; E2-06 after V1 |

Each directory also contains its original North Star and status where available. Full original task and criterion IDs remain intact. The compact meta tasklist coordinates these plans rather than renumbering them.

## Shared ownership

- DB manager directs shared Runtime schema/transaction/recovery changes, taking GEN/E2/RRP requirements. Contributors retain acceptance of their own behavior.
- UE manager owns the current P7 candidate and accepted engine-session contracts. Obtain its handoff before a shared host write.
- GEN manager directs the common output-publication patch; E2 owns lifecycle semantics and RRP owns filename/opening requirements. Implement common metadata changes once and check each consumer.
- One manager directs each worker. Shared-file custody is a scheduled turn, not another manager issuing instructions to that worker.
- V1 and E2 share **two remaining oracle calls total**, inherited from the central original three-call budget with one consumed. Their current run.yaml values are ceilings on the same balance. V1's two bounded Astra UX invocations are separately accounted, not oracle calls. Do not copy the remaining balance into two independent pools.

## Snapshot limits

Source-state records in the original E2 setup refer to workspace recovery HEAD `3291081`, while its run is stored inside Astrid. Reconcile actual Astrid/Runtime ownership before edits. Do not treat this location mismatch as a reason to widen scope or delete old state.

Older analysis may refer to a five-program portfolio or E2 being out of scope; this user's later inclusion and authority.md supersede that. Historical UE phase tables and missing original paths are provenance, not a fresh launch queue. Existing counters/reviews require the active handoff.
