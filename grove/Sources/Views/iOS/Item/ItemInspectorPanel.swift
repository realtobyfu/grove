import SwiftUI
import SwiftData

/// Inspector panel for the iPad detail column.
/// Shows item metadata, board membership, connections, and review toggles.
/// Matches the Mac app's right-column article inspector (InspectorPanelView).
struct ItemInspectorPanel: View {
    @Bindable var item: Item
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.sortOrder) private var allBoards: [Board]

    @State private var showBoardPicker = false

    /// Extract a display domain from the item's sourceURL string.
    private var sourceDomain: String? {
        guard let urlString = item.sourceURL,
              let url = URL(string: urlString),
              let host = url.host(percentEncoded: false) else {
            return nil
        }
        // Strip leading "www." for cleaner display
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // MARK: - Header
                headerSection

                Divider()

                // MARK: - Metadata
                metadataSection

                Divider()

                // MARK: - Boards
                boardsSection

                Divider()

                // MARK: - Connections
                connectionsSection

                Divider()

                // MARK: - Review
                reviewSection

                Spacer()
            }
            .padding(.horizontal, LayoutDimensions.inspectorPaddingH)
            .padding(.top, LayoutDimensions.inspectorPaddingTop)
        }
        .background(Color.bgInspector)
        .sheet(isPresented: $showBoardPicker) {
            boardPickerSheet
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: item.type.iconName)
                    .foregroundStyle(Color.textSecondary)
                Text(item.type.rawValue.capitalized)
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)
            }

            Text(item.title)
                .font(.groveItemTitle)
                .foregroundStyle(Color.textPrimary)

            if let url = item.sourceURL, !url.isEmpty {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "link")
                        .font(.system(size: 12))
                    Text(url)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.groveMeta)
                .foregroundStyle(Color.textMuted)
            }
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            metadataRow(
                icon: "calendar",
                label: "Created",
                value: item.createdAt.formatted(date: .abbreviated, time: .shortened)
            )
            metadataRow(
                icon: "calendar.badge.clock",
                label: "Updated",
                value: item.updatedAt.formatted(date: .abbreviated, time: .shortened)
            )
            if let domain = sourceDomain {
                metadataRow(icon: "globe", label: "Source", value: domain)
            }
        }
    }

    private func metadataRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.textMuted)
                .frame(width: 16)
            Text(label)
                .font(.groveMeta)
                .foregroundStyle(Color.textMuted)
            Spacer()
            Text(value)
                .font(.groveMeta)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
        }
    }

    // MARK: - Boards

    private var boardsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Boards")
                    .sectionHeaderStyle()
                Spacer()
                Button {
                    showBoardPicker = true
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.textMuted)
                }
                .frame(minWidth: LayoutDimensions.minTouchTarget,
                       minHeight: LayoutDimensions.minTouchTarget)
            }

            if item.boards.isEmpty {
                Text("Not in any board")
                    .font(.groveBodySecondary)
                    .foregroundStyle(Color.textMuted)
            } else {
                ForEach(item.boards) { board in
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: board.icon ?? "folder")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textSecondary)
                        Text(board.title)
                            .font(.groveBody)
                            .foregroundStyle(Color.textPrimary)
                    }
                }
            }
        }
    }

    // MARK: - Connections

    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Connections")
                    .sectionHeaderStyle()
                Spacer()
            }

            let outgoing = item.outgoingConnections
            let incoming = item.incomingConnections

            if outgoing.isEmpty && incoming.isEmpty {
                Text("No connections")
                    .font(.groveBodySecondary)
                    .foregroundStyle(Color.textMuted)
            } else {
                ForEach(outgoing) { connection in
                    connectionRow(connection: connection, isOutgoing: true)
                }
                ForEach(incoming) { connection in
                    connectionRow(connection: connection, isOutgoing: false)
                }
            }
        }
    }

    private func connectionRow(connection: Connection, isOutgoing: Bool) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: isOutgoing ? "arrow.right.circle" : "arrow.left.circle")
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(isOutgoing
                     ? (connection.targetItem?.title ?? "Unknown")
                     : (connection.sourceItem?.title ?? "Unknown"))
                    .font(.groveBodySecondary)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)

                Text(connection.type.displayLabel)
                    .font(.groveBadge)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentBadge)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            Spacer()
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Review

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Review")
                .sectionHeaderStyle()

            if item.isResurfacingEligible {
                Button {
                    item.isResurfacingPaused.toggle()
                    try? modelContext.save()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: item.isResurfacingPaused ? "circle" : "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(item.isResurfacingPaused ? Color.textTertiary : Color.textPrimary)
                        Text("Remind me to revisit")
                            .font(.groveBody)
                            .foregroundStyle(item.isResurfacingPaused ? Color.textSecondary : Color.textPrimary)
                    }
                }
                .buttonStyle(.plain)
                .frame(minHeight: LayoutDimensions.minTouchTarget)

                if let nextDate = item.nextResurfaceDate {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: item.isResurfacingOverdue ? "exclamationmark.circle" : "calendar.badge.clock")
                            .font(.groveBadge)
                            .foregroundStyle(item.isResurfacingOverdue ? Color.textPrimary : Color.textSecondary)
                        Text(item.isResurfacingOverdue
                             ? "Due for review"
                             : "Next review: \(nextDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.groveMeta)
                            .fontWeight(item.isResurfacingOverdue ? .semibold : .regular)
                            .foregroundStyle(item.isResurfacingOverdue ? Color.textPrimary : Color.textSecondary)
                    }
                }
            } else {
                Text("Add notes or connections to enable review reminders.")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textTertiary)
            }

            if item.type == .article {
                Divider()

                Button {
                    item.isIncludedInDiscussionSuggestions.toggle()
                    item.updatedAt = .now
                    try? modelContext.save()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: item.isIncludedInDiscussionSuggestions ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14))
                            .foregroundStyle(item.isIncludedInDiscussionSuggestions ? Color.textPrimary : Color.textTertiary)
                        Text("Include in discussion suggestions")
                            .font(.groveBody)
                            .foregroundStyle(item.isIncludedInDiscussionSuggestions ? Color.textPrimary : Color.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .frame(minHeight: LayoutDimensions.minTouchTarget)
            }
        }
    }

    // MARK: - Board Picker

    private var boardPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(allBoards) { board in
                    Button {
                        if !item.boards.contains(where: { $0.id == board.id }) {
                            item.boards.append(board)
                            try? modelContext.save()
                        }
                        showBoardPicker = false
                    } label: {
                        HStack {
                            Label(board.title, systemImage: board.icon ?? "folder")
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            if item.boards.contains(where: { $0.id == board.id }) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.textMuted)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to Board")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showBoardPicker = false }
                }
            }
        }
    }
}
