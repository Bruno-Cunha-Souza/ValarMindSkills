#!/bin/bash

# Full plugin install for OpenAI Codex CLI
# Installs: skills, hooks (via config.toml [[hooks]]), and AGENTS.md postures

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_SKILLS="$REPO_DIR/skills"
SOURCE_HOOKS="$REPO_DIR/hooks"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
SKILLS_TARGET="$CODEX_HOME/skills"
HOOKS_TARGET="$CODEX_HOME/hooks"
CONFIG_TOML="$CODEX_HOME/config.toml"
AGENTS_MD="$CODEX_HOME/AGENTS.md"

echo "Installing ValarMindSkills plugin in Codex CLI..."
echo "CODEX_HOME: $CODEX_HOME"
echo ""

# ──────────────────────────────────────────────────────────────
# Step 1/3 — Skills
# ──────────────────────────────────────────────────────────────
echo "=== Step 1/3: Skills ==="
mkdir -p "$SKILLS_TARGET"

installed_skills=()
for skill_dir in "$SOURCE_SKILLS"/*/; do
  [ -f "$skill_dir/SKILL.md" ] || continue
  slug="$(basename "$skill_dir")"
  cp -R "$skill_dir" "$SKILLS_TARGET/$slug"
  installed_skills+=("$slug")
done

echo "Installed ${#installed_skills[@]} skills → $SKILLS_TARGET"

# ──────────────────────────────────────────────────────────────
# Step 2/3 — Hooks (via config.toml [[hooks]])
# ──────────────────────────────────────────────────────────────
echo ""
echo "=== Step 2/3: Hooks ==="

mkdir -p "$HOOKS_TARGET/caveman"
mkdir -p "$HOOKS_TARGET/superpowers"
mkdir -p "$HOOKS_TARGET/obsidian-brain"

cp "$SOURCE_HOOKS/caveman/"*.js        "$HOOKS_TARGET/caveman/"
cp "$SOURCE_HOOKS/superpowers/"*.js    "$HOOKS_TARGET/superpowers/"
cp "$SOURCE_HOOKS/obsidian-brain/"*.js "$HOOKS_TARGET/obsidian-brain/"

echo "Hook scripts copied → $HOOKS_TARGET"

# Inject hooks into config.toml using correct schema format:
# hooks (HooksToml struct) → [[hooks.SessionStart]] MatcherGroup → [[hooks.SessionStart.hooks]] HookHandlerConfig
# Uses CLAUDE_CONFIG_DIR override so flag files go to $CODEX_HOME instead of ~/.claude/
if [ ! -f "$CONFIG_TOML" ]; then
  touch "$CONFIG_TOML"
fi

if grep -q "ValarMindSkills hooks" "$CONFIG_TOML"; then
  echo "Hooks already present in config.toml — skipped."
else
  cat >> "$CONFIG_TOML" << EOF

# ValarMindSkills hooks
[[hooks.SessionStart]]

[[hooks.SessionStart.hooks]]
type = "command"
command = "CLAUDE_CONFIG_DIR=$CODEX_HOME node $HOOKS_TARGET/caveman/caveman-activate.js"

[[hooks.SessionStart.hooks]]
type = "command"
command = "CLAUDE_CONFIG_DIR=$CODEX_HOME node $HOOKS_TARGET/superpowers/superpowers-activate.js"

[[hooks.SessionStart.hooks]]
type = "command"
command = "CLAUDE_CONFIG_DIR=$CODEX_HOME node $HOOKS_TARGET/obsidian-brain/obsidian-brain-activate.js"

[[hooks.UserPromptSubmit]]

[[hooks.UserPromptSubmit.hooks]]
type = "command"
command = "CLAUDE_CONFIG_DIR=$CODEX_HOME node $HOOKS_TARGET/caveman/caveman-mode-tracker.js"

[[hooks.UserPromptSubmit.hooks]]
type = "command"
command = "CLAUDE_CONFIG_DIR=$CODEX_HOME node $HOOKS_TARGET/superpowers/superpowers-mode-tracker.js"

[[hooks.UserPromptSubmit.hooks]]
type = "command"
command = "CLAUDE_CONFIG_DIR=$CODEX_HOME node $HOOKS_TARGET/obsidian-brain/obsidian-brain-mode-tracker.js"
EOF
  echo "Hooks appended → $CONFIG_TOML"
fi

# ──────────────────────────────────────────────────────────────
# Step 3/3 — AGENTS.md (static postures as fallback)
# ──────────────────────────────────────────────────────────────
echo ""
echo "=== Step 3/3: AGENTS.md ==="

AGENTS_BLOCK=$(cat << 'AGENTS_EOF'
# ValarMindSkills Postures

## Caveman Mode (active — level: lite)

Respond terse like smart caveman. All technical substance stay. Only fluff die.

Active every response. No revert after many turns. No filler drift. Off only: "stop caveman" / "normal mode".

Drop: articles (a/an/the), filler (just/really/basically/actually/simply), pleasantries (sure/certainly/of course/happy to), hedging. Fragments OK. Short synonyms (big not extensive, fix not "implement a solution for"). Technical terms exact. Code blocks unchanged. Errors quoted exact.

Pattern: `[thing] [action] [reason]. [next step].`

Drop caveman for: security warnings, irreversible action confirmations, multi-step sequences where fragment order risks misread. Resume caveman after clear part done.

Code/commits/PRs: write normal. "stop caveman" or "normal mode": revert.

## Superpowers (off by default)

To activate: `superpowers on` or `/valarmindskills:superpowers on`

## Skills

ValarMindSkills installed. Available as @slug (e.g. @code-review, @caveman, @github-commit).
AGENTS_EOF
)

if [ -f "$AGENTS_MD" ]; then
  # Backup existing AGENTS.md
  backup="$AGENTS_MD.bak.$(date +%Y%m%d%H%M%S)"
  cp "$AGENTS_MD" "$backup"
  echo "Existing AGENTS.md backed up → $backup"

  # Append ValarMindSkills block if not already present
  if ! grep -q "ValarMindSkills Postures" "$AGENTS_MD"; then
    printf "\n\n%s\n" "$AGENTS_BLOCK" >> "$AGENTS_MD"
    echo "ValarMindSkills postures appended → $AGENTS_MD"
  else
    echo "ValarMindSkills postures already present in AGENTS.md — skipped."
  fi
else
  printf "%s\n" "$AGENTS_BLOCK" > "$AGENTS_MD"
  echo "AGENTS.md created → $AGENTS_MD"
fi

# ──────────────────────────────────────────────────────────────
# Done
# ──────────────────────────────────────────────────────────────
echo ""
echo "Done! Restart Codex CLI to load hooks and skills."
echo ""
