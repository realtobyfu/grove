import SwiftUI
import SwiftData

/// Full-screen item reader for iOS.
/// Articles: displays WKWebView. Notes: navigates to MobileNoteEditorView.
/// Toolbar: back, share, "Discuss", reflections button, find-in-page.
struct MobileItemReaderView: View {
    let item: Item
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var dialecticsService = DialecticsService()
    @State private var showReflections = false
    @State private var showFindBar = false
    @State private var findQuery = ""
    @State private var findForwardToken = 0
    @State private var findBackwardToken = 0
    @State private var findCurrentMatch = 0
    @State private var findTotalMatches = 0
    @State private var selectedText: String?
    @State private var navigateToChat: Conversation?
    @FocusState private var findBarFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            contentView
            if showFindBar {
                findBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .navigationTitle(item.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbarContent }
        .sheet(isPresented: $showReflections) {
            reflectionSheetContent
        }
        .navigationDestination(item: $navigateToChat) { conversation in
            MobileChatView(conversation: conversation)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch item.type {
        case .note:
            MobileNoteEditorView(item: item)
        default:
            articleContent
        }
    }

    @ViewBuilder
    private var articleContent: some View {
        if let urlString = item.sourceURL, let url = URL(string: urlString) {
            #if os(iOS)
            MobileArticleWebView(
                url: url,
                onTextSelected: { text in selectedText = text },
                findQuery: findQuery,
                findForwardToken: findForwardToken,
                findBackwardToken: findBackwardToken,
                onFindResult: { current, total in
                    findCurrentMatch = current
                    findTotalMatches = total
                }
            )
            .ignoresSafeArea(edges: .bottom)
            #else
            Text("Article view not available on this platform")
            #endif
        } else if let content = item.content, !content.isEmpty {
            // Fallback: render item content as scrollable text
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if let summary = item.metadata["summary"], !summary.isEmpty {
                        Text(summary)
                            .font(.groveBodySecondary)
                            .foregroundStyle(Color.textSecondary)
                            .italic()
                    }
                    Text(content)
                        .font(.groveBody)
                        .foregroundStyle(Color.textPrimary)
                }
                .padding(.horizontal, LayoutDimensions.contentPaddingH)
                .padding(.vertical, Spacing.lg)
            }
        } else {
            ContentUnavailableView {
                Label("No Content", systemImage: "doc.text")
            } description: {
                Text("This item has no readable content.")
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // Find in page (articles only)
            if item.type != .note {
                Button {
                    withAnimation { showFindBar.toggle() }
                    if showFindBar { findBarFocused = true }
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .accessibilityLabel("Find in page")
            }

            // Reflect: iPad shows menu (write note or chat), iPhone opens sheet directly
            if horizontalSizeClass == .regular {
                Menu {
                    Button {
                        showReflections = true
                    } label: {
                        Label("Write a Reflection", systemImage: "text.bubble")
                    }

                    Button {
                        startDiscussion()
                    } label: {
                        Label("Discuss in Chat", systemImage: "bubble.left.and.bubble.right")
                    }
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Reflect on this item")
            } else {
                Button {
                    showReflections = true
                } label: {
                    Image(systemName: "text.bubble")
                }
                .accessibilityLabel("Reflections")
            }

            #if os(iOS)
            // Share
            ShareLink(item: shareURL) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share")
            #endif
        }
    }

    private var shareURL: URL {
        if let urlString = item.sourceURL, let url = URL(string: urlString) {
            return url
        }
        return URL(string: "grove://item/\(item.id.uuidString)")!
    }

    // MARK: - Find bar

    private var findBar: some View {
        HStack(spacing: Spacing.sm) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.textMuted)
                TextField("Find in page", text: $findQuery)
                    .font(.groveBody)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                    .focused($findBarFocused)
                    .onSubmit { findForwardToken += 1 }

                if !findQuery.isEmpty {
                    Text("\(findCurrentMatch)/\(findTotalMatches)")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textMuted)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 8)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button {
                findBackwardToken += 1
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(findTotalMatches == 0)

            Button {
                findForwardToken += 1
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(findTotalMatches == 0)

            Button("Done") {
                withAnimation {
                    showFindBar = false
                    findQuery = ""
                    findBarFocused = false
                }
            }
            .font(.groveBody)
        }
        .padding(.horizontal, LayoutDimensions.contentPaddingH)
        .padding(.vertical, Spacing.sm)
        .background(.ultraThinMaterial)
    }

    // MARK: - Reflections sheet

    @ViewBuilder
    private var reflectionSheetContent: some View {
        if horizontalSizeClass == .regular {
            MobileReflectionSheet(item: item)
                .frame(minWidth: 400)
        } else {
            MobileReflectionSheet(item: item)
                #if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                #endif
        }
    }

    // MARK: - Actions

    private func startDiscussion() {
        let conversation = dialecticsService.startConversation(
            trigger: .userInitiated,
            seedItems: [item],
            board: item.boards.first,
            context: modelContext
        )
        // Send an opening message about the item
        Task {
            _ = await dialecticsService.sendMessage(
                userText: "Let's discuss \"\(item.title)\".",
                conversation: conversation,
                context: modelContext
            )
        }
        navigateToChat = conversation
    }
}
