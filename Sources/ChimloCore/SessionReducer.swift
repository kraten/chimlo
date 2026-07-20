import Foundation

public enum ReductionResult: Equatable, Sendable {
    case applied(AgentSession)
    case ignoredDuplicate
    case ignoredStale
    case ignoredMissingSession
}

public struct SessionReducer: Sendable {
    public private(set) var sessions: [String: AgentSession]
    public private(set) var seenMessageIDs: Set<UUID>

    public init(sessions: [String: AgentSession] = [:], seenMessageIDs: Set<UUID> = []) {
        self.sessions = sessions
        self.seenMessageIDs = seenMessageIDs
    }

    public var orderedSessions: [AgentSession] {
        sessions.values.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt { return lhs.id < rhs.id }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    /// Merges non-hook evidence without inventing a second state machine.
    /// Newer evidence may update visible status, while a live actionable hook
    /// state always wins until that request is explicitly resolved.
    @discardableResult
    public mutating func merge(_ candidate: SessionCandidate) -> AgentSession {
        if var existing = sessions[candidate.id] {
            let candidateIsNewer = candidate.updatedAt >= existing.updatedAt
            if candidateIsNewer, existing.pendingRequest == nil {
                existing.detail = candidate.detail
                existing.phase = candidate.phase
                existing.updatedAt = candidate.updatedAt
            }
            if candidate.titleKind >= existing.titleKind, !candidate.title.isEmpty {
                existing.title = candidate.title
                existing.titleKind = candidate.titleKind
            }
            existing.model = existing.model ?? candidate.model
            existing.terminal = existing.terminal ?? candidate.terminal
            existing.projectPath = existing.projectPath ?? candidate.projectPath
            existing.jumpURL = existing.jumpURL ?? candidate.jumpURL
            existing.latestUserPrompt = candidate.latestUserPrompt ?? existing.latestUserPrompt
            existing.latestAgentResponse = candidate.latestAgentResponse ?? existing.latestAgentResponse
            sessions[candidate.id] = existing
            return existing
        }

        let session = AgentSession(
            id: candidate.id,
            agent: candidate.agent,
            title: candidate.title,
            titleKind: candidate.titleKind,
            detail: candidate.detail,
            model: candidate.model,
            terminal: candidate.terminal,
            projectPath: candidate.projectPath,
            jumpURL: candidate.jumpURL,
            latestUserPrompt: candidate.latestUserPrompt,
            latestAgentResponse: candidate.latestAgentResponse,
            phase: candidate.phase,
            startedAt: candidate.updatedAt,
            updatedAt: candidate.updatedAt,
            lastSequence: 0
        )
        sessions[candidate.id] = session
        return session
    }

    @discardableResult
    public mutating func remove(sessionID: String) -> AgentSession? {
        sessions.removeValue(forKey: sessionID)
    }

    @discardableResult
    public mutating func apply(_ event: AgentEvent) -> ReductionResult {
        guard !seenMessageIDs.contains(event.id) else { return .ignoredDuplicate }

        if let existing = sessions[event.sessionID], event.sequence <= existing.lastSequence {
            return .ignoredStale
        }

        if event.kind == .sessionStarted {
            let prior = sessions[event.sessionID]
            let session = AgentSession(
                id: event.sessionID,
                agent: event.agent,
                title: event.title ?? prior?.title ?? "Untitled session",
                titleKind: prior?.titleKind ?? .workspace,
                detail: event.detail ?? prior?.detail ?? "Starting",
                model: event.model ?? prior?.model,
                terminal: event.terminal ?? prior?.terminal,
                projectPath: event.projectPath ?? prior?.projectPath,
                jumpURL: event.jumpURL ?? prior?.jumpURL,
                latestUserPrompt: prior?.latestUserPrompt,
                latestAgentResponse: prior?.latestAgentResponse,
                phase: .working,
                pendingRequest: nil,
                startedAt: prior?.startedAt ?? event.timestamp,
                updatedAt: event.timestamp,
                lastSequence: event.sequence
            )
            sessions[event.sessionID] = session
            seenMessageIDs.insert(event.id)
            return .applied(session)
        }

        guard var session = sessions[event.sessionID] else {
            return .ignoredMissingSession
        }

        session.agent = event.agent
        session.title = event.title ?? session.title
        session.detail = event.detail ?? session.detail
        session.model = event.model ?? session.model
        session.terminal = event.terminal ?? session.terminal
        session.projectPath = event.projectPath ?? session.projectPath
        session.jumpURL = event.jumpURL ?? session.jumpURL
        session.updatedAt = event.timestamp
        session.lastSequence = event.sequence

        switch event.kind {
        case .sessionStarted:
            break
        case .activity:
            session.phase = .working
            session.pendingRequest = nil
        case .permissionRequested:
            guard case .approval? = event.request else { return .ignoredMissingSession }
            session.phase = .waitingForApproval
            session.pendingRequest = event.request
        case .permissionResolved:
            session.phase = .working
            session.pendingRequest = nil
        case .questionRequested:
            guard case .question? = event.request else { return .ignoredMissingSession }
            session.phase = .waitingForAnswer
            session.pendingRequest = event.request
        case .questionResolved:
            session.phase = .working
            session.pendingRequest = nil
        case .completed, .sessionEnded:
            session.phase = .completed
            session.pendingRequest = nil
        case .failed:
            session.phase = .failed
            session.pendingRequest = nil
        }

        sessions[event.sessionID] = session
        seenMessageIDs.insert(event.id)
        return .applied(session)
    }
}
