# Operating the portfolio

Treat the coordinator as a capable colleague. Give managers the goal, source, constraints and next dependency; let them solve implementation details. Keep this portfolio's live memory to a short status, a project/thread map and the current shared-source handoff. Original tasklists and review evidence stay with their projects.

## Keep work visible in the same threads

There is one orchestrator thread and one manager thread per project. Reuse the existing UE manager. For new managers, open a named Codex Terminal window once, record its actual UUID and project root in `local/managers.json`, and use that UUID for follow-ups. Thread titles are labels, not identity. Do not create a fresh manager at every hourly check.

Verified local CLI: Codex 0.153.4 has `queue --thread UUID --message TEXT`, interactive `resume UUID [PROMPT]`, `-C`, `-m` and `-c model_reasoning_effort=...`. `codex agents` provides interactive discovery; no machine-readable listing mode was verified. Terminal.app is installed. Required Luna/Sol/Astra models are present in the local model cache and native delegation is available in the preparing environment; receiving CLI account access must still be verified on first actual use. Never silently substitute a model.

Use `python3 scripts/open-manager.py PROJECT_ID --workspace /absolute/workspace` to inspect a launch command; it is **dry-run by default**. Once you have checked there is no existing live owner and the active run is initialized, add `--execute` to open one Terminal window from the canonical active portfolio root. The helper reads the coordinator binding from the active project's run.yaml, falling back to the frozen handover for dry-run readiness only. It makes no permission-policy override. Projects are `database`, `generation`, `visualization`, `render`, `ephemeral`, and `integration`; UE is intentionally not a new-launch option. Release integration after the accepted continuation checkpoint, then give it the current multi-repository manifest and its own tasklist.

Before launch, check the existing thread map plus current session/process evidence. A launch marker prevents repeated helper launches but does not prove liveness; after a failed launch inspect and reconcile it rather than deleting it blindly. In the new thread, the manager records its UUID, actual active run root and source. The helper does not invent those values.

For a **live** manager, use the same thread:

```sh
codex queue --thread ACTUAL_UUID --message 'Read the current portfolio status; here is the accepted handoff and your next ready task: ...'
```

For an **inactive persisted** manager, resume it once with `codex resume ACTUAL_UUID` in its project directory. Do not resume a live owner or use `fork` as continuation. The new user mandate authorizes the receiving orchestrator's scoped messages to these project managers; no messages are sent by preparation.

## Updates that reveal drift

Managers post after meaningful results, failures, handoffs or changed direction, and about hourly while active. A good update is four short sentences: what changed; evidence/source; what is next; any risk or decision. The orchestrator posts its cross-project update in its own thread. No unchanged polling transcript is needed.

At a check, look for a specific sign of drift: worker output outside its brief, repeated source changes under a frozen candidate, a new abstraction without a requirement, more workers than distinct ready tasks, two agents doing the same search/test, or repeated reviews without a changed candidate. Ask the manager for a concrete correction in the existing thread. Do not infer waste from window count alone or interrupt a healthy slow worker merely because it has been quiet.

Use **three ready implementation lanes** once source custody and consumed contracts permit: DB Runtime foundation, V1 visualization, and RRP scoped resolution/opening. A fourth worker may build the V1 fixture or, later, a disjoint GEN adapter when its brief has distinct paths and a ready interface. These are capacity targets, not a requirement to keep agents busy. Before the P7 checkpoint, retain the candidate freeze and run only genuinely disjoint work; reduce concurrency whenever machine capacity or file ownership requires it. Count managers, reviewers, investigators and actual test/daemon load across the whole portfolio. Serialize broad expensive tests and shared daemons; isolate focused test realms, ports and output directories. No new provider/review budget is granted. Reviewers remain leaves; no recursive panels.

GEN/E2 contract requirements and synthetic fixtures can progress while DB owns shared Runtime mutations; do not assign simultaneous owners to the same schema/store files. GEN cloud and local adapter lanes split only after T3's stable interface. V1 caption/coverage work can overlap only where shared SDK edits are serialized. The Integration & E2E manager consumes accepted handoffs continuously and directs final multi-repository main promotion; see [repositories.md](repositories.md).

## Luna evidence at every checkpoint

At every scheduled check-in and before a dependency release, integration/merge, or completion decision, deploy bounded Luna subagents to understand the work across the active projects. Split by distinct active workstreams or shared-risk surfaces; normally one or two investigators, with one able to cover several quiet projects. Inspect current manager updates, changed source, test/review receipts, blockers, ownership overlaps and agent/resource use. Cover every active project without repeating unchanged deep investigations. These are read-only evidence gatherers, not new project managers, implementers or oracles; they do not spawn further agents.

Each returns a short evidence-linked report: what actually changed, claimed versus demonstrated completion, dependencies/conflicts, signs of drift or waste, and unresolved uncertainty. Bind findings to the inspected commit or dirty-worktree state and observation time. Reuse an investigation already underway for the same checkpoint rather than spawning duplicates; count investigators in the total concurrency/resource picture.

The orchestrator judges their findings itself: compare evidence, resolve contradictions with a focused check, and explicitly accept, hold or redirect the next step. Luna conclusions do not replace required project tests or reviews and cannot authorize a merge. If investigation is unavailable or incomplete, report the gap and hold the affected evidence-dependent gate. Summarize the judgment and next action in the existing orchestrator thread; send corrections to existing manager threads. Keep this lightweight—no standing review panel or mandatory long report for unchanged work.

## Hourly checks with wakeup-loop

Use the user-selected **wakeup-loop** same-thread waiting helper, packaged in [dependencies/wakeup-loop/SKILL.md](dependencies/wakeup-loop/SKILL.md). The source was previously named wakeup-look; the user explicitly renamed it wakeup-loop for this handover. There is no custom hourly watcher, background scheduler or auto-queue loop.

The orchestrator stays in its current turn: await a bounded delay, inspect manager updates and evidence, take a useful next action, send a concise update, and await again when waiting is appropriate. Never launch a wait and end the turn. If the tool yields a running handle, keep awaiting that handle; steering or early tool returns do not mean the wait completed. Use the actual host's wait tool rather than inventing a Hub command in Codex.

Read the helper before use. For an approximately hourly cadence, a 3540-second wait leaves headroom below its documented one-hour call limit. If exactly one hour matters, await that segment and then a separate 60-second segment. Individual tool waits should yield often enough to receive steering and communicate; the helper's total sleep is not permission for a single uninterruptible hour-long tool wait.

```sh
bash dependencies/wakeup-loop/scripts/wakeup_loop.sh \
  --sleep 3540 --poll 60 --label 'Astrid portfolio check' \
  --message 'Continue this same thread. Read assets/hourly-message.md, inspect progress, and decide the next action.'
```

Prefer separate completed waits so the coordinator can act between them; an internally repeating forever sleep is not itself supervision. The helper neither restarts a closed conversation nor survives loss of the owning turn. On a later resume, read durable status and continue the same project threads. Nothing is started during handover preparation.

The check prompt is [assets/hourly-message.md](assets/hourly-message.md). Event-driven manager updates can release work before the hour. Act only when useful work or a concrete problem is available; do not manufacture edits or oracle requests while healthy work is underway. Stop waiting when the goal is complete or no authorized progress is possible, and report the precise outcome.

## Decisions and budgets

Routine in-scope scheduling, focused corrections and evidence-based handoffs belong to the managers/orchestrator. Send consequential or contested architecture judgments to the owning run's designated oracle. Ask the user only for a real missing authority or budget change, after preparing a concrete choice. Keep independent work moving.

The active meta [run.yaml](run.yaml) defines its roles; original project YAML defines theirs. Existing review counters are preserved. V1/E2 share a single remaining oracle balance; their YAML ceilings are not two grants. The handover's Astra high critique is a one-off preparation review, not an extra project certification stage. No per-hour model-review panel is needed.

Read role bindings and ceilings from run.yaml; recover consumption from active status, receipts and the actual handoff. Before either V1 or E2 invokes an oracle, identify the existing central accounting record and serialize the charge there through one owner. Record that location in portfolio status. If the old central record cannot be recovered, establish one reconciled shared balance from the original receipts (two remaining at handover), obtain both managers' acknowledgment and retain the history; never create two independent allowances.

The final check is actual code/tests/required reviews integrated to main and remote identity verified. Then stop monitoring and provide links to the result. If mandatory evidence is unavailable, name that gap; do not call the full goal complete because every agent stopped.
