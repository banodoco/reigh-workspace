# VibeComfy Migration Megaplan Chain

This directory turns `docs/migration-vibecomfy.md` into an ordered Megaplan chain without starting it.

Sprint performance reviews are recorded after each milestone under `performance/`. They are the source of truth for whether a sprint actually completed to spec, separate from the chain plan and PR metadata.

- `performance/sprint-00a-kickoff-contract-freeze.md`

## Directive

Drive `chain.yaml` one milestone at a time until the migration is complete. Use the milestone profile from the chain spec; Sprint 01 onward is intentionally `all-codex`.

For every milestone:

1. Run `chain start --one`, inspect the actual outcome, and keep fixing/resuming until the milestone is truly done.
2. If a Megaplan harness edge case blocks or corrupts progress, root-cause it in `/Users/peteromalley/Documents/megaplan`, patch the harness, test it, push the harness branch/PR, then resume the chain.
3. If live VibeComfy or backend proof is required, use real RunPod yourself. Do not require extra WGP pre-run proof when WGP is already the trusted control.
4. Publish changed nested repos before advancing the top-level chain PR, and do not hide nested repo dirt behind a top-level commit.
5. Append detailed lessons, failure phase, root cause, fix, residual risk, and evidence to `/Users/peteromalley/Documents/learnings/megaplan-vibecomfy-sprint-00a-2026-05-05.md`.
6. Keep this directory's sprint performance notes current when a milestone completes or reveals an important harness/process issue.

Operating cadence for each milestone:

1. Start or resume only one chain milestone at a time.
2. Set a timed status check while execution is active. Default interval: 5 minutes unless the current work needs a tighter loop.
3. At each check, inspect process state, chain state, latest `execution_batch_*.json`, `execution_audit.json`, and changed files before calling the sprint healthy or blocked.
4. When the milestone reaches a terminal state, update the matching `performance/sprint-*.md` review with actual completion, verification evidence, issues, residual risks, and next actions.
5. Fix or explicitly defer the issues found in the performance review before advancing the chain to the next milestone.

Megaplan chain behavior, as implemented locally:

- `megaplan chain start --spec <chain.yaml>` validates the spec, creates/checks out each milestone branch, initializes a plan from the milestone idea file, and drives it through `megaplan auto`.
- Per milestone, this local chain runner now honors `profile`, `robustness`, and `phase_model` by passing them into `megaplan init`.
- Per milestone, `bakeoff` is recorded as chain metadata. It is not auto-run by `chain start`; use it to decide whether to run a separate `megaplan bakeoff run` before accepting that milestone's implementation plan.
- `megaplan chain status --spec <chain.yaml>` reads `chain_state.json` next to the spec and reports progress without driving work.
- Progress is resumable through `chain_state.json`.
- Each milestone idea file is independent; the chain driver does not pass `--from-doc`, `--mode metaplan`, or per-milestone output paths.

Use the verified launcher from this workspace:

```bash
PYENV_VERSION=3.11.11 python -m megaplan chain status --spec docs/megaplan-vibecomfy-chain/chain.yaml
```

To run later, use:

```bash
PYENV_VERSION=3.11.11 python -m megaplan chain start --spec docs/megaplan-vibecomfy-chain/chain.yaml --no-git-refresh
```

To run one milestone at a time and pause between milestones:

```bash
PYENV_VERSION=3.11.11 python -m megaplan chain start --spec docs/megaplan-vibecomfy-chain/chain.yaml --no-git-refresh --one
```

Repeat the same command after reviewing the completed milestone. The runner resumes from `chain_state.json`.

`--no-git-refresh` is recommended for this developer checkout so the chain does not automatically checkout/pull `main` before the first milestone. Remove it only in a clean orchestrator/CI checkout where that behavior is intended.
