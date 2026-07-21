import Foundation

public enum SessionRelativeTime {
    public static func shortLabel(since date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))

        switch seconds {
        case ..<60:
            return "<1m"
        case ..<3_600:
            return "\(Int(seconds / 60))m"
        case ..<86_400:
            return "\(Int(seconds / 3_600))h"
        case ..<604_800:
            return "\(Int(seconds / 86_400))d"
        case ..<2_592_000:
            return "\(Int(seconds / 604_800))w"
        case ..<31_536_000:
            return "\(Int(seconds / 2_592_000))mo"
        default:
            return "\(Int(seconds / 31_536_000))y"
        }
    }

    public static func accessibilityLabel(since date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))

        switch seconds {
        case ..<60:
            return "Session activity updated less than a minute ago"
        case ..<3_600:
            return description(value: Int(seconds / 60), unit: "minute")
        case ..<86_400:
            return description(value: Int(seconds / 3_600), unit: "hour")
        case ..<604_800:
            return description(value: Int(seconds / 86_400), unit: "day")
        case ..<2_592_000:
            return description(value: Int(seconds / 604_800), unit: "week")
        case ..<31_536_000:
            return description(value: Int(seconds / 2_592_000), unit: "month")
        default:
            return description(value: Int(seconds / 31_536_000), unit: "year")
        }
    }

    private static func description(value: Int, unit: String) -> String {
        let suffix = value == 1 ? "" : "s"
        return "Session activity updated \(value) \(unit)\(suffix) ago"
    }
}
