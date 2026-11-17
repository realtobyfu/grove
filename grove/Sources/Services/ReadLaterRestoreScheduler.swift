import Foundation
import SwiftData

/// Returns Read Later items to the inbox when they come due: once on start,
/// then every minute until stopped.
@MainActor
final class ReadLaterRestoreScheduler {
    private let readLaterService: ReadLaterService
    private var task: Task<Void, Never>?

    init(modelContext: ModelContext) {
        self.readLaterService = ReadLaterService(modelContext: modelContext)
    }

    /// Call once on app launch.
    func start() {
        guard task == nil else { return }
        restoreDueItems()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { break }
                self?.restoreDueItems()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func restoreDueItems() {
        _ = readLaterService.restoreDueItems()
    }
}
