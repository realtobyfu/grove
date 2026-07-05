import Foundation
import NaturalLanguage

/// On-device semantic index over the knowledge base.
/// Embeds items with NLEmbedding sentence vectors, caches them on disk keyed by
/// item ID + content hash, and answers similarity queries with brute-force cosine —
/// fine at personal-KB scale (thousands of items).
///
/// Embeddings are derivable data and stay local: they are never written to
/// SwiftData or synced via CloudKit.
actor EmbeddingIndexService {
    static let shared = EmbeddingIndexService()

    /// Plain-data view of an Item, safe to pass into the actor.
    struct ItemSnapshot: Sendable {
        let id: UUID
        let text: String
    }

    private struct Entry: Codable {
        let contentHash: UInt64
        let vector: [Double]
    }

    private var entries: [UUID: Entry] = [:]
    private var loaded = false
    private var embedding: NLEmbedding?
    private var embeddingLoadAttempted = false
    private let cacheURL: URL

    init(cacheURL: URL? = nil) {
        if let cacheURL {
            self.cacheURL = cacheURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.cacheURL = support.appendingPathComponent("Grove", isDirectory: true)
                .appendingPathComponent("embedding-index.json")
        }
    }

    /// Build the text that represents an item in embedding space.
    @MainActor
    static func snapshot(_ item: Item) -> ItemSnapshot {
        var parts = [item.title]
        let tags = item.tags.map(\.name).joined(separator: ", ")
        if !tags.isEmpty { parts.append(tags) }
        if let summary = item.metadata["summary"], !summary.isEmpty { parts.append(summary) }
        if let content = item.content, !content.isEmpty {
            parts.append(String(content.prefix(1000)))
        }
        for reflection in item.reflections.prefix(3) {
            parts.append(String(reflection.content.prefix(300)))
        }
        return ItemSnapshot(id: item.id, text: parts.joined(separator: "\n"))
    }

    // MARK: - Indexing

    /// Embed any snapshots that are new or whose content changed. Prunes entries
    /// for items no longer present. Saves the cache when anything changed.
    func indexItems(_ snapshots: [ItemSnapshot]) {
        loadIfNeeded()
        guard let embedding = loadEmbedding() else { return }

        var changed = false
        let currentIDs = Set(snapshots.map(\.id))

        for snapshot in snapshots {
            let hash = Self.stableHash(snapshot.text)
            if let existing = entries[snapshot.id], existing.contentHash == hash { continue }
            guard let vector = embedding.vector(for: Self.embeddableText(snapshot.text)) else { continue }
            entries[snapshot.id] = Entry(contentHash: hash, vector: vector)
            changed = true
        }

        let stale = entries.keys.filter { !currentIDs.contains($0) }
        if !stale.isEmpty {
            for id in stale { entries.removeValue(forKey: id) }
            changed = true
        }

        if changed { save() }
    }

    // MARK: - Queries

    /// Items semantically closest to a free-text query.
    func search(query: String, limit: Int, minScore: Double = 0.55) -> [(id: UUID, score: Double)] {
        loadIfNeeded()
        guard let embedding = loadEmbedding(),
              let queryVector = embedding.vector(for: Self.embeddableText(query)) else {
            return []
        }

        return entries
            .map { (id: $0.key, score: Self.cosineSimilarity(queryVector, $0.value.vector)) }
            .filter { $0.score >= minScore }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    /// High-similarity pairs among the given item IDs, for tension detection.
    func similarPairs(among ids: [UUID], minScore: Double = 0.7, limit: Int = 40) -> [(a: UUID, b: UUID, score: Double)] {
        loadIfNeeded()
        let candidates = ids.compactMap { id in entries[id].map { (id: id, vector: $0.vector) } }

        var pairs: [(a: UUID, b: UUID, score: Double)] = []
        for i in 0..<candidates.count {
            for j in (i + 1)..<candidates.count {
                let score = Self.cosineSimilarity(candidates[i].vector, candidates[j].vector)
                if score >= minScore {
                    pairs.append((a: candidates[i].id, b: candidates[j].id, score: score))
                }
            }
        }
        return Array(pairs.sorted { $0.score > $1.score }.prefix(limit))
    }

    func vector(for id: UUID) -> [Double]? {
        loadIfNeeded()
        return entries[id]?.vector
    }

    var indexedCount: Int {
        loadIfNeeded()
        return entries.count
    }

    // MARK: - Embedding

    private func loadEmbedding() -> NLEmbedding? {
        if !embeddingLoadAttempted {
            embeddingLoadAttempted = true
            embedding = NLEmbedding.sentenceEmbedding(for: .english)
        }
        return embedding
    }

    /// Sentence embeddings degrade on very long inputs — embed a bounded prefix.
    private static func embeddableText(_ text: String) -> String {
        String(text.prefix(1500))
    }

    static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / ((normA * normB).squareRoot())
    }

    /// FNV-1a — stable across launches, unlike Hasher.
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    // MARK: - Persistence

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode([UUID: Entry].self, from: data) else {
            return
        }
        entries = decoded
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(entries)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // Cache write failure is non-fatal — index rebuilds next launch
        }
    }
}
