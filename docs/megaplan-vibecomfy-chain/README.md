# VibeComfy Migration Megaplan Chain

This directory turns `docs/migration-vibecomfy.md` into an ordered Megaplan chain without starting it.

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
