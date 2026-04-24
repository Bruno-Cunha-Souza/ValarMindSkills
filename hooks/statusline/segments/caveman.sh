#!/bin/bash
# caveman — segmento de statusline. Renderiza o badge [CAVEMAN] / [CAVEMAN:MODE].
#
# Ported from JuliusBrussee/caveman (MIT). See THIRD_PARTY_NOTICES.md.

FLAG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.caveman-active"

# Recusa symlinks — atacante local poderia apontar a flag para ~/.ssh/id_rsa
# e ter o statusline imprimindo seus bytes (incluindo escapes ANSI) a cada
# tecla.
[ -L "$FLAG" ] && exit 0
[ ! -f "$FLAG" ] && exit 0

# Cap de leitura em 64 bytes e strip de tudo fora de [a-z0-9-] — bloqueia
# injeção de escapes de terminal e spoofing de hyperlinks OSC via flag.
MODE=$(head -c 64 "$FLAG" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]')
MODE=$(printf '%s' "$MODE" | tr -cd 'a-z0-9-')

# Whitelist. Qualquer outra coisa → renderiza nada.
case "$MODE" in
  off|lite|full|ultra|commit|review) ;;
  *) exit 0 ;;
esac

# Modo off → segmento vazio.
[ "$MODE" = "off" ] && exit 0

if [ -z "$MODE" ] || [ "$MODE" = "full" ]; then
  printf '\033[38;5;172m[CAVEMAN]\033[0m'
else
  SUFFIX=$(printf '%s' "$MODE" | tr '[:lower:]' '[:upper:]')
  printf '\033[38;5;172m[CAVEMAN:%s]\033[0m' "$SUFFIX"
fi
