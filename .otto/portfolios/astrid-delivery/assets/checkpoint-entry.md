# Checkpoint entry template

Copy the observation block into the assigned project's local history. Replace placeholders with observed facts or explicit unknowns. Do not treat this template as an actual checkpoint. Follow [history ownership and workflow](../checkpoint-history.md).

```markdown
## CHECKPOINT_ID — PROJECT_ID

### Luna observation — observed at UTC_TIME

- Interval / previous entry: START → END; previous ID/link or first observation.
- Plan: original task/criterion IDs; tasklist/plan link and revision/digest; applicable steering.
- Source: repository SHA(s)/dirty identity; relevant evidence/environment identity.
- Planned → actual: expected milestone; demonstrated change and evidence links; claims/unknowns separate.
- Previous action outcome: prior decision/action ID; result/evidence, still waiting reason, or unknown.
- Discrepancies / efficiency / resources: evidence-backed finding or none observed; no invented measurements.
- Blocker and proposed next action: owner, awaited event or smallest useful assignment.

### Astra judgment — pending
```

Only after Astra decides, the sole delegated writer appends this second block. Leave the pending marker as historical state; the later timestamped judgment resolves it.

```markdown
### Astra judgment — decided at UTC_TIME

- Disposition / reason: continue | unblock | redirect | await event | hold affected lane; concise reason.
- Assignment: manager/owner; concrete next action; expected evidence and next check/event.
- Decision source: orchestrator-thread message/time or durable decision reference.
```

Do not append the decided section until a real decision exists. For no-change intervals, compress the observation to task/plan/source identity, evidence inspected, waiting event/owner and prior-action state; retain the actual timestamp and decision workflow. For failed/incomplete inspection, say what could not be established rather than writing “no change.” Corrections are separate timestamped notes referencing the original entry.
