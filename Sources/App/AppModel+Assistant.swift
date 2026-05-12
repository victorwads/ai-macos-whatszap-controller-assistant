import Combine
import Foundation

extension AppModel {
    static let defaultAssistantInstructions = """
    You can control WhatsApp through the MCP tools:

    - list_chats: List the available WhatsApp conversations.
    - get_recent_messages: Load the most recent messages from a specific chat.
    - send_message: Send a message to a specific WhatsApp chat.
    - wait_for_message: Wait for the next incoming message(s) and return any new messages received.

    If you need to notify or interact with the user, use:

    - speak: Announce something out loud to inform the user about important events, updates, or responses.
    - ask_user: Ask the user a question out loud and wait for their spoken response before continuing.

    Use get_instructions to fetch the latest instructions currently stored in the app UI.

    When using speak or ask_user, write the text with clear punctuation and spacing (short sentences, commas, and periods) so the speech synthesizer reads it naturally and accurately.
    """

    func loadAssistantInstructions() {
        assistantInstructions = UserDefaults.standard.string(forKey: assistantInstructionsDefaultsKey) ?? Self.defaultAssistantInstructions
        bindAssistantInstructionsPersistence()
    }

    private func bindAssistantInstructionsPersistence() {
        $assistantInstructions
            .dropFirst()
            .sink { [weak self] value in
                guard let self else { return }
                UserDefaults.standard.set(value, forKey: self.assistantInstructionsDefaultsKey)
            }
            .store(in: &cancellables)
    }
}
