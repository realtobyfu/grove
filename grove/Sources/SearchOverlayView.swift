import SwiftUI
import SwiftData

struct SearchOverlayView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool
    @State private var viewModel: SearchViewModel?
    @State private var selectedIndex = 0

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

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                TextField(scopeBoard != nil ? "Search in \(scopeBoard!.title)..." : "Search Grove...", text: queryBinding)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onSubmit {
                        selectCurrentResult()
                    }

                if let vm = viewModel, !vm.query.isEmpty {
                    Button {
                        vm.query = ""
                        vm.results = [:]
                        selectedIndex = 0
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    isPresented = false
                } label: {
                    Text("esc")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Results
            if let vm = viewModel, !vm.query.isEmpty {
                if vm.totalResultCount == 0 {
                    emptyState
                } else {
                    resultsList(vm: vm)
                }
            }
        }
        .frame(width: 600)
        .frame(maxHeight: 440)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .onAppear {
            let vm = SearchViewModel(modelContext: modelContext)
            vm.scopeBoard = scopeBoard
            viewModel = vm
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
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { viewModel?.query ?? "" },
            set: { newValue in
                viewModel?.query = newValue
                viewModel?.search()
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
                            // Section header
                            HStack(spacing: 6) {
                                Image(systemName: section.iconName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(section.rawValue)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                            .padding(.bottom, 4)

                            ForEach(Array(sectionResults.enumerated()), id: \.element.id) { offset, result in
                                let globalIndex = runningIndex + offset
                                resultRow(result: result, isSelected: globalIndex == selectedIndex)
                                    .id(globalIndex)
                                    .onTapGesture {
                                        selectedIndex = globalIndex
                                        navigateTo(result: result)
                                    }
                            }

                            let _ = (runningIndex += sectionResults.count)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: selectedIndex) { _, newValue in
                proxy.scrollTo(newValue, anchor: .center)
            }
        }
    }

    private func resultRow(result: SearchResult, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            resultIcon(for: result)
                .frame(width: 28, height: 28)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.body)
                    .lineLimit(1)
                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isSelected {
                Text("return")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func resultIcon(for result: SearchResult) -> some View {
        switch result.type {
        case .item:
            if let item = result.item {
                Image(systemName: item.type.iconName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .annotation:
            Image(systemName: "note.text")
                .font(.caption)
                .foregroundStyle(.purple)
        case .tag:
            if let tag = result.tag {
                Image(systemName: tag.category.iconName)
                    .font(.caption)
                    .foregroundStyle(tag.category.color)
            } else {
                Image(systemName: "tag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .board:
            if let board = result.board, let icon = board.icon {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(board.color.map { Color(hex: $0) } ?? .secondary)
            } else {
                Image(systemName: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No results found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Try a different search term")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
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
        case .annotation:
            // Navigate to the annotation's parent item
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
