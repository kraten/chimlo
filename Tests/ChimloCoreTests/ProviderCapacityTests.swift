import Foundation
import Testing
@testable import ChimloCore

@Suite("Provider capacity")
struct ProviderCapacityTests {
    @Test("Codex selects only the exact weekly app-server window")
    func parsesCodexWeeklyWindow() throws {
        let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = try #require(ProviderCapacityParser.codexAppServer([
            "rateLimits": [
                "primary": [
                    "usedPercent": 12,
                    "windowDurationMins": 300,
                    "resetsAt": 1_700_001_000,
                ],
                "secondary": [
                    "usedPercent": 36,
                    "windowDurationMins": 10_080,
                    "resetsAt": 1_700_090_000,
                ],
            ],
        ], observedAt: observedAt))

        #expect(snapshot.windows.count == 1)
        #expect(snapshot.window(.session) == nil)
        #expect(snapshot.window(.weekly)?.remainingPercentage == 64)
        #expect(snapshot.window(.weekly)?.resetsAt == Date(timeIntervalSince1970: 1_700_090_000))
    }

    @Test("Claude status-line data produces separate session and weekly windows")
    func parsesClaudeWindows() throws {
        let data = Data(#"{"rate_limits":{"five_hour":{"used_percentage":32,"resets_at":1700001000},"seven_day":{"used_percentage":67,"resets_at":1700090000}}}"#.utf8)
        let snapshot = try #require(ProviderCapacityParser.claudeStatusLine(data))

        #expect(snapshot.window(.session)?.remainingPercentage == 68)
        #expect(snapshot.window(.weekly)?.remainingPercentage == 33)
    }

    @Test("Claude utilization payload produces session and weekly windows")
    func parsesClaudeUtilizationWindows() throws {
        let data = Data(#"{"rate_limits":{"five_hour":{"utilization":36,"resets_at":"2026-07-22T07:39:59.633009+00:00"},"seven_day":{"utilization":4,"resets_at":"2026-07-27T13:59:59.633030+00:00"}}}"#.utf8)
        let snapshot = try #require(ProviderCapacityParser.claudeStatusLine(data))

        #expect(snapshot.window(.session)?.remainingPercentage == 64)
        #expect(snapshot.window(.weekly)?.remainingPercentage == 96)
        #expect(snapshot.window(.session)?.resetsAt != nil)
        #expect(snapshot.window(.weekly)?.resetsAt != nil)
    }

    @Test("Missing capacity is unavailable rather than zero")
    func missingDataIsUnavailable() {
        #expect(ProviderCapacityParser.codexAppServer(["rateLimits": [:]]) == nil)
        #expect(ProviderCapacityParser.claudeStatusLine(Data(#"{"rate_limits":{}}"#.utf8)) == nil)
    }

    @Test("Stale and reset policies preserve honest state")
    func staleAndResetPolicy() {
        let observedAt = Date(timeIntervalSince1970: 1_000)
        let window = CapacityWindowSnapshot(
            provider: .claude,
            kind: .session,
            usedPercentage: 85,
            resetsAt: Date(timeIntervalSince1970: 2_000),
            observedAt: observedAt,
            source: .claudeStatusLine
        )

        #expect(!CapacityPolicy.isApproximate(window, refreshFailed: false, now: observedAt.addingTimeInterval(599)))
        #expect(CapacityPolicy.isApproximate(window, refreshFailed: false, now: observedAt.addingTimeInterval(601)))
        #expect(CapacityPolicy.isApproximate(window, refreshFailed: true, now: observedAt))
        #expect(window.isExpired(at: Date(timeIntervalSince1970: 2_000)))
    }
}
