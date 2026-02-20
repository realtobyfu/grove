import Foundation

enum AppConstants {
    // MARK: - Time Windows (Days)
    enum Days {
        /// Recent activity window (nudge engagement, weekly digest, etc.)
        static let recent: Int = 7
        /// Stale/inactive threshold (resurface nudges, inbox staleness)
        static let stale: Int = 14
        /// Longer cooldown (dismissed nudge suppression, legacy resurface)
        static let cooldown: Int = 30
        /// Deep inactivity (resurfacing interval reset)
        static let deepInactivity: Int = 60
    }

    // MARK: - Connection Scoring
    enum Scoring {
        /// Minimum heuristic score to suggest a connection
        static let connectionSuggestionFloor: Double = 0.15
        /// Minimum heuristic score for auto-connect fallback
        static let autoConnectHeuristicFloor: Double = 0.5
        /// LLM confidence required for auto-connecting items
        static let autoConnectLLMConfidence: Double = 0.7
        /// Maximum auto-connections created per item
        static let maxAutoConnections: Int = 2
        /// Minimum other items required for meaningful auto-connect signal
        static let minItemsForAutoConnect: Int = 5
        /// Tag similarity threshold for merge suggestions
        static let tagMergeSimilarity: Double = 0.75
    }

    // MARK: - Nudge
    enum Nudge {
        /// High engagement = acted on N+ nudges in recent window
        static let highEngagementThreshold: Int = 3
        /// Stale inbox nudge fires when inbox has N+ old items
        static let staleInboxMinCount: Int = 5
    }

    // MARK: - LLM Context Limits
    enum LLM {
        /// Max candidate items sent to LLM for connection/nudge prompts
        static let maxCandidateItems: Int = 50
        /// Max content characters in item descriptions for LLM
        static let defaultContentLimit: Int = 1000
        /// Summary character cap
        static let summaryMaxLength: Int = 120
        /// Reason/explanation text cap
        static let reasonMaxLength: Int = 80
        /// Reflection prompt text cap
        static let promptMaxLength: Int = 150
        /// JPEG compression quality for downloaded images
        static let imageCompressionQuality: Double = 0.7
    }

    // MARK: - Activity Thresholds
    enum Activity {
        /// Minimum items added for weekly digest generation
        static let digestMinItems: Int = 2
        /// Minimum reflections for weekly digest (alternative to item count)
        static let digestMinReflections: Int = 1
        /// Minimum items for synthesis
        static let synthesisMinItems: Int = 2
        /// Maximum items for synthesis
        static let synthesisMaxItems: Int = 30
        /// Common tag threshold (appears in N+ items) for synthesis
        static let commonTagThreshold: Int = 2
    }

    // MARK: - Capture
    enum Capture {
        /// Auto-dismiss delay for inline board suggestions shown after capture.
        static let boardSuggestionAutoDismissSeconds: Int = 5
    }
}
