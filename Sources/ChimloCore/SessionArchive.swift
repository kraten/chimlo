import Foundation

/// A Chimlo-only visibility marker. It records when the owner archived a row,
/// never the conversation itself, and cannot mutate the provider session.
public struct SessionArchiveMarker: Equatable, Sendable {
    public let archivedAt: Date

    public init(archivedAt: Date = .now) {
        self.archivedAt = archivedAt
    }

    /// Transcript candidates carry this timestamp only in memory. Cached
    /// candidates deliberately omit it with the prompt and response previews.
    public func shouldRestore(for candidate: SessionCandidate) -> Bool {
        guard let latestConversationUpdatedAt = candidate.latestConversationUpdatedAt else {
            return false
        }
        return latestConversationUpdatedAt > archivedAt
    }

    /// Actionable requests should never remain hidden. Generic activity can be
    /// a tool heartbeat, so conversation previews remain the authority for
    /// restoring ordinary archived work.
    public func shouldRestore(for event: AgentEvent) -> Bool {
        guard event.timestamp > archivedAt else { return false }
        switch event.kind {
        case .permissionRequested, .questionRequested:
            return true
        case .sessionStarted, .activity, .permissionResolved, .questionResolved,
             .completed, .failed, .sessionEnded:
            return false
        }
    }
}
