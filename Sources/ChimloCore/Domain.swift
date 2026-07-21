import Foundation

public enum AgentKind: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case gemini
    case cursor
    case openCode = "opencode"
    case hermes
    case other
}

public enum AgentEventKind: String, Codable, Sendable {
    case sessionStarted
    case activity
    case permissionRequested
    case permissionResolved
    case questionRequested
    case questionResolved
    case completed
    case failed
    case sessionEnded
}

public enum SessionPhase: String, Codable, Sendable {
    case working
    case waitingForApproval
    case waitingForAnswer
    case completed
    case failed
}

public enum UserDecision: Codable, Equatable, Sendable {
    case allow
    case deny
    case answer(String)
}

public struct ApprovalRequest: Codable, Equatable, Sendable {
    public let id: String
    public let summary: String
    public let detail: String?
    public let expiresAt: Date?

    public init(id: String, summary: String, detail: String? = nil, expiresAt: Date? = nil) {
        self.id = id
        self.summary = summary
        self.detail = detail
        self.expiresAt = expiresAt
    }
}

public struct AgentQuestion: Codable, Equatable, Sendable {
    public let id: String
    public let prompt: String
    public let options: [String]
    public let allowsFreeText: Bool
    public let expiresAt: Date?

    public init(
        id: String,
        prompt: String,
        options: [String] = [],
        allowsFreeText: Bool = false,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.options = options
        self.allowsFreeText = allowsFreeText
        self.expiresAt = expiresAt
    }
}

/// A provider-authored choice shown transiently while the provider is blocked
/// for input. Question content is intentionally excluded from Chimlo's session
/// archive and local registry.
public struct ProviderQuestionOption: Codable, Equatable, Sendable {
    public let label: String
    public let detail: String?

    public init(label: String, detail: String? = nil) {
        self.label = label
        self.detail = detail
    }
}

public struct ProviderQuestion: Codable, Equatable, Sendable {
    public let prompt: String
    public let header: String?
    public let options: [ProviderQuestionOption]
    public let allowsMultipleSelections: Bool

    public init(
        prompt: String,
        header: String? = nil,
        options: [ProviderQuestionOption],
        allowsMultipleSelections: Bool = false
    ) {
        self.prompt = prompt
        self.header = header
        self.options = options
        self.allowsMultipleSelections = allowsMultipleSelections
    }
}

public struct ProviderQuestionRequest: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let sessionID: String
    public let agent: AgentKind
    public let title: String
    public let questions: [ProviderQuestion]
    public let expiresAt: Date?

    public init(
        id: UUID = UUID(),
        sessionID: String,
        agent: AgentKind,
        title: String,
        questions: [ProviderQuestion],
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.agent = agent
        self.title = title
        self.questions = questions
        self.expiresAt = expiresAt
    }
}

public enum ProviderQuestionOutcome: String, Codable, Equatable, Sendable {
    case answered
    case cancelled
    case unavailable
}

public struct ProviderQuestionResponse: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let outcome: ProviderQuestionOutcome
    public let answers: [String: String]
    public let note: String?
    public let resolvedAt: Date

    public init(
        requestID: UUID,
        outcome: ProviderQuestionOutcome,
        answers: [String: String] = [:],
        note: String? = nil,
        resolvedAt: Date = Date()
    ) {
        self.requestID = requestID
        self.outcome = outcome
        self.answers = answers
        self.note = note
        self.resolvedAt = resolvedAt
    }

    public static func unavailable(for requestID: UUID, reason: String? = nil) -> Self {
        Self(requestID: requestID, outcome: .unavailable, note: reason)
    }
}

/// A provider-authored tool permission shown only while the provider is
/// blocked. The action preview is transient and is never added to Chimlo's
/// archived session model.
public struct ProviderPermissionRequest: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let sessionID: String
    public let agent: AgentKind
    public let title: String
    public let toolName: String
    public let prompt: String
    public let detail: String?
    public let preview: String?
    public let allowsSessionApproval: Bool
    public let expiresAt: Date?

    public init(
        id: UUID = UUID(),
        sessionID: String,
        agent: AgentKind,
        title: String,
        toolName: String,
        prompt: String,
        detail: String? = nil,
        preview: String? = nil,
        allowsSessionApproval: Bool = false,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.agent = agent
        self.title = title
        self.toolName = toolName
        self.prompt = prompt
        self.detail = detail
        self.preview = preview
        self.allowsSessionApproval = allowsSessionApproval
        self.expiresAt = expiresAt
    }
}

public enum ProviderPermissionOutcome: String, Codable, Equatable, Sendable {
    case allowedOnce
    case allowedForSession
    case denied
    case cancelled
    case unavailable

    public var grantsPermission: Bool {
        self == .allowedOnce || self == .allowedForSession
    }
}

public struct ProviderPermissionResponse: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let outcome: ProviderPermissionOutcome
    public let note: String?
    public let resolvedAt: Date

    public init(
        requestID: UUID,
        outcome: ProviderPermissionOutcome,
        note: String? = nil,
        resolvedAt: Date = Date()
    ) {
        self.requestID = requestID
        self.outcome = outcome
        self.note = note
        self.resolvedAt = resolvedAt
    }

    public static func unavailable(for requestID: UUID, reason: String? = nil) -> Self {
        Self(requestID: requestID, outcome: .unavailable, note: reason)
    }
}

public enum PendingRequest: Codable, Equatable, Sendable {
    case approval(ApprovalRequest)
    case question(AgentQuestion)

    public var id: String {
        switch self {
        case let .approval(request): request.id
        case let .question(question): question.id
        }
    }
}

public struct AgentEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let sessionID: String
    public let sequence: Int
    public let kind: AgentEventKind
    public let agent: AgentKind
    public let title: String?
    public let detail: String?
    public let model: String?
    public let terminal: String?
    public let projectPath: String?
    public let jumpURL: URL?
    public let request: PendingRequest?
    public let decision: UserDecision?
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        sessionID: String,
        sequence: Int,
        kind: AgentEventKind,
        agent: AgentKind,
        title: String? = nil,
        detail: String? = nil,
        model: String? = nil,
        terminal: String? = nil,
        projectPath: String? = nil,
        jumpURL: URL? = nil,
        request: PendingRequest? = nil,
        decision: UserDecision? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.sequence = sequence
        self.kind = kind
        self.agent = agent
        self.title = title
        self.detail = detail
        self.model = model
        self.terminal = terminal
        self.projectPath = projectPath
        self.jumpURL = jumpURL
        self.request = request
        self.decision = decision
        self.timestamp = timestamp
    }
}

public struct AgentSession: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public var agent: AgentKind
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
    public var pendingRequest: PendingRequest?
    public var startedAt: Date
    public var updatedAt: Date
    public var lastSequence: Int

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
        phase: SessionPhase = .working,
        pendingRequest: PendingRequest? = nil,
        startedAt: Date,
        updatedAt: Date,
        lastSequence: Int
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
        self.pendingRequest = pendingRequest
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.lastSequence = lastSequence
    }
}
