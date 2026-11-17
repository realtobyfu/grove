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

                // The app's own trailing-panel glyph, the same one the
                // inspector toggle uses. A circled chevron pointed at a
                // direction nothing moves in, and matched `plus.circle` so
                // closely that the pair read as two ways to add something.
                Button {
                    withAnimation(.easeOut(duration: 0.25)) {
                        vm.isReflectionPanelCollapsed = true
                    }
                } label: {
                    Image(systemName: "sidebar.trailing")
                        .font(.groveBody)
                        .foregroundStyle(Color.textMuted)
                }
                .buttonStyle(.plain)
                .help("Close panel — keep reflections below the article")
                .accessibilityLabel("Close reflections panel")

                addReflectionMenu
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.sm)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if vm.sortedReflections.isEmpty {
                        GhostPrompts(vm: vm, focusTrigger: focusTrigger)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.top, Spacing.md)
                            .padding(.bottom, Spacing.sm)

                        Divider()
                            .padding(.horizontal, Spacing.lg)
                    }

                    reflectionBlocksList
                }
                .padding(.vertical, Spacing.sm)
            }
        }
    }

    // MARK: - Shared Components

    private var reflectionCountBadge: some View {
        Text("\(vm.item.reflections.count)")
            .font(.groveBadge)
            .foregroundStyle(Color.textMuted)
            .padding(.horizontal, Spacing.xsm)
            .padding(.vertical, 2)
            .background(Color.accentBadge)
            .clipShape(RoundedRectangle(cornerRadius: Radius.tag))
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
            DraggableReflectionRow(onDragStart: {
                draggingBlock = block
                return NSItemProvider(object: block.id.uuidString as NSString)
            }) {
                ReflectionBlockRow(
                    block: block,
                    onEdit: { vm.openBlockForEditing($0, focusTrigger: focusTrigger) },
                    onDelete: { blk in
                        vm.blockToDelete = blk
                    },
                    onNavigateToItemByTitle: { vm.navigateToItemByTitle($0) },
                    onHighlightTap: vm.articleURL != nil ? { vm.jumpToHighlight($0) } : nil,
                    onRemember: { vm.openFlashcardEditor(reflection: $0) },
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
                    .padding(.horizontal, Spacing.lg)
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
                    .padding(.horizontal, Spacing.xsm)
                    .padding(.vertical, 2)
                    .background(Color.accentBadge)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.tag))

                Spacer()

                if showExpandButton {
                    // Same glyph as the panel's own close control: one
                    // recognisable toggle for one piece of layout, rather than
                    // an up-chevron and a down-chevron that have to be read.
                    Button {
                        vm.expandReflectionPanel()
                    } label: {
                        Image(systemName: "sidebar.trailing")
                            .font(.groveBody)
                            .foregroundStyle(Color.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Open reflections as a side panel")
                    .accessibilityLabel("Open reflections panel")
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
                .padding(.top, Spacing.md)

            // Quick-add chips when no reflections exist yet
            if vm.sortedReflections.isEmpty {
                GhostPrompts(vm: vm, focusTrigger: focusTrigger)
                    .padding(.top, Spacing.md)
            }

            // Existing reflection blocks
            ForEach(Array(vm.sortedReflections.enumerated()), id: \.element.id) { index, block in
                DraggableReflectionRow(onDragStart: {
                    draggingBlock = block
                    return NSItemProvider(object: block.id.uuidString as NSString)
                }) {
                    ReflectionBlockRow(
                        block: block,
                        onEdit: { vm.openBlockForEditing($0, focusTrigger: focusTrigger) },
                        onDelete: { blk in
                            vm.blockToDelete = blk
                        },
                        onNavigateToItemByTitle: { vm.navigateToItemByTitle($0) },
                        onHighlightTap: vm.articleURL != nil ? { vm.jumpToHighlight($0) } : nil,
                        onRemember: { vm.openFlashcardEditor(reflection: $0) },
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
                        .padding(.horizontal, Spacing.lg)
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
        HStack(spacing: Spacing.sm) {
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
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.groveMeta)
                Text(label)
                    .font(.groveBodySecondary)
            }
            .foregroundStyle(Color.textTertiary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xsm)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control)
                    .strokeBorder(
                        Color.borderTagDashed,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Draggable Row Wrapper

/// Hosts a reflection row beside its reorder handle. The handle only
/// materializes on hover (always visible on touch platforms, which have no
/// hover) so the list reads as prose, not chrome.
private struct DraggableReflectionRow<Row: View>: View {
    var onDragStart: () -> NSItemProvider
    @ViewBuilder var row: () -> Row

    @State private var isHovered = false

    private var handleOpacity: Double {
        #if os(iOS)
        1
        #else
        isHovered ? 1 : 0
        #endif
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
                .frame(width: 12, height: 20)
                .padding(.top, Spacing.md)
                .opacity(handleOpacity)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
                .onDrag(onDragStart)
                .accessibilityLabel("Reorder reflection")
                #if os(iOS)
                .frame(minHeight: LayoutDimensions.minTouchTarget)
                #endif

            row()
        }
        .onHover { isHovered = $0 }
    }
}
