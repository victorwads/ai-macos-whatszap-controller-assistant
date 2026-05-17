# Backlog (WhatsApp Assistant)

Arquivo em: `/Users/DevData/victorwads/GitRepos/Personal/AssistantMCPServer/backlog.md`

Instrução: antes de qualquer commit relacionado a itens deste backlog, validar que o build está funcionando usando `scripts/check_build_and_restart.sh`.

Este arquivo reúne ideias e melhorias para retomarmos depois. Cada item fica separado por uma linha `---`.

---

## 1) Encontrar chat que não aparece na lista inicial

**Descrição**  
Quando a conversa não estiver visível na lista principal do app, o agente deve conseguir pesquisar o nome ou número na barra de busca do WhatsApp Web/Desktop, validar o resultado e abrir o chat certo antes de seguir com a ação.

**Por que isso entra no backlog**  
É um fluxo mais complexo e frágil, porque depende de busca, seleção de resultado, validação de ambiguidade e sincronização do contexto do chat antes do envio.

---

## 2) Arquivar conversa

**Descrição**  
Adicionar a capacidade de arquivar uma conversa específica para manter o conjunto de chats ativos mais enxuto e organizado. O comportamento padrão do WhatsApp de reabrir o chat quando chegam mensagens novas continua valendo.

**Por que isso entra no backlog**  
É uma melhoria útil para controle de contexto e limpeza da lista de conversas, com uma implementação relativamente direta em comparação com o fluxo de busca/resolução de chat.

---
