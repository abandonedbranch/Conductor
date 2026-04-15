enum ProjectionBudget {
    static let contextProjection         = 512
    static let actionsProjection         = 256
    static let findRelatedResults        = 384
    static let atomContent               = 256
    static let composeResponseProjection = 1024

    /// English heuristic: ~4 characters per token.
    static func estimatedTokens(for text: String) -> Int {
        max(1, text.count / 4)
    }

    /// Truncate `text` to fit in `characterBudget`. If truncated, append the sentinel.
    static func bound(_ text: String, characterBudget: Int, remainingHint: Int = 0) -> String {
        guard text.count > characterBudget else { return text }
        let prefix = String(text.prefix(characterBudget))
        return prefix + "\n" + truncationSentinel(remaining: remainingHint)
    }

    static func truncationSentinel(remaining: Int) -> String {
        "... [truncated; \(remaining) more entries available via findRelated]"
    }
}
