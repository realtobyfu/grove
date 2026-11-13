import Foundation
import SwiftData

extension ModelContext {
    /// Fetch all instances of a model type, with optional sort and predicate.
    /// Returns an empty array on failure instead of throwing.
    func fetchAll<T: PersistentModel>(
        sortBy: [SortDescriptor<T>] = [],
        predicate: Predicate<T>? = nil
    ) -> [T] {
        let descriptor = FetchDescriptor<T>(predicate: predicate, sortBy: sortBy)
        return (try? fetch(descriptor)) ?? []
    }
}
