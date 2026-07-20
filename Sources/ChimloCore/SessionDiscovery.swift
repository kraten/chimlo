import Foundation

public enum SessionEvidenceSource: String, Codable, Equatable, Sendable {
    case codexRollout
    case claudeTranscript
    case codexAppServer
    case process
    case cache
}

public enum SessionTitleKind: Int, Codable, Comparable, Sendable {
    case workspace
    case task

    public static func < (lhs: SessionTitleKind, rhs: SessionTitleKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The local-session vocabulary shared by transcript discovery, process
/// reconciliation, persistence, and the Codex app-server adapter. Prompt and
/// response previews are transient: Chimlo's registry deliberately omits them.
public struct SessionCandidate: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let agent: AgentKind
    public var title: String
    public var titleKind: SessionTitleKind
    public var detail: String
    public var model: String?
    public var terminal: String?
    public var projectPath: String?
    public var jumpURL: URL?
    public var latestUserPrompt: String?
    public var latestAgentResponse: String?
    public var latestConversationUpdatedAt: Date?
    public var phase: SessionPhase
    public var updatedAt: Date
    public var evidence: SessionEvidenceSource

    public init(
        id: String,
        agent: AgentKind,
        title: String,
        titleKind: SessionTitleKind = .workspace,
        detail: String,
        model: String? = nil,
        terminal: String? = nil,
        projectPath: String? = nil,
        jumpURL: URL? = nil,
        latestUserPrompt: String? = nil,
        latestAgentResponse: String? = nil,
        latestConversationUpdatedAt: Date? = nil,
        phase: SessionPhase,
        updatedAt: Date,
        evidence: SessionEvidenceSource
    ) {
        self.id = id
        self.agent = agent
        self.title = title
        self.titleKind = titleKind
        self.detail = detail
        self.model = model
        self.terminal = terminal
        self.projectPath = projectPath
        self.jumpURL = jumpURL
        self.latestUserPrompt = latestUserPrompt
        self.latestAgentResponse = latestAgentResponse
        self.latestConversationUpdatedAt = latestConversationUpdatedAt
        self.phase = phase
        self.updatedAt = updatedAt
        self.evidence = evidence
    }

    private enum CodingKeys: String, CodingKey {
        case id, agent, title, titleKind, detail, model, terminal, projectPath
        case jumpURL, phase, updatedAt, evidence
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        agent = try values.decode(AgentKind.self, forKey: .agent)
        title = try values.decode(String.self, forKey: .title)
        titleKind = try values.decodeIfPresent(SessionTitleKind.self, forKey: .titleKind) ?? .workspace
        detail = try values.decode(String.self, forKey: .detail)
        model = try values.decodeIfPresent(String.self, forKey: .model)
        terminal = try values.decodeIfPresent(String.self, forKey: .terminal)
        projectPath = try values.decodeIfPresent(String.self, forKey: .projectPath)
        jumpURL = try values.decodeIfPresent(URL.self, forKey: .jumpURL)
        latestUserPrompt = nil
        latestAgentResponse = nil
        latestConversationUpdatedAt = nil
        phase = try values.decode(SessionPhase.self, forKey: .phase)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        evidence = try values.decode(SessionEvidenceSource.self, forKey: .evidence)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(agent, forKey: .agent)
        try values.encode(title, forKey: .title)
        try values.encode(titleKind, forKey: .titleKind)
        try values.encode(detail, forKey: .detail)
        try values.encodeIfPresent(model, forKey: .model)
        try values.encodeIfPresent(terminal, forKey: .terminal)
        try values.encodeIfPresent(projectPath, forKey: .projectPath)
        try values.encodeIfPresent(jumpURL, forKey: .jumpURL)
        try values.encode(phase, forKey: .phase)
        try values.encode(updatedAt, forKey: .updatedAt)
        try values.encode(evidence, forKey: .evidence)
    }
}

/// Streams provider JSONL into a bounded local-session candidate. Only the
/// visible user prompt and agent response are read; reasoning, tools, tool
/// results, environment values, and file contents remain excluded.
public struct PrivacySafeSessionMetadataScanner: Sendable {
    public enum Provider: Sendable {
        case codex
        case claude
    }

    private let provider: Provider
    private var sessionID: String?
    private var workingDirectory: String?
    private var model: String?
    private var taskTitle: String?
    private var latestUserPrompt: String?
    private var latestAgentResponse: String?
    private var latestConversationUpdatedAt: Date?
    private var phase: SessionPhase = .completed
    private var updatedAt: Date?

    public init(provider: Provider) {
        self.provider = provider
    }

    public mutating func consume(line data: Data) {
        guard data.count <= Self.maximumLineBytes else { return }

        switch provider {
        case .codex:
            consumeCodex(line: data)
        case .claude:
            consumeClaude(line: data)
        }
    }

    public func candidate(
        transcriptPath: String,
        fallbackUpdatedAt: Date
    ) -> SessionCandidate? {
        guard let sessionID = Self.bounded(sessionID, maximumUTF8Bytes: 512),
              let workingDirectory = Self.bounded(workingDirectory, maximumUTF8Bytes: 4_096) else {
            return nil
        }

        let workspace = URL(fileURLWithPath: workingDirectory).lastPathComponent
        let safeWorkspace = workspace.isEmpty ? "Workspace" : workspace
        let agent: AgentKind = provider == .codex ? .codex : .claude
        let displayName = provider == .codex ? "Codex" : "Claude"
        let evidence: SessionEvidenceSource = provider == .codex ? .codexRollout : .claudeTranscript
        let jumpURL = provider == .codex
            ? URL(string: "codex://threads/\(sessionID)")
            : nil

        let title = taskTitle ?? safeWorkspace
        return SessionCandidate(
            id: sessionID,
            agent: agent,
            title: title,
            titleKind: taskTitle == nil ? .workspace : .task,
            detail: Self.detail(for: phase, displayName: displayName),
            model: Self.bounded(model, maximumUTF8Bytes: 128),
            projectPath: workingDirectory,
            jumpURL: jumpURL,
            latestUserPrompt: latestUserPrompt,
            latestAgentResponse: latestAgentResponse,
            latestConversationUpdatedAt: latestConversationUpdatedAt,
            phase: phase,
            updatedAt: updatedAt ?? fallbackUpdatedAt,
            evidence: evidence
        )
    }

    public static let maximumLineBytes = 2 * 1_024 * 1_024

    private mutating func consumeCodex(line data: Data) {
        guard let line = try? JSONDecoder().decode(CodexLine.self, from: data) else { return }

        if line.type == "session_meta", let payload = line.payload {
            sessionID = Self.prefer(payload.id, over: sessionID, maximumUTF8Bytes: 512)
            workingDirectory = Self.prefer(payload.cwd, over: workingDirectory, maximumUTF8Bytes: 4_096)
        }
        model = Self.prefer(line.payload?.model, over: model, maximumUTF8Bytes: 128)

        let lineTimestamp = Self.parseDate(line.timestamp ?? line.payload?.timestamp)
        updatedAt = Self.latest(updatedAt, lineTimestamp)

        if line.type == "event_msg" {
            switch line.payload?.type?.lowercased() {
            case "user_message":
                if let prompt = Self.previewText(
                    line.payload?.message,
                    extractingCodexRequest: true
                ) {
                    latestUserPrompt = prompt
                    latestConversationUpdatedAt = Self.latest(
                        latestConversationUpdatedAt,
                        lineTimestamp
                    )
                }
            case "agent_message":
                if let response = Self.previewText(line.payload?.message) {
                    latestAgentResponse = response
                    latestConversationUpdatedAt = Self.latest(
                        latestConversationUpdatedAt,
                        lineTimestamp
                    )
                }
            default:
                break
            }
        }

        guard let lifecycle = line.payload?.type?.lowercased() else { return }
        if Self.runningLifecycleNames.contains(lifecycle) {
            phase = .working
        } else if Self.completedLifecycleNames.contains(lifecycle) {
            phase = .completed
        } else if Self.failedLifecycleNames.contains(lifecycle) {
            phase = .failed
        }
    }

    private mutating func consumeClaude(line data: Data) {
        guard let line = try? JSONDecoder().decode(ClaudeLine.self, from: data) else { return }
        guard line.isSidechain != true else { return }

        sessionID = Self.prefer(line.sessionID, over: sessionID, maximumUTF8Bytes: 512)
        workingDirectory = Self.prefer(line.cwd, over: workingDirectory, maximumUTF8Bytes: 4_096)
        model = Self.prefer(line.message?.model, over: model, maximumUTF8Bytes: 128)
        let lineTimestamp = Self.parseDate(line.timestamp)
        updatedAt = Self.latest(updatedAt, lineTimestamp)

        switch line.type?.lowercased() {
        case "ai-title":
            taskTitle = Self.previewText(line.aiTitle) ?? taskTitle
        case "last-prompt":
            if let prompt = Self.previewText(line.lastPrompt) {
                latestUserPrompt = prompt
                latestConversationUpdatedAt = Self.latest(
                    latestConversationUpdatedAt,
                    lineTimestamp
                )
            }
        case "user":
            if line.message?.role == "user",
               let prompt = Self.previewText(line.message?.content?.visibleText) {
                latestUserPrompt = prompt
                latestConversationUpdatedAt = Self.latest(
                    latestConversationUpdatedAt,
                    lineTimestamp
                )
            }
            phase = .working
        case "assistant":
            if line.message?.role == "assistant",
               let response = Self.previewText(line.message?.content?.visibleText) {
                latestAgentResponse = response
                latestConversationUpdatedAt = Self.latest(
                    latestConversationUpdatedAt,
                    lineTimestamp
                )
            }
            phase = .working
        case "progress":
            phase = .working
        case "result", "summary":
            phase = .completed
        case "error":
            phase = .failed
        default:
            break
        }
    }

    private static let runningLifecycleNames: Set<String> = [
        "task_started", "turn_started", "turn_start", "task_start",
    ]
    private static let completedLifecycleNames: Set<String> = [
        "task_complete", "task_completed", "turn_complete", "turn_completed",
    ]
    private static let failedLifecycleNames: Set<String> = [
        "task_failed", "turn_failed", "turn_aborted", "error",
    ]

    private static func latest(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): max(lhs, rhs)
        case let (lhs?, nil): lhs
        case let (nil, rhs?): rhs
        case (nil, nil): nil
        }
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func detail(for phase: SessionPhase, displayName: String) -> String {
        switch phase {
        case .working: "\(displayName) is working"
        case .waitingForApproval: "Approval needed in \(displayName)"
        case .waitingForAnswer: "Input needed in \(displayName)"
        case .completed: "\(displayName) turn complete"
        case .failed: "\(displayName) turn stopped"
        }
    }

    private static func prefer(
        _ candidate: String?,
        over existing: String?,
        maximumUTF8Bytes: Int
    ) -> String? {
        bounded(candidate, maximumUTF8Bytes: maximumUTF8Bytes) ?? existing
    }

    private static func bounded(_ value: String?, maximumUTF8Bytes: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= maximumUTF8Bytes else { return nil }
        return trimmed
    }

    private static func previewText(
        _ value: String?,
        extractingCodexRequest: Bool = false
    ) -> String? {
        guard var value else { return nil }
        if extractingCodexRequest {
            for marker in ["## My request for Codex:", "# My request for Codex:"] {
                guard let range = value.range(of: marker) else { continue }
                value = String(value[range.upperBound...])
                break
            }
        }

        let normalized = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else { return nil }
        let maximumCharacters = 2_000
        guard normalized.count > maximumCharacters else { return normalized }
        return String(normalized.prefix(maximumCharacters)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private struct CodexLine: Decodable {
        let type: String?
        let timestamp: String?
        let payload: Payload?

        struct Payload: Decodable {
            let id: String?
            let cwd: String?
            let model: String?
            let timestamp: String?
            let type: String?
            let message: String?
        }
    }

    private struct ClaudeLine: Decodable {
        let sessionID: String?
        let cwd: String?
        let timestamp: String?
        let type: String?
        let message: Message?
        let aiTitle: String?
        let lastPrompt: String?
        let isSidechain: Bool?

        struct Message: Decodable {
            let model: String?
            let role: String?
            let content: Content?
        }

        enum Content: Decodable {
            case text(String)
            case blocks([Block])

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let text = try? container.decode(String.self) {
                    self = .text(text)
                } else {
                    self = .blocks(try container.decode([Block].self))
                }
            }

            var visibleText: String? {
                switch self {
                case let .text(text):
                    text
                case let .blocks(blocks):
                    blocks
                        .filter { $0.type == "text" }
                        .compactMap(\.text)
                        .joined(separator: "\n")
                }
            }
        }

        struct Block: Decodable {
            let type: String?
            let text: String?
        }

        private enum CodingKeys: String, CodingKey {
            case sessionID = "sessionId"
            case cwd
            case timestamp
            case type
            case message
            case aiTitle
            case lastPrompt
            case isSidechain
        }
    }
}
