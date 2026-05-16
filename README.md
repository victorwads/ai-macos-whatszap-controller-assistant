# AssistantMCPServer

Local macOS assistant bridge that combines a native SwiftUI app, Accessibility-driven control, and an embedded MCP HTTP server.

Today the project focuses on controlling WhatsApp Desktop locally on macOS.
The long-term direction is broader assistant orchestration, including future integrations with Gmail and Calendar.

## What This Project Is

This is not a generic cloud bot and not a browser-only automation layer.
It is a native macOS app that:

- reads the WhatsApp Desktop Accessibility tree
- keeps a local in-memory and persisted view of chats, messages, memories, subjects, and nicknames
- exposes those capabilities through an MCP server on `http://localhost:8080/mcp` by default
- provides a SwiftUI interface for logs, status, settings, debugging, and manual inspection

The main idea is to let Codex or another MCP client ask the app for state and actions, instead of repeatedly scanning the full UI tree or relying on model-side sleep loops.

## Current Scope

The current implementation is centered on these local capabilities:

- WhatsApp Desktop chat discovery and message inspection
- sending WhatsApp messages through Accessibility
- waiting for unread messages or client prompts without busy-waiting in the model
- text-to-speech and client prompt workflows
- local memory storage
- subject tracking for operational work
- nickname management for WhatsApp chats

The Gmail and Calendar pieces are not implemented yet, but the data model already leaves room for them through subject fields such as `gmailThreadId` and `calendarEventId`.

## Architecture

The app is a single native macOS process with a few clearly separated layers:

- `Sources/AssistantMCPServerApp.swift` launches the SwiftUI app
- `Sources/App/AppModel.swift` wires persistence, Accessibility, polling, voice, and MCP coordination
- `Sources/Features/WhatsAppIntegration/` contains Accessibility capture, parsing, and interaction logic
- `Sources/Features/Server/` contains the MCP HTTP server, transport, tool registry, and tool handlers
- `Sources/Repositories/` stores local state for memories, subjects, nicknames, chat history, and client voice events
- `Sources/Views/` and `Sources/Features/*Screen.swift` provide the UI

The MCP server runs inside the app process and serves JSON-RPC-style MCP traffic over HTTP.
The default endpoint is:

```text
http://localhost:8080/mcp
```

The server also exposes a lightweight health check:

```text
GET /health
```

## UI

The main SwiftUI window is split into sections for:

- WhatsApp chats
- integration logs
- Accessibility debug views
- server logs
- server tools
- memories
- subjects
- nicknames
- client voice
- settings

The settings screen lets you:

- change the polling interval
- refresh chats manually
- start and stop polling
- request Accessibility permission
- configure the MCP host and port
- copy an MCP client config snippet
- adjust outgoing-message prefix and signature behavior

## MCP Tools

The server currently registers these tools:

### WhatsApp chat tools

- `get_assistant_name`
- `list_chats`
- `list_unread_chats`
- `list_chats_by_search`
- `list_recent_messages`
- `send_message`
- `wait_for_chat_message`
- `wait_for_event`

### Client voice tools

- `speak_to_client`
- `ask_to_client`

### Memory tools

- `create_memory`
- `get_memory`
- `get_memories_by_tag`
- `delete_memory`

### Subject tools

- `create_subject`
- `update_subject`
- `resolve_subject`
- `cancel_subject`
- `list_active_subjects`
- `get_subject`

### Nickname tools

- `list_nicknames`
- `save_nickname`
- `delete_nickname`

## Tool Behavior Notes

- `send_message` accepts a `chatId` plus a `messages` array.
- `wait_for_chat_message` waits for unread messages in a specific chat or a client prompt.
- `wait_for_event` waits for any unread WhatsApp messages or a client prompt.
- `get_memories_by_tag` returns all memories when `tag` is omitted.
- `get_memory` looks up by `key`.
- Subject entries already include optional `gmailThreadId` and `calendarEventId` fields for future cross-app linking.
- Outgoing WhatsApp messages can be prefixed and suffixed through the settings screen.

## Development Requirements

- macOS 14.0 or newer
- Xcode with Swift 6 support
- XcodeGen `2.42.0` or newer
- WhatsApp Desktop installed locally
- Accessibility permission granted to the built app

## Build And Run

The canonical local workflow is the restart script:

```sh
./scripts/restart.sh
```

That script:

- closes running `AssistantMCPServer` instances
- regenerates the Xcode project with `xcodegen`
- builds the Debug app
- opens the freshly built app

If you only want to regenerate the project file:

```sh
xcodegen generate
```

If you want to open the generated project in Xcode:

```sh
open AssistantMCPServer.xcodeproj
```

## MCP Client Configuration

The app shows a ready-to-copy snippet in Settings.
The default shape is:

```toml
[mcp_servers.assistant_whatsapp]
enabled = true
url = "http://localhost:8080/mcp"
```

If you change the port in the app settings, update the client URL to match.

## Accessibility Setup

The app depends on macOS Accessibility permission to inspect and control WhatsApp Desktop.

If the UI says Accessibility is not trusted:

1. Open the app
2. Grant Accessibility permission in System Settings
3. Quit and relaunch the app
4. Refresh the chat list or debug tree

macOS grants permission to the exact app binary, so the identity may matter after rebuilds.

## Polling And State

The app keeps local state in sync by polling WhatsApp on a configurable interval.
The default polling interval is 5 seconds.

At a high level:

```text
poll WhatsApp Accessibility tree
parse chats and messages
update local memory store
refresh changed conversations
serve current state through MCP
```

This means the MCP layer reads from local state instead of re-parsing the UI from scratch for every tool call.

## Repository Layout

Key files and folders:

- `project.yml` - XcodeGen project definition
- `scripts/restart.sh` - canonical local build-and-run script
- `Sources/App/` - application state, polling, persistence, and MCP wiring
- `Sources/Features/Server/` - MCP server transport and tool handlers
- `Sources/Features/WhatsAppIntegration/` - Accessibility capture, parsing, and interaction
- `Sources/Repositories/` - local repositories for persistent state
- `Sources/Views/` - app views and debug screens

## Roadmap

The next major expansion areas are:

- Gmail integration
- Calendar integration
- richer cross-channel subject tracking
- deeper automation around follow-ups and task state

The current subject model already anticipates that direction, so the project can grow without redesigning the entire data model.

## Notes For Contributors

- Keep the app native and local-first.
- Prefer Accessibility semantics over screen coordinates.
- Keep MCP tool names stable once they are used by clients.
- Treat WhatsApp, Gmail, and Calendar as separate integration surfaces, even if they eventually feed the same subject model.
- Update this README whenever the tool list or runtime architecture changes.
