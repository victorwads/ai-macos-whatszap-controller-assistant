# Assistant MCP Server

Local macOS assistant bridge for controlling WhatsApp Desktop through Accessibility and exposing fast MCP tools to Codex.

## Purpose

This project exists because direct Computer Use interaction with WhatsApp is too slow and token-heavy for live conversations. The desired model is:

- A native macOS process watches WhatsApp locally.
- It parses the Accessibility tree into stable objects.
- It waits for changes locally, polling every few seconds (default 3s).
- Codex calls MCP tools and receives clean events instead of repeatedly reading the entire UI tree.

The primary use case is active personal-assistant work: WhatsApp conversations, scheduling follow-ups, waiting for replies, and coordinating tasks without model-side `sleep` loops.

## Repository Path

Use the no-space path:

```sh
/Users/victorwads/GitRepos/Personal/AssistantMCPServer
```

Avoid paths with spaces for this project.

## Architecture

The intended architecture has two main layers.

`AssistantMCPServer.app`

Native macOS SwiftUI app responsible for:

- requesting and checking Accessibility permission
- finding WhatsApp Desktop by bundle ID, currently `net.whatsapp.WhatsApp`
- reading WhatsApp Accessibility nodes through `AXUIElement`
- parsing visible chats, unread counts, selected chat, messages, typing state, and compose field
- sending text messages via Accessibility interactions
- showing live logs and raw parser output on screen
- exposing a local MCP HTTP server on `/mcp`

The current app already includes the MCP server layer in the same process, serving JSON-RPC tool requests directly. A future split into a separate MCP process is still possible, but the current implementation keeps the HTTP bridge and Accessibility logic together.

## Current Project

This repo currently contains a generated Xcode project for a macOS SwiftUI app with Accessibility polling and an embedded MCP HTTP bridge:

- `project.yml`: XcodeGen project definition
- `AssistantMCPServer.xcodeproj`: generated Xcode project
- `Sources/AssistantMCPServerApp.swift`: app entrypoint
- `Sources/ContentView.swift`: main UI and MCP server controls
- `Sources/LogView.swift`: live log panel
- `Sources/App/AppModel.swift`: app state, startup, and service wiring
- `Sources/App/AppModel+Polling.swift`: polling loop and refresh logic
- `Sources/App/AppModel+Messaging.swift`: send-message flow and enqueue semantics
- `Sources/App/AppModel+MCP.swift`: MCP JSON-RPC request handling and tool definitions
- `Sources/App/WhatsAppMemoryStore.swift`: in-memory chat state and wait-for-message support
- `Sources/WhatsAppBridge/Interaction/WhatsAppInteractor.swift`: selecting conversations and sending messages in WhatsApp
- `Sources/WhatsAppBridge/Parsing/WhatsAppAccessibilityMap.swift`: heuristics for locating WhatsApp AX nodes
- `Sources/WhatsAppBridge/Accessibility/AccessibilityService.swift`: low-level AX and keyboard event interactions

## Default Development Flow

Use the restart script as the default way to test local changes:

```sh
./scripts/restart.sh
```

This is the standard build-and-run path for the project. It:

- closes running `AssistantMCPServer` instances
- regenerates `AssistantMCPServer.xcodeproj` with `xcodegen`
- builds the Debug app
- opens the freshly built app

Use this flow when validating changes locally instead of calling `xcodebuild` manually.

Generate the Xcode project again after changing `project.yml` only if you want that step by itself:

```sh
xcodegen generate
```

Restart the app from a clean build:

```sh
./scripts/restart.sh
```

Open the project:

```sh
open AssistantMCPServer.xcodeproj
```

## Development Commands

Manual build with a stable local `DerivedData` path:

```sh
xcodebuild \
  -project AssistantMCPServer.xcodeproj \
  -scheme AssistantMCPServer \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  build
```

Prefer the restart script for day-to-day work. Use the manual build command only when you explicitly want to build without restarting the app.

The restart script uses `build/DerivedData`, so the built app path stays stable across runs.

## Desired MCP Tools

The app currently exposes a local MCP HTTP server at `/mcp` that implements JSON-RPC-style `tools/list` and `tools/call` requests.

Current implemented tools:

```text
list_chats()
get_recent_messages(chat_id, limit = 10)
send_message(chat_id, text)
wait_for_message(chat_id?, afterMessageId?, timeoutSeconds = 60)
```

The MCP server also accepts lightweight protocol messages such as `initialize`, `ping`, and `notifications/initialized` for integration compatibility.

The most important runtime pattern is:
- the native app polls WhatsApp locally on a schedule
- the MCP server answers tool calls from the app state
- `wait_for_message` can be used to avoid model-side polling by waiting until new chat state arrives

## Data Model

Suggested chat object:

```ts
type Chat = {
  id: string
  name: string
  unreadCount: number
  isPinned: boolean
  isSelected: boolean
  lastMessagePreview: string
  lastMessageAt: string | null
  lastMessageDirection: "incoming" | "outgoing" | "unknown"
  isTyping: boolean
}
```

Suggested message object:

```ts
type Message = {
  id: string
  chatId: string
  direction: "incoming" | "outgoing"
  kind: "text" | "voice" | "image" | "document" | "deleted" | "unknown"
  text?: string
  durationSeconds?: number
  timestamp?: string
  status?: "sent" | "delivered" | "read" | "unknown"
  rawAccessibilityText: string
}
```

Suggested chat state:

```ts
type ChatState = {
  chat: Chat
  messages: Message[]
  composeFocused: boolean
  canSendText: boolean
}
```

## Accessibility Parsing Strategy

Prefer Accessibility semantics over coordinates.

Use:

- `AXRole`
- `AXDescription`
- `AXValue`
- `AXTitle`
- `AXHelp`
- known labels such as `List of chats`, `Messages in chat with ...`, `Compose message`, `Send`, `Voice message`, `Unread`, and `is typing`

Suggested parser layers:

`RawAXNode`

Object representation of the raw Accessibility tree.

`WhatsAppScreenParser`

Converts raw nodes into:

- visible chat list
- selected chat
- visible message list
- typing state
- compose state

`ChangeDetector`

Compares snapshots and emits events:

- new incoming message
- outgoing message status changed
- chat became unread
- typing started/stopped
- selected chat changed

## Polling And Waits

The native app currently polls WhatsApp locally on a scheduled background loop.

```text
every 3s (default):
  capture WhatsApp AX snapshot
  parse chat list and selected chat state
  update the in-memory store
  refresh changed conversations and message state
```

The actual code uses:
- `AppModel.startPolling()` to start the loop
- `AppModel.schedulePollingRefresh()` to enqueue work in the scheduler
- `AccessibilityActionScheduler` to serialize AX actions and respect priorities
- `WhatsAppMemoryStore` to keep conversation state and signal new messages

That means the app owns the polling and state tracking. The MCP server only exposes the current state and action tools over HTTP.

## Conversation Behavior Instructions

The MCP `get_instructions()` should eventually return these rules.

Cadence:

- For hot conversations, start by waiting `5s`.
- If no reply, wait `15s`.
- Wait another `15s`.
- Then wait `30s`.
- Wait another `30s`.
- Then stay at `60s` until a reply arrives.
- Reset to `5s` when a new reply arrives in an engaged conversation.
- If the other person is visibly typing, prefer short `5s` waits before replying.

Human style:

- Do not constantly interrupt while the other person is typing.
- Use short follow-ups when silence feels unnatural.
- Keep the tone conversational, interested, and not robotic.
- Avoid over-structured or overly polished replies in WhatsApp.
- It is acceptable to sound lightly anticipatory when waiting for a response.

Audio limitation:

- The assistant cannot reliably understand WhatsApp voice messages unless transcription is added later.
- When needed, ask the person to send text.

Conversation completion:

- When a test conversation is winding down, ask if the person wants anything else.
- Then close naturally with a short thanks.

## Debug UI Requirements

The app should visibly log:

- Accessibility permission state
- whether WhatsApp is running
- selected chat
- parsed chat list
- unread chats
- latest parsed messages
- typing indicators
- raw Accessibility snippets when parsing fails
- events emitted to MCP waits
- send message attempts and results

This log panel is important because WhatsApp may change Accessibility labels or hierarchy. The parser should be easy to inspect and adjust.

## MVP Plan

1. Build the SwiftUI debug app and Accessibility permission flow.
2. Dump WhatsApp Accessibility tree into the log panel.
3. Parse visible chat list.
4. Parse selected conversation and visible messages.
5. Detect new messages by diffing snapshots.
6. Implement text sending.
7. Add a local HTTP server inside the macOS app.
8. Add a separate MCP server that calls the local app.
9. Implement `wait_for_next_message`.
10. Add `get_instructions`.

## Risks

- WhatsApp may change Accessibility labels or node hierarchy.
- Voice messages are not useful without transcription.
- Only visible messages may be available without scrolling.
- Accessibility permission may reset when app signing changes.
- Send actions need deduplication to avoid repeated messages after retries.

`send_message` should eventually return enough information to verify the send:

```json
{
  "chat_id": "example",
  "text": "message sent",
  "observed_status": "sent",
  "timestamp": "2026-05-11T15:00:00-03:00"
}
```

## Build Notes

This project uses XcodeGen. Install path on this machine:

```sh
/opt/homebrew/bin/xcodegen
```

Build from terminal:

```sh
xcodebuild -project AssistantMCPServer.xcodeproj -scheme AssistantMCPServer -configuration Debug build
```

Run from Xcode first so macOS can prompt for Accessibility permission cleanly.

For Accessibility testing, do not run the app unsigned or with `CODE_SIGNING_ALLOWED=NO`. macOS TCC keys the permission to the app identity, and ad-hoc/unsigned rebuilds can make System Settings treat the rebuilt app as a different client. The generated project is configured to use the local `Apple Development` signing identity with team `RP7J7JX9L2`; if this machine changes, update `DEVELOPMENT_TEAM` in `project.yml`, run `xcodegen generate`, then grant Accessibility once again.

## Accessibility Permission While Running From Xcode

macOS TCC grants Accessibility permission to a specific app identity/path. When the app is launched from Xcode, that binary usually lives inside Xcode DerivedData, not directly inside the repository.

If the app keeps saying Accessibility is not trusted:

1. Run the app from Xcode.
2. Press `Permission`.
3. Enable the app that appears in `System Settings > Privacy & Security > Accessibility`.
4. Return to the app; it should relaunch itself after detecting the new permission.
5. Press `Refresh`.
6. Press `Dump WhatsApp`.

If the Accessibility toggle turns itself off after every rebuild, remove the old entry from System Settings, confirm the app is being signed with a stable `Apple Development` identity, rebuild, and grant the permission again.

The app logs its current bundle id, bundle path, and executable path so you can verify which exact binary macOS needs to trust.

The `Dump WhatsApp` action checks Accessibility permission live instead of trusting cached UI state, because permission can change while the app is open.
