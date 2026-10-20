import Foundation

/// A presentation identity, separate from the identity of a saved question.
struct LearningEditorSession: Identifiable {
    let id = UUID()
    var item: Item? = nil
    var reflection: ReflectionBlock? = nil
    var card: Flashcard? = nil
    var sourceQuote: String? = nil
    var boardID: UUID? = nil
}
