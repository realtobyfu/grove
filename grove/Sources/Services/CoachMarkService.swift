import Foundation

enum CoachMarkStep: Int, CaseIterable, Sendable {
    case saveLink
    case createBoard
    case assignToBoard
    case tryDialectics
}

@MainActor
@Observable
final class CoachMarkService {
    static let shared = CoachMarkService()

    nonisolated private static let completedKey = "grove.coachMarks.completed"

    private let defaults: UserDefaults

    private(set) var isActive = false
    private(set) var currentStep: CoachMarkStep?
    private(set) var isComplete: Bool
    private(set) var showCompletionToast = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isComplete = defaults.bool(forKey: Self.completedKey)
    }

    func startGuide() {
        guard !isComplete else { return }
        isActive = true
        currentStep = .saveLink
    }

    func advanceStep() {
        guard isActive, let current = currentStep else { return }
        let allSteps = CoachMarkStep.allCases
        guard let index = allSteps.firstIndex(of: current) else { return }
        let nextIndex = index + 1
        if nextIndex < allSteps.count {
            currentStep = allSteps[nextIndex]
        } else {
            completeGuide()
        }
    }

    func skipStep() {
        advanceStep()
    }

    func dismissGuide() {
        isActive = false
        currentStep = nil
        isComplete = true
        defaults.set(true, forKey: Self.completedKey)
    }

    private func completeGuide() {
        isActive = false
        currentStep = nil
        isComplete = true
        defaults.set(true, forKey: Self.completedKey)
        showCompletionToast = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            showCompletionToast = false
        }
    }
}
