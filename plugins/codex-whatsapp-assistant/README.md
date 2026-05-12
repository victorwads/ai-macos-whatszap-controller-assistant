# Codex WhatsApp Assistant (Plugin)

Este plugin conecta o Codex a um MCP Server local que controla o WhatsApp Desktop, para você usar o Codex como **assistente pessoal** (ler mensagens, resumir pendências e responder).

## Requisitos

- WhatsApp Desktop **aberto** (logado).
- Seu **Assistant MCP Server** rodando em `localhost` (HTTP) na rota `/mcp`.
  - Padrão deste plugin: `http://localhost:8080/mcp`.

## Como usar

1. Inicie o Assistant MCP Server.
2. Abra o WhatsApp Desktop.
3. No Codex, habilite o plugin **Codex WhatsApp Assistant** e use as ferramentas expostas pelo MCP server (ex.: `list_chats`, `get_recent_messages`, `send_message`).

## Ajustes

- Se o seu servidor estiver em outra porta (ex.: `8080`), edite `./.mcp.json` e atualize a `url`.
- Se você quiser usar porta `80`, troque a `url` para `http://localhost/mcp`.
