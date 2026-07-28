#!/bin/bash

# Skills-only install for Zed IDE (no AGENTS.md instructions block).
# For the full plugin (skills + postures), use install-plugin-zed.sh.
#
# Zed loads Agent Skills from ~/.agents/skills (global). Override the target
# with ZED_SKILLS_HOME, e.g. for a project-local install:
#   ZED_SKILLS_HOME="$PWD/.agents/skills" bash scripts/install-zed.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_SKILLS="$REPO_DIR/skills"
ZED_SKILLS_HOME="${ZED_SKILLS_HOME:-$HOME/.agents/skills}"

# shellcheck source=_lib/ensure-rust.sh
source "$SCRIPT_DIR/_lib/ensure-rust.sh"
# shellcheck source=_lib/agents-skills.sh
source "$SCRIPT_DIR/_lib/agents-skills.sh"

echo "Installing ValarMindSkills (skills only) in Zed IDE..."
echo "ZED_SKILLS_HOME: $ZED_SKILLS_HOME"
echo ""

build_all_skill_binaries "$SOURCE_SKILLS"

install_agents_skills "$SOURCE_SKILLS" "$ZED_SKILLS_HOME"
report_agents_skills "$ZED_SKILLS_HOME"

echo ""
echo "Done! Skills reload live — no Zed restart needed."
echo "Invoke with /<slug> in the Agent Panel message editor, or @skill to browse."
echo "Manage them under Settings → AI → Skills (zed://settings/agent.skills)."
echo ""
echo "For the caveman/ponytail/superpowers/obsidian-brain postures, run:"
echo "  bash scripts/install-plugin-zed.sh"
