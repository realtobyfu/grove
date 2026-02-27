import Foundation

enum MainActorTaskScheduler {
    @discardableResult
    static func schedule(
        after delay: Duration,
        _ operation: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            operation()
        }
    }
}
