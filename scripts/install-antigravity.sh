#!/bin/bash

# Install script for Antigravity skills
# This script copies the skills from the ValarMindSkills repository to the global Antigravity skills directory.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/../skills"
TARGET_DIR="$HOME/.gemini/antigravity/skills"

# shellcheck source=_lib/ensure-rust.sh
source "$SCRIPT_DIR/_lib/ensure-rust.sh"

echo "Installing ValarMindSkills in Antigravity..."

# Build any Rust crates inside skills/ before copying — the destination receives
# a freshly-compiled binary alongside the source files.
build_all_skill_binaries "$SOURCE_DIR"

mkdir -p "$TARGET_DIR"

installed=()

for skill_dir in "$SOURCE_DIR"/*/; do
  skill_file="$skill_dir/SKILL.md"
  [ -f "$skill_file" ] || continue

  slug="$(basename "$skill_dir")"
  dest="$TARGET_DIR/$slug"
  # Remove pre-existing dest first — `cp -R src/ dest` on macOS BSD copies INTO
  # an existing directory, producing nested $dest/$slug on re-runs.
  rm -rf "$dest"
  cp -R "$skill_dir" "$dest"
  installed+=("$slug")
done

# Prune stale skills no longer present in source (e.g. removed/renamed in newer release).
pruned=()
if [ -d "$TARGET_DIR" ]; then
  for existing_dir in "$TARGET_DIR"/*/; do
    [ -d "$existing_dir" ] || continue
    existing_slug="$(basename "$existing_dir")"
    found=0
    for s in "${installed[@]}"; do
      if [ "$s" = "$existing_slug" ]; then
        found=1
        break
      fi
    done
    if [ "$found" -eq 0 ]; then
      rm -rf "$existing_dir"
      pruned+=("$existing_slug")
    fi
  done
fi

echo ""
echo "Skills installed (${#installed[@]}):"
for s in "${installed[@]}"; do
  echo "  @$s → $TARGET_DIR/$s"
done
if [ "${#pruned[@]}" -gt 0 ]; then
  echo ""
  echo "Stale skills pruned (${#pruned[@]}):"
  for s in "${pruned[@]}"; do
    echo "  -$s"
  done
fi
echo ""
echo "Done! Skills are available in Antigravity."
echo "Note: You may need to run 'Reload Window' (Cmd+Shift+P > Reload Window) in VS Code for the autocomplete to detect new skills."
