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
            writeDebugArtifacts(snapshot: snapshot, screenState: screenState, prefix: "refresh")
            memoryStore.replaceConversations(allowedConversations)
            lastRefreshDescription = "List refreshed at \(Date().formatted(date: .omitted, time: .standard))"
            appendLog("Parsed \(allowedConversations.count) conversations from WhatsApp.")
            appendLog("Wrote parser debug report to \(debugDirectory.path).")
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
        for conversation in conversations {
            let previousSignature = listSignaturesById[conversation.id]
            let needsMessages = memoryStore.chatState(for: conversation.id) == nil || previousSignature != conversation.listSignature
            listSignaturesById[conversation.id] = conversation.listSignature

            guard needsMessages else {
                continue
            }

            await loadMessages(
                for: conversation,
                reason: previousSignature == nil ? "first mapping" : "list changed",
                updateSelectedChat: selectedChatState?.chat.id == conversation.id
            )
        }
    }

    private func loadMessages(for conversation: ConversationSummary, reason: String, updateSelectedChat: Bool) async {
        do {
            let snapshot = try await openConversationAndCapture(conversation)
            let screenState = parser.parse(snapshot: snapshot, messageLimit: 10)
            writeDebugArtifacts(snapshot: snapshot, screenState: screenState, prefix: "chat-\(conversation.id)")
            let chatState = makeChatState(from: screenState, preferredConversation: conversation)
            memoryStore.upsertChatState(chatState)
            appendLog("Loaded \(screenState.messages.count) messages for \(conversation.name) (\(reason)).")
        } catch {
            appendLog("Failed to load messages for \(conversation.name): \(error.localizedDescription)", level: .error)
        }
    }

    func openConversationAndCapture(_ targetConversation: ConversationSummary) async throws -> WhatsAppSnapshot {
        for attempt in 1...3 {
            let baselineSnapshot = try accessibility.captureWhatsAppSnapshot(maxDepth: 14)
            let baselineState = parser.parse(snapshot: baselineSnapshot, messageLimit: 10)

            if baselineState.conversations.isEmpty, try dismissModalSheetIfPresent(in: baselineSnapshot) {
                try await Task.sleep(for: .milliseconds(300))
                continue
            }

            if baselineState.selectedChatName == targetConversation.name {
                return baselineSnapshot
            }

            let liveConversation = baselineState.conversations.first {
                $0.id == targetConversation.id || $0.name == targetConversation.name
            } ?? targetConversation

            try accessibility.activateWhatsApp()
            try interactor.selectConversation(liveConversation, using: accessibility)
            try await Task.sleep(for: .milliseconds(500))

            let updatedSnapshot = try accessibility.captureWhatsAppSnapshot(maxDepth: 14)
            let updatedState = parser.parse(snapshot: updatedSnapshot, messageLimit: 10)
            if updatedState.selectedChatName == targetConversation.name {
                return updatedSnapshot
            }

            appendLog("Conversation selection retry \(attempt) failed for \(targetConversation.name); current chat is \(updatedState.selectedChatName ?? "unknown").", level: .warning)
        }

        throw AccessibilityError.unexpectedChatSelection(targetConversation.name)
    }

    private func dismissModalSheetIfPresent(in snapshot: WhatsAppSnapshot) throws -> Bool {
        guard let doneButton = snapshot.rootNode.firstDescendant(where: { node in
            guard node.role == "AXButton" else {
                return false
            }

            let text = [node.title, node.nodeDescription, node.help]
                .compactMap { $0?.normalizedAXText.lowercased() }
                .joined(separator: " ")
            return text.contains("done")
        }) else {
            return false
        }

        try accessibility.activateWhatsApp()
        try? accessibility.pressNode(at: doneButton.accessibilityPath)
        try? accessibility.focusNode(at: doneButton.accessibilityPath)
        try accessibility.pressEnterKey()
        appendLog("Dismissed a WhatsApp modal sheet before selecting a conversation.", level: .warning)
        return true
    }
}
