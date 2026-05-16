# Handoff Prompt

Use this prompt when opening a new Codex session in this repository.

```text
Voce esta trabalhando no projeto macOS nativo AssistantMCPServer em:
/Users/victorwads/GitRepos/Personal/AssistantMCPServer

Objetivo do projeto:
Criar uma aplicacao macOS nativa em SwiftUI que usa Accessibility para ler e controlar o WhatsApp Desktop e expor isso depois como um MCP server local. O objetivo final e substituir ciclos manuais de sleep por ferramentas como wait_for_next_message, list_conversations, list_unread_conversations, list_recent_messages, send_message e get_instructions.

Estado atual:
- Projeto Xcode SwiftUI criado e versionado.
- Bundle identifier configurado como dev.wads.AssistantMCPServer, seguindo o dominio wads.dev.
- README.md contem o plano tecnico completo, arquitetura, ferramentas MCP desejadas, comportamento esperado para conversas e instrucoes de permissao de Accessibility.
- A UI atual mostra logs, status de Accessibility, identidade runtime do app, botoes Permission, Refresh e Dump WhatsApp.
- AccessibilityService ja tenta localizar o WhatsApp pelo bundle id net.whatsapp.WhatsApp e fazer dump inicial da arvore de acessibilidade.
- Memories agora usam `key` como identificador canonico.
- `get_memory(key)` faz busca exata.
- `get_memories_by_tag(tag?)` filtra por tag e retorna tudo quando `tag` e omitida.
- `title` ficou reservado para Subjects e Nicknames.
- Keys devem ser enviadas em snake_case.
- O build validado anteriormente usou:
  xcodebuild -project AssistantMCPServer.xcodeproj -scheme AssistantMCPServer -configuration Debug CODE_SIGNING_ALLOWED=NO build

Regras de trabalho:
- Antes de alterar, rode git status --short.
- Nao use caminhos com espacos.
- Preserve o caminho canonico /Users/victorwads/GitRepos/Personal/AssistantMCPServer.
- Faca commits pequenos e frequentes depois de mudancas relevantes.
- Nunca reverta alteracoes do usuario sem autorizacao explicita.
- Use apply_patch para edicoes manuais de arquivos.
- Se o usuario for agressivo, responda com limite respeitoso e uma reformulacao usando CNV e comunicacao assertiva.

Proxima etapa sugerida:
1. Rodar o app pelo Xcode e confirmar que Accessibility esta trusted.
2. Validar `create_memory`, `get_memory` e `get_memories_by_tag` via MCP inspector.
3. Melhorar o dump do WhatsApp para extrair uma representacao estruturada da tela, com role, title, value, description, frame e children relevantes.
4. Criar modelos Swift para ConversationSummary e Message.
5. Implementar list_conversations a partir da lista lateral do WhatsApp.
6. Implementar logs claros na UI mostrando exatamente quais elementos foram detectados.
7. Depois implementar polling/wait_for_next_message com checagem local frequente sem gastar tokens do Codex.

Cuidados com Accessibility:
- macOS concede permissao para a identidade exata do app/binario. Quando rodar pelo Xcode, pode ser necessario habilitar o app em System Settings > Privacy & Security > Accessibility, parar a execucao, rodar novamente e apertar Refresh.
- Se Dump WhatsApp disser que nao tem permissao, confira a identidade runtime mostrada na UI.
- Evite assumir que a arvore do WhatsApp e estavel; sempre mantenha logs de debug suficientes para corrigir parsers.

Continue a partir daqui implementando a proxima menor etapa verificavel, rode build e faca commit.
```
