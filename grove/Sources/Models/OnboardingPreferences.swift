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

enum CaptureType: String, CaseIterable, Identifiable {
    case links, notes, courses
    var id: String { rawValue }
    var label: String {
        switch self {
        case .links: return "Links & articles"
        case .notes: return "Notes & ideas"
        case .courses: return "Course materials"
        }
    }
}

enum OrganizeStyle: String, CaseIterable, Identifiable {
    case byProject, byTopic, figureItOut
    var id: String { rawValue }
    var label: String {
        switch self {
        case .byProject: return "By project"
        case .byTopic: return "By topic or interest"
        case .figureItOut: return "I'll figure it out"
        }
    }
}

enum OnboardingGoal: String, CaseIterable, Identifiable {
    case research, journaling, aiThinking
    var id: String { rawValue }
    var label: String {
        switch self {
        case .research: return "Research & reading"
        case .journaling: return "Journaling & reflection"
        case .aiThinking: return "AI-powered thinking"
        }
    }
}

struct OnboardingPreferences: Sendable {
    private static var defaults: UserDefaults { UserDefaults.standard }
    private static let key = "grove.onboarding.useCases"
    private static let captureKey = "grove.onboarding.captureTypes"
    private static let organizeKey = "grove.onboarding.organizeStyle"
    private static let goalsKey = "grove.onboarding.goals"

    static var selectedUseCases: Set<GroveUseCase> {
        get {
            guard let raw = defaults.stringArray(forKey: key) else { return [] }
            return Set(raw.compactMap { GroveUseCase(rawValue: $0) })
        }
        set {
            defaults.set(Array(newValue.map(\.rawValue)), forKey: key)
        }
    }

    static var captureTypes: Set<CaptureType> {
        get {
            guard let raw = defaults.stringArray(forKey: captureKey) else { return [] }
            return Set(raw.compactMap { CaptureType(rawValue: $0) })
        }
        set {
            defaults.set(Array(newValue.map(\.rawValue)), forKey: captureKey)
        }
    }

    static var organizeStyle: OrganizeStyle? {
        get {
            guard let raw = defaults.string(forKey: organizeKey) else { return nil }
            return OrganizeStyle(rawValue: raw)
        }
        set {
            defaults.set(newValue?.rawValue, forKey: organizeKey)
        }
    }

    static var goals: Set<OnboardingGoal> {
        get {
            guard let raw = defaults.stringArray(forKey: goalsKey) else { return [] }
            return Set(raw.compactMap { OnboardingGoal(rawValue: $0) })
        }
        set {
            defaults.set(Array(newValue.map(\.rawValue)), forKey: goalsKey)
        }
    }
}
