#!/bin/bash
# superpowers — segmento de statusline. Renderiza o badge [SUPERPOWERS] sempre
# visível: cyan quando on, cinza dim quando off ou ausente.
#
# Inspired by obra/superpowers (MIT, Copyright 2025 Jesse Vincent).
# See THIRD_PARTY_NOTICES.md.

FLAG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.superpowers-active"

render_off() {
  printf '\033[38;5;240m[SUPERPOWERS]\033[0m'
}

# Recusa symlinks — atacante local poderia apontar a flag para ~/.ssh/id_rsa
# e ter o statusline imprimindo seus bytes (incluindo escapes ANSI) a cada
# tecla. Trata como off.
if [ -L "$FLAG" ] || [ ! -f "$FLAG" ]; then
  render_off
  exit 0
fi

# Cap de leitura em 64 bytes e strip de tudo fora de [a-z0-9-] — bloqueia
# injeção de escapes de terminal e spoofing de hyperlinks OSC via flag.
MODE=$(head -c 64 "$FLAG" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]')
MODE=$(printf '%s' "$MODE" | tr -cd 'a-z0-9-')

# Whitelist binária — apenas on|off são válidos. Conteúdo inválido → off.
case "$MODE" in
  on)  printf '\033[38;5;39m[SUPERPOWERS]\033[0m' ;;
  *)   render_off ;;
esac
