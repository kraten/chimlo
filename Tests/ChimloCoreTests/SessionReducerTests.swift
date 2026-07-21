import Foundation
import Testing
@testable import ChimloCore

@Suite("Session reducer")
struct SessionReducerTests {
    private let start = Date(timeIntervalSince1970: 100)

    @Test("Lifecycle applies in sequence")
    func lifecycleAppliesInSequence() {
        var reducer = SessionReducer()

        expectApplied(reducer.apply(event(sequence: 1, kind: .sessionStarted, detail: "Starting")))
        expectApplied(reducer.apply(event(sequence: 2, kind: .activity, detail: "Testing")))
        expectApplied(reducer.apply(event(sequence: 3, kind: .completed, detail: "Done")))

        let session = reducer.sessions["s1"]
        #expect(session?.phase == .completed)
        #expect(session?.detail == "Done")
        #expect(session?.lastSequence == 3)
    }

    @Test("A duplicate message ID is ignored")
    func duplicateMessageIsIgnored() {
        var reducer = SessionReducer()
        let message = event(sequence: 1, kind: .sessionStarted)

        expectApplied(reducer.apply(message))
        #expect(reducer.apply(message) == .ignoredDuplicate)
    }

    @Test("A stale per-session sequence is ignored")
    func staleSequenceIsIgnored() {
        var reducer = SessionReducer()
        expectApplied(reducer.apply(event(sequence: 2, kind: .sessionStarted)))
        #expect(reducer.apply(event(sequence: 1, kind: .activity)) == .ignoredStale)
        #expect(reducer.sessions["s1"]?.lastSequence == 2)
    }

    @Test("Approval is explicit and clears on resolution")
    func approvalMustBeExplicitAndClearsOnResolution() {
        var reducer = SessionReducer()
        expectApplied(reducer.apply(event(sequence: 1, kind: .sessionStarted)))
        let request = PendingRequest.approval(ApprovalRequest(id: "a1", summary: "Run tests?"))
        expectApplied(reducer.apply(event(sequence: 2, kind: .permissionRequested, request: request)))

        #expect(reducer.sessions["s1"]?.phase == .waitingForApproval)
        #expect(reducer.sessions["s1"]?.pendingRequest?.id == "a1")

        expectApplied(reducer.apply(event(sequence: 3, kind: .permissionResolved, decision: .deny)))
        #expect(reducer.sessions["s1"]?.phase == .working)
        #expect(reducer.sessions["s1"]?.pendingRequest == nil)
    }

    @Test("Questions resolve and failures clear pending input")
    func questionAndFailureTransitions() {
        var reducer = SessionReducer()
        expectApplied(reducer.apply(event(sequence: 1, kind: .sessionStarted)))
        let question = PendingRequest.question(
            AgentQuestion(id: "q1", prompt: "Which target?", options: ["Local", "Staging"])
        )
        expectApplied(reducer.apply(event(sequence: 2, kind: .questionRequested, request: question)))
        #expect(reducer.sessions["s1"]?.phase == .waitingForAnswer)

        expectApplied(reducer.apply(event(sequence: 3, kind: .questionResolved, decision: .answer("Local"))))
        expectApplied(reducer.apply(event(sequence: 4, kind: .failed, detail: "A focused check failed")))
        #expect(reducer.sessions["s1"]?.phase == .failed)
        #expect(reducer.sessions["s1"]?.pendingRequest == nil)
    }

    @Test("Optionless input signals do not become questions")
    func optionlessInputIsNotAQuestion() {
        var reducer = SessionReducer()
        expectApplied(reducer.apply(event(sequence: 1, kind: .sessionStarted)))
        let input = PendingRequest.question(
            AgentQuestion(id: "q1", prompt: "Continue in source app")
        )

        #expect(
            reducer.apply(event(sequence: 2, kind: .questionRequested, request: input))
                == .ignoredMissingSession
        )
        #expect(reducer.sessions["s1"]?.phase == .working)
        #expect(reducer.sessions["s1"]?.pendingRequest == nil)
    }

    @Test("Non-start events cannot invent a session")
    func nonStartEventCannotCreateSession() {
        var reducer = SessionReducer()
        #expect(reducer.apply(event(sequence: 1, kind: .activity)) == .ignoredMissingSession)
        #expect(reducer.sessions.isEmpty)
    }

    @Test("Discovered evidence merges without clearing actionable state")
    func discoveryPreservesActionableState() {
        var reducer = SessionReducer()
        expectApplied(reducer.apply(event(sequence: 1, kind: .sessionStarted)))
        let request = PendingRequest.approval(ApprovalRequest(id: "a1", summary: "Approve?"))
        expectApplied(reducer.apply(event(sequence: 2, kind: .permissionRequested, request: request)))

        reducer.merge(SessionCandidate(
            id: "s1",
            agent: .codex,
            title: "Recovered title",
            detail: "Recovered status",
            projectPath: "/tmp/project",
            jumpURL: URL(string: "codex://threads/s1"),
            phase: .completed,
            updatedAt: start.addingTimeInterval(20),
            evidence: .codexAppServer
        ))

        #expect(reducer.sessions["s1"]?.phase == .waitingForApproval)
        #expect(reducer.sessions["s1"]?.pendingRequest?.id == "a1")
        #expect(reducer.sessions["s1"]?.jumpURL?.absoluteString == "codex://threads/s1")
    }

    @Test("The onboarding script is deterministic")
    func demoScriptIsDeterministic() {
        let first = DemoScript.make()
        let second = DemoScript.make()

        #expect(first == second)
        #expect(first.map(\.offsetMilliseconds) == [0, 900, 1_800, 3_200, 4_200])
        #expect(first.last?.event.kind == .completed)
    }

    private func event(
        sequence: Int,
        kind: AgentEventKind,
        detail: String? = nil,
        request: PendingRequest? = nil,
        decision: UserDecision? = nil
    ) -> AgentEvent {
        AgentEvent(
            sessionID: "s1",
            sequence: sequence,
            kind: kind,
            agent: .codex,
            title: "A session",
            detail: detail,
            request: request,
            decision: decision,
            timestamp: start.addingTimeInterval(Double(sequence))
        )
    }

    private func expectApplied(_ result: ReductionResult) {
        guard case .applied = result else {
            Issue.record("Expected an applied event, got \(result)")
            return
        }
    }
}
