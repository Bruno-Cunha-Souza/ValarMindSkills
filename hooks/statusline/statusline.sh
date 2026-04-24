#!/bin/bash
# statusline — composer genérico do statusline.
#
# Lê o JSON enviado pelo Claude Code via stdin uma única vez, exporta como
# STATUSLINE_JSON, e executa cada segmento em ordem. Saídas não-vazias são
# concatenadas com espaço.
#
# Usage in ~/.claude/settings.json:
#   "statusLine": { "type": "command", "command": "bash /path/to/hooks/statusline/statusline.sh" }

STATUSLINE_JSON=""
if [ ! -t 0 ]; then
  STATUSLINE_JSON=$(cat 2>/dev/null || true)
fi
export STATUSLINE_JSON

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEGMENTS=(caveman context)

OUT=""
for seg in "${SEGMENTS[@]}"; do
  script="$DIR/segments/${seg}.sh"
  [ -f "$script" ] || continue
  out=$(bash "$script" 2>/dev/null || true)
  [ -z "$out" ] && continue
  if [ -z "$OUT" ]; then
    OUT="$out"
  else
    OUT="$OUT $out"
  fi
done

printf '%s' "$OUT"
