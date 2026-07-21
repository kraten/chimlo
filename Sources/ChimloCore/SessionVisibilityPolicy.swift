import Foundation

public enum SessionVisibilityPolicy {
    public static func shouldDisplay(
        title: String,
        titleKind: SessionTitleKind,
        isDemo: Bool,
        hasActionableRequest: Bool,
        hasConversationPreview: Bool = false,
        agent: AgentKind? = nil,
        model: String? = nil
    ) -> Bool {
        guard !isCodexAutoReview(agent: agent, model: model) else { return false }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        // Workspace basenames alone are discovery fallbacks, not session
        // titles. A transient conversation preview is stronger evidence of a
        // real session, while remaining excluded from Chimlo's saved registry.
        return titleKind == .task
            || isDemo
            || hasActionableRequest
            || hasConversationPreview
    }

    private static func isCodexAutoReview(agent: AgentKind?, model: String?) -> Bool {
        guard agent == .codex, let model else { return false }
        let normalizedModel = model
            .lowercased()
            .split { $0 == "-" || $0 == "_" || $0.isWhitespace }
            .joined(separator: "-")
        return normalizedModel == "codex-auto-review"
    }
}
