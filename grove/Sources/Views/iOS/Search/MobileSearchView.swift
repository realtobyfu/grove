import SwiftUI
import SwiftData

/// Full-screen search view for iOS with segmented result filtering.
/// Shows sections (Items, Boards, Tags, Reflections) in a List.
/// Tap navigates to the result. Supports board-scoped search.
struct MobileSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var searchVM: SearchViewModel?
    @State private var searchText = ""
    @State private var filterType: SearchResultType?
    @State private var navigateToItem: Item?
    @State private var navigateToBoard: Board?

    /// Optional board scope — when set, shows a removable chip and restricts results.
    var scopeBoard: Board?

    var body: some View {
        NavigationStack {
            Group {
                if let searchVM {
                    if searchText.isEmpty {
                        emptyPrompt
                    } else if searchVM.isSearching {
                        ProgressView("Searching…")
                    } else if searchVM.totalResultCount == 0 {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        resultsList(searchVM)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Search")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: "Search items, boards, tags…")
            .onChange(of: searchText) { _, newValue in
                searchVM?.updateQuery(newValue)
            }
            .onSubmit(of: .search) {
                searchVM?.flushPendingSearch()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(item: $navigateToItem) { item in
                MobileItemReaderView(item: item)
            }
            .navigationDestination(item: $navigateToBoard) { board in
                MobileBoardDetailView(board: board)
            }
        }
        .onAppear {
            if searchVM == nil {
                let vm = SearchViewModel(modelContext: modelContext)
                vm.scopeBoard = scopeBoard
                searchVM = vm
            }
        }
    }

    // MARK: - Empty prompt

    private var emptyPrompt: some View {
        VStack(spacing: Spacing.lg) {
            if let scopeBoard {
                // Show board scope chip
                HStack(spacing: Spacing.sm) {
                    Label(scopeBoard.title, systemImage: scopeBoard.icon ?? "folder")
                        .font(.groveBodySecondary)
                        .foregroundStyle(Color.textSecondary)
                    Button {
                        searchVM?.scopeBoard = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.textMuted)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(Color.bgCard)
                .clipShape(Capsule())
            }

            ContentUnavailableView {
                Label("Search Grove", systemImage: "magnifyingglass")
            } description: {
                Text("Find items, boards, tags, and reflections.")
            }
        }
    }

    // MARK: - Filter picker

    private var filterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                filterChip(label: "All", type: nil)
                filterChip(label: "Items", type: .item)
                filterChip(label: "Boards", type: .board)
                filterChip(label: "Tags", type: .tag)
                filterChip(label: "Reflections", type: .reflection)
            }
            .padding(.horizontal, LayoutDimensions.contentPaddingH)
        }
    }

    private func filterChip(label: String, type: SearchResultType?) -> some View {
        let isSelected = filterType == type
        return Button {
            filterType = type
        } label: {
            Text(label)
                .font(.groveBodySecondary)
                .foregroundStyle(isSelected ? Color.textPrimary : Color.textTertiary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 6)
                .background(isSelected ? Color.bgCardHover : Color.bgCard)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? Color.borderPrimary : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Results list

    private func resultsList(_ vm: SearchViewModel) -> some View {
        VStack(spacing: 0) {
            filterPicker
                .padding(.vertical, Spacing.sm)

            List {
                let sections = filteredSections(vm)
                ForEach(sections, id: \.self) { sectionType in
                    if let sectionResults = vm.results[sectionType] {
                        Section {
                            ForEach(sectionResults) { result in
                                resultRow(result)
                            }
                        } header: {
                            Text(sectionType.rawValue)
                                .sectionHeaderStyle()
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func filteredSections(_ vm: SearchViewModel) -> [SearchResultType] {
        if let filterType {
            return vm.orderedSections.filter { $0 == filterType }
        }
        return vm.orderedSections
    }

    private func resultRow(_ result: SearchResult) -> some View {
        Button {
            navigateToResult(result)
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: result.type.iconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.groveBody)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)

                    if let subtitle = result.subtitle {
                        Text(subtitle)
                            .font(.groveMeta)
                            .foregroundStyle(Color.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(minHeight: LayoutDimensions.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Navigation

    private func navigateToResult(_ result: SearchResult) {
        switch result.type {
        case .item, .reflection:
            if let item = result.item {
                navigateToItem = item
            }
        case .board:
            if let board = result.board {
                navigateToBoard = board
            }
        case .tag:
            // Navigate to library filtered by tag — for now, just dismiss
            dismiss()
        }
    }
}
