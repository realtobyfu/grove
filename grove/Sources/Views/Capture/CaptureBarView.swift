import SwiftUI
import SwiftData

// MARK: - Board Suggestion Banner

/// Non-blocking inline suggestion shown after auto-tagging proposes the best board action.
private struct BoardSuggestionBanner: View {
    let decision: BoardSuggestionDecision
    let onPrimary: () -> Void
    let onChoose: () -> Void
    let onDismiss: () -> Void

    private var headline: String {
        switch decision.mode {
        case .existing:
            return "Best fit: \"\(decision.suggestedName)\""
        case .create:
            return "Create board \"\(decision.suggestedName)\"?"
        }
    }

    private var primaryLabel: String {
        switch decision.mode {
        case .existing:
            return "Add"
        case .create:
            return "Create"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "square.stack")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)

                Text(headline)
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss board suggestion")
                .accessibilityHint("Hides this suggestion without assigning a board.")
            }

            HStack(spacing: Spacing.sm) {
                if !decision.reason.isEmpty {
                    Text(decision.reason)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(BoardSuggestionEngine.confidenceLabel(for: decision.confidence))
                    .font(.groveBadge)
                    .foregroundStyle(Color.textTertiary)
            }

            HStack(spacing: Spacing.sm) {
                Button(primaryLabel) {
                    onPrimary()
                }
                .font(.groveBodySmall)
                .foregroundStyle(Color.textPrimary)
                .buttonStyle(.plain)

                Button("Choose…") {
                    onChoose()
                }
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.control))
        .padding(.horizontal, Spacing.lg)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Capture Confirmation

/// Post-capture flash. A duplicate paste is not a capture, so it never shows
/// the success checkmark — it names the existing item and offers to open it.
private struct CaptureConfirmationChip: View {
    let message: String
    let duplicateItemID: UUID?
    let onOpen: (UUID) -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let duplicateItemID {
                Text(message)
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)

                Text("\u{2014}")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textMuted)

                Button("Open") {
                    onOpen(duplicateItemID)
                }
                .buttonStyle(.plain)
                .font(.groveMeta)
                .foregroundStyle(Color.textPrimary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)
                Text(message)
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.control))
        .overlay {
            if duplicateItemID != nil {
                RoundedRectangle(cornerRadius: Radius.control)
                    .stroke(Color.borderPrimary, lineWidth: 1)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}

// MARK: - CaptureBarView

/// The one capture bar. `.inline` is the field on Today and board pages;
/// `.overlay` is the floating ⌘N card, which focuses itself on appear and
/// closes after each action.
struct CaptureBarView: View {
    enum Presentation {
        case inline
        case overlay(isPresented: Binding<Bool>)
    }

    private static let confirmationDuration: Duration = .seconds(1)
    private static let duplicateConfirmationDuration: Duration = .seconds(5)
    private static let fadeDuration: Double = 0.2

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @State private var inputText = ""
    @State private var showConfirmation = false
    @State private var confirmationMessage = "Captured"
    /// Set when the last capture matched an item already in the library.
    @State private var duplicateItemID: UUID? = nil
    @FocusState private var isFocused: Bool

    // Board suggestion state
    @State private var pendingSuggestionItemID: UUID? = nil
    @State private var pendingSuggestion: BoardSuggestionDecision? = nil
    @State private var showBoardSuggestion = false
    @State private var showBoardPicker = false
    @State private var suggestionDismissTask: Task<Void, Never>? = nil

    private let presentation: Presentation
    /// Board new captures are filed into, when the bar sits on a board page.
    private let currentBoardID: UUID?

    init(currentBoardID: UUID? = nil) {
        self.init(presentation: .inline, currentBoardID: currentBoardID)
    }

    init(presentation: Presentation, currentBoardID: UUID? = nil) {
        self.presentation = presentation
        self.currentBoardID = currentBoardID
    }

    private var isOverlay: Bool {
        if case .overlay = presentation { return true }
        return false
    }

    private var isURL: Bool {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              url.host != nil else { return false }
        return true
    }

    var body: some View {
        chrome
            .onReceive(NotificationCenter.default.publisher(for: .groveNewBoardSuggestion)) { notification in
                guard let notificationSuggestion = BoardSuggestionMetadata.decision(from: notification) else { return }

                if currentBoardID != nil { return }

                pendingSuggestionItemID = notificationSuggestion.itemID
                pendingSuggestion = notificationSuggestion.decision
                withAnimation(.easeOut(duration: Self.fadeDuration)) {
                    showBoardSuggestion = true
                }
                scheduleAutoDismiss()
            }
            .sheet(isPresented: $showBoardPicker) {
                if let pendingSuggestion {
                    BoardPickerView(
                        boards: boards,
                        mode: .add,
                        suggestedName: pendingSuggestion.suggestedName,
                        recommendedBoardID: pendingSuggestion.recommendedBoardID,
                        alternativeBoardIDs: pendingSuggestion.alternativeBoardIDs,
                        onSelect: { board in
                            selectBoardFromPicker(board)
                        },
                        onCreate: { boardName in
                            createBoardFromPicker(named: boardName)
                        }
                    )
                }
            }
            .onChange(of: showBoardPicker) { _, isPresented in
                if !isPresented, showBoardSuggestion {
                    scheduleAutoDismiss()
                }
            }
            .onAppear {
                if isOverlay { isFocused = true }
            }
            #if os(macOS)
            .onExitCommand(perform: isOverlay ? { closeOverlay() } : nil)
            #endif
    }

    // MARK: - Chrome

    @ViewBuilder
    private var chrome: some View {
        switch presentation {
        case .inline:
            VStack(spacing: 0) {
                inputRow
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.bgInput)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.control))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.control)
                            .stroke(isFocused ? Color.borderPrimary : Color.borderInput, lineWidth: 1)
                    )
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .overlay { confirmationChip }

                suggestionBanner
                    .padding(.top, Spacing.xs)
            }
        case .overlay:
            VStack(spacing: 0) {
                inputRow
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.md)

                suggestionBanner
                    .padding(.vertical, Spacing.xs)
            }
            .frame(width: 600)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .stroke(Color.borderPrimary, lineWidth: 1)
            )
            // The one shadow: this card floats over content.
            .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
            .overlay { confirmationChip }
        }
    }

    private var inputRow: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: isURL ? "link" : "note.text")
                .font(.groveMeta)
                .foregroundStyle(Color.textMuted)
                .frame(width: 16)

            TextField("", text: $inputText, prompt:
                Text("Paste a URL or type a note...")
                    .font(.groveGhostText)
                    .foregroundStyle(Color.textMuted)
            )
            .textFieldStyle(.plain)
            .font(.groveBody)
            .foregroundStyle(Color.textPrimary)
            .focused($isFocused)
            .onSubmit {
                capture()
            }

            if !inputText.isEmpty {
                Button {
                    capture()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.groveBody)
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Capture item")
                .accessibilityHint("Saves the current note or URL.")
            }

            Text("⏎")
                .font(.groveShortcut)
                .foregroundStyle(Color.textTertiary)
        }
    }

    @ViewBuilder
    private var confirmationChip: some View {
        if showConfirmation {
            CaptureConfirmationChip(
                message: confirmationMessage,
                duplicateItemID: duplicateItemID,
                onOpen: { openDuplicate($0) }
            )
        }
    }

    @ViewBuilder
    private var suggestionBanner: some View {
        if showBoardSuggestion, let pendingSuggestion {
            BoardSuggestionBanner(
                decision: pendingSuggestion,
                onPrimary: { acceptBoardSuggestion() },
                onChoose: {
                    suggestionDismissTask?.cancel()
                    showBoardPicker = true
                },
                onDismiss: { dismissBoardSuggestion() }
            )
        }
    }

    // MARK: - Capture

    private func capture() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let captureService = CaptureService(modelContext: modelContext)
        let board = currentBoardID.flatMap { boardID in
            boards.first(where: { $0.id == boardID })
        }
        let result = captureService.captureItemDetailed(input: trimmed, board: board)

        inputText = ""

        // A duplicate is not a capture: no new item, no success checkmark.
        // The flash names the existing item and stays long enough to open it.
        duplicateItemID = result.isDuplicate ? result.item.id : nil
        confirmationMessage = result.isDuplicate ? "Already in your library" : "Captured"
        withAnimation(.easeIn(duration: 0.15)) {
            showConfirmation = true
        }
        let visibleFor = result.isDuplicate ? Self.duplicateConfirmationDuration : Self.confirmationDuration
        Task { @MainActor in
            try? await Task.sleep(for: visibleFor)
            withAnimation(.easeOut(duration: Self.fadeDuration)) {
                showConfirmation = false
            }
            if !showBoardSuggestion {
                closeOverlay()
            }
        }
    }

    /// In the overlay, opening the existing item replaces the card — the
    /// handler for `.groveOpenItem` closes it on the way to the reader.
    private func openDuplicate(_ itemID: UUID) {
        withAnimation(.easeOut(duration: Self.fadeDuration)) { showConfirmation = false }
        NotificationCenter.default.post(name: .groveOpenItem, object: itemID)
        closeOverlay()
    }

    /// Closes the floating card; a no-op for the inline field.
    private func closeOverlay() {
        guard case .overlay(let isPresented) = presentation else { return }
        withAnimation(.easeOut(duration: Self.fadeDuration)) {
            isPresented.wrappedValue = false
        }
    }

    // MARK: - Board Suggestion Actions
    //
    // Each handler reads `pendingSuggestionItemID` into a local before queuing
    // its Task: `dismissBoardSuggestion()` clears it synchronously, before the
    // Task body runs.

    private func acceptBoardSuggestion() {
        guard let pendingSuggestion, let itemID = pendingSuggestionItemID else {
            dismissBoardSuggestion()
            return
        }

        let viewModel = ItemViewModel(modelContext: modelContext)
        Task { @MainActor in
            viewModel.assignPendingItem(itemID, accepting: pendingSuggestion)
        }

        dismissBoardSuggestion()
        closeOverlay()
    }

    private func selectBoardFromPicker(_ board: Board) {
        if let itemID = pendingSuggestionItemID {
            let viewModel = ItemViewModel(modelContext: modelContext)
            Task { @MainActor in
                viewModel.assignPendingItem(itemID, to: board)
            }
        }

        dismissBoardSuggestion()
        closeOverlay()
    }

    private func createBoardFromPicker(named boardName: String) {
        let normalizedName = BoardSuggestionEngine.cleanedBoardName(boardName)
        guard !normalizedName.isEmpty else { return }

        if let itemID = pendingSuggestionItemID {
            let viewModel = ItemViewModel(modelContext: modelContext)
            Task { @MainActor in
                viewModel.assignPendingItem(itemID, toBoardNamed: normalizedName)
            }
        }

        dismissBoardSuggestion()
        closeOverlay()
    }

    private func dismissBoardSuggestion() {
        suggestionDismissTask?.cancel()
        suggestionDismissTask = nil
        showBoardPicker = false

        withAnimation(.easeOut(duration: Self.fadeDuration)) {
            showBoardSuggestion = false
        }

        pendingSuggestionItemID = nil
        pendingSuggestion = nil
    }

    private func scheduleAutoDismiss() {
        suggestionDismissTask?.cancel()
        suggestionDismissTask = MainActorTaskScheduler.schedule(
            after: .seconds(AppConstants.Capture.boardSuggestionAutoDismissSeconds)
        ) {
            dismissBoardSuggestion()
            closeOverlay()
        }
    }
}

// MARK: - Capture Bar Overlay

/// The floating ⌘N capture card: `CaptureBarView` in its overlay presentation.
struct CaptureBarOverlayView: View {
    @Binding var isPresented: Bool
    var currentBoardID: UUID?

    var body: some View {
        CaptureBarView(
            presentation: .overlay(isPresented: $isPresented),
            currentBoardID: currentBoardID
        )
    }
}
