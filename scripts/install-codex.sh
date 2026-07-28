#!/bin/bash

# Install script for OpenAI Codex CLI skills
# Copies ValarMindSkills to the user-level Codex CLI skills directory.
#
# Codex discovers skills in $HOME/.agents/skills, in .agents/skills from the CWD
# up to the repo root, and in /etc/codex/skills — see
# https://learn.chatgpt.com/docs/build-skills. ~/.codex/skills is NOT a discovery
# path, so earlier releases installed to a directory Codex no longer scans; any
# ValarMind skills left there are removed below.
#
# Override the target with CODEX_SKILLS_HOME (e.g. a project-local install:
#   CODEX_SKILLS_HOME="$PWD/.agents/skills" bash scripts/install-codex.sh).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/../skills"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
TARGET_DIR="${CODEX_SKILLS_HOME:-$HOME/.agents/skills}"
LEGACY_DIR="$CODEX_HOME/skills"

# shellcheck source=_lib/ensure-rust.sh
source "$SCRIPT_DIR/_lib/ensure-rust.sh"
# shellcheck source=_lib/agents-skills.sh
source "$SCRIPT_DIR/_lib/agents-skills.sh"

echo "Installing ValarMindSkills in Codex CLI..."
echo "Skills target: $TARGET_DIR"

# Build any Rust crates inside skills/ before copying — the destination receives
# a freshly-compiled binary alongside the source files.
build_all_skill_binaries "$SOURCE_DIR"

install_agents_skills "$SOURCE_DIR" "$TARGET_DIR"

# Drop copies from the pre-.agents layout so the catalog is not duplicated.
if [ "$LEGACY_DIR" != "$TARGET_DIR" ]; then
  migrate_legacy_skills_dir "$LEGACY_DIR" "$SOURCE_DIR"
  if [ "${#AGENTS_SKILLS_MIGRATED[@]}" -gt 0 ]; then
    echo "Removed ${#AGENTS_SKILLS_MIGRATED[@]} skill(s) from the legacy $LEGACY_DIR."
  fi
fi

report_agents_skills "$TARGET_DIR"

echo ""
echo "Done! Skills are available in Codex CLI."
echo "Note: Restart Codex CLI for new skills to be detected."
