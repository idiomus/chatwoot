# Staging testa o PR, não o merge

Vale para todo projeto da Idiomus. Regra do Caio, dita em 2026-09-23.

## A regra

Para validar em staging algo que está num PR, o PR vai para staging. Não se espera merge para testar, e não se faz merge para poder testar. O merge vem depois de o PR ser validado em staging.

Quem põe o PR em staging é o tech lead. O pedido vai para ele, dizendo o que entra (a branch de cada repositório) e o que se quer validar.

## Mudança que atravessa repositórios

Quando a validação depende de mais de um repositório, as branches entram juntas em staging, no mesmo patch. Uma branch sozinha em staging testa uma combinação que nunca vai existir.

## Como aplicar

- Plano ou handoff que diz "depois do merge, testar em staging" está errado: troque por "pedir ao tech lead o PR em staging, validar, depois merge".
- A branch que vai para staging precisa estar no GitHub. Branch só local não entra.
