#!/bin/bash

# Update script for Antigravity skills
# This script copies the skills from the ValarMindSkills repository to the global Antigravity skills directory.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/../skills"
TARGET_DIR="$HOME/.gemini/antigravity/skills"

echo "Updating ValarMindSkills in Antigravity..."

mkdir -p "$TARGET_DIR"
cp -R "$SOURCE_DIR/"* "$TARGET_DIR/"

echo "Skills updated successfully!"
echo "Note: You may need to run 'Reload Window' (Cmd+Shift+P > Reload Window) in VS Code for the autocomplete to detect new skills."
