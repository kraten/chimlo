import Foundation

public enum SessionDiscoveryRetentionPolicy {
    public static let activeLifetime: TimeInterval = 30 * 60
    public static let completedLifetime: TimeInterval = 5 * 60
    public static let lastResponseLifetime: TimeInterval = 24 * 60 * 60

    public static func shouldRetain(
        phase: SessionPhase,
        updatedAt: Date,
        hasActiveProcess: Bool,
        hasLastResponse: Bool,
        now: Date = .now
    ) -> Bool {
        if hasActiveProcess { return true }

        let maximumAge: TimeInterval
        switch phase {
        case .working, .waitingForApproval, .waitingForAnswer:
            maximumAge = activeLifetime
        case .completed, .failed:
            maximumAge = hasLastResponse ? lastResponseLifetime : completedLifetime
        }
        return updatedAt >= now.addingTimeInterval(-maximumAge)
    }
}
