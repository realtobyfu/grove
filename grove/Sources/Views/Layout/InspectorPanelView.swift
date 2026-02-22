import SwiftUI
import SwiftData

struct InspectorPanelView: View {
    @Bindable var item: Item
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.sortOrder) private var allBoards: [Board]
    @Query private var allItems: [Item]
    @State private var isAddingConnection = false
    @State private var connectionSearchText = ""
    @State private var selectedConnectionType: ConnectionType = .related

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                metadataSection
                    .padding(.top)
                Divider().padding(.horizontal)
                boardMembershipSection
                Divider().padding(.horizontal)
                connectionsSection
                Divider().padding(.horizontal)
                resurfacingSection
                if item.type == .article {
                    discussionSuggestionsSection
                }

                Spacer()
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color.bgInspector)
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Type
            HStack {
                Image(systemName: item.type.iconName)
                    .foregroundStyle(Color.textSecondary)
                Text(item.type.rawValue.capitalized)
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)

                Spacer()

                // Discuss button
                Button {
                    NotificationCenter.default.postDiscussItem(DiscussItemPayload(item: item))
                } label: {
                    Label("Discuss", systemImage: "bubble.left.and.bubble.right")
                        .font(.groveBadge)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .cardStyle(cornerRadius: 4)
                }
                .buttonStyle(.plain)
                .help("Discuss this item in Dialectics")
            }
            .padding(.horizontal)

            // Editable Title
            TextField("Title", text: $item.title)
                .textFieldStyle(.plain)
                .font(.groveBodyMedium)
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal)
                .onChange(of: item.title) {
                    item.updatedAt = .now
                }

            // Source URL
            if let sourceURL = item.sourceURL, !sourceURL.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)
                    Text(sourceURL)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal)
            }

            // Dates
            VStack(alignment: .leading, spacing: 4) {
                Label("Created: \(item.createdAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)
                Label("Updated: \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar.badge.clock")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Board Membership Section

    private var boardMembershipSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Boards")
                .sectionHeaderStyle()
                .padding(.horizontal)

            if item.boards.isEmpty {
                Text("Not in any board")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal)
            } else {
                ForEach(item.boards) { board in
                    HStack(spacing: 6) {
                        if let icon = board.icon {
                            Image(systemName: icon)
                                .font(.groveBadge)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Text(board.title)
                            .font(.groveBody)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - Connections Section

    private var connectionSearchResults: [Item] {
        let existingIDs = Set(
            item.outgoingConnections.compactMap(\.targetItem?.id) +
            item.incomingConnections.compactMap(\.sourceItem?.id)
        )
        return allItems.filter { candidate in
            guard candidate.id != item.id else { return false }
            guard !existingIDs.contains(candidate.id) else { return false }
            if connectionSearchText.isEmpty { return true }
            return candidate.title.localizedCaseInsensitiveContains(connectionSearchText)
        }.prefix(12).map { $0 }
    }

    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Connections")
                    .sectionHeaderStyle()
                Spacer()
                Button {
                    isAddingConnection.toggle()
                    connectionSearchText = ""
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.groveMeta)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textMuted)
                .accessibilityLabel("Add connection")
                .accessibilityHint("Open the connection picker for this item.")
            }
            .padding(.horizontal)

            let allConnections = item.outgoingConnections + item.incomingConnections
            if allConnections.isEmpty && !isAddingConnection {
                Text("No connections yet")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal)
            } else {
                ForEach(allConnections) { connection in
                    connectionRow(connection)
                }
            }

            if isAddingConnection {
                addConnectionPanel
            }
        }
    }

    private var addConnectionPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Type", selection: $selectedConnectionType) {
                ForEach(ConnectionType.allCases, id: \.self) { type in
                    Text(type.displayLabel).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            TextField("Search items...", text: $connectionSearchText)
                .textFieldStyle(.roundedBorder)
                .font(.groveBodySmall)

            if !connectionSearchResults.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(connectionSearchResults) { candidate in
                            Button {
                                createConnectionTo(candidate)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: candidate.type.iconName)
                                        .font(.groveBadge)
                                        .foregroundStyle(Color.textSecondary)
                                        .frame(width: 14)
                                    Text(candidate.title)
                                        .font(.groveBodySmall)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 150)
                .cardStyle(cornerRadius: 4)
            } else if !connectionSearchText.isEmpty {
                Text("No matching items")
                    .font(.groveBadge)
                    .foregroundStyle(Color.textTertiary)
            }

            Button("Cancel") {
                isAddingConnection = false
                connectionSearchText = ""
            }
            .font(.groveBodySmall)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(Spacing.sm)
        .cardStyle(cornerRadius: 6)
        .padding(.horizontal)
    }

    private func connectionRow(_ connection: Connection) -> some View {
        let isOutgoing = connection.sourceItem?.id == item.id
        let linkedItem = isOutgoing ? connection.targetItem : connection.sourceItem
        let typeLabel = connection.type.displayLabel

        return HStack(spacing: 6) {
            Image(systemName: isOutgoing ? "arrow.right.circle" : "arrow.left.circle")
                .font(.groveBadge)
                .foregroundStyle(Color.textSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(linkedItem?.title ?? "Unknown")
                    .font(.groveBody)
                    .lineLimit(1)
                    .foregroundStyle(Color.textPrimary)
                Text(typeLabel)
                    .font(.groveBadge)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentBadge)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            Spacer()
            Button {
                deleteConnection(connection)
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.groveBadge)
                    .foregroundStyle(Color.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete connection to \(linkedItem?.title ?? "item")")
            .accessibilityHint("Removes this relationship from the graph.")
        }
        .padding(.horizontal)
    }

    private func createConnectionTo(_ target: Item) {
        let viewModel = ItemViewModel(modelContext: modelContext)
        _ = viewModel.createConnection(source: item, target: target, type: selectedConnectionType)
        isAddingConnection = false
        connectionSearchText = ""
        selectedConnectionType = .related
    }

    private func deleteConnection(_ connection: Connection) {
        let viewModel = ItemViewModel(modelContext: modelContext)
        viewModel.deleteConnection(connection)
    }

    // MARK: - Discussion Suggestions Section

    private var discussionSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                item.isIncludedInDiscussionSuggestions.toggle()
                item.updatedAt = .now
                try? modelContext.save()

                Task { @MainActor in
                    let allItems = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []
                    await ConversationStarterService.shared.forceRefresh(items: allItems)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: item.isIncludedInDiscussionSuggestions ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(item.isIncludedInDiscussionSuggestions ? Color.textPrimary : Color.textTertiary)
                    Text("Include in discussion suggestions")
                        .font(.groveBodySmall)
                        .foregroundStyle(item.isIncludedInDiscussionSuggestions ? Color.textPrimary : Color.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .help("Include or exclude this article from discussion suggestions.")
        }
    }

    // MARK: - Review Section

    private var resurfacingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Review")
                .sectionHeaderStyle()
                .padding(.horizontal)

            if item.isResurfacingEligible {
                Button {
                    item.isResurfacingPaused.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.isResurfacingPaused ? "circle" : "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(item.isResurfacingPaused ? Color.textTertiary : Color.textPrimary)
                        Text("Remind me to revisit")
                            .font(.groveBodySmall)
                            .foregroundStyle(item.isResurfacingPaused ? Color.textSecondary : Color.textPrimary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                if let nextDate = item.nextResurfaceDate {
                    HStack(spacing: 4) {
                        Image(systemName: item.isResurfacingOverdue ? "exclamationmark.circle" : "calendar.badge.clock")
                            .font(.groveBadge)
                            .foregroundStyle(item.isResurfacingOverdue ? Color.textPrimary : Color.textSecondary)
                        Text(item.isResurfacingOverdue ? "Due for review" : "Next review: \(nextDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.groveMeta)
                            .fontWeight(item.isResurfacingOverdue ? .semibold : .regular)
                            .foregroundStyle(item.isResurfacingOverdue ? Color.textPrimary : Color.textSecondary)
                    }
                    .padding(.horizontal)
                }
            } else {
                Text("Add notes or connections to enable review reminders.")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal)
            }
        }
    }
}

// MARK: - Inspector Empty State

struct InspectorEmptyView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Select an item to see details.")
                .font(.groveBody)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal)
                .padding(.top)

            Spacer()
        }
        .frame(maxHeight: .infinity)
        .background(Color.bgInspector)
    }
}
