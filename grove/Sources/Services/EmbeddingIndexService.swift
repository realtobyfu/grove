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

    /// An embedded query, tagged with the language space it lives in. Vectors
    /// from different languages are not comparable, so callers must carry the
    /// language alongside the vector.
    struct EmbeddedText: Sendable {
        let language: String
        let vector: [Double]
    }

    private struct Entry: Codable {
        let contentHash: UInt64
        let language: String   // NLLanguage.rawValue of the embedding space
        let vector: [Double]
    }

    private var entries: [UUID: Entry] = [:]
    private var loaded = false
    /// Sentence embeddings memoized per language; a nil marks a language with no
    /// available embedding so we don't retry loading it.
    private var embeddings: [String: NLEmbedding] = [:]
    private var embeddingMisses: Set<String> = []
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

        var changed = false
        let currentIDs = Set(snapshots.map(\.id))

        for snapshot in snapshots {
            let hash = Self.stableHash(snapshot.text)
            if let existing = entries[snapshot.id], existing.contentHash == hash { continue }
            guard let embedded = embed(snapshot.text) else { continue }
            entries[snapshot.id] = Entry(contentHash: hash, language: embedded.language, vector: embedded.vector)
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

    /// Items semantically closest to a free-text query. Only entries embedded in
    /// the query's detected language are comparable.
    func search(query: String, limit: Int, minScore: Double = 0.55) -> [(id: UUID, score: Double)] {
        loadIfNeeded()
        guard let embedded = embed(query) else { return [] }

        return entries
            .filter { $0.value.language == embedded.language }
            .map { (id: $0.key, score: Self.cosineSimilarity(embedded.vector, $0.value.vector)) }
            .filter { $0.score >= minScore }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    /// High-similarity pairs among the given item IDs, for tension detection.
    /// Pairs are only formed within a shared language space.
    func similarPairs(among ids: [UUID], minScore: Double = 0.7, limit: Int = 40) -> [(a: UUID, b: UUID, score: Double)] {
        loadIfNeeded()
        let candidates = ids.compactMap { id in
            entries[id].map { (id: id, language: $0.language, vector: $0.vector) }
        }

        var pairs: [(a: UUID, b: UUID, score: Double)] = []
        for i in 0..<candidates.count {
            for j in (i + 1)..<candidates.count {
                guard candidates[i].language == candidates[j].language else { continue }
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

    /// Embed arbitrary text without touching the cache — for ad-hoc ranking of
    /// items (e.g. a freshly captured item) that may not be indexed yet. Detects
    /// the text's language and uses the matching sentence embedding; returns nil
    /// when no embedding is available for that language.
    func embed(_ text: String) -> EmbeddedText? {
        let language = Self.detectLanguage(text)
        guard let embedding = embedding(for: language),
              let vector = embedding.vector(for: Self.embeddableText(text)) else {
            return nil
        }
        return EmbeddedText(language: language.rawValue, vector: vector)
    }

    /// Cosine similarity of `query` against each cached id in the same language
    /// space, in one actor hop. Ids without a comparable cached vector are omitted.
    func similarities(to query: EmbeddedText, among ids: [UUID]) -> [UUID: Double] {
        loadIfNeeded()
        var result: [UUID: Double] = [:]
        for id in ids {
            guard let entry = entries[id], entry.language == query.language else { continue }
            result[id] = Self.cosineSimilarity(query.vector, entry.vector)
        }
        return result
    }

    var indexedCount: Int {
        loadIfNeeded()
        return entries.count
    }

    // MARK: - Embedding

    /// Memoized sentence embedding for a language, or nil if none is available.
    private func embedding(for language: NLLanguage) -> NLEmbedding? {
        let key = language.rawValue
        if let cached = embeddings[key] { return cached }
        if embeddingMisses.contains(key) { return nil }
        if let embedding = NLEmbedding.sentenceEmbedding(for: language) {
            embeddings[key] = embedding
            return embedding
        }
        embeddingMisses.insert(key)
        return nil
    }

    /// Dominant language of the text, defaulting to English when undetermined.
    private static func detectLanguage(_ text: String) -> NLLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage ?? .english
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
