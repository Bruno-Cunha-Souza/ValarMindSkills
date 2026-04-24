#!/bin/bash
# context — segmento de statusline. Mostra uso de contexto da sessão atual.
#
# Formato: "X% Yk/Zk" onde X = used_percentage, Y = tokens da última chamada
# (input + cache_read + cache_creation) e Z = context_window_size.
# Cor do percentual varia por threshold: verde <50%, laranja 50-80%, vermelho >80%.
#
# Lê o JSON do Claude Code via env STATUSLINE_JSON (exportado pelo composer).

[ -z "${STATUSLINE_JSON:-}" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

pct=$(printf '%s' "$STATUSLINE_JSON" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
size=$(printf '%s' "$STATUSLINE_JSON" | jq -r '.context_window.context_window_size // empty' 2>/dev/null)
input=$(printf '%s' "$STATUSLINE_JSON" | jq -r '.context_window.current_usage.input_tokens // 0' 2>/dev/null)
cache_r=$(printf '%s' "$STATUSLINE_JSON" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0' 2>/dev/null)
cache_c=$(printf '%s' "$STATUSLINE_JSON" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0' 2>/dev/null)

[ -z "$pct" ] && exit 0
[ -z "$size" ] && exit 0

total=$(( input + cache_r + cache_c ))
pct_int=${pct%.*}
pct_int=${pct_int:-0}

if   [ "$pct_int" -lt 50 ]; then color='\033[38;5;28m'
elif [ "$pct_int" -lt 80 ]; then color='\033[38;5;172m'
else                             color='\033[38;5;160m'
fi

fmt_tokens() {
  local n=$1
  if   [ "$n" -lt 1000 ];     then printf '%d' "$n"
  elif [ "$n" -lt 1000000 ];  then awk -v n="$n" 'BEGIN{printf "%.0fk", n/1000}'
  else                             awk -v n="$n" 'BEGIN{printf "%.1fM", n/1000000}'
  fi
}

printf '\033[38;5;245mcontext:\033[0m %b%s%%\033[0m \033[38;5;245m%s/%s\033[0m' \
  "$color" "$pct_int" \
  "$(fmt_tokens "$total")" "$(fmt_tokens "$size")"
