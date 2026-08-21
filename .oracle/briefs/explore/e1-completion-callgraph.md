# Explore E1: completion call-graph fan-in (every caller of the media publication helpers)

Read `.oracle/northstar.md` and `.oracle/agent_goal.md` first. Work in `/Users/peteromalley/Documents/Astrid-oracle`.

Known: `TaskRepository.complete` (astrid/core/repositories/tasks.py:3517) → `materialize_prepared` (media.py:1603, in-UoW) → `publish_prepared_media` (io/media_import.py:938–949). The §5 amendment moves publication before `BEGIN IMMEDIATE`. Task: find EVERY caller of `stage_prepared_media`, `publish_staged_media`, `publish_prepared_media`, and `materialize_prepared` across the whole repo (grep + read each call site). For each caller: file:line, what it publishes, whether pre-transaction publication changes its behavior, and whether it must migrate in Phase A or can be scoped later. Also verify `_fsync_file`:746 / `os.replace`:920 durability pattern details.

Report ranked findings (<300 words) with file:line evidence; end with a clear recommendation: clean cutover of all callers vs scoped-to-Reigh-path.
