import Foundation

extension AppModel {
    func sendMessageToSelectedChat() async {
        let trimmedMessage = messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            appendLog("Cannot send an empty message.", level: .warning)
            return
        }

        guard let selectedChatState else {
            appendLog("No selected conversation available to send a message.", level: .warning)
            return
        }

        isSendingMessage = true
        defer { isSendingMessage = false }

        await enqueueSendMessage(trimmedMessage, to: selectedChatState.chat.id, clearDraftOnSuccess: true)
    }

    /// Sends a message while coordinating with the accessibility action scheduler.
    /// This mirrors the UI send flow by canceling background refreshes and pausing polling to avoid races.
    func sendMessageViaScheduler(_ text: String, to conversationId: String) async throws {
        await accessibilityScheduler.cancelAll { $0 == .background }

        let resumePollingAfterSend = isPolling
        if resumePollingAfterSend {
            stopPolling()
        }

        defer {
            if resumePollingAfterSend {
                startPolling()
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                await self.accessibilityScheduler.enqueue(priority: .critical) { [weak self] in
                    guard let self else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    do {
                        try await self.sendMessage(text, to: conversationId)
                        continuation.resume(returning: ())
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    func sendMessage(_ text: String, to conversationId: String) async throws {
        guard prepareForWhatsAppInspection() else {
            throw MCPServerError.invalidRequest
        }

        let trimmedMessage = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            throw MCPServerError.invalidParameter("text")
        }

        guard let conversation = memoryStore.conversation(for: conversationId) else {
            throw MCPServerError.invalidParameter("chatId")
        }

        guard !isBlocked(conversation.name) else {
            throw MCPServerError.invalidRequest
        }

        let snapshot = try await openConversationAndCapture(conversation)
        if experimentalInputLockEnabled {
            // Experimental: prevent the user from stealing focus mid-send.
            accessibility.lockUserInputForSend(seconds: 5)
        }
        try interactor.sendMessage(trimmedMessage, in: snapshot, using: accessibility)
        appendLog("Send action executed for \(conversation.name). Verifying delivery in UI…")

        let verification = try await verifyRecentlySentMessage(
            trimmedMessage,
            expectedChatName: conversation.name,
            timeoutSeconds: 12,
            pollIntervalMs: 500,
            messageWindow: 12
        )

        writeDebugArtifacts(snapshot: verification.snapshot, screenState: verification.state, prefix: "send-\(conversation.id)")
        memoryStore.replaceConversations(verification.state.conversations)
        updateSelectedChatState(from: verification.state, preferredConversation: conversation)

        appendLog("Sent message to \(conversation.name) confirmed in UI.")
    }

    private func enqueueSendMessage(_ text: String, to conversationId: String, clearDraftOnSuccess: Bool) async {
        // Ensure any pending background refresh does not race with a send.
        await accessibilityScheduler.cancelAll { $0 == .background }

        let resumePollingAfterSend = isPolling
        if resumePollingAfterSend {
            stopPolling()
        }

        await accessibilityScheduler.enqueue(priority: .critical) { [weak self] in
            guard let self else { return }
            defer {
                if resumePollingAfterSend {
                    Task { @MainActor in
                        self.startPolling()
                    }
                }
            }

            do {
                try await self.sendMessage(text, to: conversationId)
                if clearDraftOnSuccess {
                    await MainActor.run { self.messageDraft = "" }
                }
            } catch {
                await MainActor.run {
                    self.appendLog("Failed to send message: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }

    private struct SendVerificationResult {
        let snapshot: WhatsAppSnapshot
        let state: WhatsAppScreenState
    }

    private func verifyRecentlySentMessage(
        _ text: String,
        expectedChatName: String,
        timeoutSeconds: Int,
        pollIntervalMs: Int,
        messageWindow: Int
    ) async throws -> SendVerificationResult {
        let normalizedTarget = normalizeMessageTextForVerification(text)
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))

        var attempts = 0
        var lastState: WhatsAppScreenState?
        var lastSnapshot: WhatsAppSnapshot?

        while Date() < deadline {
            attempts += 1
            try await Task.sleep(for: .milliseconds(pollIntervalMs))

            let snapshot = try accessibility.captureWhatsAppSnapshot(maxDepth: 14)
            let state = parser.parse(snapshot: snapshot, messageLimit: max(10, messageWindow))

            lastState = state
            lastSnapshot = snapshot

            // Best-effort: ensure we are still on the intended chat.
            if let selected = state.selectedChatName, !selected.isEmpty, selected != expectedChatName {
                continue
            }

            let recent = Array(state.messages.suffix(messageWindow))
            if recent.contains(where: { message in
                guard message.direction == .outgoing else { return false }
                guard let raw = message.text else { return false }
                let candidate = normalizeMessageTextForVerification(raw)
                if candidate == normalizedTarget { return true }
                // The parser can sometimes return truncated/normalized versions of the message text.
                // Use a conservative contains match to reduce false negatives.
                if candidate.count >= 6 && normalizedTarget.contains(candidate) { return true }
                if normalizedTarget.count >= 6 && candidate.contains(normalizedTarget) { return true }
                return false
            }) {
                return SendVerificationResult(snapshot: snapshot, state: state)
            }
        }

        let selectedName = lastState?.selectedChatName ?? "nil"
        let recentDump = (lastState?.messages.suffix(messageWindow) ?? []).map { message in
            let dir = message.direction.rawValue
            let txt = message.text ?? "nil"
            return "\(dir): \(txt)"
        }.joined(separator: " | ")

        // Keep a debug artifact even on failure, so we can inspect what the UI looked like.
        if let snapshot = lastSnapshot, let state = lastState {
            writeDebugArtifacts(snapshot: snapshot, screenState: state, prefix: "send-not-confirmed")
        }

        throw MCPServerError.sendNotConfirmed(
            "chat='\(expectedChatName)' selected='\(selectedName)' attempts=\(attempts) recent=[\(recentDump)]"
        )
    }

    private func normalizeMessageTextForVerification(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .lowercased()
    }
}
