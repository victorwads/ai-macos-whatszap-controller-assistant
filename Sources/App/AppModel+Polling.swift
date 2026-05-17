import Foundation

extension AppModel {
    func refreshConversations() async {
        let mode = whatsAppIntegrationSettings.mode

        switch mode {
        case .web:
            guard let accountId = selectedWhatsAppWebAccountId else {
                appendLog("WhatsApp Web polling enabled but no account is selected.", level: .warning)
                return
            }
            let provider = WebProvider(
                accountId: accountId,
                accounts: { [weak self] in self?.whatsAppWebAccounts ?? [] },
                sessionStore: whatsAppWebSessionStore,
                bridge: whatsAppWebBridge
            )
            await whatsAppPollingOrchestrator.refresh(provider: provider, messageLimit: 50)
            lastRefreshDescription = "Web refreshed at \(Date().formatted(date: .omitted, time: .standard))"
            return

        case .desktopAX:
            guard prepareForWhatsAppInspection() else {
                return
            }
            let provider = DesktopAXProvider(accessibility: accessibility, parser: parser, interactor: interactor)
            await whatsAppPollingOrchestrator.refresh(provider: provider, messageLimit: 10)
            lastRefreshDescription = "Desktop refreshed at \(Date().formatted(date: .omitted, time: .standard))"
            return
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
        if whatsAppIntegrationSettings.mode == .desktopAX {
            await accessibilityScheduler.enqueue(priority: .background) { [weak self] in
                guard let self else { return }
                await self.refreshConversations()
            }
        } else {
            await refreshConversations()
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
        let targetNameKey = WhatsAppParserSupport.chatNameComparisonKey(targetConversation.name)
        for attempt in 1...3 {
            let baselineSnapshot = try accessibility.captureWhatsAppSnapshot(maxDepth: 14)
            let baselineState = parser.parse(snapshot: baselineSnapshot, messageLimit: 10)

            if WhatsAppParserSupport.chatNameComparisonKey(baselineState.selectedChatName) == targetNameKey {
                return baselineSnapshot
            }

            let liveConversation = baselineState.conversations.first {
                $0.id == targetConversation.id || WhatsAppParserSupport.chatNameComparisonKey($0.name) == targetNameKey
            } ?? targetConversation

            try interactor.selectConversation(liveConversation, using: accessibility)
            try await Task.sleep(for: .milliseconds(500))

            let updatedSnapshot = try accessibility.captureWhatsAppSnapshot(maxDepth: 14)
            let updatedState = parser.parse(snapshot: updatedSnapshot, messageLimit: 10)
            if WhatsAppParserSupport.chatNameComparisonKey(updatedState.selectedChatName) == targetNameKey {
                return updatedSnapshot
            }

            appendLog("Conversation selection retry \(attempt) failed for \(targetConversation.name); current chat is \(updatedState.selectedChatName ?? "unknown").", level: .warning)
        }

        throw AccessibilityError.actionFailed(-1)
    }
}
