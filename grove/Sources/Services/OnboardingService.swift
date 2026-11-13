import Foundation

enum OnboardingStep: Int, CaseIterable, Codable, Sendable, Identifiable {
    case capture
    case organize
    case chat

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .capture: return "Capture"
        case .organize: return "Organize"
        case .chat: return "Chat"
        }
    }
}

struct OnboardingProgress: Codable, Sendable {
    var currentStep: OnboardingStep
    var captureCompleted: Bool
    var organizeCompleted: Bool
    var chatCompleted: Bool
    var completedVersion: Int
    var skippedAt: Date?
}

@MainActor
@Observable
final class OnboardingService {
    static let shared = OnboardingService()
    static let currentVersion = 1

    nonisolated private static let completedVersionKey = "grove.onboarding.completedVersion"
    nonisolated private static let skippedAtKey = "grove.onboarding.skippedAt"

    private let defaults: UserDefaults
    private var didEvaluateAutoPresentation = false

    private(set) var isPresented = false
    private(set) var progress: OnboardingProgress

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let completedVersion = defaults.integer(forKey: Self.completedVersionKey)
        let skippedAt = defaults.object(forKey: Self.skippedAtKey) as? Date
        self.progress = OnboardingProgress(
            currentStep: .capture,
            captureCompleted: false,
            organizeCompleted: false,
            chatCompleted: false,
            completedVersion: completedVersion,
            skippedAt: skippedAt
        )
    }

    var hasCompletedCurrentVersion: Bool {
        progress.completedVersion >= Self.currentVersion
    }

    func evaluateAutoPresentation(itemCount: Int, boardCount: Int) {
        guard !didEvaluateAutoPresentation else { return }
        didEvaluateAutoPresentation = true

        guard progress.completedVersion < Self.currentVersion else { return }
        guard progress.skippedAt == nil else { return }
        guard itemCount == 0, boardCount == 0 else { return }

        progress.currentStep = .capture
        isPresented = true
    }

    func updateProgress(captureCompleted: Bool, organizeCompleted: Bool, chatCompleted: Bool) {
        progress.captureCompleted = captureCompleted
        progress.organizeCompleted = organizeCompleted
        progress.chatCompleted = chatCompleted

        if progress.currentStep == .capture && captureCompleted {
            progress.currentStep = .organize
        }
        if progress.currentStep == .organize && organizeCompleted {
            progress.currentStep = .chat
        }
    }

    func presentReplay() {
        progress.currentStep = .capture
        isPresented = true
    }

    func skip() {
        progress.skippedAt = .now
        defaults.set(progress.skippedAt, forKey: Self.skippedAtKey)
        isPresented = false
    }

    func complete() {
        progress.completedVersion = Self.currentVersion
        defaults.set(progress.completedVersion, forKey: Self.completedVersionKey)
        progress.skippedAt = nil
        defaults.removeObject(forKey: Self.skippedAtKey)
        isPresented = false
    }
}
