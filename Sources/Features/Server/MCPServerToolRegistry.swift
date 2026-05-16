import Foundation

@MainActor
enum MCPServerToolRegistry {
    static let tools: [any MCPToolHandler.Type] = [
        ListChatsTool.self,
        ListUnreadChatsTool.self,
        ListChatsBySearchTool.self,
        ListRecentMessagesTool.self,
        SendMessageTool.self,
        WaitForMessageTool.self,
        WaitNextEventTool.self,
        SpeakToClientTool.self,
        AskToClientTool.self,
        CreateMemoryTool.self,
        GetMemoryTool.self,
        GetMemoriesByTagTool.self,
        DeleteMemoryTool.self,
        CreateSubjectTool.self,
        UpdateSubjectTool.self,
        ResolveSubjectTool.self,
        ListActiveSubjectsTool.self,
        GetSubjectTool.self,
        DeleteSubjectTool.self,
        ListNicknamesTool.self,
        SaveNicknameTool.self,
        DeleteNicknameTool.self
    ]

    static var toolsByName: [String: any MCPToolHandler.Type] {
        var result: [String: any MCPToolHandler.Type] = [:]
        for tool in tools {
            result[tool.definition.name] = tool
        }
        return result
    }

    static var toolDefinitions: [MCPToolDefinition] {
        tools.map { $0.definition }
    }
}
