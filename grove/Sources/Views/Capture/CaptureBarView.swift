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
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, Spacing.lg)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - CaptureBarView

struct CaptureBarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @State private var inputText = ""
    @State private var showConfirmation = false
    @FocusState private var isFocused: Bool

    // Board suggestion state
    @State private var pendingSuggestionItemID: UUID? = nil
    @State private var pendingSuggestion: BoardSuggestionDecision? = nil
    @State private var showBoardSuggestion = false
    @State private var showBoardPicker = false
    @State private var suggestionDismissTask: Task<Void, Never>? = nil

    /// Currently selected board (passed from ContentView)
    var currentBoardID: UUID?

    private var isURL: Bool {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              url.host != nil else { return false }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
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
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(Color.bgInput)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isFocused ? Color.borderPrimary : Color.borderInput, lineWidth: 1)
            )
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .overlay {
                if showConfirmation {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.groveBody)
                        Text("Captured")
                            .font(.groveBodySmall)
                    }
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.bgCard)
                    .clipShape(Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }

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
                .padding(.top, Spacing.xs)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .groveNewBoardSuggestion)) { notification in
            guard let notificationSuggestion = BoardSuggestionMetadata.decision(from: notification) else { return }

            if currentBoardID != nil { return }

            pendingSuggestionItemID = notificationSuggestion.itemID
            pendingSuggestion = notificationSuggestion.decision
            withAnimation(.easeOut(duration: 0.2)) {
                showBoardSuggestion = true
            }
            scheduleAutoDismiss()
        }
        .sheet(isPresented: $showBoardPicker) {
            if let pendingSuggestion {
                SmartBoardPickerSheet(
                    boards: boards,
                    suggestedName: pendingSuggestion.suggestedName,
                    recommendedBoardID: pendingSuggestion.recommendedBoardID,
                    prioritizedBoardIDs: pendingSuggestion.alternativeBoardIDs,
                    onSelectBoard: { board in
                        selectBoardFromPicker(board)
                    },
                    onCreateBoard: { boardName in
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
        .onReceive(NotificationCenter.default.publisher(for: .groveCoachMarkPrefill)) { notification in
            if let url = notification.object as? String {
                inputText = url
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    capture()
                }
            }
        }
    }

    // MARK: - Capture

    private func capture() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let captureService = CaptureService(modelContext: modelContext)
        let item = captureService.captureItem(input: trimmed)

        // Auto-assign to current board if one is selected
        if let boardID = currentBoardID,
           let board = boards.first(where: { $0.id == boardID }) {
            let viewModel = ItemViewModel(modelContext: modelContext)
            viewModel.assignToBoard(item, board: board)
        }

        inputText = ""

        // Flash confirmation
        withAnimation(.easeIn(duration: 0.15)) {
            showConfirmation = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            withAnimation(.easeOut(duration: 0.3)) {
                showConfirmation = false
            }
        }
    }

    // MARK: - Board Suggestion Actions

    private func acceptBoardSuggestion() {
        guard let pendingSuggestion else {
            dismissBoardSuggestion()
            return
        }

        let suggestedName = BoardSuggestionEngine.cleanedBoardName(pendingSuggestion.suggestedName)

        Task { @MainActor in
            let boardDescriptor = FetchDescriptor<Board>()
            let allBoards = (try? modelContext.fetch(boardDescriptor)) ?? []

            let board: Board
            if pendingSuggestion.mode == .existing,
               let recommendedBoardID = pendingSuggestion.recommendedBoardID,
               let recommended = allBoards.first(where: { $0.id == recommendedBoardID }) {
                board = recommended
            } else if let existing = allBoards.first(where: {
                $0.title.localizedCaseInsensitiveCompare(suggestedName) == .orderedSame
            }) {
                board = existing
            } else {
                let newBoard = Board(title: suggestedName.isEmpty ? "General" : suggestedName)
                modelContext.insert(newBoard)
                board = newBoard
            }

            assignPendingItem(to: board)
        }

        dismissBoardSuggestion()
    }

    private func selectBoardFromPicker(_ board: Board) {
        Task { @MainActor in
            assignPendingItem(to: board)
        }

        dismissBoardSuggestion()
    }

    private func createBoardFromPicker(named boardName: String) {
        let normalizedName = BoardSuggestionEngine.cleanedBoardName(boardName)
        guard !normalizedName.isEmpty else { return }

        Task { @MainActor in
            let boardDescriptor = FetchDescriptor<Board>()
            let allBoards = (try? modelContext.fetch(boardDescriptor)) ?? []

            if let existing = allBoards.first(where: {
                $0.title.localizedCaseInsensitiveCompare(normalizedName) == .orderedSame
            }) {
                assignPendingItem(to: existing)
            } else {
                let newBoard = Board(title: normalizedName)
                modelContext.insert(newBoard)
                assignPendingItem(to: newBoard)
            }
        }

        dismissBoardSuggestion()
    }

    private func assignPendingItem(to board: Board) {
        guard let itemID = pendingSuggestionItemID else { return }

        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
        guard let item = try? modelContext.fetch(descriptor).first else { return }

        if !item.boards.contains(where: { $0.id == board.id }) {
            item.boards.append(board)
        }

        BoardSuggestionMetadata.clearPendingSuggestion(on: item)
        try? modelContext.save()
    }

    private func dismissBoardSuggestion() {
        suggestionDismissTask?.cancel()
        suggestionDismissTask = nil
        showBoardPicker = false

        withAnimation(.easeOut(duration: 0.2)) {
            showBoardSuggestion = false
        }

        pendingSuggestionItemID = nil
        pendingSuggestion = nil
    }

    private func scheduleAutoDismiss() {
        suggestionDismissTask?.cancel()
        suggestionDismissTask = Task {
            try? await Task.sleep(for: .seconds(AppConstants.Capture.boardSuggestionAutoDismissSeconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                dismissBoardSuggestion()
            }
        }
    }
}

// MARK: - Capture Bar Overlay

struct CaptureBarOverlayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @Binding var isPresented: Bool
    @State private var inputText = ""
    @State private var showConfirmation = false
    @FocusState private var isFocused: Bool

    // Board suggestion state
    @State private var pendingSuggestionItemID: UUID? = nil
    @State private var pendingSuggestion: BoardSuggestionDecision? = nil
    @State private var showBoardSuggestion = false
    @State private var showBoardPicker = false
    @State private var suggestionDismissTask: Task<Void, Never>? = nil

    var currentBoardID: UUID?

    private var isURL: Bool {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              url.host != nil else { return false }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
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
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)

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
                .padding(.vertical, Spacing.xs)
            }
        }
        .frame(width: 600)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderPrimary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        .overlay {
            if showConfirmation {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.groveBody)
                    Text("Captured")
                        .font(.groveBodySmall)
                }
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(Color.bgCard)
                .clipShape(Capsule())
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .groveNewBoardSuggestion)) { notification in
            guard let notificationSuggestion = BoardSuggestionMetadata.decision(from: notification) else { return }

            if currentBoardID != nil { return }

            pendingSuggestionItemID = notificationSuggestion.itemID
            pendingSuggestion = notificationSuggestion.decision
            withAnimation(.easeOut(duration: 0.2)) {
                showBoardSuggestion = true
            }
            scheduleAutoDismiss()
        }
        .sheet(isPresented: $showBoardPicker) {
            if let pendingSuggestion {
                SmartBoardPickerSheet(
                    boards: boards,
                    suggestedName: pendingSuggestion.suggestedName,
                    recommendedBoardID: pendingSuggestion.recommendedBoardID,
                    prioritizedBoardIDs: pendingSuggestion.alternativeBoardIDs,
                    onSelectBoard: { board in
                        selectBoardFromPicker(board)
                    },
                    onCreateBoard: { boardName in
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
            isFocused = true
        }
        .onExitCommand {
            dismiss()
        }
    }

    private func capture() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let captureService = CaptureService(modelContext: modelContext)
        let item = captureService.captureItem(input: trimmed)

        if let boardID = currentBoardID,
           let board = boards.first(where: { $0.id == boardID }) {
            let viewModel = ItemViewModel(modelContext: modelContext)
            viewModel.assignToBoard(item, board: board)
        }

        inputText = ""

        withAnimation(.easeIn(duration: 0.15)) {
            showConfirmation = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            withAnimation(.easeOut(duration: 0.2)) {
                showConfirmation = false
                if !showBoardSuggestion {
                    dismiss()
                }
            }
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            isPresented = false
        }
    }

    // MARK: - Board Suggestion Actions

    private func acceptBoardSuggestion() {
        guard let pendingSuggestion else {
            dismissBoardSuggestion()
            return
        }

        let suggestedName = BoardSuggestionEngine.cleanedBoardName(pendingSuggestion.suggestedName)

        Task { @MainActor in
            let boardDescriptor = FetchDescriptor<Board>()
            let allBoards = (try? modelContext.fetch(boardDescriptor)) ?? []

            let board: Board
            if pendingSuggestion.mode == .existing,
               let recommendedBoardID = pendingSuggestion.recommendedBoardID,
               let recommended = allBoards.first(where: { $0.id == recommendedBoardID }) {
                board = recommended
            } else if let existing = allBoards.first(where: {
                $0.title.localizedCaseInsensitiveCompare(suggestedName) == .orderedSame
            }) {
                board = existing
            } else {
                let newBoard = Board(title: suggestedName.isEmpty ? "General" : suggestedName)
                modelContext.insert(newBoard)
                board = newBoard
            }

            assignPendingItem(to: board)
        }

        dismissBoardSuggestion()
        dismiss()
    }

    private func selectBoardFromPicker(_ board: Board) {
        Task { @MainActor in
            assignPendingItem(to: board)
        }

        dismissBoardSuggestion()
        dismiss()
    }

    private func createBoardFromPicker(named boardName: String) {
        let normalizedName = BoardSuggestionEngine.cleanedBoardName(boardName)
        guard !normalizedName.isEmpty else { return }

        Task { @MainActor in
            let boardDescriptor = FetchDescriptor<Board>()
            let allBoards = (try? modelContext.fetch(boardDescriptor)) ?? []

            if let existing = allBoards.first(where: {
                $0.title.localizedCaseInsensitiveCompare(normalizedName) == .orderedSame
            }) {
                assignPendingItem(to: existing)
            } else {
                let newBoard = Board(title: normalizedName)
                modelContext.insert(newBoard)
                assignPendingItem(to: newBoard)
            }
        }

        dismissBoardSuggestion()
        dismiss()
    }

    private func assignPendingItem(to board: Board) {
        guard let itemID = pendingSuggestionItemID else { return }

        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
        guard let item = try? modelContext.fetch(descriptor).first else { return }

        if !item.boards.contains(where: { $0.id == board.id }) {
            item.boards.append(board)
        }

        BoardSuggestionMetadata.clearPendingSuggestion(on: item)
        try? modelContext.save()
    }

    private func dismissBoardSuggestion() {
        suggestionDismissTask?.cancel()
        suggestionDismissTask = nil
        showBoardPicker = false

        withAnimation(.easeOut(duration: 0.2)) {
            showBoardSuggestion = false
        }
        pendingSuggestionItemID = nil
        pendingSuggestion = nil
    }

    private func scheduleAutoDismiss() {
        suggestionDismissTask?.cancel()
        suggestionDismissTask = Task {
            try? await Task.sleep(for: .seconds(AppConstants.Capture.boardSuggestionAutoDismissSeconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                dismissBoardSuggestion()
                dismiss()
            }
        }
    }
}
