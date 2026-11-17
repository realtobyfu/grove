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
    @State private var navigateToItemRoute: MobileItemRoute?
    @State private var navigateToBoard: Board?

    /// Optional board scope — when set, shows a removable chip and restricts results.
    var scopeBoard: Board?
    var initialQuery: String? = nil
    /// Set where items open somewhere other than this sheet's own stack — the
    /// regular-width iPad, whose detail column is the reader. The sheet
    /// dismisses and hands the item over. Nil pushes the compact reader here.
    var onOpenItem: ((Item) -> Void)? = nil
    /// Same hand-over for boards: the regular-width iPad selects the board in
    /// its sidebar instead of pushing a compact board view inside the sheet.
    var onOpenBoard: ((Board) -> Void)? = nil

    var body: some View {
        NavigationStack {
            Group {
                if let searchVM {
                    if searchText.isEmpty {
                        emptyPrompt
                    } else if searchVM.isSearching {
                        ProgressView("Searching…")
                    } else if !searchVM.hasAnyResults {
                        GroveEmptyState(
                            title: "Nothing matches \u{201C}\(searchText)\u{201D}.",
                            detail: "Try a shorter word or a different spelling."
                        )
                        .padding(.horizontal, LayoutDimensions.contentPaddingH)
                        .frame(maxHeight: .infinity, alignment: .top)
                    } else {
                        resultsList(searchVM)
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.bgPrimary)
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
            .navigationDestination(item: $navigateToItemRoute) { route in
                MobileItemRouteDestinationView(route: route)
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
            if searchText.isEmpty,
               let initialQuery,
               !initialQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchText = initialQuery
                searchVM?.updateQuery(initialQuery)
            }
        }
    }

    // MARK: - Empty prompt

    private var emptyPrompt: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
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
                .background(Color.bgCard, in: RoundedRectangle(cornerRadius: Radius.control))
            }

            GroveEmptyState(
                title: "Search your library.",
                detail: "Items, boards, tags and reflections all turn up here."
            )
        }
        .padding(.horizontal, LayoutDimensions.contentPaddingH)
        .frame(maxHeight: .infinity, alignment: .top)
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
        FilterChip(label: label, isActive: filterType == type) {
            filterType = type
        }
    }

    // MARK: - Results list

    private func resultsList(_ vm: SearchViewModel) -> some View {
        VStack(spacing: 0) {
            filterPicker
                .padding(.vertical, Spacing.xs)

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

                if showsSemanticSection(vm) {
                    Section {
                        ForEach(vm.semanticResults) { result in
                            resultRow(result)
                        }
                    } header: {
                        Text("Related by meaning")
                            .sectionHeaderStyle()
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(Color.bgPrimary)
    }

    private func filteredSections(_ vm: SearchViewModel) -> [SearchResultType] {
        if let filterType {
            return vm.orderedSections.filter { $0 == filterType }
        }
        return vm.orderedSections
    }

    /// Semantic rows are items, so they belong under "All" and "Items" only.
    private func showsSemanticSection(_ vm: SearchViewModel) -> Bool {
        guard !vm.semanticResults.isEmpty else { return false }
        return filterType == nil || filterType == .item
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
        .listRowBackground(Color.bgPrimary)
        .alignmentGuide(.listRowSeparatorLeading) { dimensions in
            dimensions[.leading]
        }
    }

    // MARK: - Navigation

    private func openItem(_ item: Item) {
        if let onOpenItem {
            onOpenItem(item)
            dismiss()
        } else {
            navigateToItemRoute = MobileItemRoute(id: item.id)
        }
    }

    private func navigateToResult(_ result: SearchResult) {
        switch result.type {
        case .item, .reflection:
            if let item = result.item {
                openItem(item)
            }
        case .board:
            if let board = result.board {
                if let onOpenBoard {
                    onOpenBoard(board)
                    dismiss()
                } else {
                    navigateToBoard = board
                }
            }
        case .tag:
            guard let tag = result.tag else {
                dismiss()
                return
            }

            if let mostRecentTaggedItem = tag.items.max(by: { $0.updatedAt < $1.updatedAt }) {
                openItem(mostRecentTaggedItem)
            } else {
                searchText = tag.name
                searchVM?.updateQuery(tag.name)
            }
        }
    }
}
