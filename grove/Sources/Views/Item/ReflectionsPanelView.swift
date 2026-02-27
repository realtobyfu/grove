import SwiftUI
import SwiftData

// MARK: - Reflections List Panel (split-pane right side, Mode B)

struct ReflectionsListPanel: View {
    @Bindable var vm: ItemReaderViewModel
    @Binding var draggingBlock: ReflectionBlock?
    var focusTrigger: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: "REFLECTIONS" + count badge + collapse + "+" menu
            HStack {
                Text("REFLECTIONS")
                    .sectionHeaderStyle()

                reflectionCountBadge

                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.25)) {
                        vm.isReflectionPanelCollapsed = true
                    }
                } label: {
                    Image(systemName: "chevron.up.circle")
                        .font(.groveBody)
                        .foregroundStyle(Color.textMuted)
                }
                .buttonStyle(.plain)
                .help("Hide reflections panel")

                addReflectionMenu
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    reflectionBlocksList
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Shared Components

    private var reflectionCountBadge: some View {
        Text("\(vm.item.reflections.count)")
            .font(.groveBadge)
            .foregroundStyle(Color.textMuted)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentBadge)
            .clipShape(Capsule())
    }

    private var addReflectionMenu: some View {
        Menu {
            ForEach(ReflectionBlockType.allCases, id: \.self) { type in
                Button {
                    vm.openReflectionEditor(type: type, content: "", highlight: nil, focusTrigger: focusTrigger)
                } label: {
                    Label(type.displayName, systemImage: type.systemImage)
                }
            }
        } label: {
            Image(systemName: "plus.circle")
                .font(.groveBody)
                .foregroundStyle(Color.textMuted)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 22)
        .help("Add reflection")
    }

    @ViewBuilder
    private var reflectionBlocksList: some View {
        ForEach(Array(vm.sortedReflections.enumerated()), id: \.element.id) { index, block in
            HStack(alignment: .top, spacing: 4) {
                // Drag handle
                Image(systemName: "line.3.horizontal")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 12, height: 20)
                    .padding(.top, 12)
                    .onDrag {
                        draggingBlock = block
                        return NSItemProvider(object: block.id.uuidString as NSString)
                    }

                ReflectionBlockRow(
                    block: block,
                    isVideoItem: vm.isVideoItem,
                    videoSeekTarget: Binding(
                        get: { vm.videoSeekTarget },
                        set: { vm.videoSeekTarget = $0 }
                    ),
                    onEdit: { vm.openBlockForEditing($0, focusTrigger: focusTrigger) },
                    onDelete: { blk in
                        vm.blockToDelete = blk
                    },
                    onNavigateToItemByTitle: { vm.navigateToItemByTitle($0) },
                    modelContext: vm.modelContext
                )
            }
            .onDrop(of: [.text], delegate: BlockDropDelegate(
                targetBlock: block,
                allBlocks: vm.sortedReflections,
                draggingBlock: $draggingBlock,
                modelContext: vm.modelContext
            ))

            if index < vm.sortedReflections.count - 1 {
                Divider()
                    .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Inline Reflections Section (single column, Mode A when collapsed or empty)

struct InlineReflectionsSection: View {
    @Bindable var vm: ItemReaderViewModel
    @Binding var draggingBlock: ReflectionBlock?
    var focusTrigger: () -> Void

    /// When true, show the expand button (used in collapsed mode).
    var showExpandButton: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack {
                Text("REFLECTIONS")
                    .sectionHeaderStyle()

                Text("\(vm.item.reflections.count)")
                    .font(.groveBadge)
                    .foregroundStyle(Color.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentBadge)
                    .clipShape(Capsule())

                Spacer()

                if showExpandButton {
                    Button {
                        withAnimation(.easeOut(duration: 0.25)) {
                            vm.isReflectionPanelCollapsed = false
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle")
                            .font(.groveBody)
                            .foregroundStyle(Color.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Show reflections panel")
                }

                Menu {
                    ForEach(ReflectionBlockType.allCases, id: \.self) { type in
                        Button {
                            vm.openReflectionEditor(type: type, content: "", highlight: nil, focusTrigger: focusTrigger)
                        } label: {
                            Label(type.displayName, systemImage: type.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.groveBody)
                        .foregroundStyle(Color.textMuted)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 22)
                .help("Add reflection")
            }

            Divider()
                .padding(.top, 12)

            // Quick-add chips when no reflections exist yet
            if vm.sortedReflections.isEmpty {
                GhostPrompts(vm: vm, focusTrigger: focusTrigger)
                    .padding(.top, 12)
            }

            // Existing reflection blocks
            ForEach(Array(vm.sortedReflections.enumerated()), id: \.element.id) { index, block in
                HStack(alignment: .top, spacing: 4) {
                    // Drag handle
                    Image(systemName: "line.3.horizontal")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 12, height: 20)
                        .padding(.top, 12)
                        .onDrag {
                            draggingBlock = block
                            return NSItemProvider(object: block.id.uuidString as NSString)
                        }

                    ReflectionBlockRow(
                        block: block,
                        isVideoItem: vm.isVideoItem,
                        videoSeekTarget: Binding(
                            get: { vm.videoSeekTarget },
                            set: { vm.videoSeekTarget = $0 }
                        ),
                        onEdit: { vm.openBlockForEditing($0, focusTrigger: focusTrigger) },
                        onDelete: { blk in
                            vm.blockToDelete = blk
                        },
                        onNavigateToItemByTitle: { vm.navigateToItemByTitle($0) },
                        modelContext: vm.modelContext
                    )
                }
                .onDrop(of: [.text], delegate: BlockDropDelegate(
                    targetBlock: block,
                    allBlocks: vm.sortedReflections,
                    draggingBlock: $draggingBlock,
                    modelContext: vm.modelContext
                ))

                if index < vm.sortedReflections.count - 1 {
                    Divider()
                        .padding(.horizontal, 16)
                }
            }
        }
    }
}

// MARK: - Ghost Prompts

struct GhostPrompts: View {
    @Bindable var vm: ItemReaderViewModel
    var focusTrigger: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ghostPromptChip(
                label: "Key claim?",
                icon: ReflectionBlockType.keyInsight.systemImage,
                blockType: .keyInsight
            )
            ghostPromptChip(
                label: "Connections?",
                icon: ReflectionBlockType.connection.systemImage,
                blockType: .connection
            )
            ghostPromptChip(
                label: "Challenge?",
                icon: ReflectionBlockType.disagreement.systemImage,
                blockType: .disagreement
            )
        }
    }

    private func ghostPromptChip(label: String, icon: String, blockType: ReflectionBlockType) -> some View {
        Button {
            vm.openReflectionEditor(type: blockType, content: "", highlight: nil, focusTrigger: focusTrigger)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.groveMeta)
                Text(label)
                    .font(.groveBodySecondary)
            }
            .foregroundStyle(Color.textTertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(
                        Color.borderTagDashed,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
