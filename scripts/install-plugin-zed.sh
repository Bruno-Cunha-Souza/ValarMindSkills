#!/bin/bash

# Full plugin install for Zed IDE.
# Installs: skills → ~/.agents/skills/, postures → ~/.config/zed/AGENTS.md
#
# Zed has no agent lifecycle hooks yet (proposed in zed-industries/zed#57943),
# so the caveman / ponytail / superpowers postures ship as static personal
# instructions instead of SessionStart + UserPromptSubmit hooks. Everything else
# (skill catalog, /slash invocation, @skill mentions) is native.
#
# Overrides:
#   ZED_SKILLS_HOME               skills root.   Default: ~/.agents/skills
#   ZED_CONFIG_HOME               config root.   Default: ~/.config/zed
#   VALARMIND_SKIP_INSTRUCTIONS=1 skills only — leave AGENTS.md untouched
#   VALARMIND_SKIP_HOOKS=1        same as above (name kept for parity)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_SKILLS="$REPO_DIR/skills"
ZED_SKILLS_HOME="${ZED_SKILLS_HOME:-$HOME/.agents/skills}"
ZED_CONFIG_HOME="${ZED_CONFIG_HOME:-$HOME/.config/zed}"
AGENTS_MD="$ZED_CONFIG_HOME/AGENTS.md"

# shellcheck source=_lib/ensure-rust.sh
source "$SCRIPT_DIR/_lib/ensure-rust.sh"
# shellcheck source=_lib/agents-skills.sh
source "$SCRIPT_DIR/_lib/agents-skills.sh"

echo "Installing ValarMindSkills plugin in Zed IDE..."
echo "ZED_SKILLS_HOME: $ZED_SKILLS_HOME"
echo "ZED_CONFIG_HOME: $ZED_CONFIG_HOME"
echo ""

# ──────────────────────────────────────────────────────────────
# Step 1/2 — Skills
# ──────────────────────────────────────────────────────────────
echo "=== Step 1/2: Skills ==="

# Build any Rust crates inside skills/ before copying — the destination receives
# a freshly-compiled binary alongside the source files.
build_all_skill_binaries "$SOURCE_SKILLS"

install_agents_skills "$SOURCE_SKILLS" "$ZED_SKILLS_HOME"

echo "Installed ${#AGENTS_SKILLS_INSTALLED[@]} skills → $ZED_SKILLS_HOME"
if [ "${#AGENTS_SKILLS_PRUNED[@]}" -gt 0 ]; then
  echo "Pruned ${#AGENTS_SKILLS_PRUNED[@]} stale skill(s): ${AGENTS_SKILLS_PRUNED[*]}"
fi
if [ "${#AGENTS_SKILLS_INVALID[@]}" -gt 0 ]; then
  echo "Skipped ${#AGENTS_SKILLS_INVALID[@]} skill(s) with slugs Zed rejects: ${AGENTS_SKILLS_INVALID[*]}"
fi

# ──────────────────────────────────────────────────────────────
# Step 2/2 — Personal instructions (postures)
# ──────────────────────────────────────────────────────────────
if [ "${VALARMIND_SKIP_INSTRUCTIONS:-${VALARMIND_SKIP_HOOKS:-0}}" = "1" ]; then
  echo ""
  echo "VALARMIND_SKIP_INSTRUCTIONS=1 — leaving $AGENTS_MD untouched."
  echo ""
  echo "Done! Skills reload live; invoke with /<slug> in the Agent Panel."
  exit 0
fi

echo ""
echo "=== Step 2/2: AGENTS.md (personal instructions) ==="

mkdir -p "$ZED_CONFIG_HOME"

AGENTS_BEGIN="<!-- VALARMIND BEGIN — do not edit between markers -->"
AGENTS_END="<!-- VALARMIND END -->"

AGENTS_BLOCK=$(cat << AGENTS_EOF
$AGENTS_BEGIN
# ValarMindSkills Postures

## Caveman Mode (active — level: lite)

Respond terse like smart caveman. All technical substance stay. Only fluff die.

Active every response. No revert after many turns. No filler drift. Off only: "stop caveman" / "normal mode".

Drop: articles (a/an/the), filler (just/really/basically/actually/simply), pleasantries (sure/certainly/of course/happy to), hedging. Fragments OK. Short synonyms (big not extensive, fix not "implement a solution for"). Technical terms exact. Code blocks unchanged. Errors quoted exact.

Pattern: \`[thing] [action] [reason]. [next step].\`

Drop caveman for: security warnings, irreversible action confirmations, multi-step sequences where fragment order risks misread. Resume caveman after clear part done.

Code/commits/PRs: write normal. "stop caveman" or "normal mode": revert.

## Ponytail Mode (active — level: full)

You are a lazy senior developer. Lazy means efficient, not careless. The best code is the code never written.

Before writing any code, stop at the first rung that holds: 1. needed at all? (YAGNI) 2. already in this codebase? reuse it 3. stdlib does it? use it 4. native platform feature? use it 5. installed dependency? use it 6. one line? one line 7. only then: minimum code that works. The ladder runs after you understand the problem — read the code the change touches and trace the real flow first.

No unrequested abstractions, no avoidable dependencies, no boilerplate. Deletion over addition. Fewest files possible. Mark deliberate simplifications with a \`ponytail:\` comment naming ceiling and upgrade path. Code first, then at most three short lines of explanation.

Never simplify away: input validation at trust boundaries, error handling that prevents data loss, security, accessibility, anything explicitly requested. Non-trivial logic leaves one runnable check behind.

Ponytail governs what you build, not how you talk. "stop ponytail" or "normal mode": revert.

## Superpowers (off by default)

To activate: say \`superpowers on\`, or invoke \`/superpowers\`.

## Skills

ValarMindSkills installed under \`~/.agents/skills/\`. Invoke with \`/<slug>\` in the message editor (e.g. \`/code-review\`, \`/caveman\`, \`/github-commit\`), or \`@skill\` to browse. The agent may also load one on its own when the task matches a skill description.

Zed has no lifecycle hooks yet, so posture levels here are static. Switch level in-conversation ("caveman full", "ponytail lite", "normal mode") or edit this block.
$AGENTS_END
AGENTS_EOF
)

if [ -f "$AGENTS_MD" ]; then
  # Backup existing AGENTS.md before any mutation.
  backup="$AGENTS_MD.bak.$(date +%Y%m%d%H%M%S)"
  cp "$AGENTS_MD" "$backup"
  echo "Existing AGENTS.md backed up → $backup"

  if grep -qF "$AGENTS_BEGIN" "$AGENTS_MD"; then
    # Strip block AND trim trailing blanks in one pass — prevents blank-line
    # accumulation across re-runs.
    tmp_md=$(mktemp)
    awk -v begin="$AGENTS_BEGIN" -v end="$AGENTS_END" '
      $0 == begin { skip = 1; next }
      $0 == end   { skip = 0; next }
      skip        { next }
      /^[[:space:]]*$/ { blanks++; next }
      { while (blanks-- > 0) print ""; blanks = 0; print }
    ' "$AGENTS_MD" > "$tmp_md"
    mv "$tmp_md" "$AGENTS_MD"
    echo "Existing ValarMind postures stripped from AGENTS.md."
  fi

  # Single blank-line separator only when prior user content exists.
  if [ -s "$AGENTS_MD" ]; then
    printf '\n' >> "$AGENTS_MD"
  fi
  printf '%s\n' "$AGENTS_BLOCK" >> "$AGENTS_MD"
  echo "ValarMindSkills postures written → $AGENTS_MD"
else
  printf "%s\n" "$AGENTS_BLOCK" > "$AGENTS_MD"
  echo "AGENTS.md created → $AGENTS_MD"
fi

# ──────────────────────────────────────────────────────────────
# Done
# ──────────────────────────────────────────────────────────────
report_agents_skills "$ZED_SKILLS_HOME"

echo ""
echo "Done! Skills reload live — no restart needed."
echo "Instructions load per thread: open a new thread in the Agent Panel to pick up AGENTS.md."
echo ""
echo "Caveman posture: ON (level = lite). Ponytail: ON (level = full). Superpowers: OFF."
echo "Switch in-conversation (\"caveman full\", \"normal mode\") or edit $AGENTS_MD."
echo ""
echo "Note: a project-level instruction file (.rules, .cursorrules, AGENT.md, AGENTS.md,"
echo "CLAUDE.md, ...) in the open worktree takes precedence over this personal AGENTS.md"
echo "where the two conflict."
