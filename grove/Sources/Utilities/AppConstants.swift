import Foundation

enum AppConstants {
    // MARK: - External URLs
    enum URLs {
        static let privacyPolicy = URL(string: "https://realtobyfu.github.io/grove/PRIVACY")
        static let support = URL(string: "https://realtobyfu.github.io/grove/SUPPORT")
        static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
        static let manageSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")
    }

    // MARK: - Capture
    enum Capture {
        /// Auto-dismiss delay for inline board suggestions shown after capture.
        static let boardSuggestionAutoDismissSeconds: Int = 5
    }
}
