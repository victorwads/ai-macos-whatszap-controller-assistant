import Foundation

extension AppModel {
    func refreshConversations() async {
        guard prepareForWhatsAppInspection() else {
            return
        }

        do {
            let snapshot = try accessibility.captureWhatsAppSnapshot(maxDepth: 14)
            let screenState = parser.parse(snapshot: snapshot, messageLimit: 10)
            let allowedConversations = filteredConversations(screenState.conversations)
            memoryStore.replaceConversations(allowedConversations)
            lastRefreshDescription = "List refreshed at \(Date().formatted(date: .omitted, time: .standard))"
            appendLog("Parsed \(allowedConversations.count) conversations from WhatsApp.")
            await refreshChangedChats(from: allowedConversations)
        } catch {
            appendLog("Failed to refresh conversations: \(error.localizedDescription)", level: .error)
        }
    }

    func startPolling() {
        guard pollingTask == nil else {
            return
        }

        isPolling = true
        appendLog("Started WhatsApp polling.")

        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.schedulePollingRefresh()
                try? await Task.sleep(for: .seconds(self.pollingIntervalSeconds))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
        appendLog("Stopped WhatsApp polling.")
    }

    private func schedulePollingRefresh() async {
        await accessibilityScheduler.enqueue(priority: .background) { [weak self] in
            guard let self else { return }
            await self.refreshConversations()
        }
    }

    func updateSelectedChatState(from screenState: WhatsAppScreenState, preferredConversation: ConversationSummary) {
        let chatState = makeChatState(from: screenState, preferredConversation: preferredConversation)
        memoryStore.upsertChatState(chatState)
    }

    func makeChatState(from screenState: WhatsAppScreenState, preferredConversation: ConversationSummary) -> ChatState {
        let latestConversation = screenState.conversations.first { $0.id == preferredConversation.id } ?? preferredConversation

        return ChatState(
            chat: latestConversation,
            messages: screenState.messages,
            composeFocused: screenState.composeFocused,
            canSendText: screenState.canSendText
        )
    }

    private func refreshChangedChats(from conversations: [ConversationSummary]) async {
        var didUpdateSignatures = false
        for conversation in conversations {
            guard !isBlocked(conversation.name) else {
                continue
            }
            let previousSignature = listSignaturesById[conversation.id]
            let signatureChanged = previousSignature != conversation.listSignature
            if previousSignature == nil || signatureChanged {
                listSignaturesById[conversation.id] = conversation.listSignature
                didUpdateSignatures = true
            }

            let isMissingCachedMessages = memoryStore.chatState(for: conversation.id) == nil
            let needsMessages = isMissingCachedMessages || previousSignature == nil || signatureChanged

            guard needsMessages else {
                continue
            }

            await loadMessages(
                for: conversation,
                reason: previousSignature == nil ? "first mapping" : "list changed",
                updateSelectedChat: selectedChatState?.chat.id == conversation.id
            )
        }

        if didUpdateSignatures {
            persistChatListSignatures()
        }
    }

    func loadMessages(for conversation: ConversationSummary, reason: String, updateSelectedChat: Bool) async {
        guard !isBlocked(conversation.name) else {
            appendLog("Skipped loading messages for blocked conversation \(conversation.name) (\(reason)).", level: .warning)
            return
        }
        do {
            let snapshot = try await openConversationAndCapture(conversation)
            let screenState = parser.parse(snapshot: snapshot, messageLimit: 10)
            let chatState = makeChatState(from: screenState, preferredConversation: conversation)
            memoryStore.upsertChatState(chatState)
            appendLog("Loaded \(screenState.messages.count) messages for \(conversation.name) (\(reason)).")
        } catch {
            appendLog("Failed to load messages for \(conversation.name): \(error.localizedDescription)", level: .error)
        }
    }

    func ensureChatLoaded(chatId: String, reason: String) async {
        guard memoryStore.chatState(for: chatId) == nil else {
            return
        }
        guard let conversation = memoryStore.conversation(for: chatId) else {
            return
        }
        guard !isBlocked(conversation.name) else {
            appendLog("Skipped loading blocked conversation \(conversation.name) (\(reason)).", level: .warning)
            return
        }
        await loadMessages(for: conversation, reason: reason, updateSelectedChat: false)
    }

    func openConversationAndCapture(_ targetConversation: ConversationSummary) async throws -> WhatsAppSnapshot {
        for attempt in 1...3 {
            let baselineSnapshot = try accessibility.captureWhatsAppSnapshot(maxDepth: 14)
            let baselineState = parser.parse(snapshot: baselineSnapshot, messageLimit: 10)

            if baselineState.selectedChatName == targetConversation.name {
                return baselineSnapshot
            }

            let liveConversation = baselineState.conversations.first {
                $0.id == targetConversation.id || $0.name == targetConversation.name
            } ?? targetConversation

            try interactor.selectConversation(liveConversation, using: accessibility)
            try await Task.sleep(for: .milliseconds(500))

            let updatedSnapshot = try accessibility.captureWhatsAppSnapshot(maxDepth: 14)
            let updatedState = parser.parse(snapshot: updatedSnapshot, messageLimit: 10)
            if updatedState.selectedChatName == targetConversation.name {
                return updatedSnapshot
            }

            appendLog("Conversation selection retry \(attempt) failed for \(targetConversation.name); current chat is \(updatedState.selectedChatName ?? "unknown").", level: .warning)
        }

        throw AccessibilityError.actionFailed(-1)
    }
}
