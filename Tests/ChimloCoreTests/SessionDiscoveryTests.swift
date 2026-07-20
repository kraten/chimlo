import Foundation
import Testing
@testable import ChimloCore

@Suite("Privacy-safe session discovery")
struct SessionDiscoveryTests {
    @Test("Codex rollout exposes lifecycle metadata without retaining content")
    func codexMetadataOnly() throws {
        var scanner = PrivacySafeSessionMetadataScanner(provider: .codex)
        scanner.consume(line: Data(#"{"type":"session_meta","payload":{"id":"codex-1","cwd":"/Users/me/Projects/chimlo","model":"gpt-5.6","timestamp":"2026-07-20T10:00:00Z"}}"#.utf8))
        scanner.consume(line: Data(#"{"timestamp":"2026-07-20T10:01:00Z","type":"event_msg","payload":{"type":"task_started","prompt":"DO NOT RETAIN"}}"#.utf8))
        scanner.consume(line: Data(#"{"timestamp":"2026-07-20T10:02:00Z","type":"event_msg","payload":{"type":"task_complete","last_agent_message":"DO NOT RETAIN"}}"#.utf8))

        let candidate = try #require(scanner.candidate(
            transcriptPath: "/Users/me/.codex/sessions/rollout-codex-1.jsonl",
            fallbackUpdatedAt: .distantPast
        ))
        #expect(candidate.id == "codex-1")
        #expect(candidate.title == "chimlo")
        #expect(candidate.phase == .completed)
        #expect(candidate.jumpURL?.absoluteString == "codex://threads/codex-1")

        let encoded = String(decoding: try JSONEncoder().encode(candidate), as: UTF8.self)
        #expect(!encoded.contains("DO NOT RETAIN"))
        #expect(!encoded.contains("rollout-codex-1"))
    }

    @Test("Claude transcript exposes identity and working state only")
    func claudeMetadataOnly() throws {
        var scanner = PrivacySafeSessionMetadataScanner(provider: .claude)
        scanner.consume(line: Data(#"{"sessionId":"claude-1","cwd":"/Users/me/Projects/chimlo","timestamp":"2026-07-20T10:00:00Z","type":"user","message":{"role":"user","content":"DO NOT RETAIN"}}"#.utf8))
        scanner.consume(line: Data(#"{"sessionId":"claude-1","timestamp":"2026-07-20T10:00:02Z","type":"assistant","message":{"role":"assistant","model":"claude-sonnet","content":[{"type":"text","text":"DO NOT RETAIN"}]}}"#.utf8))

        let candidate = try #require(scanner.candidate(
            transcriptPath: "/Users/me/.claude/projects/chimlo/claude-1.jsonl",
            fallbackUpdatedAt: .distantPast
        ))
        #expect(candidate.id == "claude-1")
        #expect(candidate.phase == .working)
        #expect(candidate.model == "claude-sonnet")
        #expect(candidate.jumpURL == nil)

        let encoded = String(decoding: try JSONEncoder().encode(candidate), as: UTF8.self)
        #expect(!encoded.contains("DO NOT RETAIN"))
        #expect(!encoded.contains("claude-1.jsonl"))
    }
}

