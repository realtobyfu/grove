import SwiftUI
import SwiftData

struct SearchOverlayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isPresented: Bool
    @State private var viewModel: SearchViewModel?
    @State private var selectedIndex = 0
    @State private var hoveredIndex: Int?
    @FocusState private var isQueryFieldFocused: Bool

    /// Optional board scope for board-context search
    var scopeBoard: Board?

    /// Called when a result is selected — navigates to item or board
    var onSelectItem: ((Item) -> Void)?
    var onSelectBoard: ((Board) -> Void)?
    var onSelectTag: ((Tag) -> Void)?

    /// Every row in display order — exact-match sections, then "Related by
    /// meaning". Keyboard selection indexes into this.
    private var flatResults: [SearchResult] {
        guard let vm = viewModel else { return [] }
        return resultSections(vm: vm).flatMap(\.results)
    }

    /// Display sections with each one's first global row index, computed up
    /// front so row indices match `flatResults` regardless of view evaluation order.
    private func resultSections(vm: SearchViewModel) -> [SearchResultSection] {
        var sections: [SearchResultSection] = []
        var startIndex = 0
        for type in vm.orderedSections {
            guard let sectionResults = vm.results[type], !sectionResults.isEmpty else { continue }
            sections.append(SearchResultSection(
                id: type.rawValue,
                title: type.rawValue,
                startIndex: startIndex,
                results: sectionResults
            ))
            startIndex += sectionResults.count
        }
        if !vm.semanticResults.isEmpty {
            sections.append(SearchResultSection(
                id: "semantic",
                title: "Related by meaning",
                startIndex: startIndex,
                results: vm.semanticResults
            ))
        }
        return sections
    }

    private var queryPlaceholder: String {
        if let scopeBoard {
            return "Search in \(scopeBoard.title)…"
        }
        return "Search Grove…"
    }

    var body: some View {
        VStack(spacing: 0) {
            queryField
            Rectangle()
                .fill(Color.borderPrimary)
                .frame(height: 1)

            overlayContent

            Rectangle()
                .fill(Color.borderPrimary)
                .frame(height: 1)
            keyHints
        }
        .frame(width: 640)
        .frame(maxHeight: 520)
        .background(Color.bgCard)
        .clipShape(.rect(cornerRadius: Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card)
                .stroke(Color.borderPrimary, lineWidth: 1)
        }
        // One soft shadow: the card floats above the window.
        .shadow(color: .black.opacity(0.12), radius: Spacing.lg, y: Spacing.xs)
        .onAppear {
            let vm = SearchViewModel(modelContext: modelContext)
            vm.scopeBoard = scopeBoard
            viewModel = vm
            Task { @MainActor in
                await Task.yield()
                isQueryFieldFocused = true
            }
        }
        .onChange(of: flatResults.count) { _, newCount in
            if newCount == 0 {
                selectedIndex = 0
            } else if selectedIndex >= newCount {
                selectedIndex = max(0, newCount - 1)
            }
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 {
                selectedIndex -= 1
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < flatResults.count - 1 {
                selectedIndex += 1
            }
            return .handled
        }
        .onKeyPress(.return) {
            viewModel?.flushPendingSearch()
            selectCurrentResult()
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    // MARK: - Query Field

    private var queryField: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.groveBodyLarge)
                .foregroundStyle(Color.textMuted)

            TextField(
                "",
                text: queryBinding,
                prompt: Text(queryPlaceholder)
                    .font(.groveItemTitle)
                    .foregroundStyle(Color.textMuted)
            )
            .textFieldStyle(.plain)
            .font(.groveItemTitle)
            .foregroundStyle(Color.textPrimary)
            .focused($isQueryFieldFocused)
            .onSubmit {
                viewModel?.flushPendingSearch()
                selectCurrentResult()
            }

            if let vm = viewModel, vm.isSearching {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.textMuted)
            }

            if let vm = viewModel, !vm.query.isEmpty {
                Button {
                    vm.clearSearch()
                    selectedIndex = 0
                    isQueryFieldFocused = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .accessibilityHint("Clears the current search query.")
            }

            scopeLabel

            Button {
                isPresented = false
            } label: {
                keycap("esc")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close search")
            .accessibilityHint("Dismisses the search overlay.")
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
    }

    /// Where the search looks. Fixed by the presenting context (a board, or
    /// everything), so it reads as a label; ink when narrowed to a board.
    private var scopeLabel: some View {
        Text(scopeBoard?.title ?? "All")
            .font(.groveMeta)
            .lineLimit(1)
            .foregroundStyle(scopeBoard == nil ? Color.textSecondary : Color.textPrimary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control)
                    .stroke(Color.borderInput, lineWidth: 1)
            }
            .accessibilityLabel(scopeBoard.map { "Searching in \($0.title)" } ?? "Searching all of Grove")
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { viewModel?.query ?? "" },
            set: { newValue in
                viewModel?.updateQuery(newValue)
                selectedIndex = 0
            }
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var overlayContent: some View {
        if let vm = viewModel {
            if vm.query.isEmpty {
                quietLine("Search titles, notes, highlights and reflections.")
            } else if !vm.hasAnyResults {
                quietLine(vm.isSearching ? "Searching…" : noMatchesLine(query: vm.query))
            } else {
                resultsList(vm: vm)
            }
        } else {
            quietLine("Searching…")
        }
    }

    private func noMatchesLine(query: String) -> String {
        "Nothing matches \u{201C}\(query)\u{201D}."
    }

    private func quietLine(_ text: String) -> some View {
        Text(text)
            .font(.groveGhostText)
            .foregroundStyle(Color.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
    }

    // MARK: - Results List

    private func resultsList(vm: SearchViewModel) -> some View {
        let sections = resultSections(vm: vm)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Only "Related by meaning" has rows: say so before it.
                    if vm.totalResultCount == 0 && !vm.isSearching {
                        Text(noMatchesLine(query: vm.query))
                            .font(.groveGhostText)
                            .foregroundStyle(Color.textMuted)
                            .padding(.horizontal, Spacing.md)
                            .padding(.bottom, Spacing.sm)
                    }

                    ForEach(sections) { section in
                        sectionHeader(title: section.title, count: section.results.count)

                        ForEach(Array(section.results.enumerated()), id: \.element.id) { offset, result in
                            let globalIndex = section.startIndex + offset
                            Button {
                                selectedIndex = globalIndex
                                navigateTo(result: result)
                            } label: {
                                resultRow(
                                    result: result,
                                    isSelected: globalIndex == selectedIndex,
                                    isHovered: globalIndex == hoveredIndex
                                )
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                if hovering {
                                    hoveredIndex = globalIndex
                                } else if hoveredIndex == globalIndex {
                                    hoveredIndex = nil
                                }
                            }
                            .id(globalIndex)
                        }
                    }
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.md)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selectedIndex) { _, newValue in
                if reduceMotion {
                    proxy.scrollTo(newValue, anchor: .center)
                } else {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }

    /// Section header set like a table-of-contents entry: tracked mono label,
    /// dotted leader, result count as the page number.
    private func sectionHeader(title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(title)
                .sectionHeaderStyle()
                .lineLimit(1)
                .layoutPriority(1)

            SearchTOCLeader()
                .frame(minWidth: Spacing.sm)

            Text("\(count)")
                .font(.groveMeta)
                .foregroundStyle(Color.textTertiary)
                .monospacedDigit()
                .fixedSize()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func resultRow(result: SearchResult, isSelected: Bool, isHovered: Bool) -> some View {
        let isLit = isSelected || isHovered
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Image(systemName: symbolName(for: result))
                .font(.groveMeta)
                .foregroundStyle(Color.textMuted)
                .frame(width: Spacing.lg)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(result.title)
                    .font(.groveListTitle)
                    .foregroundStyle(isLit ? Color.textPrimary : Color.textSecondary)
                    .lineLimit(1)

                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Hover only darkens the ink. The rule and wash mark the one row that
        // return will open, so the pointer can never show a second selection.
        .background(isSelected ? Color.textPrimary.opacity(0.045) : Color.clear)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(Color.textPrimary)
                    .frame(width: 2)
            }
        }
        .clipShape(.rect(cornerRadius: Radius.control))
        .contentShape(.rect)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: isLit)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func symbolName(for result: SearchResult) -> String {
        switch result.type {
        case .item:
            result.item?.type.iconName ?? "doc"
        case .reflection:
            "text.alignleft"
        case .tag:
            result.tag?.category.iconName ?? "tag"
        case .board:
            result.board?.icon ?? "folder"
        }
    }

    // MARK: - Key Hints

    private var keyHints: some View {
        HStack(spacing: Spacing.lg) {
            keyHint(key: "↑↓", label: "move")
            keyHint(key: "return", label: "open")
            keyHint(key: "esc", label: "close")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.sm)
    }

    private func keyHint(key: String, label: String) -> some View {
        HStack(spacing: Spacing.xsm) {
            keycap(key)
            Text(label)
                .font(.groveMeta)
                .foregroundStyle(Color.textMuted)
        }
        .accessibilityElement(children: .combine)
    }

    private func keycap(_ label: String) -> some View {
        Text(label)
            .font(.groveMeta)
            .foregroundStyle(Color.textMuted)
            .padding(.horizontal, Spacing.xsm)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.tag)
                    .stroke(Color.borderInput, lineWidth: 1)
            }
    }

    // MARK: - Navigation

    private func selectCurrentResult() {
        let flat = flatResults
        guard selectedIndex >= 0 && selectedIndex < flat.count else { return }
        navigateTo(result: flat[selectedIndex])
    }

    private func navigateTo(result: SearchResult) {
        isPresented = false

        switch result.type {
        case .item:
            if let item = result.item {
                onSelectItem?(item)
            }
        case .reflection:
            // Navigate to the reflection's parent item
            if let item = result.item {
                onSelectItem?(item)
            }
        case .tag:
            if let tag = result.tag {
                onSelectTag?(tag)
            }
        case .board:
            if let board = result.board {
                onSelectBoard?(board)
            }
        }
    }
}

private struct SearchResultSection: Identifiable {
    let id: String
    let title: String
    /// Global index of this section's first row in the overlay's flat result list.
    let startIndex: Int
    let results: [SearchResult]
}

/// Dotted leader between a section label and its count, as in SidebarView.
private struct SearchTOCLeader: View {
    var body: some View {
        LeaderLine()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
            .foregroundStyle(Color.borderTagDashed)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private struct LeaderLine: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
            return path
        }
    }
}
