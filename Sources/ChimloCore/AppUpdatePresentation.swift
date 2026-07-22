import Foundation

public enum AppUpdatePhase: Equatable, Sendable {
    case available
    case checking
    case downloading(progress: Double?)
    case preparing
    case installing
    case failed
}

public struct AppUpdatePresentation: Equatable, Sendable {
    public static let availableTitle = "Update to latest version"

    public let phase: AppUpdatePhase

    public init(phase: AppUpdatePhase) {
        self.phase = phase
    }

    public var title: String {
        switch phase {
        case .available:
            Self.availableTitle
        case .checking:
            "Checking for update"
        case .downloading:
            "Downloading update"
        case .preparing:
            "Preparing update"
        case .installing:
            "Installing update"
        case .failed:
            "Try update again"
        }
    }

    public var isActionable: Bool {
        switch phase {
        case .available, .failed:
            true
        case .checking, .downloading, .preparing, .installing:
            false
        }
    }

    public var normalizedProgress: Double? {
        guard case let .downloading(progress?) = phase else { return nil }
        return min(1, max(0, progress))
    }
}

public enum AppUpdatePresentationPolicy {
    public static func shouldTakeIdlePanel(
        presentation: AppUpdatePresentation?,
        hasOwnerInteraction: Bool,
        isOnboarding: Bool
    ) -> Bool {
        presentation != nil && !hasOwnerInteraction && !isOnboarding
    }
}
