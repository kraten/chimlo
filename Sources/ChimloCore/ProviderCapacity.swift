import Foundation

public enum CapacityProvider: String, Codable, CaseIterable, Sendable {
    case codex
    case claude
}

public enum CapacityWindowKind: String, Codable, CaseIterable, Sendable {
    case session
    case weekly
}

public enum CapacitySource: String, Codable, Sendable {
    case codexAppServer
    case claudeStatusLine
    case claudeCLIUsage
}

public struct CapacityWindowSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let provider: CapacityProvider
    public let kind: CapacityWindowKind
    public let usedPercentage: Double
    public let resetsAt: Date?
    public let observedAt: Date
    public let source: CapacitySource

    public init(
        provider: CapacityProvider,
        kind: CapacityWindowKind,
        usedPercentage: Double,
        resetsAt: Date?,
        observedAt: Date,
        source: CapacitySource
    ) {
        self.provider = provider
        self.kind = kind
        self.usedPercentage = min(100, max(0, usedPercentage))
        self.resetsAt = resetsAt
        self.observedAt = observedAt
        self.source = source
    }

    public var id: String { "\(provider.rawValue)-\(kind.rawValue)" }

    public var remainingPercentage: Double {
        min(100, max(0, 100 - usedPercentage))
    }

    public func isExpired(at date: Date = .now) -> Bool {
        guard let resetsAt else { return false }
        return resetsAt <= date
    }
}

public struct ProviderCapacitySnapshot: Codable, Equatable, Sendable {
    public let provider: CapacityProvider
    public let windows: [CapacityWindowSnapshot]
    public let observedAt: Date

    public init(
        provider: CapacityProvider,
        windows: [CapacityWindowSnapshot],
        observedAt: Date
    ) {
        self.provider = provider
        self.windows = windows
        self.observedAt = observedAt
    }

    public func window(_ kind: CapacityWindowKind) -> CapacityWindowSnapshot? {
        windows.first { $0.kind == kind }
    }

    /// The Claude `/usage` panel reports exact percentages and a rounded reset
    /// countdown, while the status line supplies a more precise timestamp.
    /// Keep still-valid prior metadata instead of replacing it with the rounded
    /// fallback value, and retain windows omitted by some account types.
    public func preservingValidResetTimes(
        from previous: ProviderCapacitySnapshot?
    ) -> ProviderCapacitySnapshot {
        guard provider == .claude, previous?.provider == .claude else { return self }
        var merged = windows.map { window in
            guard window.source == .claudeCLIUsage,
                  let reset = previous?.window(window.kind)?.resetsAt,
                  reset > observedAt else {
                return window
            }
            return CapacityWindowSnapshot(
                provider: window.provider,
                kind: window.kind,
                usedPercentage: window.usedPercentage,
                resetsAt: reset,
                observedAt: window.observedAt,
                source: window.source
            )
        }
        for kind in CapacityWindowKind.allCases where !merged.contains(where: { $0.kind == kind }) {
            guard let previousWindow = previous?.window(kind),
                  !previousWindow.isExpired(at: observedAt) else { continue }
            merged.append(previousWindow)
        }
        return ProviderCapacitySnapshot(
            provider: provider,
            windows: merged,
            observedAt: observedAt
        )
    }
}

public enum CapacityPolicy {
    public static let warningRemainingPercentage = 20.0
    public static let freshnessInterval: TimeInterval = 5 * 60
    public static let claudeUsageProbeRetryInterval: TimeInterval = 5 * 60

    public static func isApproximate(
        _ window: CapacityWindowSnapshot,
        refreshFailed: Bool,
        now: Date = .now
    ) -> Bool {
        refreshFailed || now.timeIntervalSince(window.observedAt) > freshnessInterval
    }

    public static func shouldProbeClaudeUsage(
        snapshot: ProviderCapacitySnapshot?,
        lastAttemptAt: Date?,
        now: Date = .now
    ) -> Bool {
        if let lastAttemptAt,
           now.timeIntervalSince(lastAttemptAt) < claudeUsageProbeRetryInterval {
            return false
        }
        guard let snapshot, snapshot.provider == .claude else { return true }
        let hasEveryWindow = CapacityWindowKind.allCases.allSatisfy {
            snapshot.window($0) != nil
        }
        return !hasEveryWindow
            || now.timeIntervalSince(snapshot.observedAt) > freshnessInterval
    }
}

public enum ProviderCapacityParser {
    public static func codexAppServer(
        _ object: [String: Any],
        observedAt: Date = .now
    ) -> ProviderCapacitySnapshot? {
        let rateLimits = dictionary(object["rateLimits"])
            ?? dictionary(object["rate_limits"])
            ?? object

        let candidates = ["secondary", "primary"].compactMap { key -> [String: Any]? in
            dictionary(rateLimits[key])
        }
        guard let weekly = candidates.first(where: { windowDurationMinutes($0) == 10_080 }),
              let usedPercentage = number(weekly["usedPercent"])
                ?? number(weekly["used_percent"]) else {
            return nil
        }

        let window = CapacityWindowSnapshot(
            provider: .codex,
            kind: .weekly,
            usedPercentage: usedPercentage,
            resetsAt: date(weekly["resetsAt"] ?? weekly["resets_at"]),
            observedAt: observedAt,
            source: .codexAppServer
        )
        return ProviderCapacitySnapshot(
            provider: .codex,
            windows: [window],
            observedAt: observedAt
        )
    }

    public static func claudeStatusLine(
        _ data: Data,
        observedAt: Date = .now
    ) -> ProviderCapacitySnapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rateLimits = dictionary(object["rate_limits"]) else {
            return nil
        }

        let windows: [CapacityWindowSnapshot] = [
            claudeWindow(
                dictionary(rateLimits["five_hour"]),
                kind: .session,
                observedAt: observedAt
            ),
            claudeWindow(
                dictionary(rateLimits["seven_day"]),
                kind: .weekly,
                observedAt: observedAt
            ),
        ].compactMap { $0 }

        guard !windows.isEmpty else { return nil }
        return ProviderCapacitySnapshot(
            provider: .claude,
            windows: windows,
            observedAt: observedAt
        )
    }

    /// Parses Claude Code's provider-owned `/usage` terminal panel. Claude has
    /// shipped both used and remaining percentage labels, so Chimlo normalizes
    /// either form to the status-line source's used-percentage model.
    public static func claudeUsagePanel(
        _ output: String,
        observedAt: Date = .now
    ) -> ProviderCapacitySnapshot? {
        let plainText = strippingTerminalControlSequences(output)
        let panel: Substring
        if let marker = plainText.range(
            of: "Settings: Usage",
            options: [.caseInsensitive, .backwards]
        ) {
            panel = plainText[marker.lowerBound...]
        } else {
            panel = plainText[...]
        }

        let windows: [CapacityWindowSnapshot] = [
            claudeUsageWindow(
                in: panel,
                label: "Current session",
                kind: .session,
                observedAt: observedAt
            ),
            claudeUsageWindow(
                in: panel,
                label: "Current week (all models)",
                kind: .weekly,
                observedAt: observedAt
            ),
        ].compactMap { $0 }

        guard !windows.isEmpty else { return nil }
        return ProviderCapacitySnapshot(
            provider: .claude,
            windows: windows,
            observedAt: observedAt
        )
    }

    private static func claudeWindow(
        _ object: [String: Any]?,
        kind: CapacityWindowKind,
        observedAt: Date
    ) -> CapacityWindowSnapshot? {
        guard let object,
              let usedPercentage = number(object["used_percentage"])
                ?? number(object["utilization"]) else {
            return nil
        }
        return CapacityWindowSnapshot(
            provider: .claude,
            kind: kind,
            usedPercentage: usedPercentage,
            resetsAt: date(object["resets_at"]),
            observedAt: observedAt,
            source: .claudeStatusLine
        )
    }

    private static func claudeUsageWindow(
        in panel: Substring,
        label: String,
        kind: CapacityWindowKind,
        observedAt: Date
    ) -> CapacityWindowSnapshot? {
        guard let expression = try? NSRegularExpression(
            pattern: #"([0-9]{1,3}(?:\.[0-9]+)?)\s*%\s*(used|spent|consumed|left|remaining|available)"#,
            options: [.caseInsensitive]
        ) else { return nil }

        let lines = String(panel).components(separatedBy: .newlines)
        let normalizedLines = lines.map(normalizedUsageLabel)
        let normalizedLabel = normalizedUsageLabel(label)
        for index in lines.indices.reversed()
        where normalizedLines[index].contains(normalizedLabel) {
            var upperBound = min(lines.endIndex, index + 12)
            if index + 1 < upperBound,
               let nextWindow = (index + 1..<upperBound).first(where: {
                   normalizedLines[$0].hasPrefix("current")
                       && !normalizedLines[$0].contains(normalizedLabel)
               }) {
                upperBound = nextWindow
            }
            let resetsAt = claudeUsageReset(
                in: lines[index..<upperBound],
                kind: kind,
                observedAt: observedAt
            )
            for candidateIndex in index..<upperBound {
                let value = lines[candidateIndex]
                guard let match = expression.firstMatch(
                    in: value,
                    range: NSRange(value.startIndex..., in: value)
                ), match.numberOfRanges > 2,
                   let percentageRange = Range(match.range(at: 1), in: value),
                   let semanticRange = Range(match.range(at: 2), in: value),
                   let percentage = Double(value[percentageRange]),
                   (0...100).contains(percentage) else {
                    continue
                }
                let semantic = value[semanticRange].lowercased()
                let usedPercentage = ["used", "spent", "consumed"].contains(semantic)
                    ? percentage
                    : 100 - percentage
                return CapacityWindowSnapshot(
                    provider: .claude,
                    kind: kind,
                    usedPercentage: usedPercentage,
                    resetsAt: resetsAt,
                    observedAt: observedAt,
                    source: .claudeCLIUsage
                )
            }
        }
        return nil
    }

    private static func claudeUsageReset(
        in lines: ArraySlice<String>,
        kind: CapacityWindowKind,
        observedAt: Date
    ) -> Date? {
        guard let relativeExpression = try? NSRegularExpression(
            pattern: #"\bresets?\s+in\s+(?:(\d+)\s*(?:days?|d))?\s*(?:(\d+)\s*(?:hours?|hrs?|h))?\s*(?:(\d+)\s*(?:minutes?|mins?|m))?"#,
            options: [.caseInsensitive]
        ) else { return nil }

        for line in lines {
            if let match = relativeExpression.firstMatch(
                in: line,
                range: NSRange(line.startIndex..., in: line)
            ) {
                let days = capturedInteger(match, at: 1, in: line) ?? 0
                let hours = capturedInteger(match, at: 2, in: line) ?? 0
                let minutes = capturedInteger(match, at: 3, in: line) ?? 0
                let interval = TimeInterval(days) * 24 * 60 * 60
                    + TimeInterval(hours) * 60 * 60
                    + TimeInterval(minutes) * 60
                guard interval > 0, interval <= 8 * 24 * 60 * 60 else { continue }
                return observedAt.addingTimeInterval(interval)
            }

            let reset: Date?
            switch kind {
            case .session:
                reset = claudeSessionReset(in: line, observedAt: observedAt)
            case .weekly:
                reset = claudeWeeklyReset(in: line, observedAt: observedAt)
            }
            if let reset { return reset }
        }
        return nil
    }

    private static func claudeSessionReset(
        in line: String,
        observedAt: Date
    ) -> Date? {
        guard let expression = try? NSRegularExpression(
            pattern: #"\bresets?\s+(\d{1,2}):(\d{2})\s*(am|pm)\s*(?:\(([^)]+)\))?"#,
            options: [.caseInsensitive]
        ), let match = expression.firstMatch(
            in: line,
            range: NSRange(line.startIndex..., in: line)
        ), let hour = capturedInteger(match, at: 1, in: line),
           let minute = capturedInteger(match, at: 2, in: line),
           let meridiem = capturedString(match, at: 3, in: line),
           let hour24 = hour24(hour, meridiem: meridiem),
           (0..<60).contains(minute),
           let timeZone = claudeResetTimeZone(match, at: 4, in: line) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.dateComponents([.year, .month, .day], from: observedAt)
        guard let year = day.year, let month = day.month, let dayOfMonth = day.day,
              var reset = calendar.date(from: DateComponents(
                timeZone: timeZone,
                year: year,
                month: month,
                day: dayOfMonth,
                hour: hour24,
                minute: minute
              )) else { return nil }

        if reset <= observedAt {
            let endOfDisplayedMinute = reset.addingTimeInterval(60)
            if observedAt < endOfDisplayedMinute {
                reset = endOfDisplayedMinute
            } else if let nextDay = calendar.date(byAdding: .day, value: 1, to: reset) {
                reset = nextDay
            } else {
                return nil
            }
        }
        let interval = reset.timeIntervalSince(observedAt)
        return interval > 0 && interval <= 24 * 60 * 60 ? reset : nil
    }

    private static func claudeWeeklyReset(
        in line: String,
        observedAt: Date
    ) -> Date? {
        guard let expression = try? NSRegularExpression(
            pattern: #"\bresets?\s+([a-z]{3,9})\s+(\d{1,2})(?:,?\s+(\d{4}))?\s+at\s+(\d{1,2}):(\d{2})\s*(am|pm)\s*(?:\(([^)]+)\))?"#,
            options: [.caseInsensitive]
        ), let match = expression.firstMatch(
            in: line,
            range: NSRange(line.startIndex..., in: line)
        ), let monthName = capturedString(match, at: 1, in: line),
           let month = claudeMonth(monthName),
           let day = capturedInteger(match, at: 2, in: line),
           let hour = capturedInteger(match, at: 4, in: line),
           let minute = capturedInteger(match, at: 5, in: line),
           let meridiem = capturedString(match, at: 6, in: line),
           let hour24 = hour24(hour, meridiem: meridiem),
           (1...31).contains(day),
           (0..<60).contains(minute),
           let timeZone = claudeResetTimeZone(match, at: 7, in: line) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let explicitYear = capturedInteger(match, at: 3, in: line)
        var year = explicitYear ?? calendar.component(.year, from: observedAt)
        guard var reset = validatedDate(
            calendar: calendar,
            timeZone: timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour24,
            minute: minute
        ) else { return nil }

        if explicitYear == nil, reset <= observedAt {
            year += 1
            guard let nextYear = validatedDate(
                calendar: calendar,
                timeZone: timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour24,
                minute: minute
            ) else { return nil }
            reset = nextYear
        }
        let interval = reset.timeIntervalSince(observedAt)
        return interval > 0 && interval <= 370 * 24 * 60 * 60 ? reset : nil
    }

    private static func validatedDate(
        calendar: Calendar,
        timeZone: TimeZone,
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int
    ) -> Date? {
        let expected = DateComponents(
            timeZone: timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
        guard let date = calendar.date(from: expected) else { return nil }
        let actual = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        guard actual.year == year, actual.month == month, actual.day == day,
              actual.hour == hour, actual.minute == minute else { return nil }
        return date
    }

    private static func hour24(_ hour: Int, meridiem: String) -> Int? {
        guard (1...12).contains(hour) else { return nil }
        let normalized = meridiem.lowercased()
        guard normalized == "am" || normalized == "pm" else { return nil }
        return hour % 12 + (normalized == "pm" ? 12 : 0)
    }

    private static func claudeResetTimeZone(
        _ match: NSTextCheckingResult,
        at index: Int,
        in value: String
    ) -> TimeZone? {
        guard let identifier = capturedString(match, at: index, in: value) else {
            return .current
        }
        return TimeZone(identifier: identifier)
    }

    private static func claudeMonth(_ value: String) -> Int? {
        let key = String(value.lowercased().prefix(3))
        return [
            "jan": 1, "feb": 2, "mar": 3, "apr": 4,
            "may": 5, "jun": 6, "jul": 7, "aug": 8,
            "sep": 9, "oct": 10, "nov": 11, "dec": 12,
        ][key]
    }

    private static func capturedInteger(
        _ match: NSTextCheckingResult,
        at index: Int,
        in value: String
    ) -> Int? {
        guard index < match.numberOfRanges,
              match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: value) else {
            return nil
        }
        return Int(value[range])
    }

    private static func capturedString(
        _ match: NSTextCheckingResult,
        at index: Int,
        in value: String
    ) -> String? {
        guard index < match.numberOfRanges,
              match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: value) else {
            return nil
        }
        return String(value[range])
    }

    private static func normalizedUsageLabel(_ value: String) -> String {
        String(value.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains))
    }

    private static func strippingTerminalControlSequences(_ output: String) -> String {
        let scalars = Array(output.unicodeScalars)
        var plain = String.UnicodeScalarView()
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]
            if scalar.value == 0x1B {
                index += 1
                guard index < scalars.count else { break }
                if scalars[index] == "[" {
                    index += 1
                    while index < scalars.count {
                        let value = scalars[index].value
                        index += 1
                        if (0x40...0x7E).contains(value) { break }
                    }
                } else if scalars[index] == "]" {
                    index += 1
                    while index < scalars.count {
                        if scalars[index].value == 0x07 {
                            index += 1
                            break
                        }
                        if scalars[index].value == 0x1B,
                           index + 1 < scalars.count,
                           scalars[index + 1] == "\\" {
                            index += 2
                            break
                        }
                        index += 1
                    }
                } else {
                    index += 1
                }
                continue
            }

            if scalar.value == 0x0D {
                plain.append("\n")
            } else if scalar.value == 0x0A || scalar.value == 0x09 || scalar.value >= 0x20 {
                plain.append(scalar)
            }
            index += 1
        }
        return String(plain)
    }

    private static func windowDurationMinutes(_ object: [String: Any]) -> Int? {
        integer(object["windowDurationMins"])
            ?? integer(object["window_minutes"])
            ?? integer(object["windowDurationMinutes"])
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as NSNumber: value.doubleValue
        case let value as String: Double(value)
        default: nil
        }
    }

    private static func integer(_ value: Any?) -> Int? {
        switch value {
        case let value as NSNumber: value.intValue
        case let value as String: Int(value)
        default: nil
        }
    }

    private static func date(_ value: Any?) -> Date? {
        if let seconds = number(value) {
            return Date(timeIntervalSince1970: seconds)
        }
        guard let value = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}

public enum ProviderCapacityFile {
    public static func load(from url: URL) throws -> ProviderCapacitySnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            ProviderCapacitySnapshot.self,
            from: Data(contentsOf: url)
        )
    }

    public static func write(
        _ snapshot: ProviderCapacitySnapshot,
        to url: URL,
        fileManager: FileManager = .default
    ) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: url, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}
