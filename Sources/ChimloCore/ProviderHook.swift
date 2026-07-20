import Foundation

public enum ProviderHookSource: String, Codable, Sendable {
    case codex
    case claude

    public var agent: AgentKind {
        switch self {
        case .codex: .codex
        case .claude: .claude
        }
    }

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        }
    }
}

public enum ProviderHookMappingError: Error, LocalizedError, Sendable {
    case payloadTooLarge
    case malformedPayload
    case missingSessionID

    public var errorDescription: String? {
        switch self {
        case .payloadTooLarge: "Hook payload exceeds the local safety limit"
        case .malformedPayload: "Hook payload is not valid JSON"
        case .missingSessionID: "Hook payload has no session identifier"
        }
    }
}

/// Converts provider hook JSON into the deliberately small status vocabulary
/// Chimlo needs. Unknown JSON fields are never decoded, which prevents prompts,
/// transcripts, tool inputs, outputs, and file contents from entering app state.
public enum PrivacySafeHookMapper {
    public static let maximumPayloadBytes = 64 * 1024

    public static func event(
        from data: Data,
        source: ProviderHookSource,
        timestamp: Date = Date()
    ) throws -> AgentEvent? {
        guard data.count <= maximumPayloadBytes else {
            throw ProviderHookMappingError.payloadTooLarge
        }

        let input: HookInput
        do {
            input = try JSONDecoder().decode(HookInput.self, from: data)
        } catch {
            throw ProviderHookMappingError.malformedPayload
        }

        let sessionID = input.sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionID.isEmpty, sessionID.utf8.count <= 512 else {
            throw ProviderHookMappingError.missingSessionID
        }

        let projectPath = bounded(input.cwd, maximumUTF8Bytes: 4_096)
        let title = projectTitle(from: projectPath) ?? "\(source.displayName) session"
        let hookName = input.hookEventName
        let notification = input.notificationType
        let toolName = safeToolName(input.toolName)

        let mapping = map(hookName: hookName, notification: notification, toolName: toolName, source: source)
        guard let mapping else { return nil }

        return AgentEvent(
            sessionID: sessionID,
            sequence: 0,
            kind: mapping.kind,
            agent: source.agent,
            title: title,
            detail: mapping.detail,
            model: bounded(input.model, maximumUTF8Bytes: 128),
            projectPath: projectPath,
            request: mapping.request,
            timestamp: timestamp
        )
    }

    private static func map(
        hookName: String,
        notification: String?,
        toolName: String?,
        source: ProviderHookSource
    ) -> Mapping? {
        switch hookName {
        case "SessionStart":
            return Mapping(kind: .sessionStarted, detail: "Connected locally")
        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "SubagentStart":
            return Mapping(kind: .activity, detail: "Working")
        case "PermissionRequest":
            return permissionMapping(toolName: toolName, source: source)
        case "PermissionDenied":
            return Mapping(kind: .activity, detail: "Approval handled in \(source.displayName)")
        case "Stop", "SubagentStop", "TaskCompleted":
            return Mapping(kind: .completed, detail: "Turn complete")
        case "StopFailure":
            return Mapping(kind: .failed, detail: "Turn stopped")
        case "SessionEnd":
            return Mapping(kind: .sessionEnded, detail: "Session ended")
        case "Notification":
            switch notification {
            case "permission_prompt":
                return permissionMapping(toolName: toolName, source: source)
            case "agent_needs_input", "idle_prompt":
                return Mapping(
                    kind: .questionRequested,
                    detail: "Needs input in \(source.displayName)",
                    request: .question(
                        AgentQuestion(
                            id: "\(source.rawValue)-input",
                            prompt: "Continue in \(source.displayName)"
                        )
                    )
                )
            case "agent_completed":
                return Mapping(kind: .completed, detail: "Turn complete")
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private static func permissionMapping(toolName: String?, source: ProviderHookSource) -> Mapping {
        let category = toolName.map { " for \($0)" } ?? ""
        return Mapping(
            kind: .permissionRequested,
            detail: "Approval needed in \(source.displayName)",
            request: .approval(
                ApprovalRequest(
                    id: "\(source.rawValue)-permission",
                    summary: "Approval requested\(category)"
                )
            )
        )
    }

    private static func safeToolName(_ value: String?) -> String? {
        guard let value = bounded(value, maximumUTF8Bytes: 80) else { return nil }
        let allowed = value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._- ")).contains($0)
        }
        return allowed ? value : nil
    }

    private static func bounded(_ value: String?, maximumUTF8Bytes: Int) -> String? {
        guard let value, !value.isEmpty, value.utf8.count <= maximumUTF8Bytes else { return nil }
        return value
    }

    private static func projectTitle(from path: String?) -> String? {
        guard let path else { return nil }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? nil : name
    }

    private struct Mapping {
        let kind: AgentEventKind
        let detail: String
        var request: PendingRequest?
    }

    private struct HookInput: Decodable {
        let sessionID: String
        let hookEventName: String
        let cwd: String?
        let model: String?
        let notificationType: String?
        let toolName: String?

        private enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case hookEventName = "hook_event_name"
            case cwd
            case model
            case notificationType = "notification_type"
            case toolName = "tool_name"
        }
    }
}
