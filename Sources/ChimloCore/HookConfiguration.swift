import Foundation

public enum CodexHookConfigurationError: Error, LocalizedError, Sendable {
    case malformedRoot
    case malformedHooks
    case malformedEvent(String)

    public var errorDescription: String? {
        switch self {
        case .malformedRoot:
            "Codex hooks must be a JSON object"
        case .malformedHooks:
            "The Codex hooks field must be a JSON object"
        case let .malformedEvent(event):
            "The Codex \(event) hook must be a JSON array"
        }
    }
}

public enum CodexHookInstallationState: Equatable, Sendable {
    case missing
    case current
    case needsRepair
}

public struct CodexHookConfigurationPlan: Equatable, Sendable {
    public let data: Data
    public let changed: Bool

    public init(data: Data, changed: Bool) {
        self.data = data
        self.changed = changed
    }
}

/// Creates a marker-scoped merge for Codex's documented command hooks. Unknown
/// top-level fields, events, matchers, and observers survive round-tripping.
public enum CodexHookConfiguration {
    public static let marker = "# chimlo-codex-observer"
    public static let observedEvents = [
        "SessionStart",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "PermissionRequest",
        "Stop",
        "SubagentStop",
    ]

    public static func observerCommand(helperPath: String) -> String {
        "\(shellQuoted(helperPath)) hook codex observe \(marker)"
    }

    public static func installationState(
        in data: Data?,
        helperPath: String
    ) throws -> CodexHookInstallationState {
        guard let data, !data.isEmpty else { return .missing }
        let root = try decodeRoot(data)
        guard let hooks = root["hooks"] else { return .missing }
        guard let hooks = hooks as? [String: Any] else {
            throw CodexHookConfigurationError.malformedHooks
        }

        let expectedCommand = observerCommand(helperPath: helperPath)
        var foundMarkedObserver = false
        var allEventsAreCurrent = true

        for event in observedEvents {
            guard let rawEntries = hooks[event] else {
                allEventsAreCurrent = false
                continue
            }
            guard let entries = rawEntries as? [[String: Any]] else {
                throw CodexHookConfigurationError.malformedEvent(event)
            }
            let commands = observerCommands(in: entries)
            foundMarkedObserver = foundMarkedObserver || commands.contains(where: { $0.contains(marker) })
            if !commands.contains(expectedCommand) { allEventsAreCurrent = false }
        }

        if allEventsAreCurrent { return .current }
        return foundMarkedObserver ? .needsRepair : .missing
    }

    public static func merging(
        existingData: Data?,
        helperPath: String
    ) throws -> CodexHookConfigurationPlan {
        var root = try existingData.flatMap { $0.isEmpty ? nil : try decodeRoot($0) } ?? [:]
        var hooks: [String: Any]
        if let existingHooks = root["hooks"] {
            guard let decodedHooks = existingHooks as? [String: Any] else {
                throw CodexHookConfigurationError.malformedHooks
            }
            hooks = decodedHooks
        } else {
            hooks = [:]
        }

        let command = observerCommand(helperPath: helperPath)
        var changed = false
        for event in observedEvents {
            var entries: [[String: Any]]
            if let rawEntries = hooks[event] {
                guard let decodedEntries = rawEntries as? [[String: Any]] else {
                    throw CodexHookConfigurationError.malformedEvent(event)
                }
                entries = decodedEntries
            } else {
                entries = []
            }

            let markedCommands = observerCommands(in: entries).filter { $0.contains(marker) }
            if markedCommands != [command] {
                entries = removingMarkedObservers(from: entries)
                var registration: [String: Any] = [
                    "hooks": [[
                        "type": "command",
                        "command": command,
                        "timeout": 2,
                    ]],
                ]
                if event == "SessionStart" {
                    registration["matcher"] = "startup|resume|clear|compact"
                }
                entries.append(registration)
                changed = true
            }
            hooks[event] = entries
        }

        root["hooks"] = hooks
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        return CodexHookConfigurationPlan(data: data + Data("\n".utf8), changed: changed)
    }

    public static func removing(existingData: Data) throws -> CodexHookConfigurationPlan {
        var root = try decodeRoot(existingData)
        guard let rawHooks = root["hooks"] else {
            return CodexHookConfigurationPlan(data: existingData, changed: false)
        }
        guard var hooks = rawHooks as? [String: Any] else {
            throw CodexHookConfigurationError.malformedHooks
        }

        var changed = false
        for (event, rawEntries) in hooks {
            guard let entries = rawEntries as? [[String: Any]] else { continue }
            let filtered = removingMarkedObservers(from: entries)
            if filtered.count != entries.count || observerCommands(in: filtered) != observerCommands(in: entries) {
                changed = true
                if filtered.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = filtered
                }
            }
        }
        guard changed else {
            return CodexHookConfigurationPlan(data: existingData, changed: false)
        }

        root["hooks"] = hooks
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        return CodexHookConfigurationPlan(data: data + Data("\n".utf8), changed: true)
    }

    private static func decodeRoot(_ data: Data) throws -> [String: Any] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CodexHookConfigurationError.malformedRoot
        }
        guard let root = object as? [String: Any] else {
            throw CodexHookConfigurationError.malformedRoot
        }
        return root
    }

    private static func observerCommands(in entries: [[String: Any]]) -> [String] {
        entries.flatMap { entry in
            (entry["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
        }
    }

    private static func removingMarkedObservers(from entries: [[String: Any]]) -> [[String: Any]] {
        entries.compactMap { entry in
            guard let observers = entry["hooks"] as? [[String: Any]] else { return entry }
            let retained = observers.filter { observer in
                guard let command = observer["command"] as? String else { return true }
                return !command.contains(marker)
            }
            guard !retained.isEmpty else { return nil }
            var copy = entry
            copy["hooks"] = retained
            return copy
        }
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

public enum ClaudeHookConfigurationError: Error, LocalizedError, Sendable {
    case malformedRoot
    case malformedHooks
    case malformedEvent(String)

    public var errorDescription: String? {
        switch self {
        case .malformedRoot:
            "Claude settings must be a JSON object"
        case .malformedHooks:
            "The Claude hooks field must be a JSON object"
        case let .malformedEvent(event):
            "The Claude \(event) hook must be a JSON array"
        }
    }
}

public enum ClaudeHookInstallationState: Equatable, Sendable {
    case missing
    case current
    case needsRepair
}

public struct ClaudeHookConfigurationPlan: Equatable, Sendable {
    public let data: Data
    public let changed: Bool

    public init(data: Data, changed: Bool) {
        self.data = data
        self.changed = changed
    }
}

/// Marker-scoped installation for Claude Code command hooks. Existing settings,
/// hook groups, and user-authored commands are preserved exactly at the JSON
/// value level.
public enum ClaudeHookConfiguration {
    public static let marker = "# chimlo-claude-observer"
    public static let questionMarker = "# chimlo-claude-question"
    public static let permissionMarker = "# chimlo-claude-permission"

    private struct EventSpec {
        let name: String
        let matcher: String?
        let asynchronous: Bool
    }

    private static let eventSpecs = [
        EventSpec(name: "SessionStart", matcher: "startup|resume|clear|compact", asynchronous: true),
        EventSpec(name: "UserPromptSubmit", matcher: nil, asynchronous: true),
        EventSpec(name: "PreToolUse", matcher: "*", asynchronous: true),
        EventSpec(name: "PostToolUse", matcher: "*", asynchronous: true),
        EventSpec(name: "Notification", matcher: "permission_prompt|agent_needs_input|agent_completed|idle_prompt", asynchronous: true),
        EventSpec(name: "Stop", matcher: nil, asynchronous: true),
        EventSpec(name: "StopFailure", matcher: nil, asynchronous: true),
        EventSpec(name: "SessionEnd", matcher: nil, asynchronous: false),
    ]

    public static var observedEvents: [String] { eventSpecs.map(\.name) }

    public static func observerCommand(helperPath: String) -> String {
        "\(shellQuoted(helperPath)) hook claude observe \(marker)"
    }

    public static func questionCommand(helperPath: String) -> String {
        "\(shellQuoted(helperPath)) hook claude question \(questionMarker)"
    }

    public static func permissionCommand(helperPath: String) -> String {
        "\(shellQuoted(helperPath)) hook claude permission \(permissionMarker)"
    }

    public static func installationState(
        in data: Data?,
        helperPath: String
    ) throws -> ClaudeHookInstallationState {
        guard let data, !data.isEmpty else { return .missing }
        let root = try decodeRoot(data)
        guard let hooksValue = root["hooks"] else { return .missing }
        guard let hooks = hooksValue as? [String: Any] else {
            throw ClaudeHookConfigurationError.malformedHooks
        }

        let expected = observerCommand(helperPath: helperPath)
        let expectedQuestion = questionCommand(helperPath: helperPath)
        let expectedPermission = permissionCommand(helperPath: helperPath)
        var foundManaged = false
        var allCurrent = true
        for spec in eventSpecs {
            guard let value = hooks[spec.name] else {
                allCurrent = false
                continue
            }
            guard let groups = value as? [[String: Any]] else {
                throw ClaudeHookConfigurationError.malformedEvent(spec.name)
            }
            let commands = observerCommands(in: groups)
            foundManaged = foundManaged || commands.contains(where: isManagedCommand)
            if !commands.contains(expected) { allCurrent = false }
        }

        if let value = hooks["PreToolUse"] as? [[String: Any]] {
            let commands = observerCommands(in: value)
            foundManaged = foundManaged || commands.contains(where: isManagedCommand)
            if !hasCurrentQuestionRegistration(in: value, expectedCommand: expectedQuestion) {
                allCurrent = false
            }
        } else {
            allCurrent = false
        }

        if let value = hooks["PermissionRequest"] as? [[String: Any]] {
            let commands = observerCommands(in: value)
            foundManaged = foundManaged || commands.contains(where: isManagedCommand)
            if commands.contains(where: { $0.contains(marker) })
                || !hasCurrentPermissionRegistration(
                    in: value,
                    expectedCommand: expectedPermission
                ) {
                allCurrent = false
            }
        } else {
            allCurrent = false
        }

        if allCurrent { return .current }
        return foundManaged ? .needsRepair : .missing
    }

    public static func merging(
        existingData: Data?,
        helperPath: String
    ) throws -> ClaudeHookConfigurationPlan {
        var root = try existingData.flatMap { $0.isEmpty ? nil : try decodeRoot($0) } ?? [:]
        var hooks: [String: Any]
        if let value = root["hooks"] {
            guard let existing = value as? [String: Any] else {
                throw ClaudeHookConfigurationError.malformedHooks
            }
            hooks = existing
        } else {
            hooks = [:]
        }

        let command = observerCommand(helperPath: helperPath)
        let questionObserverCommand = questionCommand(helperPath: helperPath)
        let permissionObserverCommand = permissionCommand(helperPath: helperPath)
        var changed = false
        for spec in eventSpecs {
            var groups: [[String: Any]]
            if let value = hooks[spec.name] {
                guard let existing = value as? [[String: Any]] else {
                    throw ClaudeHookConfigurationError.malformedEvent(spec.name)
                }
                groups = existing
            } else {
                groups = []
            }

            let markedCommands = observerCommands(in: groups).filter { $0.contains(marker) }
            guard markedCommands != [command] else { continue }
            groups = removingMarkedObservers(from: groups)
            var observer: [String: Any] = [
                "type": "command",
                "command": command,
                "timeout": 2,
            ]
            if spec.asynchronous { observer["async"] = true }
            var group: [String: Any] = ["hooks": [observer]]
            if let matcher = spec.matcher { group["matcher"] = matcher }
            groups.append(group)
            hooks[spec.name] = groups
            changed = true
        }


        var preToolGroups: [[String: Any]]
        if let value = hooks["PreToolUse"] {
            guard let existing = value as? [[String: Any]] else {
                throw ClaudeHookConfigurationError.malformedEvent("PreToolUse")
            }
            preToolGroups = existing
        } else {
            preToolGroups = []
        }
        if !hasCurrentQuestionRegistration(
            in: preToolGroups,
            expectedCommand: questionObserverCommand
        ) {
            preToolGroups = removingManagedCommands(
                from: preToolGroups,
                matching: questionMarker
            )
            preToolGroups.append([
                "matcher": "AskUserQuestion",
                "hooks": [[
                    "type": "command",
                    "command": questionObserverCommand,
                    "timeout": 600,
                ]],
            ])
            hooks["PreToolUse"] = preToolGroups
            changed = true
        }

        var permissionGroups: [[String: Any]]
        if let value = hooks["PermissionRequest"] {
            guard let existing = value as? [[String: Any]] else {
                throw ClaudeHookConfigurationError.malformedEvent("PermissionRequest")
            }
            permissionGroups = existing
        } else {
            permissionGroups = []
        }

        // Older Chimlo builds observed PermissionRequest asynchronously. The
        // blocking bridge owns this event now, so remove only that marked
        // observer before installing the exact replacement.
        let withoutLegacyObserver = removingManagedCommands(
            from: permissionGroups,
            matching: marker
        )
        if observerCommands(in: withoutLegacyObserver) != observerCommands(in: permissionGroups) {
            permissionGroups = withoutLegacyObserver
            changed = true
        }
        if !hasCurrentPermissionRegistration(
            in: permissionGroups,
            expectedCommand: permissionObserverCommand
        ) {
            permissionGroups = removingManagedCommands(
                from: permissionGroups,
                matching: permissionMarker
            )
            permissionGroups.append([
                "matcher": "*",
                "hooks": [[
                    "type": "command",
                    "command": permissionObserverCommand,
                    "timeout": 600,
                ]],
            ])
            changed = true
        }
        hooks["PermissionRequest"] = permissionGroups

        root["hooks"] = hooks
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        return ClaudeHookConfigurationPlan(data: data + Data("\n".utf8), changed: changed)
    }

    public static func removing(existingData: Data) throws -> ClaudeHookConfigurationPlan {
        var root = try decodeRoot(existingData)
        guard let value = root["hooks"] else {
            return ClaudeHookConfigurationPlan(data: existingData, changed: false)
        }
        guard var hooks = value as? [String: Any] else {
            throw ClaudeHookConfigurationError.malformedHooks
        }

        var changed = false
        for (name, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let cleaned = removingManagedCommands(from: groups, matching: marker)
            let fullyCleaned = removingManagedCommands(from: cleaned, matching: questionMarker)
            let allCleaned = removingManagedCommands(from: fullyCleaned, matching: permissionMarker)
            if observerCommands(in: allCleaned) != observerCommands(in: groups) {
                if allCleaned.isEmpty {
                    hooks.removeValue(forKey: name)
                } else {
                    hooks[name] = allCleaned
                }
                changed = true
            }
        }
        guard changed else {
            return ClaudeHookConfigurationPlan(data: existingData, changed: false)
        }

        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        return ClaudeHookConfigurationPlan(data: data + Data("\n".utf8), changed: true)
    }

    private static func decodeRoot(_ data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            throw ClaudeHookConfigurationError.malformedRoot
        }
        return root
    }

    private static func observerCommands(in groups: [[String: Any]]) -> [String] {
        groups.flatMap { group in
            (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
        }
    }

    private static func removingMarkedObservers(from groups: [[String: Any]]) -> [[String: Any]] {
        removingManagedCommands(from: groups, matching: marker)
    }

    private static func removingManagedCommands(
        from groups: [[String: Any]],
        matching marker: String
    ) -> [[String: Any]] {
        groups.compactMap { group in
            guard let observers = group["hooks"] as? [[String: Any]] else { return group }
            let retained = observers.filter { observer in
                guard let command = observer["command"] as? String else { return true }
                return !command.contains(marker)
            }
            guard !retained.isEmpty else { return nil }
            var copy = group
            copy["hooks"] = retained
            return copy
        }
    }

    private static func isManagedCommand(_ command: String) -> Bool {
        command.contains(marker)
            || command.contains(questionMarker)
            || command.contains(permissionMarker)
    }

    private static func hasCurrentQuestionRegistration(
        in groups: [[String: Any]],
        expectedCommand: String
    ) -> Bool {
        let registrations = groups.flatMap { group -> [(String?, [String: Any])] in
            let matcher = group["matcher"] as? String
            return (group["hooks"] as? [[String: Any]] ?? []).compactMap { hook in
                guard let command = hook["command"] as? String,
                      command.contains(questionMarker) else { return nil }
                return (matcher, hook)
            }
        }
        guard registrations.count == 1,
              let registration = registrations.first else { return false }
        let timeout = registration.1["timeout"] as? NSNumber
        return registration.0 == "AskUserQuestion"
            && registration.1["type"] as? String == "command"
            && registration.1["command"] as? String == expectedCommand
            && registration.1["async"] == nil
            && timeout?.intValue == 600
    }

    private static func hasCurrentPermissionRegistration(
        in groups: [[String: Any]],
        expectedCommand: String
    ) -> Bool {
        let registrations = groups.flatMap { group -> [(String?, [String: Any])] in
            let matcher = group["matcher"] as? String
            return (group["hooks"] as? [[String: Any]] ?? []).compactMap { hook in
                guard let command = hook["command"] as? String,
                      command.contains(permissionMarker) else { return nil }
                return (matcher, hook)
            }
        }
        guard registrations.count == 1,
              let registration = registrations.first else { return false }
        let timeout = registration.1["timeout"] as? NSNumber
        return registration.0 == "*"
            && registration.1["type"] as? String == "command"
            && registration.1["command"] as? String == expectedCommand
            && registration.1["async"] == nil
            && timeout?.intValue == 600
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
