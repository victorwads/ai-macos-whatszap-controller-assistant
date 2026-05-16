import Foundation

struct MCPServerCallEntry: Identifiable, Sendable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let durationMilliseconds: Int

    let requestMethod: String
    let requestPath: String
    let requestHeaders: [String: String]
    let requestBody: Data

    let responseStatusCode: Int
    let responseHeaders: [String: String]
    let responseBody: Data

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        durationMilliseconds: Int,
        requestMethod: String,
        requestPath: String,
        requestHeaders: [String: String],
        requestBody: Data,
        responseStatusCode: Int,
        responseHeaders: [String: String],
        responseBody: Data
    ) {
        self.id = id
        self.timestamp = timestamp
        self.durationMilliseconds = durationMilliseconds
        self.requestMethod = requestMethod
        self.requestPath = requestPath
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.responseStatusCode = responseStatusCode
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
    }
}

extension MCPServerCallEntry {
    var mcpMethod: String? {
        guard let object = requestBodyJSONObject else { return nil }
        return object["method"] as? String
    }

    var mcpIdDescription: String? {
        guard let object = requestBodyJSONObject else { return nil }
        let id = object["id"]
        switch id {
        case let number as NSNumber:
            return number.stringValue
        case let string as String:
            return string
        default:
            return nil
        }
    }

    var mcpToolName: String? {
        guard mcpMethod == "tools/call" else { return nil }
        guard let params = requestBodyJSONObject?["params"] as? [String: Any] else { return nil }
        return params["name"] as? String
    }

    private var requestBodyJSONObject: [String: Any]? {
        guard !requestBody.isEmpty else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: requestBody) else { return nil }
        return json as? [String: Any]
    }
}
