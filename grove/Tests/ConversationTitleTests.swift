import Foundation
import SwiftData
import Testing
@testable import grove

@MainActor
struct ConversationTitleTests {
    private func makeInMemoryModelContext() throws -> ModelContext {
        let schema = SharedModelContainer.schema
        let config = ModelConfiguration(
            "ConversationTitleTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func add(_ role: ChatRole, _ content: String, hidden: Bool = false,
                     to conversation: Conversation, in context: ModelContext) {
        let message = ChatMessage(role: role, content: content,
                                  position: conversation.nextPosition, isHidden: hidden)
        context.insert(message)
        message.conversation = conversation
        conversation.messages.append(message)
    }

    @Test func untouchedConversationReadsAsNewConversation() throws {
        let context = try makeInMemoryModelContext()
        let conversation = Conversation()
        context.insert(conversation)

        #expect(conversation.displayTitle == "New conversation")
    }

    @Test func storedTitleWins() throws {
        let context = try makeInMemoryModelContext()
        let conversation = Conversation(title: "Moss and memory")
        context.insert(conversation)
        add(.user, "Something else entirely", to: conversation, in: context)

        #expect(conversation.displayTitle == "Moss and memory")
    }

    @Test func boardConversationIsTheBoardDiscussion() throws {
        let context = try makeInMemoryModelContext()
        let board = Board(title: "Gardens")
        context.insert(board)
        let conversation = Conversation(board: board)
        context.insert(conversation)
        add(.user, "What do these have in common?", to: conversation, in: context)

        #expect(conversation.displayTitle == "Gardens Discussion")
    }

    @Test func firstUserMessageBecomesTheTitle() throws {
        let context = try makeInMemoryModelContext()
        let conversation = Conversation()
        context.insert(conversation)
        add(.assistant, "Hello, what's on your mind?", to: conversation, in: context)
        add(.user, "hidden seed prompt", hidden: true, to: conversation, in: context)
        add(.user, "  Why do   forests\nfeel quiet?  ", to: conversation, in: context)
        add(.user, "A later message", to: conversation, in: context)

        #expect(conversation.displayTitle == "Why do forests")
    }

    @Test func longFirstMessageIsCutAtAWordWithAnEllipsis() {
        let text = "How does spaced repetition interact with the way I already annotate long essays?"
        let title = Conversation.oneLineTitle(from: text)

        #expect(title == "How does spaced repetition interact with the…")
        #expect((title?.count ?? 0) <= Conversation.derivedTitleLimit + 1)
    }

    @Test func unbrokenLongMessageIsHardCut() {
        let text = String(repeating: "a", count: 80)

        #expect(Conversation.oneLineTitle(from: text) == String(repeating: "a", count: 48) + "…")
    }

    @Test func blankMessageGivesNoTitle() {
        #expect(Conversation.oneLineTitle(from: " \n\t ") == nil)
    }
}
