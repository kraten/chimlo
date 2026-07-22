import Foundation

public enum SystemFeedbackKind: String, Equatable, Sendable {
    case outputVolume
    case displayBrightness
}

public struct SystemFeedbackPresentation: Equatable, Sendable {
    public let kind: SystemFeedbackKind
    public let value: Double
    public let isMuted: Bool

    public init(kind: SystemFeedbackKind, value: Double, isMuted: Bool = false) {
        self.kind = kind
        self.value = SystemFeedbackPolicy.clamp(value)
        self.isMuted = kind == .outputVolume && isMuted
    }

    public var percentage: Int {
        Int((value * 100).rounded())
    }

    public var accessibilityDescription: String {
        switch kind {
        case .outputVolume:
            if isMuted || value == 0 { return "Output volume muted" }
            return "Output volume \(percentage) percent"
        case .displayBrightness:
            return "Display brightness \(percentage) percent"
        }
    }
}

public enum SystemFeedbackPolicy {
    public static let holdMilliseconds = 2_000
    public static let meterCellCount = 8
    public static let standardStep = 1.0 / 16.0
    public static let fineStep = 1.0 / 64.0

    public static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    public static func adjustedValue(from value: Double, direction: Int, fine: Bool) -> Double {
        let step = fine ? fineStep : standardStep
        return clamp(value + (direction < 0 ? -step : step))
    }

    public static func meterFillWidth(for value: Double, trackWidth: Double) -> Double {
        clamp(value) * max(0, trackWidth)
    }
}
