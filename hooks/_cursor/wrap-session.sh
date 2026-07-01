#!/usr/bin/env bash
# Cursor sessionStart wrapper — runs ValarMind *-activate.js hooks and emits
# Cursor-compatible JSON ({ "additional_context": "...", "continue": true }).
#
# Usage (from ~/.cursor/ as CWD): ./hooks/_cursor/wrap-session.sh caveman|ponytail|superpowers|obsidian-brain

set -euo pipefail

HOOK_NAME="${1:?usage: wrap-session.sh caveman|ponytail|superpowers|obsidian-brain}"

case "$HOOK_NAME" in
  caveman|ponytail|superpowers|obsidian-brain) ;;
  *)
    echo '{"continue":true}' >&1
    exit 0
    ;;
esac

CURSOR_HOME="${CURSOR_HOME:-${CLAUDE_CONFIG_DIR:-$HOME/.cursor}}"
SKILLS_ROOT="${VALARMIND_SKILLS_ROOT:-$CURSOR_HOME/skills}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ACTIVATE="$HOOKS_DIR/$HOOK_NAME/${HOOK_NAME}-activate.js"

emit_json() {
  local ctx="$1"
  if [ -z "$ctx" ] || [ "$ctx" = "OK" ]; then
    printf '%s\n' '{"continue":true}'
    return
  fi
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ctx "$ctx" '{additional_context: $ctx, continue: true}'
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$ctx" | python3 -c 'import json,sys; print(json.dumps({"additional_context": sys.stdin.read(), "continue": True}))'
  else
    # Last resort: minimal escape for quotes and backslashes
    local escaped
    escaped=$(printf '%s' "$ctx" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '{"additional_context":"%s","continue":true}\n' "$escaped"
  fi
}

if [ ! -f "$ACTIVATE" ]; then
  emit_json ""
  exit 0
fi

tmp_out="$(mktemp)"
trap 'rm -f "$tmp_out"' EXIT

if ! CLAUDE_CONFIG_DIR="$CURSOR_HOME" \
     VALARMIND_SKILLS_ROOT="$SKILLS_ROOT" \
     VALARMIND_HOOK_RUNTIME=cursor \
     node "$ACTIVATE" >"$tmp_out" 2>/dev/null; then
  emit_json ""
  exit 0
fi

OUT="$(cat "$tmp_out")"
emit_json "$OUT"
