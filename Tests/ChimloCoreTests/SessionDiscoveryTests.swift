import Foundation
import Testing
@testable import ChimloCore

@Suite("Local session discovery")
struct SessionDiscoveryTests {
    @Test("Cached owner interactions do not restore without their transient options")
    func cachedOwnerInteractionsRequireLiveOptions() {
        for phase in [SessionPhase.waitingForAnswer, .waitingForApproval] {
            let restored = SessionCandidate(
                id: "claude-1",
                agent: .claude,
                title: "Create a file",
                detail: phase == .waitingForAnswer ? "Waiting for input" : "Waiting for approval",
                phase: phase,
                updatedAt: Date(timeIntervalSince1970: 100),
                evidence: .cache
            ).normalizedForCache()

            #expect(restored.phase == .working)
            #expect(restored.detail == "Working")
        }
    }

    @Test("Codex rollout exposes visible conversation previews without persisting them")
    func codexConversationPreview() throws {
        var scanner = PrivacySafeSessionMetadataScanner(provider: .codex)
        scanner.consume(line: Data(#"{"type":"session_meta","payload":{"id":"codex-1","cwd":"/Users/me/Projects/chimlo","model":"gpt-5.6","timestamp":"2026-07-20T10:00:00Z"}}"#.utf8))
        scanner.consume(line: Data(#"{"timestamp":"2026-07-20T10:01:00Z","type":"event_msg","payload":{"type":"task_started","prompt":"DO NOT RETAIN"}}"#.utf8))
        scanner.consume(line: Data(#"{"timestamp":"2026-07-20T10:01:01Z","type":"event_msg","payload":{"type":"user_message","message":"Polish the expanded session row"}}"#.utf8))
        scanner.consume(line: Data(#"{"timestamp":"2026-07-20T10:01:02Z","type":"event_msg","payload":{"type":"agent_message","message":"Implemented the compact three-line layout."}}"#.utf8))
        scanner.consume(line: Data(#"{"timestamp":"2026-07-20T10:02:00Z","type":"event_msg","payload":{"type":"task_complete","last_agent_message":"DO NOT RETAIN"}}"#.utf8))

        let candidate = try #require(scanner.candidate(
            transcriptPath: "/Users/me/.codex/sessions/rollout-codex-1.jsonl",
            fallbackUpdatedAt: .distantPast
        ))
        #expect(candidate.id == "codex-1")
        #expect(candidate.title == "chimlo")
        #expect(candidate.phase == .completed)
        #expect(candidate.jumpURL?.absoluteString == "codex://threads/codex-1")
        #expect(candidate.latestUserPrompt == "Polish the expanded session row")
        #expect(candidate.latestAgentResponse == "Implemented the compact three-line layout.")
        #expect(candidate.latestConversationUpdatedAt == Date(timeIntervalSince1970: 1_784_541_662))

        let data = try JSONEncoder().encode(candidate)
        let encoded = String(decoding: data, as: UTF8.self)
        #expect(!encoded.contains("DO NOT RETAIN"))
        #expect(!encoded.contains("Polish the expanded session row"))
        #expect(!encoded.contains("Implemented the compact three-line layout."))
        #expect(!encoded.contains("rollout-codex-1"))
        let restored = try JSONDecoder().decode(SessionCandidate.self, from: data)
        #expect(restored.latestConversationUpdatedAt == nil)
    }

    @Test("Claude transcript exposes title and visible conversation previews")
    func claudeConversationPreview() throws {
        var scanner = PrivacySafeSessionMetadataScanner(provider: .claude)
        scanner.consume(line: Data(#"{"sessionId":"claude-1","cwd":"/Users/me/Projects/chimlo","timestamp":"2026-07-20T10:00:00Z","type":"user","message":{"role":"user","content":"Polish the expanded session row"}}"#.utf8))
        scanner.consume(line: Data(#"{"sessionId":"claude-1","timestamp":"2026-07-20T10:00:01Z","type":"ai-title","aiTitle":"Polish Chimlo expanded UI"}"#.utf8))
        scanner.consume(line: Data(#"{"sessionId":"claude-1","timestamp":"2026-07-20T10:00:02Z","type":"assistant","message":{"role":"assistant","model":"claude-sonnet","content":[{"type":"text","text":"Implemented the compact three-line layout."}]}}"#.utf8))

        let candidate = try #require(scanner.candidate(
            transcriptPath: "/Users/me/.claude/projects/chimlo/claude-1.jsonl",
            fallbackUpdatedAt: .distantPast
        ))
        #expect(candidate.id == "claude-1")
        #expect(candidate.phase == .working)
        #expect(candidate.model == "claude-sonnet")
        #expect(candidate.jumpURL == nil)
        #expect(candidate.title == "Polish Chimlo expanded UI")
        #expect(candidate.latestUserPrompt == "Polish the expanded session row")
        #expect(candidate.latestAgentResponse == "Implemented the compact three-line layout.")
        #expect(candidate.latestConversationUpdatedAt == Date(timeIntervalSince1970: 1_784_541_602))

        let encoded = String(decoding: try JSONEncoder().encode(candidate), as: UTF8.self)
        #expect(!encoded.contains("Polish the expanded session row"))
        #expect(!encoded.contains("Implemented the compact three-line layout."))
        #expect(!encoded.contains("claude-1.jsonl"))
    }
}
