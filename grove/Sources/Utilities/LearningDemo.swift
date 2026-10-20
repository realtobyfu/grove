import Foundation
import SwiftData

/// An explicitly launched, isolated library for native UI review. No user store
/// is opened, and the fixture is unavailable in Release builds.
@MainActor
enum LearningDemo {
    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--learning-demo")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
        #else
        false
        #endif
    }

    static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: SharedModelContainer.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: SharedModelContainer.schema, configurations: [configuration])
        #if DEBUG
        let context = container.mainContext
        let board = Board(title: "Learning how to learn", icon: "brain")
        let note = Item(title: "Why retrieval makes learning last", type: .note)
        note.status = .active
        note.content = "Retrieval practice means bringing an idea to mind before looking at the answer. The effort of reconstructing an explanation strengthens your ability to recall it later. Rereading can make a passage feel familiar without making it easier to explain from memory. A small hint can help you begin; returning to the source helps you repair a gap."
        context.insert(board)
        context.insert(note)
        note.boards = [board]
        let card = Flashcard(
            question: "Why can recalling an idea help more than rereading it?",
            answer: "Recalling makes you reconstruct the explanation. That effort strengthens later retrieval and reveals gaps that familiarity from rereading can hide.",
            sourceItem: note,
            sourceQuote: note.content,
            hints: ["Think about the difference between recognition and reconstruction.", "What work does your mind do when the answer is out of sight?"]
        )
        context.insert(card)
        let second = Flashcard(question: "What is a useful next step when you draw a blank?", answer: "Try a small hint, read the supporting passage if needed, then return to the question and explain it in your own words.", sourceItem: note, sourceQuote: note.content, hints: ["Look for the smallest amount of support that helps you start."])
        context.insert(second)
        try context.save()
        #endif
        return container
    }
}
