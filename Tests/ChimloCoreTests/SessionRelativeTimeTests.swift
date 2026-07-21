import Foundation
import Testing
@testable import ChimloCore

@Suite("Session relative time")
struct SessionRelativeTimeTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("Recent and future activity stays in the first-minute bucket")
    func recentActivity() {
        #expect(label(secondsAgo: 0) == "<1m")
        #expect(label(secondsAgo: 59) == "<1m")
        #expect(label(secondsAgo: -10) == "<1m")
    }

    @Test("Activity age uses compact whole time units")
    func compactUnits() {
        #expect(label(secondsAgo: 60) == "1m")
        #expect(label(secondsAgo: 59 * 60) == "59m")
        #expect(label(secondsAgo: 3_600) == "1h")
        #expect(label(secondsAgo: 23 * 3_600) == "23h")
        #expect(label(secondsAgo: 86_400) == "1d")
        #expect(label(secondsAgo: 7 * 86_400) == "1w")
        #expect(label(secondsAgo: 30 * 86_400) == "1mo")
        #expect(label(secondsAgo: 365 * 86_400) == "1y")
    }

    @Test("Accessibility labels spell out relative units")
    func accessibilityLabels() {
        #expect(accessibilityLabel(secondsAgo: 30) == "Session activity updated less than a minute ago")
        #expect(accessibilityLabel(secondsAgo: 60) == "Session activity updated 1 minute ago")
        #expect(accessibilityLabel(secondsAgo: 2 * 3_600) == "Session activity updated 2 hours ago")
    }

    private func label(secondsAgo: TimeInterval) -> String {
        SessionRelativeTime.shortLabel(
            since: now.addingTimeInterval(-secondsAgo),
            now: now
        )
    }

    private func accessibilityLabel(secondsAgo: TimeInterval) -> String {
        SessionRelativeTime.accessibilityLabel(
            since: now.addingTimeInterval(-secondsAgo),
            now: now
        )
    }
}
