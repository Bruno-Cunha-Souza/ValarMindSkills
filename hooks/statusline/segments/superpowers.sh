#!/bin/bash
# superpowers — segmento de statusline. Renderiza o badge [SUPERPOWERS] quando
# o flag de sessão está ativo (modo `on`). Mantém-se mudo quando off-by-default.
#
# Inspired by obra/superpowers (MIT, Copyright 2025 Jesse Vincent).
# See THIRD_PARTY_NOTICES.md.

FLAG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.superpowers-active"

# Recusa symlinks — atacante local poderia apontar a flag para ~/.ssh/id_rsa
# e ter o statusline imprimindo seus bytes (incluindo escapes ANSI) a cada
# tecla.
[ -L "$FLAG" ] && exit 0
[ ! -f "$FLAG" ] && exit 0

# Cap de leitura em 64 bytes e strip de tudo fora de [a-z0-9-] — bloqueia
# injeção de escapes de terminal e spoofing de hyperlinks OSC via flag.
MODE=$(head -c 64 "$FLAG" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]')
MODE=$(printf '%s' "$MODE" | tr -cd 'a-z0-9-')

# Whitelist binária — apenas on|off são válidos. Qualquer outra coisa → mudo.
case "$MODE" in
  on|off) ;;
  *) exit 0 ;;
esac

# Modo off → segmento vazio.
[ "$MODE" = "off" ] && exit 0

# Modo on → badge cyan-blue (distinto do orange 172 do caveman).
printf '\033[38;5;39m[SUPERPOWERS]\033[0m'
