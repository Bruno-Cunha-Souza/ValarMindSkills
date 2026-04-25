#!/bin/bash
# obsidian-brain — segmento de statusline. Renderiza o badge [OBSIDIAN-BRAIN]
# em roxo (cor 99 ≈ #875FFF, próxima do roxo oficial do Obsidian) somente
# quando a flag está ativa. Hide quando flag absent — paralelo ao caveman.sh.
#
# Trade-off da cor: 99 é o melhor compromisso ANSI-256 para o roxo Obsidian.
# Alternativas se o terminal estiver com tema agressivo: 105 (lavender claro)
# ou 141 (lilac).

FLAG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.obsidian-brain-active"

# Recusa symlinks — atacante local poderia apontar a flag para ~/.ssh/id_rsa
# e ter o statusline imprimindo seus bytes (incluindo escapes ANSI) a cada
# tecla.
[ -L "$FLAG" ] && exit 0
[ ! -f "$FLAG" ] && exit 0

# Cap de leitura em 64 bytes e strip de tudo fora de [a-z0-9-] — bloqueia
# injeção de escapes de terminal e spoofing de hyperlinks OSC via flag.
MODE=$(head -c 64 "$FLAG" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]')
MODE=$(printf '%s' "$MODE" | tr -cd 'a-z0-9-')

# Whitelist binária — apenas 'on' renderiza. Qualquer outra coisa → hide.
[ "$MODE" = "on" ] || exit 0

printf '\033[38;5;99m[OBSIDIAN-BRAIN]\033[0m'
