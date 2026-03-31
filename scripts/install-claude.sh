#!/bin/bash

# Install script for Claude Code CLI skills
# This script creates symlinks from ~/.claude/commands/ and ~/.claude/skills/
# to each skill's SKILL.md

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/../skills"
COMMANDS_DIR="$HOME/.claude/commands"
SKILLS_DIR="$HOME/.claude/skills"

echo "Installing ValarMindSkills in Claude Code CLI..."

mkdir -p "$COMMANDS_DIR"
mkdir -p "$SKILLS_DIR"

installed=()

for skill_dir in "$SOURCE_DIR"/*/; do
  skill_file="$skill_dir/SKILL.md"
  [ -f "$skill_file" ] || continue

  slug="$(basename "$skill_dir")"
  source="$(cd "$skill_dir" && pwd)/SKILL.md"
  source_dir="$(cd "$skill_dir" && pwd)"

  # Commands: flat .md symlink (slash command format)
  ln -sf "$source" "$COMMANDS_DIR/$slug.md"

  # Skills: directory symlink (Claude Code /skills dialog format)
  rm -rf "${SKILLS_DIR:?}/$slug"
  ln -sf "$source_dir" "$SKILLS_DIR/$slug"
  installed+=("$slug")
done

echo ""
echo "Skills installed (${#installed[@]}):"
for s in "${installed[@]}"; do
  echo "  /$s"
done
echo ""
echo "Done! Skills are available via /skills dialog and as slash commands in Claude Code."
