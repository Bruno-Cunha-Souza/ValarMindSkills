#!/usr/bin/env bash
# Source-able helper for installers that target the shared `.agents/skills` root.
#
# Both Zed and Codex CLI discover Agent Skills there:
#   Zed   — ~/.agents/skills (global) + <worktree>/.agents/skills (trusted worktrees)
#           https://zed.dev/docs/ai/skills
#   Codex — $HOME/.agents/skills, plus .agents/skills from CWD up to the repo root
#           https://learn.chatgpt.com/docs/build-skills
#
# Unlike ~/.cursor/skills, `~/.agents/skills` is a SHARED root that other
# agents/tools also write to. A blind "delete anything not in source" prune would
# nuke third-party skills, so pruning here is manifest driven: only slugs a
# previous ValarMind run recorded get removed.
#
# Usage:
#     source "$REPO_DIR/scripts/_lib/agents-skills.sh"
#     install_agents_skills "$REPO_DIR/skills" "$SKILLS_TARGET"
#     report_agents_skills "$SKILLS_TARGET"

VALARMIND_MANIFEST_NAME=".valarmind-manifest"

# Populated by install_agents_skills / migrate_legacy_skills_dir for the
# report_agents_skills consumer.
AGENTS_SKILLS_INSTALLED=()
AGENTS_SKILLS_PRUNED=()
AGENTS_SKILLS_INVALID=()
AGENTS_SKILLS_MIGRATED=()

# Zed rejects skill names that are not lowercase alphanumeric + single internal
# hyphens, max 64 chars. The directory slug is the name, so validate it before
# copying instead of letting Zed silently drop the skill from the catalog.
_agents_valid_slug() {
  local slug="$1"
  [ "${#slug}" -le 64 ] || return 1
  printf '%s' "$slug" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$'
}

install_agents_skills() {
  local source_skills="$1"
  local skills_target="$2"
  local manifest="$skills_target/$VALARMIND_MANIFEST_NAME"

  AGENTS_SKILLS_INSTALLED=()
  AGENTS_SKILLS_PRUNED=()
  AGENTS_SKILLS_INVALID=()

  mkdir -p "$skills_target"

  local skill_dir slug dest
  for skill_dir in "$source_skills"/*/; do
    [ -f "$skill_dir/SKILL.md" ] || continue
    slug="$(basename "$skill_dir")"

    if ! _agents_valid_slug "$slug"; then
      AGENTS_SKILLS_INVALID+=("$slug")
      continue
    fi

    dest="$skills_target/$slug"
    # Wipe dest first — BSD `cp -R src/ dest` copies INTO an existing directory,
    # which would nest $dest/$slug on re-runs.
    rm -rf "$dest"
    cp -R "$skill_dir" "$dest"
    AGENTS_SKILLS_INSTALLED+=("$slug")
  done

  # Prune only what we installed before and no longer ship (renamed/removed
  # skills). Anything absent from the manifest is someone else's — leave it.
  local prev found s
  if [ -f "$manifest" ]; then
    while IFS= read -r prev; do
      [ -n "$prev" ] || continue
      case "$prev" in \#*) continue ;; esac
      found=0
      if [ "${#AGENTS_SKILLS_INSTALLED[@]}" -gt 0 ]; then
        for s in "${AGENTS_SKILLS_INSTALLED[@]}"; do
          if [ "$s" = "$prev" ]; then
            found=1
            break
          fi
        done
      fi
      if [ "$found" -eq 0 ] && [ -d "$skills_target/$prev" ]; then
        rm -rf "$skills_target/$prev"
        AGENTS_SKILLS_PRUNED+=("$prev")
      fi
    done < "$manifest"
  fi

  {
    printf '# ValarMindSkills — slugs managed by scripts/install-*.sh. Do not edit.\n'
    if [ "${#AGENTS_SKILLS_INSTALLED[@]}" -gt 0 ]; then
      printf '%s\n' "${AGENTS_SKILLS_INSTALLED[@]}"
    fi
  } > "$manifest"
}

# Remove skills a previous ValarMind release installed in a location the agent no
# longer scans (e.g. ~/.codex/skills, before Codex moved discovery to
# .agents/skills). Only slugs we currently ship are deleted, and the legacy root
# is removed when it ends up empty — anything else the user put there is left
# alone. Leaving the old copies in place risks a duplicated catalog: Codex does
# not merge same-named skills, "both can appear in skill selectors".
migrate_legacy_skills_dir() {
  local legacy_dir="$1"
  local source_skills="$2"

  AGENTS_SKILLS_MIGRATED=()
  [ -d "$legacy_dir" ] || return 0

  local skill_dir slug
  for skill_dir in "$source_skills"/*/; do
    [ -f "$skill_dir/SKILL.md" ] || continue
    slug="$(basename "$skill_dir")"
    if [ -f "$legacy_dir/$slug/SKILL.md" ]; then
      rm -rf "$legacy_dir/$slug"
      AGENTS_SKILLS_MIGRATED+=("$slug")
    fi
  done

  # Only succeeds when nothing else lives there.
  rmdir "$legacy_dir" 2>/dev/null || true
}

report_agents_skills() {
  local skills_target="$1"
  local s

  echo ""
  echo "Skills installed (${#AGENTS_SKILLS_INSTALLED[@]}):"
  if [ "${#AGENTS_SKILLS_INSTALLED[@]}" -gt 0 ]; then
    for s in "${AGENTS_SKILLS_INSTALLED[@]}"; do
      echo "  /$s → $skills_target/$s"
    done
  fi

  if [ "${#AGENTS_SKILLS_PRUNED[@]}" -gt 0 ]; then
    echo ""
    echo "Stale ValarMind skills pruned (${#AGENTS_SKILLS_PRUNED[@]}):"
    for s in "${AGENTS_SKILLS_PRUNED[@]}"; do
      echo "  -$s"
    done
  fi

  if [ "${#AGENTS_SKILLS_INVALID[@]}" -gt 0 ]; then
    echo ""
    echo "Skipped — slug not valid for Zed (lowercase, digits, single hyphens, ≤64 chars):"
    for s in "${AGENTS_SKILLS_INVALID[@]}"; do
      echo "  !$s"
    done
  fi
}
