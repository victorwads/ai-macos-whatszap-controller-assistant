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

        _ = try await openConversationAndCapture(conversation)
        let shouldLockInput = inputLockSettings.isEnabled
        if shouldLockInput {
            // Experimental: prevent the user from stealing focus mid-send.
            accessibility.lockUserInputForSend(seconds: 5)
        }
        defer {
            if shouldLockInput {
                accessibility.unlockUserInputAfterSend()
            }
        }
        appendLog("Sending message to \(conversation.name)…")
        let verification = try await interactor.sendMessageConfirmed(
            trimmedMessage,
            expectedChatName: conversation.name,
            using: accessibility,
            parser: parser
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

    // Message send verification lives inside WhatsAppInteractor to keep the send flow fully
    // orchestrated in one place (type -> confirm -> enter -> confirm -> retry).
}
