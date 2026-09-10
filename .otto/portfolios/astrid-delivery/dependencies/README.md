# Fetch and sync the inspected skills

Use GitHub repository `https://github.com/peteromallet/poms-skills.git`, branch `handover/astrid-portfolio-20260910`, exact commit **`d849898cd0c191cffc5ababbb5ea7d2c188e8ed0`**. Its remote ref was verified after publication. Parent `f1296034386486d65cf19876d5e5ebfb0547e7cf` alone is insufficient: it does not contain `sync.sh` or the selected wakeup-loop helper, and predates the inspected local Megado changes.

The published branch adds only the inspected Megado update, actual local `sync.sh`, and user-renamed wakeup-loop skill/script to the existing public skills tree. It intentionally excludes unrelated local skills and `_global/`; therefore this checkout's sync cannot replace global CLAUDE.md/AGENTS.md files. Source/export hashes are in [provenance.json](provenance.json).

## Required receiving-machine setup

Use a new dedicated directory; never clone over an existing checkout or switch a dirty shared skills repository:

```sh
POMS_DIR="$HOME/.local/share/poms-skills-astrid-20260910"
test ! -e "$POMS_DIR" && test ! -L "$POMS_DIR"
# Continue only if the preceding check succeeded; otherwise inspect/reuse it below.
git clone --branch handover/astrid-portfolio-20260910 --single-branch \
  https://github.com/peteromallet/poms-skills.git "$POMS_DIR"
git -C "$POMS_DIR" rev-parse HEAD
```

Verify HEAD equals `d849898cd0c191cffc5ababbb5ea7d2c188e8ed0` before syncing. For a previously created **clean checkout of this same branch**, inspect `git status --porcelain`, branch and remote first, then use `git -C "$POMS_DIR" pull --ff-only origin handover/astrid-portfolio-20260910`. Verify the same pin again. If the branch has advanced, inspect the change and use a separate checkout pinned to the agreed commit; do not silently adopt a newer skill or overwrite a dirty checkout.

Read the fetched `sync.sh`, verify its hash against provenance, ensure the desired harness skill directory exists, then **run the actual sync command on the receiving machine**:

```sh
POMS_SKILLS_SKIP_CLOUD=1 bash "$POMS_DIR/sync.sh"
```

The local-only flag is mandatory here. Without it, the existing script also synchronizes its configured cloud workspace, outside this handover's setup scope. It has no dry-run flag. The command creates links only in harness skill directories that already exist and skips every existing skill entry. It does not overwrite or delete them. The dedicated published checkout has no `_global/`; do not add one as a setup step.

Inspect the output and resolve the actual installed paths for `megado`, `megado-handover`, and `wakeup-loop`. A `skip` is not proof that the installed version matches this pin. If an existing entry differs, preserve it and use the explicit pinned skill paths below; record the mismatch in local status rather than claiming the alias was upgraded. Do not replace other active agents' skill entries silently. No global or cloud sync was run during preparation; this is a required recipient action.

## Exact use and fallback

Read `$POMS_DIR/megado/SKILL.md` and `$POMS_DIR/megado-handover/SKILL.md` directly. Use `$POMS_DIR/wakeup-loop/SKILL.md` and execute its exact `scripts/wakeup_loop.sh`, not a same-named older installed helper. The inspected equivalents are vendored here as [Megado](megado/SKILL.md), [handover](megado-handover/SKILL.md), and [wakeup-loop](wakeup-loop/SKILL.md), so network failure does not prevent reading or independent readiness work. Report failed GitHub sync and finish it before claiming setup complete.

For supervision, follow [operations.md](../operations.md): separately awaited bounded waits in the current thread, with a real status decision between waits. Never use an internal forever repeat as a substitute for the coordinator checking work. Verify required model and native delegation access on the receiving account; no silent model substitutions.
