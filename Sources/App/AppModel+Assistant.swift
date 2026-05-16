import Combine
import Foundation

extension AppModel {
    static let defaultAssistantInstructions = """
    You can control WhatsApp through the MCP tools:

    - list_chats: List the available WhatsApp conversations.
    - list_unread_chats: List only the conversations with unread messages.
    - get_recent_messages: Load the most recent messages from a specific chat.
    - send_message: Send a message to a specific WhatsApp chat.
    - wait_next_event / wait_for_message: Wait for the next incoming event or message and return any new messages received.
    - list_nicknames / save_nickname / delete_nickname: Manage nicknames for chats (e.g. “mom”, “partner”, “Leo”).

    Use Subjects to track multi-day operational threads:

    - create_subject / update_subject / finish_subject: Create and manage an operational subject until resolution.
    - list_active_subjects / get_subject / delete_subject: List, fetch, and delete subjects.

    Use Memories to store long-term useful context:

    - create_memory / get_memory / list_memories_by_tag / delete_memory: Manage memories using snake_case keys.
    - Use get_memory for exact key lookups and list_memories_by_tag to group related context.

    If you need to notify or interact with the client, use:

    - speak_to_client: Announce something out loud to inform the client about important events, updates, or responses.
    - ask_to_client: Ask the client a question out loud and wait for their response before continuing.

    Use get_instructions to fetch the latest instructions currently stored in the app UI.

    When using speak_to_client or ask_to_client, write the text with clear punctuation and spacing (short sentences, commas, and periods) so the speech synthesizer reads it naturally and accurately.
    """

    func loadAssistantInstructions() {
        assistantInstructions = AssistantInstructionsRepository.shared.load(defaultValue: Self.defaultAssistantInstructions)
        bindAssistantInstructionsPersistence()
    }

    private func bindAssistantInstructionsPersistence() {
        $assistantInstructions
            .dropFirst()
            .sink { [weak self] value in
                guard let self else { return }
                AssistantInstructionsRepository.shared.save(value)
            }
            .store(in: &cancellables)
    }
}
