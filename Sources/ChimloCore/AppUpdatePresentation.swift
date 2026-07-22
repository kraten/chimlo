import Foundation

public enum AppUpdatePhase: Equatable, Sendable {
    case available
    case checking
    case upToDate
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
        case .upToDate:
            "Chimlo is up to date"
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

    public var statusText: String {
        switch phase {
        case .available:
            "Update available"
        case .checking:
            "Checking for updates…"
        case .upToDate:
            "Chimlo is up to date"
        case .downloading:
            if let progress = normalizedProgress {
                "Downloading update: \(Int((progress * 100).rounded()))%"
            } else {
                "Downloading update…"
            }
        case .preparing:
            "Preparing update…"
        case .installing:
            "Installing and relaunching…"
        case .failed:
            "Couldn’t check for updates"
        }
    }

    public var actionTitle: String {
        switch phase {
        case .available:
            Self.availableTitle
        case .checking:
            "Checking…"
        case .upToDate:
            "Check Again"
        case .downloading:
            "Downloading…"
        case .preparing:
            "Preparing…"
        case .installing:
            "Installing…"
        case .failed:
            "Try Again"
        }
    }

    public var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .preparing, .installing:
            true
        case .available, .upToDate, .failed:
            false
        }
    }

    public var isActionable: Bool {
        switch phase {
        case .available, .upToDate, .failed:
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
        guard let presentation, !hasOwnerInteraction, !isOnboarding else { return false }
        return presentation.phase != .upToDate
    }
}
