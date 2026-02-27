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

    /// Fetch the first instance matching an optional predicate.
    /// Returns nil on failure or if no match is found.
    func fetchFirst<T: PersistentModel>(
        where predicate: Predicate<T>? = nil
    ) -> T? {
        var descriptor = FetchDescriptor<T>(predicate: predicate)
        descriptor.fetchLimit = 1
        return (try? fetch(descriptor))?.first
    }
}
