#!/bin/bash

# Full plugin install for OpenAI Codex CLI
# Installs: skills, hooks (via config.toml [[hooks]]), and AGENTS.md postures
#
# Codex discovers skills in $HOME/.agents/skills, in .agents/skills from the CWD
# up to the repo root, and in /etc/codex/skills — see
# https://learn.chatgpt.com/docs/build-skills. ~/.codex/skills is NOT a discovery
# path, so earlier releases installed to a directory Codex no longer scans; any
# ValarMind skills left there are removed below. Hooks and AGENTS.md stay under
# $CODEX_HOME.
#
# Overrides:
#   CODEX_HOME         config root. Default: ~/.codex
#   CODEX_SKILLS_HOME  skills root. Default: ~/.agents/skills

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_SKILLS="$REPO_DIR/skills"
SOURCE_HOOKS="$REPO_DIR/hooks"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
SKILLS_TARGET="${CODEX_SKILLS_HOME:-$HOME/.agents/skills}"
LEGACY_SKILLS_DIR="$CODEX_HOME/skills"
HOOKS_TARGET="$CODEX_HOME/hooks"
CONFIG_TOML="$CODEX_HOME/config.toml"
AGENTS_MD="$CODEX_HOME/AGENTS.md"

# shellcheck source=_lib/ensure-rust.sh
source "$SCRIPT_DIR/_lib/ensure-rust.sh"
# shellcheck source=_lib/agents-skills.sh
source "$SCRIPT_DIR/_lib/agents-skills.sh"

echo "Installing ValarMindSkills plugin in Codex CLI..."
echo "CODEX_HOME:    $CODEX_HOME"
echo "Skills target: $SKILLS_TARGET"
echo ""

# ──────────────────────────────────────────────────────────────
# Step 1/3 — Skills
# ──────────────────────────────────────────────────────────────
echo "=== Step 1/3: Skills ==="

# Build any Rust crates inside skills/ before copying — the destination receives
# a freshly-compiled binary alongside the source files.
build_all_skill_binaries "$SOURCE_SKILLS"

# ~/.agents/skills is shared with Zed (and any other agent following the
# convention), so pruning is manifest driven — see _lib/agents-skills.sh.
install_agents_skills "$SOURCE_SKILLS" "$SKILLS_TARGET"

echo "Installed ${#AGENTS_SKILLS_INSTALLED[@]} skills → $SKILLS_TARGET"
if [ "${#AGENTS_SKILLS_PRUNED[@]}" -gt 0 ]; then
  echo "Pruned ${#AGENTS_SKILLS_PRUNED[@]} stale skill(s): ${AGENTS_SKILLS_PRUNED[*]}"
fi
if [ "${#AGENTS_SKILLS_INVALID[@]}" -gt 0 ]; then
  echo "Skipped ${#AGENTS_SKILLS_INVALID[@]} skill(s) with an unusable slug: ${AGENTS_SKILLS_INVALID[*]}"
fi

# Drop copies from the pre-.agents layout so the catalog is not duplicated —
# Codex does not merge same-named skills, both would show in the selector.
if [ "$LEGACY_SKILLS_DIR" != "$SKILLS_TARGET" ]; then
  migrate_legacy_skills_dir "$LEGACY_SKILLS_DIR" "$SOURCE_SKILLS"
  if [ "${#AGENTS_SKILLS_MIGRATED[@]}" -gt 0 ]; then
    echo "Removed ${#AGENTS_SKILLS_MIGRATED[@]} skill(s) from the legacy $LEGACY_SKILLS_DIR."
  fi
fi

# ──────────────────────────────────────────────────────────────
# Step 2/3 — Hooks (via config.toml [[hooks]])
# ──────────────────────────────────────────────────────────────
echo ""
echo "=== Step 2/3: Hooks ==="

mkdir -p "$HOOKS_TARGET/_lib"
mkdir -p "$HOOKS_TARGET/caveman"
mkdir -p "$HOOKS_TARGET/ponytail"
mkdir -p "$HOOKS_TARGET/superpowers"
mkdir -p "$HOOKS_TARGET/obsidian-brain"

cp "$SOURCE_HOOKS/_lib/"*.js           "$HOOKS_TARGET/_lib/"
cp "$SOURCE_HOOKS/caveman/"*.js        "$HOOKS_TARGET/caveman/"
cp "$SOURCE_HOOKS/ponytail/"*.js       "$HOOKS_TARGET/ponytail/"
cp "$SOURCE_HOOKS/superpowers/"*.js    "$HOOKS_TARGET/superpowers/"
cp "$SOURCE_HOOKS/obsidian-brain/"*.js "$HOOKS_TARGET/obsidian-brain/"

echo "Hook scripts copied → $HOOKS_TARGET"

# Inject hooks into config.toml using correct schema format:
# hooks (HooksToml struct) → [[hooks.SessionStart]] MatcherGroup → [[hooks.SessionStart.hooks]] HookHandlerConfig
# Uses CLAUDE_CONFIG_DIR override so flag files go to $CODEX_HOME instead of ~/.claude/,
# and VALARMIND_SKILLS_ROOT so the hooks find SKILL.md now that skills live in
# $SKILLS_TARGET rather than alongside $HOOKS_TARGET — resolve-skill-path.js would
# otherwise look in $CODEX_HOME/skills, miss it, and inject only the short
# built-in posture summary instead of the full skill.
#
# Block is wrapped in sentinel comments so re-runs strip the previous block
# and inject a fresh one (idempotent updates).
if [ ! -f "$CONFIG_TOML" ]; then
  touch "$CONFIG_TOML"
fi

TOML_BEGIN="# >>> VALARMIND BEGIN — do not edit between markers"
TOML_END="# >>> VALARMIND END"

if grep -qF "$TOML_BEGIN" "$CONFIG_TOML"; then
  # Single awk pass: strip managed block AND trim trailing blank lines so
  # re-runs do not accumulate empty separators.
  tmp_toml=$(mktemp)
  awk -v begin="$TOML_BEGIN" -v end="$TOML_END" '
    $0 == begin { skip = 1; next }
    $0 == end   { skip = 0; next }
    skip        { next }
    /^[[:space:]]*$/ { blanks++; next }
    { while (blanks-- > 0) print ""; blanks = 0; print }
  ' "$CONFIG_TOML" > "$tmp_toml"
  mv "$tmp_toml" "$CONFIG_TOML"
  echo "Existing ValarMind block stripped from config.toml."
fi

# Single blank-line separator before the block, only when user content exists.
if [ -s "$CONFIG_TOML" ]; then
  printf '\n' >> "$CONFIG_TOML"
fi

cat >> "$CONFIG_TOML" << EOF
$TOML_BEGIN
# ValarMindSkills hooks
[[hooks.SessionStart]]

[[hooks.SessionStart.hooks]]
type = "command"
command = "CLAUDE_CONFIG_DIR=$CODEX_HOME VALARMIND_SKILLS_ROOT=$SKILLS_TARGET node $HOOKS_TARGET/caveman/caveman-activate.js"

[[hooks.SessionStart.hooks]]
type = "command"
command = "CLAUDE_CONFIG_DIR=$CODEX_HOME VALARMIND_SKILLS_ROOT=$SKILLS_TARGET node $HOOKS_TARGET/ponytail/ponytail-activate.js"

[[hooks.SessionStart.hooks]]
type = "command"
command = "CLAUDE_CONFIG_DIR=$CODEX_HOME VALARMIND_SKILLS_ROOT=$SKILLS_TARGET node $HOOKS_TARGET/superpowers/superpowers-activate.js"

[[hooks.SessionStart.hooks]]
type = "command"
command = "CLAUDE_CONFIG_DIR=$CODEX_HOME VALARMIND_SKILLS_ROOT=$SKILLS_TARGET node $HOOKS_TARGET/obsidian-brain/obsidian-brain-activate.js"

[[hooks.UserPromptSubmit]]

[[hooks.UserPromptSubmit.hooks]]
type = "command"
command = "CLAUDE_CONFIG_DIR=$CODEX_HOME VALARMIND_SKILLS_ROOT=$SKILLS_TARGET node $HOOKS_TARGET/caveman/caveman-mode-tracker.js"

[[hooks.UserPromptSubmit.hooks]]
type = "command"
command = "CLAUDE_CONFIG_DIR=$CODEX_HOME VALARMIND_SKILLS_ROOT=$SKILLS_TARGET node $HOOKS_TARGET/ponytail/ponytail-mode-tracker.js"

[[hooks.UserPromptSubmit.hooks]]
type = "command"
command = "CLAUDE_CONFIG_DIR=$CODEX_HOME VALARMIND_SKILLS_ROOT=$SKILLS_TARGET node $HOOKS_TARGET/superpowers/superpowers-mode-tracker.js"

[[hooks.UserPromptSubmit.hooks]]
type = "command"
command = "CLAUDE_CONFIG_DIR=$CODEX_HOME VALARMIND_SKILLS_ROOT=$SKILLS_TARGET node $HOOKS_TARGET/obsidian-brain/obsidian-brain-mode-tracker.js"
$TOML_END
EOF
echo "Hooks block written → $CONFIG_TOML"

# ──────────────────────────────────────────────────────────────
# Step 3/3 — AGENTS.md (static postures as fallback)
# ──────────────────────────────────────────────────────────────
echo ""
echo "=== Step 3/3: AGENTS.md ==="

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

To activate: \`superpowers on\` or \`/valarmindskills:superpowers on\`

## Skills

ValarMindSkills installed. Available as @slug (e.g. @code-review, @caveman, @github-commit).
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
echo ""
echo "Done! Restart Codex CLI to load hooks and skills."
echo ""
