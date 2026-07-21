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
}

public enum CapacityPolicy {
    public static let warningRemainingPercentage = 20.0
    public static let freshnessInterval: TimeInterval = 10 * 60

    public static func isApproximate(
        _ window: CapacityWindowSnapshot,
        refreshFailed: Bool,
        now: Date = .now
    ) -> Bool {
        refreshFailed || now.timeIntervalSince(window.observedAt) > freshnessInterval
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

    private static func claudeWindow(
        _ object: [String: Any]?,
        kind: CapacityWindowKind,
        observedAt: Date
    ) -> CapacityWindowSnapshot? {
        guard let object,
              let usedPercentage = number(object["used_percentage"]) else {
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
