import SwiftUI
import SwiftData

struct SearchOverlayView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool
    @State private var viewModel: SearchViewModel?
    @State private var selectedIndex = 0
    @FocusState private var isQueryFieldFocused: Bool

    /// Optional board scope for board-context search
    var scopeBoard: Board?

    /// Called when a result is selected — navigates to item or board
    var onSelectItem: ((Item) -> Void)?
    var onSelectBoard: ((Board) -> Void)?
    var onSelectTag: ((Tag) -> Void)?

    private var flatResults: [SearchResult] {
        guard let vm = viewModel else { return [] }
        var flat: [SearchResult] = []
        for section in vm.orderedSections {
            if let sectionResults = vm.results[section] {
                flat.append(contentsOf: sectionResults)
            }
        }
        return flat
    }

    private var queryPlaceholder: String {
        if let scopeBoard {
            return "Search in \(scopeBoard.title)..."
        }
        return "Search Grove..."
    }

    private var overlayTitle: String {
        if let scopeBoard {
            return "Search inside \(scopeBoard.title)"
        }
        return "Find anything in Grove"
    }

    private var overlaySubtitle: String {
        if scopeBoard != nil {
            return "Search notes, article text, reflections, tags, and linked context without leaving this board."
        }
        return "Search notes, articles, reflections, tags, and boards from one focused command surface."
    }

    private var landingCards: [SearchLandingCard] {
        if scopeBoard != nil {
            return [
                SearchLandingCard(
                    iconName: "doc.text.magnifyingglass",
                    title: "Notes and articles",
                    detail: "Match titles, URLs, and captured text inside the current board."
                ),
                SearchLandingCard(
                    iconName: "text.alignleft",
                    title: "Reflections",
                    detail: "Jump back into prior thinking attached to these items."
                ),
                SearchLandingCard(
                    iconName: "tag",
                    title: "Tags and people",
                    detail: "Search topic labels, concepts, and named entities in context."
                ),
                SearchLandingCard(
                    iconName: "viewfinder.circle",
                    title: "Board-scoped results",
                    detail: "Everything stays focused here until you dismiss the overlay."
                )
            ]
        }

        return [
            SearchLandingCard(
                iconName: "doc.text.magnifyingglass",
                title: "Notes and articles",
                detail: "Search titles, URLs, and body text from everything you have captured."
            ),
            SearchLandingCard(
                iconName: "text.alignleft",
                title: "Reflections",
                detail: "Surface your previous analysis alongside the source material."
            ),
            SearchLandingCard(
                iconName: "tag",
                title: "Tags and people",
                detail: "Jump across concepts, topics, technologies, and named entities."
            ),
            SearchLandingCard(
                iconName: "square.grid.2x2",
                title: "Boards",
                detail: "Move directly into the right workspace from the same search."
            )
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider()

            overlayContent
        }
        .frame(width: 640)
        .frame(minHeight: 320, maxHeight: 520)
        .background(overlayBackground)
        .clipShape(.rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.borderPrimary.opacity(0.9), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 28, y: 14)
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

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Text(scopeBoard == nil ? "Search" : "Board Search")
                    .sectionHeaderStyle()

                scopeChip

                Spacer()

                if let vm = viewModel, !vm.query.isEmpty, vm.totalResultCount > 0 {
                    Text("\(vm.totalResultCount) matches")
                        .font(.groveBadge)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            HStack(spacing: Spacing.md) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)

                TextField(
                    "",
                    text: queryBinding,
                    prompt: Text(queryPlaceholder)
                        .font(.groveItemTitle)
                        .foregroundStyle(Color.textTertiary)
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
                        .tint(Color.textSecondary)
                }

                if let vm = viewModel, !vm.query.isEmpty {
                    Button {
                        vm.clearSearch()
                        selectedIndex = 0
                        isQueryFieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.groveBody)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                    .accessibilityHint("Clears the current search query.")
                }

                Button {
                    isPresented = false
                } label: {
                    keycap("esc")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close search")
                .accessibilityHint("Dismisses the search overlay.")
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 14)
            .background(Color.bgInput.opacity(isQueryFieldFocused ? 0.96 : 0.82), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isQueryFieldFocused ? Color.accentSelection.opacity(0.85) : Color.borderPrimary.opacity(0.75),
                        lineWidth: 1
                    )
            }

            if let vm = viewModel, vm.query.isEmpty {
                Text(overlaySubtitle)
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.xl)
    }

    @ViewBuilder
    private var overlayContent: some View {
        if let vm = viewModel {
            if vm.query.isEmpty {
                landingState
            } else if vm.totalResultCount == 0 {
                if vm.isSearching {
                    searchingState
                } else {
                    emptyState(query: vm.query)
                }
            } else {
                resultsList(vm: vm)
            }
        } else {
            searchingState
        }
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

    // MARK: - Results List

    private func resultsList(vm: SearchViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    var runningIndex = 0
                    ForEach(vm.orderedSections, id: \.self) { section in
                        if let sectionResults = vm.results[section] {
                            sectionHeader(section: section, count: sectionResults.count)

                            ForEach(Array(sectionResults.enumerated()), id: \.element.id) { offset, result in
                                let globalIndex = runningIndex + offset
                                Button {
                                    selectedIndex = globalIndex
                                    navigateTo(result: result)
                                } label: {
                                    resultRow(result: result, isSelected: globalIndex == selectedIndex)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .id(globalIndex)
                            }

                            let _ = (runningIndex += sectionResults.count)
                        }
                    }
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.md)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selectedIndex) { _, newValue in
                withAnimation(.easeInOut(duration: 0.12)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func sectionHeader(section: SearchResultType, count: Int) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: section.iconName)
                .font(.groveMeta)
                .foregroundStyle(Color.textMuted)

            Text(section.rawValue)
                .sectionHeaderStyle()

            Text("\(count)")
                .font(.groveBadge)
                .foregroundStyle(Color.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.bgInput.opacity(0.85), in: Capsule())

            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.xs)
    }

    private func resultRow(result: SearchResult, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentBadge.opacity(0.9) : Color.bgInput.opacity(0.82))

                resultIcon(for: result, isSelected: isSelected)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(result.title)
                    .font(.groveBody)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isSelected {
                keycap("return", emphasized: true)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .background(isSelected ? Color.bgPrimary.opacity(0.96) : Color.clear, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentSelection.opacity(0.8) : Color.clear, lineWidth: 1)
        }
        .contentShape(.rect)
    }

    @ViewBuilder
    private func resultIcon(for result: SearchResult, isSelected: Bool) -> some View {
        switch result.type {
        case .item:
            if let item = result.item {
                Image(systemName: item.type.iconName)
                    .font(.groveMeta)
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
            } else {
                Image(systemName: "doc")
                    .font(.groveMeta)
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
            }
        case .reflection:
            Image(systemName: "text.alignleft")
                .font(.groveMeta)
                .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
        case .tag:
            if let tag = result.tag {
                Image(systemName: tag.category.iconName)
                    .font(.groveMeta)
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
            } else {
                Image(systemName: "tag")
                    .font(.groveMeta)
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
            }
        case .board:
            if let board = result.board, let icon = board.icon {
                Image(systemName: icon)
                    .font(.groveMeta)
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
            } else {
                Image(systemName: "folder")
                    .font(.groveMeta)
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
            }
        }
    }

    private var landingState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                landingHero

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Spacing.md),
                        GridItem(.flexible(), spacing: Spacing.md)
                    ],
                    alignment: .leading,
                    spacing: Spacing.md
                ) {
                    ForEach(landingCards) { card in
                        landingCard(card)
                    }
                }

                HStack(spacing: Spacing.sm) {
                    shortcutHint(key: "↑ ↓", label: "Move")
                    shortcutHint(key: "return", label: "Open")
                    shortcutHint(key: "esc", label: "Dismiss")
                }
                .padding(.top, Spacing.xs)
            }
            .padding(Spacing.xl)
        }
        .scrollIndicators(.hidden)
    }

    private var landingHero: some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.bgPrimary.opacity(0.7))

                Image(systemName: scopeBoard?.icon ?? "magnifyingglass")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(overlayTitle)
                    .font(.groveTitleLarge)
                    .foregroundStyle(Color.textPrimary)

                Text(overlaySubtitle)
                    .font(.groveBodySecondary)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Spacing.sm) {
                    keycap(scopeBoard?.title ?? "all content")
                    keycap("titles, text, tags")
                }
                .padding(.top, 2)
            }
        }
        .padding(Spacing.xl)
        .background(
            LinearGradient(
                colors: [
                    Color.bgInput.opacity(0.94),
                    Color.bgCard.opacity(0.68)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: .rect(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.borderPrimary.opacity(0.7), lineWidth: 1)
        }
    }

    private func landingCard(_ card: SearchLandingCard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Image(systemName: card.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 34, height: 34)
                .background(Color.bgInput.opacity(0.8), in: .rect(cornerRadius: 10))

            Text(card.title)
                .font(.groveBodyMedium)
                .foregroundStyle(Color.textPrimary)

            Text(card.detail)
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .background(Color.bgCard.opacity(0.78), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.borderPrimary.opacity(0.6), lineWidth: 1)
        }
    }

    private var searchingState: some View {
        VStack(spacing: Spacing.sm) {
            ProgressView()
                .controlSize(.regular)

            Text("Searching \(scopeBoard?.title ?? "Grove")")
                .font(.groveBodyMedium)
                .foregroundStyle(Color.textPrimary)

            Text("Looking through notes, reflections, tags, and boards.")
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xxl)
    }

    private func emptyState(query: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.textTertiary)

            Text("No matches for \"\(query)\"")
                .font(.groveBodyMedium)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)

            Text(scopeBoard == nil ? "Try a shorter phrase, a tag name, or part of a title." : "Try a broader phrase or search outside this board.")
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: Spacing.sm) {
                keycap("shorter query")
                keycap("part of a title")
                keycap(scopeBoard == nil ? "check tags" : "all boards")
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xxl)
    }

    private var overlayBackground: some View {
        ZStack {
            Color.bgCard

            LinearGradient(
                colors: [
                    Color.bgInput.opacity(0.92),
                    Color.bgCard.opacity(0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.accentBadge.opacity(0.55),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 12,
                endRadius: 260
            )
        }
    }

    private var scopeChip: some View {
        HStack(spacing: 6) {
            Image(systemName: scopeBoard?.icon ?? "square.grid.2x2")
                .font(.groveMeta)
            Text(scopeBoard?.title ?? "All content")
                .font(.groveBadge)
                .lineLimit(1)
        }
        .foregroundStyle(Color.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.bgInput.opacity(0.85), in: Capsule())
    }

    private func shortcutHint(key: String, label: String) -> some View {
        HStack(spacing: 6) {
            keycap(key)
            Text(label)
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.bgCard.opacity(0.72), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.borderPrimary.opacity(0.55), lineWidth: 1)
        }
    }

    private func keycap(_ label: String, emphasized: Bool = false) -> some View {
        Text(label)
            .font(.groveBadge)
            .foregroundStyle(emphasized ? Color.textPrimary : Color.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((emphasized ? Color.accentBadge : Color.bgInput).opacity(emphasized ? 0.95 : 0.92), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.borderPrimary.opacity(0.55), lineWidth: 1)
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

private struct SearchLandingCard: Identifiable {
    let iconName: String
    let title: String
    let detail: String

    var id: String { title }
}
