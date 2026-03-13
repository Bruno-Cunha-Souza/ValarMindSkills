#!/bin/bash

# Install all ValarMindSkills in Claude Code CLI and Antigravity

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================"
echo " ValarMindSkills — Install All"
echo "========================================"
echo ""

bash "$SCRIPT_DIR/install-claude.sh"

echo ""
echo "========================================"
echo ""

bash "$SCRIPT_DIR/install-antigravity.sh"
