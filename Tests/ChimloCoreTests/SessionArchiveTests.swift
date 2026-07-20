import Foundation
import Testing
@testable import ChimloCore

@Suite("Session archive visibility")
struct SessionArchiveTests {
    private let archivedAt = Date(timeIntervalSince1970: 200)

    @Test("Only a newer visible conversation restores an archived session")
    func transcriptRestorationUsesMessageTime() {
        let marker = SessionArchiveMarker(archivedAt: archivedAt)

        #expect(!marker.shouldRestore(for: candidate(messageAt: nil)))
        #expect(!marker.shouldRestore(for: candidate(messageAt: archivedAt)))
        #expect(marker.shouldRestore(for: candidate(
            messageAt: archivedAt.addingTimeInterval(1)
        )))
    }

    @Test("Actionable live events restore while tool activity and end states stay archived")
    func liveRestorationIsScoped() {
        let marker = SessionArchiveMarker(archivedAt: archivedAt)

        #expect(marker.shouldRestore(for: event(kind: .permissionRequested, offset: 1)))
        #expect(marker.shouldRestore(for: event(kind: .questionRequested, offset: 1)))
        #expect(!marker.shouldRestore(for: event(kind: .sessionStarted, offset: 1)))
        #expect(!marker.shouldRestore(for: event(kind: .activity, offset: 1)))
        #expect(!marker.shouldRestore(for: event(kind: .completed, offset: 1)))
        #expect(!marker.shouldRestore(for: event(kind: .permissionRequested, offset: 0)))
    }

    private func candidate(messageAt: Date?) -> SessionCandidate {
        SessionCandidate(
            id: "archived-session",
            agent: .codex,
            title: "Archived session",
            detail: "Working",
            latestUserPrompt: "Run the same check",
            latestConversationUpdatedAt: messageAt,
            phase: .working,
            updatedAt: messageAt ?? archivedAt,
            evidence: .codexRollout
        )
    }

    private func event(kind: AgentEventKind, offset: TimeInterval) -> AgentEvent {
        AgentEvent(
            sessionID: "archived-session",
            sequence: 2,
            kind: kind,
            agent: .codex,
            timestamp: archivedAt.addingTimeInterval(offset)
        )
    }
}
