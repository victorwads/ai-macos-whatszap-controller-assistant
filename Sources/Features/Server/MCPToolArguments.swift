import Foundation

struct MCPToolArguments {
    let values: [String: JSONValue]

    func value(for keys: [String]) -> JSONValue? {
        for key in keys {
            if let value = values[key] {
                return value
            }
        }
        return nil
    }

    func value(for keys: String...) -> JSONValue? {
        value(for: keys)
    }

    func string(for keys: String...) -> String? {
        value(for: keys)?.stringValue
    }

    func int(for keys: String...) -> Int? {
        value(for: keys)?.intValue
    }

    func number(for keys: String...) -> Double? {
        value(for: keys)?.numberValue
    }

    func stringArray(for keys: String...) -> [String]? {
        guard let values = value(for: keys)?.arrayValue else {
            return nil
        }
        return values.compactMap(\.stringValue)
    }

    func uuid(for keys: String...) -> UUID? {
        guard let raw = value(for: keys)?.stringValue, !raw.isEmpty else { return nil }
        return UUID(uuidString: raw)
    }

    func requiredString(_ name: String) throws -> String {
        guard let value = string(for: name), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPServerError.missingParameter(name)
        }
        return value
    }

    func requiredUUID(_ name: String) throws -> UUID {
        guard let value = uuid(for: name) else {
            throw MCPServerError.invalidParameter(name)
        }
        return value
    }
}
