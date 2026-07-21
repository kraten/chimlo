import Foundation

public enum SessionVisibilityPolicy {
    public static func shouldDisplay(
        title: String,
        titleKind: SessionTitleKind,
        isDemo: Bool,
        hasActionableRequest: Bool
    ) -> Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        // Workspace basenames are discovery fallbacks, not session titles.
        // Keep only deliberate exceptions where hiding the row would break an
        // onboarding beat or conceal an action the owner must resolve.
        return titleKind == .task || isDemo || hasActionableRequest
    }
}
