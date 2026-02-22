import Foundation

enum GroveUseCase: String, CaseIterable, Identifiable {
    case reading, notes, projects, learning, journaling

    var id: String { rawValue }

    var label: String {
        switch self {
        case .reading: return "Reading & Research"
        case .notes: return "Notes & Writing"
        case .projects: return "Project Organization"
        case .learning: return "Courses & Learning"
        case .journaling: return "Journaling & Reflection"
        }
    }
}

struct OnboardingPreferences: Sendable {
    private static var defaults: UserDefaults { UserDefaults.standard }
    private static let key = "grove.onboarding.useCases"

    static var selectedUseCases: Set<GroveUseCase> {
        get {
            guard let raw = defaults.stringArray(forKey: key) else { return [] }
            return Set(raw.compactMap { GroveUseCase(rawValue: $0) })
        }
        set {
            defaults.set(Array(newValue.map(\.rawValue)), forKey: key)
        }
    }
}
