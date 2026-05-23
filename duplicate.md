## Contexto

Para respeitar o `clean code` e melhorar a manutenção do código, verificar duplicações de código desnecessárias e remove-las do código.

Em termos simples, duplicidade ocorre quando o mesmo conhecimento, lógica ou intenção é expresso em mais de um lugar no sistema.

### O Princípio DRY (Don't Repeat Yourself)

A base do combate à duplicidade é o princípio **DRY** ("Não se repita"). A ideia central é que cada peça de conhecimento dentro de um sistema deve ter uma representação única, clara e autoritativa.

### Tasks:

1. Identifique os trechos duplicados.
2. Aplique a melhor solução de refatoração (Extrair Método, Substituir Algoritmo ou Polimorfismo).
3. Apresente a versão refatorada e explique brevemente as mudanças realizadas. Comparando o antes e o depois, quantas linhas foram adicionadas e quantas foram removidas ( usar recursos dos commandos do git para isso ).

## Buscar Duplicidades

- **Duplicidade Óbvia (Literal):** É o caso clássico onde blocos de código são idênticos ou quase idênticos em métodos ou classes diferentes.
- **Duplicidade Sutil (Lógica):** O código parece diferente (usa nomes de variáveis diferentes ou estruturas de controle distintas), mas o **resultado final e a lógica de negócio** são exatamente os mesmos.
- **Duplicidade de Estrutura:** Quando você tem cadeias de `if/else` ou `switch/case` repetitivas espalhadas pelo código. Se você precisa adicionar uma nova condição em cinco lugares diferentes, você tem duplicidade estrutural.

## Solução

O Clean Code sugere ferramentas de refatoração para eliminar esses "cheiros" (code smells):

- **Extrair Método (Extract Method):** Pegue o código repetido e coloque-o em uma função única que possa ser chamada de qualquer lugar.
- **Substituir Algoritmo:** Se dois métodos fazem a mesma coisa de formas diferentes, escolha a mais limpa e use-a em ambos.
- **Polimorfismo:** No caso de `switch` statements repetitivos, o Clean Code recomenda o uso de classes e interfaces para tratar comportamentos diferentes, eliminando a necessidade de repetir a mesma estrutura de decisão.
