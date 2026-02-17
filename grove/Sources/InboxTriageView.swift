import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct InboxTriageView: View {
    @Binding var selectedItem: Item?
    var openedItem: Binding<Item?>?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.createdAt, order: .reverse) private var allItems: [Item]
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @State private var focusedIndex: Int = 0
    @State private var showBoardPicker = false
    @State private var itemToAssign: Item?

    private var inboxItems: [Item] {
        allItems.filter { $0.status == .inbox }
    }

    var body: some View {
        Group {
            if inboxItems.isEmpty {
                emptyState
            } else {
                inboxList
            }
        }
        .sheet(isPresented: $showBoardPicker) {
            if let item = itemToAssign {
                BoardPickerSheet(boards: boards) { board in
                    let viewModel = ItemViewModel(modelContext: modelContext)
                    viewModel.assignToBoard(item, board: board)
                    showBoardPicker = false
                    itemToAssign = nil
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleVideoDrop(providers: providers)
        }
        .background(keyboardHandlers)
    }

    // MARK: - Inbox List

    private var inboxList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(inboxItems.enumerated()), id: \.element.id) { index, item in
                        InboxCard(
                            item: item,
                            isSelected: index == focusedIndex,
                            onKeep: { keepItem(item) },
                            onLater: { /* no-op — stays in inbox */ },
                            onDrop: { dropItem(item) }
                        )
                        .id(item.id)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95)),
                            removal: .opacity.combined(with: .move(edge: .trailing))
                        ))
                        .onTapGesture {
                            focusedIndex = index
                            selectedItem = item
                        }
                    }
                }
                .padding()
                .animation(.easeInOut(duration: 0.25), value: inboxItems.map(\.id))
            }
            .onChange(of: focusedIndex) { _, newIndex in
                let items = inboxItems
                guard newIndex >= 0, newIndex < items.count else { return }
                selectedItem = items[newIndex]
                withAnimation {
                    proxy.scrollTo(items[newIndex].id, anchor: .center)
                }
            }
            .onAppear {
                if !inboxItems.isEmpty {
                    focusedIndex = 0
                    selectedItem = inboxItems.first
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Inbox Clear")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Nice work! No items waiting for triage.\nCapture something with ⌘+Shift+K to get started.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Keyboard Handlers

    private var keyboardHandlers: some View {
        Group {
            // J — move down
            Button("") { moveFocus(by: 1) }
                .keyboardShortcut("j", modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)

            // K — move up
            Button("") { moveFocus(by: -1) }
                .keyboardShortcut("k", modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)

            // 1 — Keep
            Button("") { performAction(.keep) }
                .keyboardShortcut("1", modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)

            // 2 — Later
            Button("") { performAction(.later) }
                .keyboardShortcut("2", modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)

            // 3 — Drop
            Button("") { performAction(.drop) }
                .keyboardShortcut("3", modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)

            // Enter — Open selected item
            Button("") {
                let items = inboxItems
                guard focusedIndex >= 0, focusedIndex < items.count else { return }
                openedItem?.wrappedValue = items[focusedIndex]
            }
            .keyboardShortcut(.return, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
        }
    }

    // MARK: - Actions

    private enum TriageAction {
        case keep, later, drop
    }

    private func performAction(_ action: TriageAction) {
        let items = inboxItems
        guard focusedIndex >= 0, focusedIndex < items.count else { return }
        let item = items[focusedIndex]

        switch action {
        case .keep:
            keepItem(item)
        case .later:
            break // stays in inbox
        case .drop:
            dropItem(item)
        }
    }

    private func keepItem(_ item: Item) {
        item.status = .active
        item.updatedAt = .now
        try? modelContext.save()

        // Show board picker
        itemToAssign = item
        showBoardPicker = true

        adjustFocusAfterRemoval()
    }

    private func dropItem(_ item: Item) {
        withAnimation(.easeOut(duration: 0.3)) {
            item.status = .dismissed
            item.updatedAt = .now
            try? modelContext.save()
        }

        adjustFocusAfterRemoval()
    }

    private func moveFocus(by offset: Int) {
        let items = inboxItems
        guard !items.isEmpty else { return }
        let newIndex = max(0, min(items.count - 1, focusedIndex + offset))
        focusedIndex = newIndex
    }

    private func adjustFocusAfterRemoval() {
        // After an item is removed, adjust focus so it stays in bounds
        let items = inboxItems
        if items.isEmpty {
            focusedIndex = 0
            selectedItem = nil
        } else {
            focusedIndex = min(focusedIndex, items.count - 1)
            selectedItem = items[focusedIndex]
        }
    }

    // MARK: - Video Drag-and-Drop

    private func handleVideoDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                let path = url.path
                guard ItemViewModel.isSupportedVideoFile(path) else { return }
                nonisolated(unsafe) let context = modelContext
                Task { @MainActor in
                    let viewModel = ItemViewModel(modelContext: context)
                    _ = viewModel.createVideoItem(filePath: path)
                }
            }
            handled = true
        }
        return handled
    }
}

// MARK: - Board Picker Sheet

struct BoardPickerSheet: View {
    let boards: [Board]
    let onSelect: (Board) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Assign to Board")
                .font(.headline)
                .padding(.top)

            if boards.isEmpty {
                Text("No boards yet. Create one from the sidebar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List(boards) { board in
                    Button {
                        onSelect(board)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            if let hex = board.color {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 10, height: 10)
                            }
                            if let icon = board.icon {
                                Image(systemName: icon)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Text(board.title)
                                .font(.body)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 200)
            }

            HStack {
                Spacer()
                Button("Skip") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 320, height: 360)
    }
}
