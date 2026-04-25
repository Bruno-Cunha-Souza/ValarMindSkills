#!/bin/bash
# statusline — composer genérico do statusline.
#
# Lê o JSON enviado pelo Claude Code via stdin uma única vez, exporta como
# STATUSLINE_JSON, executa cada segmento em ordem e concatena as saídas
# não-vazias com separador ` | `.
#
# Usage in ~/.claude/settings.json:
#   "statusLine": { "type": "command", "command": "bash /path/to/hooks/statusline/statusline.sh" }

STATUSLINE_JSON=""
if [ ! -t 0 ]; then
  STATUSLINE_JSON=$(cat 2>/dev/null || true)
fi
export STATUSLINE_JSON

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEGMENTS=(caveman superpowers obsidian-brain context)
SEPARATOR=' \033[38;5;240m|\033[0m '

OUT=""
for seg in "${SEGMENTS[@]}"; do
  script="$DIR/segments/${seg}.sh"
  [ -f "$script" ] || continue
  piece=$(bash "$script" 2>/dev/null || true)
  [ -z "$piece" ] && continue
  if [ -z "$OUT" ]; then
    OUT="$piece"
  else
    OUT="$OUT$(printf '%b' "$SEPARATOR")$piece"
  fi
done

printf '%s' "$OUT"
