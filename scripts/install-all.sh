#!/bin/bash

# Install all ValarMindSkills in Claude Code CLI, Antigravity, Codex CLI, and Cursor IDE

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================"
echo " ValarMindSkills — Install All"
echo "========================================"
echo ""

bash "$SCRIPT_DIR/install-plugin-claude.sh"

echo ""
echo "========================================"
echo ""

bash "$SCRIPT_DIR/install-antigravity.sh"

echo ""
echo "========================================"
echo ""

bash "$SCRIPT_DIR/install-plugin-codex.sh"

echo ""
echo "========================================"
echo ""

bash "$SCRIPT_DIR/install-plugin-cursor.sh"
