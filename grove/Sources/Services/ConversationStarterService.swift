import Foundation
import SwiftData
import Observation

// MARK: - Protocol

@MainActor protocol ConversationStarterServiceProtocol {
    var bubbles: [PromptBubble] { get }
    var isLoading: Bool { get }
    func refresh(items: [Item]) async
    func forceRefresh(items: [Item]) async
    func bubbles(for boardID: UUID, maxResults: Int) -> [PromptBubble]
    func refreshBoard(_ boardID: UUID, items: [Item]) async
    func forceRefreshBoard(_ boardID: UUID, items: [Item]) async
}

// MARK: - ConversationStarterService

/// Generates up to 3 contextual conversation starters for the HomeView prompt bubbles.
/// Delegates to `StarterContextBuilder`, `StarterLLMGenerator`, and
/// `StarterHeuristicGenerator` for the heavy lifting.
/// Results are persisted to UserDefaults (TTL: 8 hours) so they appear instantly on relaunch.
@MainActor @Observable final class ConversationStarterService: ConversationStarterServiceProtocol {
    static let shared = ConversationStarterService()

    private(set) var bubbles: [PromptBubble] = []
    private(set) var boardBubbles: [UUID: [PromptBubble]] = [:]
    private(set) var isLoading: Bool = false

    /// Whether this service has fetched starters for the current launch.
    private var hasLoaded: Bool = false
    /// Track which boards have been loaded this launch.
    private var loadedBoards: Set<UUID> = []
    /// Track if we already showed the unboarded-cluster bubble this launch (show at most once).
    private(set) var didShowClusterBubble: Bool = false

    private let provider: LLMProvider

    // MARK: - Tier Constants

    static let maxBubbleCountPro = 3
    static let maxBubbleCountFree = 2

    private static var maxBubbleCount: Int {
        EntitlementService.currentTier == .pro ? maxBubbleCountPro : maxBubbleCountFree
    }

    // MARK: - Init

    init(provider: LLMProvider = LLMServiceConfig.makeProvider()) {
        self.provider = provider
        // Only load cache for Pro users — prevents stale Pro bubbles showing after downgrade
        if EntitlementService.currentTier == .pro, let cached = Self.loadCachedBubbles() {
            self.bubbles = cached
        }
    }

    // MARK: - Public API

    /// Refreshes the prompt bubbles if not already loaded for this launch.
    /// Cached bubbles are shown immediately (from init); this replaces them with fresh ones.
    func refresh(items: [Item]) async {
        guard !hasLoaded else { return }
        hasLoaded = true
        isLoading = true
        defer { isLoading = false }

        let context = StarterContextBuilder.buildContext(from: items)
        let isPro = await EntitlementService.shared.isPro
        let cap = isPro ? Self.maxBubbleCountPro : Self.maxBubbleCountFree

        if isPro {
            // Pro: attempt full LLM generation, fall back to heuristics
            if let llmBubbles = await generateViaLLM(context: context) {
                bubbles = Array(llmBubbles.prefix(cap))
                Self.saveCachedBubbles(bubbles)
            } else {
                let heuristics = StarterHeuristicGenerator.buildHeuristics(
                    context: context,
                    didShowClusterBubble: didShowClusterBubble
                )
                if !heuristics.isEmpty {
                    bubbles = Array(heuristics.prefix(cap))
                    Self.saveCachedBubbles(bubbles)
                }
                // Update cluster flag if heuristics included an ORGANIZE bubble
                if heuristics.contains(where: { $0.clusterTag != nil }) {
                    didShowClusterBubble = true
                }
            }
        } else {
            // Free: attempt 1 LLM bubble, always include 1 heuristic fallback
            let heuristics = StarterHeuristicGenerator.buildHeuristics(
                context: context,
                didShowClusterBubble: didShowClusterBubble
            )
            if heuristics.contains(where: { $0.clusterTag != nil }) {
                didShowClusterBubble = true
            }
            if let llmBubbles = await generateViaLLM(context: context), let first = llmBubbles.first {
                var result = [first]
                if let heuristic = heuristics.first(where: { $0.prompt != first.prompt }) {
                    result.append(heuristic)
                } else if heuristics.count > 1 {
                    result.append(heuristics[1])
                } else if let fallback = heuristics.first {
                    result.append(fallback)
                }
                bubbles = Array(result.prefix(cap))
            } else {
                bubbles = Array(heuristics.prefix(cap))
            }
            Self.saveCachedBubbles(bubbles)
        }
    }

    func forceRefresh(items: [Item]) async {
        hasLoaded = false
        await refresh(items: items)
    }

    func bubbles(for boardID: UUID, maxResults: Int) -> [PromptBubble] {
        guard maxResults > 0 else { return [] }
        if let cached = boardBubbles[boardID] {
            return Array(cached.prefix(maxResults))
        }
        // Fall back to filtering global pool
        return Array(
            bubbles
                .filter { $0.boardIDs.contains(boardID) }
                .prefix(maxResults)
        )
    }

    /// Lazily generates board-scoped starters. Returns cached results immediately if available.
    func refreshBoard(_ boardID: UUID, items: [Item]) async {
        guard !loadedBoards.contains(boardID) else { return }
        loadedBoards.insert(boardID)

        // Try loading from disk cache first
        if let cached = Self.loadCachedBoardBubbles(for: boardID), !cached.isEmpty {
            boardBubbles[boardID] = cached
            return
        }

        // Generate board-specific starters
        let boardItems = items.filter { $0.boards.contains(where: { $0.id == boardID }) }
        let context = StarterContextBuilder.buildContext(from: boardItems)
        let isPro = await EntitlementService.shared.isPro
        let cap = isPro ? Self.maxBubbleCountPro : Self.maxBubbleCountFree

        var result: [PromptBubble] = []
        if isPro, let llmBubbles = await generateViaLLM(context: context) {
            result = Array(llmBubbles.prefix(cap))
        } else {
            result = Array(
                StarterHeuristicGenerator.buildBoardHeuristics(context: context, boardID: boardID)
                    .prefix(cap)
            )
        }

        boardBubbles[boardID] = result
        if !result.isEmpty {
            Self.saveCachedBoardBubbles(result, for: boardID)
        }
    }

    func forceRefreshBoard(_ boardID: UUID, items: [Item]) async {
        loadedBoards.remove(boardID)
        boardBubbles[boardID] = nil
        Self.clearCachedBoardBubbles(for: boardID)
        await refreshBoard(boardID, items: items)
    }

    // MARK: - LLM Delegation

    private func generateViaLLM(context: StarterContext) async -> [PromptBubble]? {
        let result = await StarterLLMGenerator.generate(
            context: context,
            didShowClusterBubble: didShowClusterBubble,
            provider: provider
        )
        if result?.contains(where: { $0.clusterTag != nil }) == true {
            didShowClusterBubble = true
        }
        return result
    }

    // MARK: - Disk Cache

    private struct CachedBubble: Codable {
        let prompt: String
        let label: String
        let clusterTag: String?
        let clusterItemIDs: [UUID]
        let boardIDs: [UUID]?
    }

    private static let cacheKey = "grove.conversationStarters"
    private static let cacheTTLSeconds: TimeInterval = 8 * 3600  // 8 hours

    private static func saveCachedBubbles(_ bubbles: [PromptBubble]) {
        let encoded = bubbles.map {
            CachedBubble(
                prompt: $0.prompt,
                label: $0.label,
                clusterTag: $0.clusterTag,
                clusterItemIDs: $0.clusterItemIDs,
                boardIDs: $0.boardIDs
            )
        }
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        let entry: [String: Any] = ["data": data, "timestamp": Date().timeIntervalSince1970]
        UserDefaults.standard.set(entry, forKey: cacheKey)
    }

    private static func loadCachedBubbles() -> [PromptBubble]? {
        guard let entry = UserDefaults.standard.dictionary(forKey: cacheKey),
              let data = entry["data"] as? Data,
              let timestamp = entry["timestamp"] as? TimeInterval else { return nil }

        let age = Date().timeIntervalSince1970 - timestamp
        guard age < cacheTTLSeconds else { return nil }

        guard let cached = try? JSONDecoder().decode([CachedBubble].self, from: data) else { return nil }
        let cap = maxBubbleCount
        return Array(
            cached
                .map {
                    PromptBubble(
                        prompt: $0.prompt,
                        label: $0.label,
                        clusterTag: $0.clusterTag,
                        clusterItemIDs: $0.clusterItemIDs,
                        boardIDs: $0.boardIDs ?? []
                    )
                }
                .prefix(cap)
        )
    }

    // MARK: - Per-Board Cache

    private static func boardCacheKey(for boardID: UUID) -> String {
        "\(cacheKey).board.\(boardID.uuidString)"
    }

    private static func saveCachedBoardBubbles(_ bubbles: [PromptBubble], for boardID: UUID) {
        let encoded = bubbles.map {
            CachedBubble(
                prompt: $0.prompt,
                label: $0.label,
                clusterTag: $0.clusterTag,
                clusterItemIDs: $0.clusterItemIDs,
                boardIDs: $0.boardIDs
            )
        }
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        let entry: [String: Any] = ["data": data, "timestamp": Date().timeIntervalSince1970]
        UserDefaults.standard.set(entry, forKey: boardCacheKey(for: boardID))
    }

    private static func loadCachedBoardBubbles(for boardID: UUID) -> [PromptBubble]? {
        let key = boardCacheKey(for: boardID)
        guard let entry = UserDefaults.standard.dictionary(forKey: key),
              let data = entry["data"] as? Data,
              let timestamp = entry["timestamp"] as? TimeInterval else { return nil }

        let age = Date().timeIntervalSince1970 - timestamp
        guard age < cacheTTLSeconds else { return nil }

        guard let cached = try? JSONDecoder().decode([CachedBubble].self, from: data) else { return nil }
        return cached.map {
            PromptBubble(
                prompt: $0.prompt,
                label: $0.label,
                clusterTag: $0.clusterTag,
                clusterItemIDs: $0.clusterItemIDs,
                boardIDs: $0.boardIDs ?? []
            )
        }
    }

    private static func clearCachedBoardBubbles(for boardID: UUID) {
        UserDefaults.standard.removeObject(forKey: boardCacheKey(for: boardID))
    }
}
