import Foundation
import SwiftData

/// A suggested dialectical check-in with trigger context.
struct CheckInSuggestion {
    let trigger: ConversationTrigger
    let seedItems: [Item]
    let board: Board?
    let message: String
    let openingPrompt: String
}

/// Evaluates conditions for proactive dialectical conversations.
/// Four trigger types: contradiction, knowledge gap, stale items, periodic reflection.
@MainActor
protocol CheckInTriggerServiceProtocol {
    func evaluate(context: ModelContext) -> CheckInSuggestion?
}

@MainActor
final class CheckInTriggerService: CheckInTriggerServiceProtocol {

    private static let staleThresholdDays = 30
    private static let knowledgeGapMinItems = 5
    private static let knowledgeGapReflectionRatio = 0.25
    private static let periodicReflectionKey = "grove.lastPeriodicReflection"

    /// Evaluate all triggers in priority order. Returns the first match.
    func evaluate(context: ModelContext) -> CheckInSuggestion? {
        if let contradiction = checkContradictions(context: context) {
            return contradiction
        }
        if let gap = checkKnowledgeGaps(context: context) {
            return gap
        }
        if let stale = checkStaleItems(context: context) {
            return stale
        }
        if let periodic = checkPeriodicReflection(context: context) {
            return periodic
        }
        return nil
    }

    // MARK: - Contradiction Detection

    /// Items with `.contradicts` connections or opposing reflections.
    private func checkContradictions(context: ModelContext) -> CheckInSuggestion? {
        let allConnections: [Connection] = context.fetchAll()

        let contradictions = allConnections.filter { $0.type == .contradicts }
        guard let connection = contradictions.first(where: { conn in
            conn.sourceItem != nil && conn.targetItem != nil
        }) else {
            return nil
        }

        guard let source = connection.sourceItem, let target = connection.targetItem else {
            return nil
        }

        let message = "Tension detected between \"\(source.title)\" and \"\(target.title)\" — worth exploring?"

        let openingPrompt = """
        I noticed you have two items that seem to be in tension with each other: \
        [[\(source.title)]] and [[\(target.title)]]. They're marked as contradicting. \
        Let's explore this disagreement — what do you think is the core tension here? \
        Is there a way to reconcile these views, or is the contradiction genuine and productive?
        """

        return CheckInSuggestion(
            trigger: .contradictionDetected,
            seedItems: [source, target],
            board: source.boards.first,
            message: message,
            openingPrompt: openingPrompt
        )
    }

    // MARK: - Knowledge Gap Detection

    /// Boards with many items but few reflections.
    private func checkKnowledgeGaps(context: ModelContext) -> CheckInSuggestion? {
        let allBoards: [Board] = context.fetchAll()

        for board in allBoards {
            let items = board.items.filter { $0.status == .active }
            guard items.count >= Self.knowledgeGapMinItems else { continue }

            let reflectedCount = items.filter { !$0.reflections.isEmpty }.count
            let ratio = Double(reflectedCount) / Double(items.count)

            guard ratio < Self.knowledgeGapReflectionRatio else { continue }

            // Find the most engaged unreflected items
            let unreflected = items
                .filter { $0.reflections.isEmpty }
                .sorted { $0.depthScore > $1.depthScore }
            let seeds = Array(unreflected.prefix(3))
            guard !seeds.isEmpty else { continue }

            let message = "\"\(board.title)\" has \(items.count) items but only \(reflectedCount) reflections — time to dig deeper?"

            let itemNames = seeds.map { "[[\($0.title)]]" }.joined(separator: ", ")
            let openingPrompt = """
            Your board "\(board.title)" has a lot of saved material but relatively few reflections. \
            Let's start with some of the items you've engaged with most: \(itemNames). \
            What themes or questions are emerging from this collection? \
            Is there a central idea that ties them together?
            """

            return CheckInSuggestion(
                trigger: .knowledgeGap,
                seedItems: seeds,
                board: board,
                message: message,
                openingPrompt: openingPrompt
            )
        }

        return nil
    }

    // MARK: - Stale Items Detection

    /// High depth-score items not engaged in 30+ days.
    private func checkStaleItems(context: ModelContext) -> CheckInSuggestion? {
        let allItems: [Item] = context.fetchAll()
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.staleThresholdDays, to: .now) ?? .now

        let staleHighValue = allItems.filter { item in
            item.status == .active &&
            item.depthScore >= 30 && // sapling or higher
            item.updatedAt < cutoff
        }.sorted { $0.depthScore > $1.depthScore }

        guard let top = staleHighValue.first else { return nil }
        let seeds = Array(staleHighValue.prefix(2))

        let daysSince = Calendar.current.dateComponents([.day], from: top.updatedAt, to: .now).day ?? 0
        let message = "\"\(top.title)\" (\(top.growthStage.displayName)) hasn't been revisited in \(daysSince) days"

        let openingPrompt = """
        You spent significant time with [[\(top.title)]] — it's at the \(top.growthStage.displayName) stage — \
        but it hasn't been touched in \(daysSince) days. Let's revisit: \
        has your thinking on this changed since you last engaged with it? \
        Are there new items in your collection that might connect to or challenge its ideas?
        """

        return CheckInSuggestion(
            trigger: .staleItems,
            seedItems: seeds,
            board: top.boards.first,
            message: message,
            openingPrompt: openingPrompt
        )
    }

    // MARK: - Periodic Reflection

    /// Weekly check-in on the user's most active board.
    private func checkPeriodicReflection(context: ModelContext) -> CheckInSuggestion? {
        let lastReflection = UserDefaults.standard.double(forKey: Self.periodicReflectionKey)
        let sevenDaysInSeconds: TimeInterval = 7 * 24 * 3600
        guard Date.now.timeIntervalSince1970 - lastReflection >= sevenDaysInSeconds else {
            return nil
        }

        let allBoards: [Board] = context.fetchAll()
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now

        // Find the board with most recent activity
        let boardActivity: [(board: Board, recentCount: Int)] = allBoards.compactMap { board in
            let recentItems = board.items.filter { $0.updatedAt > sevenDaysAgo }
            guard !recentItems.isEmpty else { return nil }
            return (board: board, recentCount: recentItems.count)
        }.sorted { $0.recentCount > $1.recentCount }

        guard let most = boardActivity.first else { return nil }
        let recentItems = most.board.items
            .filter { $0.updatedAt > sevenDaysAgo }
            .sorted { $0.updatedAt > $1.updatedAt }
        let seeds = Array(recentItems.prefix(3))

        let message = "Weekly reflection: you engaged with \(most.recentCount) items in \"\(most.board.title)\" this week"

        let itemNames = seeds.map { "[[\($0.title)]]" }.joined(separator: ", ")
        let openingPrompt = """
        It's been a week — let's take stock. You've been most active in "\(most.board.title)" \
        with \(most.recentCount) items touched this week, including \(itemNames). \
        What's the most important thing you've learned or changed your mind about this week? \
        Are there any ideas that surprised you or challenged your prior beliefs?
        """

        return CheckInSuggestion(
            trigger: .periodicReflection,
            seedItems: seeds,
            board: most.board,
            message: message,
            openingPrompt: openingPrompt
        )
    }

    /// Mark periodic reflection as completed (called after conversation starts).
    static func recordPeriodicReflection() {
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: periodicReflectionKey)
    }
}
