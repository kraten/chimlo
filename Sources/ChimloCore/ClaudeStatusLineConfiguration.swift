import Foundation

public enum ClaudeStatusLineConfigurationError: Error, LocalizedError, Sendable {
    case malformedRoot
    case malformedStatusLine

    public var errorDescription: String? {
        switch self {
        case .malformedRoot:
            "Claude settings must be a JSON object"
        case .malformedStatusLine:
            "Claude's existing statusLine setting must be a command object"
        }
    }
}

public enum ClaudeStatusLineInstallationState: Equatable, Sendable {
    case missing
    case current
    case needsRepair
}

public struct ClaudeStatusLineConfigurationPlan: Equatable, Sendable {
    public let data: Data
    public let changed: Bool

    public init(data: Data, changed: Bool) {
        self.data = data
        self.changed = changed
    }
}

/// Marker-scoped configuration for Chimlo's capacity-only Claude status-line
/// bridge. The original status-line object is retained verbatim at the JSON
/// value level and restored on removal.
public enum ClaudeStatusLineConfiguration {
    public static let managedKey = "_chimloStatusLineManaged"
    public static let originalKey = "_chimloOriginalStatusLine"

    public static func installationState(
        in data: Data?,
        wrapperPath: String
    ) throws -> ClaudeStatusLineInstallationState {
        guard let data, !data.isEmpty else { return .missing }
        let root = try decodeRoot(data)
        guard root[managedKey] as? Bool == true else { return .missing }
        guard let statusLine = root["statusLine"] as? [String: Any],
              statusLine["type"] as? String == "command",
              statusLine["command"] as? String == wrapperPath else {
            return .needsRepair
        }
        return .current
    }

    public static func merging(
        existingData: Data?,
        wrapperPath: String
    ) throws -> ClaudeStatusLineConfigurationPlan {
        var root = try existingData.flatMap { $0.isEmpty ? nil : try decodeRoot($0) } ?? [:]
        let wasManaged = root[managedKey] as? Bool == true

        if !wasManaged, let existingStatusLine = root["statusLine"] {
            guard let object = existingStatusLine as? [String: Any],
                  object["type"] as? String == "command",
                  object["command"] is String else {
                throw ClaudeStatusLineConfigurationError.malformedStatusLine
            }
            root[originalKey] = object
        }

        var managed = (root[originalKey] as? [String: Any]) ?? [:]
        managed["type"] = "command"
        managed["command"] = wrapperPath
        root["statusLine"] = managed
        root[managedKey] = true

        let data = try encode(root)
        return ClaudeStatusLineConfigurationPlan(
            data: data,
            changed: data != existingData
        )
    }

    public static func removing(existingData: Data) throws -> ClaudeStatusLineConfigurationPlan {
        var root = try decodeRoot(existingData)
        guard root[managedKey] as? Bool == true else {
            return ClaudeStatusLineConfigurationPlan(data: existingData, changed: false)
        }

        if let original = root[originalKey] {
            root["statusLine"] = original
        } else {
            root.removeValue(forKey: "statusLine")
        }
        root.removeValue(forKey: originalKey)
        root.removeValue(forKey: managedKey)
        return ClaudeStatusLineConfigurationPlan(data: try encode(root), changed: true)
    }

    public static func originalCommand(in data: Data) throws -> String? {
        let root = try decodeRoot(data)
        guard root[managedKey] as? Bool == true,
              let original = root[originalKey] as? [String: Any] else {
            return nil
        }
        return original["command"] as? String
    }

    private static func decodeRoot(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeStatusLineConfigurationError.malformedRoot
        }
        return object
    }

    private static func encode(_ root: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(root) else {
            throw ClaudeStatusLineConfigurationError.malformedRoot
        }
        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        ) + Data("\n".utf8)
    }
}
