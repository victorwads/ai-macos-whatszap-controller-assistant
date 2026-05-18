# Architecture

This document explains how the current system is organized and how the major pieces fit together.

## High-level model

The project is a native macOS assistant runtime with three major responsibilities:

1. keep local state and workflow state
2. expose operational tools through MCP
3. supervise model sessions and WhatsApp integration

LM Studio remains the inference engine. The Swift app is the runtime, supervisor, and integration layer.

## Platform rationale (macOS + Swift)

This project is intentionally macOS-first.

- macOS provides strong on-device voice building blocks through public APIs (Text-to-Speech and Speech Recognition).
- Apple Silicon machines can run local LLMs via LM Studio with enough unified memory, without depending on a discrete GPU.
- The app can stay local-first: state, tools, and integrations run on the user's machine.

### Speech and Speech Recognition

The runtime can speak and listen using a few approaches:

- macOS system `say` command (uses the configured system voice)
- Swift speech APIs (high quality voices available through the public API surface)

There are tradeoffs. For Portuguese, some voices available via Swift APIs (for example, "Fernanda Enhanced") handle accents and punctuation well, while the system/Siri voice behavior can be inconsistent for some text shapes. The goal is to keep both paths available and pick the best experience per locale and device.

## Main runtime layers

### Swift app

The macOS app is the central process.

It owns:

- application state
- persistence
- UI
- Accessibility integration
- polling and orchestration
- MCP server lifecycle
- LM Studio session supervision

### WhatsApp integration

WhatsApp is currently integrated through local Accessibility and WebView surfaces.

The integration layer is responsible for:

- discovering chats
- reading chat state
- sending messages
- waiting for unread messages and prompts
- handling WhatsApp Web or desktop UI changes

### MCP server

The embedded MCP server is the main tool interface for the assistant model.

It exposes structured actions for:

- WhatsApp operations
- voice operations
- memory management
- sensitive data management
- subjects and workflow state
- utility helpers

### LM Studio supervision

The app is expected to supervise LM Studio sessions instead of relying on a long manual chat session.

This means:

- launching and pausing assistant sessions
- observing streaming events
- recovering from stalls or invalid tool behavior
- rebuilding context when necessary
- separating operational reasoning from social rendering

## Assistant lifecycle

The assistant currently runs as a local operational loop coordinated between LM Studio and the macOS app.

At a high level:

1. the macOS app starts and exposes the embedded MCP server
2. LM Studio loads a model and starts a stateful chat session
3. the operational prompt is loaded from [Assistant System prompt-ptBR.md](../plugins/lmstudio/Assistant%20System%20prompt-ptBR.md)
4. the model connects to the app through MCP tools
5. the model enters a continuous workflow of reading state, waiting for events, deciding what to do, and calling tools
6. the Swift runtime persists the results and serves the next observable state back to the model

The English prompt variant is available at [Assistant System prompt.md](../plugins/lmstudio/Assistant%20System%20prompt.md), but the Portuguese prompt is the main operational prompt for the current assistant behavior.

## Operational cycle

Once the assistant is running, the prompt guides it through a loop similar to this:

1. check current date and runtime context
2. review memories and standing preferences when relevant
3. inspect active subjects and pending work
4. wait for new events or unread messages
5. read recent messages for the specific chat or event
6. update subjects, memories, nicknames, or sensitive-data references when needed
7. decide whether to reply, ask the client, speak to the client, or wait
8. persist the outcome so the next cycle starts from a coherent state

The important architectural point is that the model does not own durable state by itself. The Swift app owns the durable state, and the prompt teaches the model how to interact with that state through tools.

## Subjects lifecycle

Subjects represent ongoing pieces of work, such as a task, a follow-up, an appointment flow, or a conversation thread that needs continuity.

The assistant can:

- create a subject when a new thread of work appears
- update it as more information arrives
- attach external references such as chat IDs, future Gmail threads, or calendar IDs
- resolve or cancel it when the work is done
- list active subjects to recover operational context after waiting or restarting

This is one of the ways the runtime avoids relying only on the LM Studio chat context.

## Multi-profile motivation

Multi-profile support exists because the runtime can host more than one assistant on the same Mac.

In practice:

- the local model instance can stay loaded in memory
- WhatsApp polling and state sync are usually the main background cost
- different people receive messages at different times, so inference load tends not to spike constantly

This enables hosting assistants for family members (for example: partner, mother) on a single machine, while exposing a UI (and future mobile UI) so those users can manage memories, subjects, and state without local access to LM Studio.

## Current tool surface

The registered tool list is defined in [MCPServerToolRegistry.swift](../Sources/Features/Server/MCPServerToolRegistry.swift).
Each concrete tool lives under [Sources/Features/Server/Tools/](../Sources/Features/Server/Tools/).
Those Swift files are the source of truth for names, schemas, behavior, and documentation.

The current tool groups are:

### WhatsApp chat tools

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
- `search_memories`
- `list_memories`
- `delete_memory`

### Sensitive data tools

- `save_sensitive_data`
- `update_sensitive_data`
- `get_sensitive_data`
- `search_sensitive_data`
- `list_sensitive_data`
- `delete_sensitive_data`

### Subject tools

- `create_subject`
- `update_subject`
- `resolve_subject`
- `cancel_subject`
- `check_active_subjects`
- `get_subject`

### Nickname tools

- `list_nicknames`
- `save_nickname`
- `delete_nickname`

When changing or documenting tool behavior, check the corresponding `*Tool.swift` implementation first.

## State model

The runtime keeps a local model of the assistant world:

- chats and chat history
- pending events and waits
- voice events
- memories
- sensitive data
- subjects
- nicknames
- server logs and debug artifacts

That local state is what MCP serves, rather than re-parsing everything from scratch on every request.

## Polling and sync

At a high level, the runtime loop looks like this:

1. poll the WhatsApp integration surface
2. parse chat and message changes
3. update local repositories
4. refresh pending events and voice state
5. expose the resulting state through MCP

This is what makes the system feel more like a runtime than a thin server.

## Separation of concerns

The architecture now separates these conceptual concerns:

- runtime supervision
- MCP-facing actions
- WhatsApp integration
- social/humanization rendering
- persistence
- observability

That separation is important because the assistant now needs to behave differently depending on whether it is reasoning, speaking, replying, or only rendering a human-friendly message.

## LM Studio event stream

When the app talks to LM Studio using the streaming API, it can observe events such as:

- chat lifecycle events
- model loading events
- prompt processing events
- reasoning deltas
- tool call boundaries
- message deltas
- errors
- final response completion

That event stream is useful both for supervision and for future UI surfaces that show what the model is doing in real time.

## Future shape

Likely next steps in the architecture are:

- a dedicated LM Studio control panel
- a separate humanization pass after reasoning
- mobile/remote observability
- more formal session recovery
- stronger test orchestration around model and integration flows
