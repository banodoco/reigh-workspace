# Operating the portfolio

Mandatory latest direction: read [the pure orchestration contract](orchestrator-contract.md). Astra low coordinates; Luna xhigh managers delegate all substantive execution; Astra high supplies sparse meta-oracle judgment within the existing budget. Give the startup read-back before dispatch. Operational instructions to inspect, edit, test, sync or merge mean delegate those actions, then judge the returned evidence.

Treat the coordinator as a capable colleague. Give managers the goal, source, constraints and next dependency; let them solve implementation details. Keep this portfolio's live memory to a short status, a project/thread map and the current shared-source handoff. Original tasklists and review evidence stay with their projects.

## Keep work visible in the same threads

### Startup and the portfolio ledger

Use [project checkpoint histories](checkpoint-history.md) for append-only hourly/event observations and subsequent Astra judgments. One assigned Luna writer owns each project's history; product inspection remains read-only. Keep status.md as the latest compact cross-project view, linked to those histories and original tasklists. This is the requested chronological evidence trail, not another source of task/acceptance authority.

This orchestrator is itself a tracked portfolio at `.otto/portfolios/astrid-delivery/`: `tasklist.md` holds META-1 through META-6, `status.md` is the current-state ledger, and `run.yaml` declares roles/budgets. Do not create a competing top-level run or another ledger. At receiving bootstrap, delegate recording the actual orchestrator thread UUID, receiving workspace/control root and resume mechanism alongside manager identities in `local/managers.json`. In `status.md`, record lifecycle, current META outcome/gate, last checkpoint time and judgment, next due check or earlier awaited event, current heavy job/next ready job, source-manifest link, remaining meta-oracle balance and blockers with owners. Link project-local counters/evidence rather than copying them. Update at meaningful events/checkpoints, preserving history; never fabricate an active session entry during preparation.

On startup, recover and supervise the destination's existing GPU/UE owner immediately, get its actual milestone and source handoff, and establish checkpoint coordination. **Do not simply watch Astrid and idle until a task named T7 finishes.** P7 CPU closure is the previously confirmed gate; R7/T7 wording must be mapped to the owner's actual current tasklist rather than assumed equivalent. While that gate is pending, delegate setup/source inventory, other-project readiness, disjoint contract/fixture preparation and authorized work that cannot mutate the protected GPU candidate. If no independent ready work exists, await the named event instead of manufacturing activity. Only overlapping implementation waits for the accepted checkpoint/main/dirty continuation composition. At that gate, delegate the preserve/compose → merge latest main → affected validation → same-owner continuation handoff.

### Thread identity and messages

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

## Resource-aware validation

### Test load and smart validation waypoints — 8 GB receiving Mac

Latest user direction: tests and their subprocesses are the expected RAM/CPU pressure point. Be thoughtful about what runs, when, and with how many processes. Do not turn each edit, agent handoff or hourly checkpoint into another validation campaign. Checkpoint investigators normally inspect existing evidence; they do not automatically rerun tests.

Use three meaningful validation levels: focused checks for changed behavior during implementation; affected integration checks when shared contracts or repository compositions meet; and the required broad campaign on the settled candidate. Batch related edits before running a relevant check where safe. Reuse passing receipts only when source, consumed dependencies/contracts, fixtures and relevant environment assumptions still match. After a correction rerun affected checks and prescribed reviews, not every unrelated suite. Required destination setup/smoke checks and original acceptance gates remain mandatory. Efficiency removes duplicate work, never missing proof.

The orchestrator coordinates admission of expensive local jobs through existing manager messages. Keep only the current job and next ready job in existing status; no scheduler, watcher or new ledger. A request names command/scope, exact source, expected child-process fan-out and services. Include the existing GPU manager's local load before granting admission. Start with **one heavy local job portfolio-wide**, using one test worker/build job/encoder thread where supported; alternatively allow **up to two small focused test processes when no heavy job is running**. Full suites, builds, dependency installation, browser suites, fixture renders and media encodes share that allowance. Disable automatic CPU-count parallelism initially; child processes count too. Independent project work does not confer independent heavy-test capacity.

Keep disjoint editing, reading and model/network work parallel when responsiveness permits. Delegate native macOS memory-pressure, swap/page-out trend, CPU contention and responsiveness checks before heavy launches and after slowdowns. Sustained pressure, growing paging or developer lag means defer the next heavy job and lower subsequent fan-out. Let healthy bounded work finish where practical; stop only an owned restartable offending process when necessary. Never stop the user's apps or another project's service as a shortcut. Resume conservatively after pressure settles; increase concurrency only after representative work demonstrates headroom, not from an invented free-RAM threshold. Prioritize dependency-unblocking checks and short corrective reruns without indefinitely starving the final required suite.

Reuse a compatible running service only when its revision/configuration matches and each test has isolated realms/databases, credentials, ports and output/cache locations as applicable. Never share mutable test state or a service reset globally by a test. Otherwise serialize isolated service lifetimes. Workers own teardown of their test children and temporary services, verify teardown after completion/failure, and report leftovers instead of launching another overlapping run. No remote GPU/provider allowance changes.

These rules are ordinary coordinator resource judgment, not another oracle invocation or review stage. [Astra's bounded preparation advice](analysis/mac8gb-astra-advice.md) informed the resource defaults; the user's latest smart-waypoint instruction governs cadence.

### Storage is a shared admission constraint too

Latest user direction: the receiving Mac also has constrained storage. Astra low owns disk-aware scheduling alongside RAM/CPU scheduling; delegated workers measure and perform any approved cleanup. Before clones/worktrees, dependency installs, builds, media downloads/renders or large tests, check available space on the actual destination volumes and estimate peak temporary plus retained output, including concurrent admitted jobs. Account for package/model caches, environments, duplicate checkouts, test databases, browser traces, encoded media and evidence. Keep a practical OS/developer reserve based on observed needs; no guessed universal threshold replaces an existing explicit project minimum (including UE's 4 GiB free-space and evidence limits).

Do not start a job whose expected peak and reserve will not fit. With unknown output size, use a bounded small probe or tighter output limits before admitting a large run. Reuse compatible dependencies and immutable artifacts where isolation permits, avoid unnecessary full clones/worktree copies and duplicate renders, and retain the source/test identities needed for receipt reuse. Avoid speculative large downloads. Check disk trend after output-heavy jobs or low-space alerts, not with another always-on watcher. After ENOSPC or disk-I/O failure, hold affected retries until capacity and partial-output integrity are checked; do not repeatedly rerun into a full disk or treat truncated evidence as passing proof.

Workers own their temporary paths, child processes and artifact retention. Delegate cleanup only of exact, verified run-owned disposable outputs/caches after checking no active process or receipt depends on them; prefer recoverable deletion. Preserve active worktrees, dirty source, user media/data, credentials, required fixtures and accepted evidence. Never sweep broad directories, remove another manager's files, or delete required proof just to make a job fit. If safe in-scope cleanup is insufficient, reduce scratch/output volume, serialize work or ask for storage/user direction while independent low-footprint work continues. Report what was removed and recoverability; no automatic broad cleanup script.

## Luna evidence at every checkpoint

At every scheduled check-in and before a dependency release, integration/merge, or completion decision, assign **one bounded Luna investigator per active project**, including GPU/UE and INT once active. Each independently inspects its manager's updates, changed source, test/review receipts, blockers, ownership overlaps and agent/resource use. This is per-project coverage, not a requirement to launch all investigators simultaneously: stagger them on the constrained Mac and reuse an already-running investigation for that same project/checkpoint. Dormant projects need only a readiness/dependency check. Avoid repeating unchanged deep investigations. These are read-only evidence gatherers, not new project managers, implementers or oracles; they do not spawn further agents.

Each returns a short evidence-linked report: what actually changed, claimed versus demonstrated completion, dependencies/conflicts, signs of drift or waste, and unresolved uncertainty. Bind findings to the inspected commit or dirty-worktree state and observation time. Reuse an investigation already underway for the same checkpoint rather than spawning duplicates; count investigators in the total concurrency/resource picture.

The orchestrator judges their findings itself: compare evidence, resolve contradictions with a focused check, and explicitly accept, hold or redirect the next step. Luna conclusions do not replace required project tests or reviews and cannot authorize a merge. If investigation is unavailable or incomplete, report the gap and hold the affected evidence-dependent gate. Summarize the judgment and next action in the existing orchestrator thread; send corrections to existing manager threads. Keep this lightweight—no standing review panel or mandatory long report for unchanged work.

## Hourly checks with wakeup-loop

Run the explicit eight-step [hourly checklist and targeted manager drill-down](assets/hourly-message.md). It covers progress evidence, delegated-worker efficiency, slow milestones, RAM/CPU/storage, budgets, dependencies, next assignments and same-thread reporting. This is a lightweight investigation/decision waypoint, not another test or review gate.

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
