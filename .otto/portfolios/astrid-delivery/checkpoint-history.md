# Project checkpoint histories

Keep an hourly/event history so the orchestrator can compare the plan, observed work and its own previous decisions. This is a record of observations and decisions, not a second task list, acceptance ledger or scheduler. Original project tasklists/criteria and counters remain authoritative; portfolio status.md is only the latest cross-project summary.

## Location and ownership

On the receiving Mac, create histories only when a project is first inspected:

`local/checkpoints/PROJECT_ID.md`

Use IDs `unified-execution`, `database`, `generation`, `visualization`, `render`, `ephemeral` and `integration`. The existing `local/` ignore rule keeps destination identities and operational history out of public handover commits. Do not create fabricated hourly entries during preparation. Preserve these files across resume/handover; transfer them privately when required, never silently discard them as temporary logs.

At every checkpoint, the project's assigned Luna investigator reads its previous entry and pending action plus the original tasklist/current plan. It appends one concise observation using [the entry template](assets/checkpoint-entry.md). Its access is read-only for product source, tests and other agents' state; the sole write exception is its assigned history entry. One writer per project history at a time. Reuse an in-flight investigation for the same project/checkpoint rather than duplicate it.

The orchestrator supplies a shared checkpoint ID (UTC timestamp plus `hourly` or a named event) in the briefs. Record actual inspection time and the interval since the previous observation, not a fictional exact hour. If a checkpoint was missed, mark the gap; do not backfill invented results. Different projects may finish their inspections at different times. An incomplete/failed investigation is recorded as such, never as “no change.”

## What an observation must establish

- Planned task/criterion IDs, original tasklist link and plan revision/digest, including the applicable accepted steering. Plans changing legitimately is not itself drift: link the instruction and preserve the old baseline.
- Inspected source revision/dirty identity and observation interval; link evidence at its original location instead of copying transcripts or test output.
- What actually changed, with evidence: implementation, test result, resolved uncertainty, handoff or justified waiting. Separate manager claims from verified facts; missing access remains unknown.
- Plan-versus-actual discrepancy, if any; blocker/owner; worker duplication or scope drift; repeated validation; relevant RAM/CPU/storage or orphan-process issue. An absent discrepancy is not project acceptance.
- Outcome of the previous assigned action: completed with evidence, still in progress with reason, ineffective or unknown. Suggest the smallest useful next action, not an oracle verdict.

Normally use 6–10 short lines. For a genuinely unchanged interval, a compact entry naming the same task/source, waiting event/owner and previous-action state is enough. Never copy the entire project plan or repeat unchanged historical evidence. No new tests are launched merely to populate the history.

## Judgment and next-check feedback

After reading the project reports and comparing them with the original tasklists/dependencies, Astra states its judgment in the existing orchestrator thread. Delegate appending that exact judgment to each entry: continue / unblock / redirect / await named event / hold affected lane; reason; assigned manager/action; evidence expected; next meaningful check or event. Use the same investigator after its observation is finished, or a bounded bookkeeping worker with explicit sole write custody. No investigator may invent Astra's judgment. Until supplied, the decision is explicitly **pending**; an observation is not an accepted gate.

Entries are append-only: preserve the original observations and judgments. Add timestamped corrections or later decisions referencing the entry rather than rewriting history. Append the judgment once after the observation; deduplicate by checkpoint ID and project. On interruption, recover the existing entry and append the missing section rather than rerun completed investigation or duplicate the entry.

The next checkpoint starts by checking whether that action produced the intended result. Repeated discrepancies or decisions without changed evidence trigger the existing targeted drill-down/coordination repair, not an automatic whole-project audit, extra model review or extra tests. Quiet healthy work and resource-aware waiting remain valid outcomes.

## Portfolio view

Every 12 hours, [the scheduled Astra course-correction checkpoint](periodic-course-correction.md) consumes the overall plan and complete history access. Its relevant rulings are appended to affected project histories with action owners; subsequent hourly entries assess the outcomes. Keep observed elapsed hours distinct from the number of actual observations, and preserve gaps honestly.

A delegated recorder maintains a short row per active project in status.md: original task/gate, latest observed change, Astra disposition, owner/next action and link to the latest history entry. Use portable relative links within the receiving workspace when possible; actual local history links are created at bootstrap, not shipped as broken public links. Older rows are not a competing history—the per-project file owns chronology. The hourly user update highlights material changes, discrepancies and actions; it need not reproduce every entry.

Keep histories small by linking evidence and avoiding raw logs. If a history becomes unwieldy, split closed periods into chronological files in the same local directory and retain an index/link from the current project file; preserve the records. Storage pressure does not authorize deleting required evidence or rewriting past judgments.
