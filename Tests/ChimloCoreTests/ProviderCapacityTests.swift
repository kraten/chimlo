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
        #expect(ProviderCapacityParser.claudeUsagePanel("No usage data here") == nil)
    }

    @Test("Claude usage panel parses provider-reported remaining percentages")
    func parsesClaudeUsagePanel() throws {
        let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let output = """
        \u{001B}[2JSettings: Usage

        Current session
        ███████░░░ 72% left
        Resets in 2 hr 14 min

        Current week (all models)
        ████░░░░░░ 41% left
        Resets Monday at 6:30 PM
        \u{001B}[0m
        """

        let snapshot = try #require(
            ProviderCapacityParser.claudeUsagePanel(output, observedAt: observedAt)
        )

        #expect(snapshot.window(.session)?.usedPercentage == 28)
        #expect(snapshot.window(.weekly)?.usedPercentage == 59)
        #expect(
            snapshot.window(.session)?.resetsAt
                == observedAt.addingTimeInterval((2 * 60 + 14) * 60)
        )
        #expect(snapshot.window(.session)?.source == .claudeCLIUsage)
        #expect(snapshot.window(.weekly)?.source == .claudeCLIUsage)
        #expect(snapshot.observedAt == observedAt)
    }

    @Test("Claude usage panel parses local reset timestamps")
    func parsesClaudeLocalResetTimestamps() throws {
        let timeZone = try #require(TimeZone(identifier: "Asia/Calcutta"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let observedAt = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 22,
            hour: 12
        )))
        let output = """
        Settings  Status  Config  Usage  Stats
        Current session
        0% used
        Resets 6:39pm (Asia/Calcutta)
        Current week (all models)
        10% used
        Resets Jul 27 at 7:29pm (Asia/Calcutta)
        """

        let snapshot = try #require(
            ProviderCapacityParser.claudeUsagePanel(output, observedAt: observedAt)
        )
        let expectedSessionReset = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 22,
            hour: 18,
            minute: 39
        )))
        let expectedWeeklyReset = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 27,
            hour: 19,
            minute: 29
        )))

        #expect(snapshot.window(.session)?.resetsAt == expectedSessionReset)
        #expect(snapshot.window(.weekly)?.resetsAt == expectedWeeklyReset)
    }

    @Test("Claude usage parser ignores stale terminal fragments before the latest panel")
    func ignoresEarlierTerminalFragments() throws {
        let output = """
        Current session 0% left
        Current week (all models) 0% left
        some redraw noise
        Settings: Usage
        Current session 65% left
        Current week (all models) 20% left
        """

        let snapshot = try #require(ProviderCapacityParser.claudeUsagePanel(output))

        #expect(snapshot.window(.session)?.remainingPercentage == 65)
        #expect(snapshot.window(.weekly)?.remainingPercentage == 20)
    }

    @Test("Claude 2.1 usage panel parses used percentages across partial redraws")
    func parsesCurrentClaudeUsedPercentages() throws {
        let output = """
        Settings  Status  Config  Usage  Stats
        Current\u{001B}[12Gsession
        ████████████████████████████████████████████████ 96% used
        Current\u{001B}[12Gweek\u{001B}[17G(all\u{001B}[22Gmodels)
        █████ 10% used
        Settings  Status  Config  Usage  Stats
        Current session
        ████████████████████████████████████████████████ 96% used
        Current week ( ll models)
        █████ 10% used
        """

        let snapshot = try #require(ProviderCapacityParser.claudeUsagePanel(output))

        #expect(snapshot.window(.session)?.usedPercentage == 96)
        #expect(snapshot.window(.weekly)?.usedPercentage == 10)
    }

    @Test("CLI refresh retains still-valid reset metadata from the status line")
    func retainsResetMetadata() throws {
        let oldObservedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let newObservedAt = oldObservedAt.addingTimeInterval(900)
        let sessionReset = oldObservedAt.addingTimeInterval(4_000)
        let weeklyReset = oldObservedAt.addingTimeInterval(80_000)
        let previous = ProviderCapacitySnapshot(
            provider: .claude,
            windows: [
                CapacityWindowSnapshot(
                    provider: .claude,
                    kind: .session,
                    usedPercentage: 20,
                    resetsAt: sessionReset,
                    observedAt: oldObservedAt,
                    source: .claudeStatusLine
                ),
                CapacityWindowSnapshot(
                    provider: .claude,
                    kind: .weekly,
                    usedPercentage: 40,
                    resetsAt: weeklyReset,
                    observedAt: oldObservedAt,
                    source: .claudeStatusLine
                ),
            ],
            observedAt: oldObservedAt
        )
        let probed = try #require(ProviderCapacityParser.claudeUsagePanel(
            "Settings: Usage\nCurrent session 50% left\nResets in 1 hr\nCurrent week (all models) 25% left",
            observedAt: newObservedAt
        ))

        let merged = probed.preservingValidResetTimes(from: previous)

        #expect(merged.window(.session)?.resetsAt == sessionReset)
        #expect(merged.window(.weekly)?.resetsAt == weeklyReset)
        #expect(merged.window(.session)?.usedPercentage == 50)
        #expect(merged.window(.weekly)?.usedPercentage == 75)

        let partial = try #require(ProviderCapacityParser.claudeUsagePanel(
            "Settings: Usage\nCurrent session 45% left",
            observedAt: newObservedAt
        ))
        let partialMerged = partial.preservingValidResetTimes(from: previous)
        #expect(partialMerged.window(.weekly)?.usedPercentage == 40)
        #expect(partialMerged.window(.weekly)?.observedAt == oldObservedAt)
    }

    @Test("Claude CLI fallback runs only for stale disclosure data and observes cooldown")
    func claudeUsageFallbackPolicy() {
        let now = Date(timeIntervalSince1970: 20_000)
        let freshComplete = ProviderCapacitySnapshot(
            provider: .claude,
            windows: CapacityWindowKind.allCases.map { kind in
                CapacityWindowSnapshot(
                    provider: .claude,
                    kind: kind,
                    usedPercentage: 20,
                    resetsAt: nil,
                    observedAt: now.addingTimeInterval(-60),
                    source: .claudeStatusLine
                )
            },
            observedAt: now.addingTimeInterval(-60)
        )
        let freshIncomplete = ProviderCapacitySnapshot(
            provider: .claude,
            windows: [],
            observedAt: now.addingTimeInterval(-60)
        )
        let stale = ProviderCapacitySnapshot(
            provider: .claude,
            windows: [],
            observedAt: now.addingTimeInterval(-(CapacityPolicy.freshnessInterval + 1))
        )

        #expect(CapacityPolicy.shouldProbeClaudeUsage(snapshot: nil, lastAttemptAt: nil, now: now))
        #expect(!CapacityPolicy.shouldProbeClaudeUsage(
            snapshot: freshComplete,
            lastAttemptAt: nil,
            now: now
        ))
        #expect(CapacityPolicy.shouldProbeClaudeUsage(
            snapshot: freshIncomplete,
            lastAttemptAt: nil,
            now: now
        ))
        #expect(CapacityPolicy.shouldProbeClaudeUsage(snapshot: stale, lastAttemptAt: nil, now: now))
        #expect(!CapacityPolicy.shouldProbeClaudeUsage(
            snapshot: stale,
            lastAttemptAt: now.addingTimeInterval(-30),
            now: now
        ))
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

        #expect(!CapacityPolicy.isApproximate(
            window,
            refreshFailed: false,
            now: observedAt.addingTimeInterval(CapacityPolicy.freshnessInterval - 1)
        ))
        #expect(CapacityPolicy.isApproximate(
            window,
            refreshFailed: false,
            now: observedAt.addingTimeInterval(CapacityPolicy.freshnessInterval + 1)
        ))
        #expect(CapacityPolicy.isApproximate(window, refreshFailed: true, now: observedAt))
        #expect(window.isExpired(at: Date(timeIntervalSince1970: 2_000)))
    }
}
