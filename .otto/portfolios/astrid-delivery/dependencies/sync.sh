#!/usr/bin/env bash
# Sync skills + global instructions from this directory into ~/.claude, ~/.codex,
# ~/.agents, and the persistent Megaplan Cloud workspace.
#
# Three jobs:
#   1. SKILLS — for each top-level directory here (except _underscore ones),
#      create a symlink in ~/.claude/skills, ~/.codex/skills, and ~/.agents/skills,
#      ONLY IF nothing exists at that path yet. Never deletes or overwrites existing entries.
#   2. GLOBAL INSTRUCTIONS — symlink _global/global-instructions.md to each
#      harness's universal preamble file (~/.claude/CLAUDE.md, ~/.codex/AGENTS.md).
#      If a real file already lives there, it is moved aside to a timestamped
#      .bak (never deleted); an existing correct symlink is left alone; a symlink
#      pointing elsewhere is reported and left.
#   3. MEGAPLAN CLOUD — rsync a dereferenced copy of this repository to the
#      persistent AgentBox workspace and expose each skill through its shared
#      .codex/skills directory and the resident control container. Unrelated
#      cloud skills and isolated running project containers are left untouched.
#      Set POMS_SKILLS_SKIP_CLOUD=1 for an intentionally local-only sync.
#
# Anything pre-existing that you want replaced (other than the global files, which
# are backed up) must be removed by hand.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_TARGETS=(
  "$HOME/.claude/skills"
  "$HOME/.codex/skills"
  "$HOME/.agents/skills"
)

created=0
skipped=0
skill_names=()

# --- job 1: skills ---
for entry in "$SRC_DIR"/*/; do
  [ -d "$entry" ] || continue
  name="$(basename "$entry")"
  case "$name" in
    _*) continue ;;   # _global and other underscore dirs are not skills
  esac
  src="$SRC_DIR/$name"
  skill_names+=("$name")

  for target_dir in "${SKILL_TARGETS[@]}"; do
    [ -d "$target_dir" ] || continue
    dest="$target_dir/$name"

    if [ -e "$dest" ] || [ -L "$dest" ]; then
      printf 'skip   %s (exists)\n' "$dest"
      skipped=$((skipped + 1))
      continue
    fi

    ln -s "$src" "$dest"
    printf 'linked %s -> %s\n' "$dest" "$src"
    created=$((created + 1))
  done
done

# --- job 2: global instructions ---
GLOBAL_SRC="$SRC_DIR/_global/global-instructions.md"
GLOBAL_TARGETS=(
  "$HOME/.claude/CLAUDE.md"
  "$HOME/.codex/AGENTS.md"
)

if [ -f "$GLOBAL_SRC" ]; then
  for dest in "${GLOBAL_TARGETS[@]}"; do
    parent="$(dirname "$dest")"
    [ -d "$parent" ] || { printf 'skip   %s (parent missing)\n' "$dest"; continue; }

    if [ -L "$dest" ]; then
      cur="$(readlink "$dest")"
      if [ "$cur" = "$GLOBAL_SRC" ]; then
        printf 'skip   %s (already linked)\n' "$dest"
        skipped=$((skipped + 1))
      else
        printf 'warn   %s -> %s (points elsewhere; leaving)\n' "$dest" "$cur"
      fi
      continue
    fi

    if [ -e "$dest" ]; then
      bak="$dest.bak.$(date +%Y%m%d%H%M%S)"
      mv "$dest" "$bak"
      printf 'backup %s -> %s\n' "$dest" "$bak"
    fi

    ln -s "$GLOBAL_SRC" "$dest"
    printf 'linked %s -> %s\n' "$dest" "$GLOBAL_SRC"
    created=$((created + 1))
  done
fi

# --- job 3: persistent Megaplan Cloud mirror ---
if [ "${POMS_SKILLS_SKIP_CLOUD:-0}" != "1" ]; then
  CLOUD_HOST="${POMS_SKILLS_CLOUD_HOST:-root@159.69.51.216}"
  CLOUD_WORKSPACE="/opt/megaplan-cloud/workspace"
  CLOUD_MIRROR="$CLOUD_WORKSPACE/poms_skills"
  CLOUD_SKILLS="$CLOUD_WORKSPACE/.codex/skills"
  CLOUD_RESIDENT="megaplan-cloud-agent-resident-only"

  ssh -o BatchMode=yes -o ConnectTimeout=10 "$CLOUD_HOST" \
    mkdir -p "$CLOUD_MIRROR" "$CLOUD_SKILLS"

  # Dereference each valid skill independently so the cloud mirror never
  # contains laptop-only absolute links. A broken optional source symlink must
  # not poison every other skill. --delete is bounded to that exact named skill.
  for name in "${skill_names[@]}"; do
    rsync -azL --delete \
      --exclude '.DS_Store' --exclude '.git/' \
      -e 'ssh -o BatchMode=yes -o ConnectTimeout=10' \
      "$SRC_DIR/$name/" "$CLOUD_HOST:$CLOUD_MIRROR/$name/"
  done

  # Relative links resolve on both the host and containers that mount the
  # workspace at /workspace. Preserve any pre-existing non-managed entry.
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$CLOUD_HOST" \
    bash -s -- "$CLOUD_SKILLS" "$CLOUD_RESIDENT" "${skill_names[@]}" <<'REMOTE_LINKS'
set -euo pipefail
target_dir="$1"
resident="$2"
shift 2

for name in "$@"; do
  dest="$target_dir/$name"
  src="../../poms_skills/$name"

  if [ -L "$dest" ]; then
    current="$(readlink "$dest")"
    if [ "$current" = "$src" ]; then
      printf 'cloud skip   %s (already linked)\n' "$dest"
    else
      printf 'cloud warn   %s -> %s (points elsewhere; leaving)\n' "$dest" "$current"
    fi
  elif [ -e "$dest" ]; then
    printf 'cloud warn   %s (exists; leaving)\n' "$dest"
  else
    ln -s "$src" "$dest"
    printf 'cloud linked %s -> %s\n' "$dest" "$src"
  fi
done

if docker inspect "$resident" >/dev/null 2>&1; then
  docker exec "$resident" mkdir -p /root/.codex/skills
  for name in "$@"; do
    dest="/root/.codex/skills/$name"
    src="/workspace/poms_skills/$name"

    if docker exec "$resident" test -L "$dest"; then
      current="$(docker exec "$resident" readlink "$dest")"
      if [ "$current" = "$src" ]; then
        printf 'resident skip   %s (already linked)\n' "$dest"
      else
        printf 'resident warn   %s -> %s (points elsewhere; leaving)\n' "$dest" "$current"
      fi
    elif docker exec "$resident" test -e "$dest"; then
      printf 'resident warn   %s (exists; leaving)\n' "$dest"
    else
      docker exec "$resident" ln -s "$src" "$dest"
      printf 'resident linked %s -> %s\n' "$dest" "$src"
    fi
  done
else
  printf 'resident warn   %s (container missing; persistent mirror is still current)\n' "$resident"
fi
REMOTE_LINKS

  printf 'cloud synced %s -> %s:%s\n' "$SRC_DIR" "$CLOUD_HOST" "$CLOUD_MIRROR"
else
  printf 'cloud skip   (POMS_SKILLS_SKIP_CLOUD=1)\n'
fi

echo ""
echo "done: $created created, $skipped skipped"
