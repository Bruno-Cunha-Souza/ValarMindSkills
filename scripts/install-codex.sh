#!/bin/bash

# Install script for OpenAI Codex CLI skills
# Copies ValarMindSkills to the global Codex CLI skills directory.
# If skills don't appear, verify the path with: codex --help

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/../skills"
TARGET_DIR="$HOME/.codex/skills"

echo "Installing ValarMindSkills in Codex CLI..."

mkdir -p "$TARGET_DIR"

installed=()

for skill_dir in "$SOURCE_DIR"/*/; do
  skill_file="$skill_dir/SKILL.md"
  [ -f "$skill_file" ] || continue

  slug="$(basename "$skill_dir")"
  cp -R "$skill_dir" "$TARGET_DIR/$slug"
  installed+=("$slug")
done

echo ""
echo "Skills installed (${#installed[@]}):"
for s in "${installed[@]}"; do
  echo "  @$s → $TARGET_DIR/$s"
done
echo ""
echo "Done! Skills are available in Codex CLI."
echo "Note: Restart Codex CLI for new skills to be detected."
