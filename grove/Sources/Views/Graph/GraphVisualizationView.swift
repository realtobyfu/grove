import SwiftUI
import SwiftData
import SpriteKit

// Cross-platform label color: NSColor uses .labelColor, UIColor uses .label
private extension SKColor {
    #if os(macOS)
    static var graphLabel: SKColor { .labelColor }
    #else
    static var graphLabel: SKColor { .label }
    #endif
}

// MARK: - Graph Visualization View

struct GraphVisualizationView: View {
    @Binding var selectedItem: Item?
    @Binding var openedItem: Item?
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [Item]
    @Query private var allConnections: [Connection]
    @Query(sort: \Board.sortOrder) private var allBoards: [Board]
    @Query private var allTags: [Tag]

    @State private var filterBoard: Board?
    @State private var filterTag: Tag?
    @State private var filterRelationshipTypes: Set<ConnectionType> = Set(ConnectionType.allCases)
    @State private var scene: GraphScene?

    private var filteredItems: [Item] {
        var items = allItems.filter { $0.status == .active || $0.status == .inbox }
        if let board = filterBoard {
            let boardItemIDs = Set(board.items.map(\.id))
            items = items.filter { boardItemIDs.contains($0.id) }
        }
        if let tag = filterTag {
            let tagItemIDs = Set(tag.items.map(\.id))
            items = items.filter { tagItemIDs.contains($0.id) }
        }
        return items
    }

    private var filteredConnections: [Connection] {
        let itemIDs = Set(filteredItems.map(\.id))
        return allConnections.filter { conn in
            guard filterRelationshipTypes.contains(conn.type) else { return false }
            guard let sourceID = conn.sourceItem?.id, let targetID = conn.targetItem?.id else { return false }
            return itemIDs.contains(sourceID) && itemIDs.contains(targetID)
        }
    }

    private var isBoardOrTagFilterActive: Bool {
        filterBoard != nil || filterTag != nil
    }

    private var hasRelationshipTypeFilter: Bool {
        filterRelationshipTypes.count != ConnectionType.allCases.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .foregroundStyle(Color.textSecondary)
                    Text("Knowledge Graph")
                        .font(.groveBodyMedium)

                    Spacer()

                    // Board filter
                    Picker("Board", selection: $filterBoard) {
                        Text("All Boards").tag(Board?.none)
                        Divider()
                        ForEach(allBoards) { board in
                            Label(board.title, systemImage: board.icon ?? "folder")
                                .tag(Board?.some(board))
                        }
                    }
                    .frame(width: 160)

                    // Tag filter
                    Picker("Tag", selection: $filterTag) {
                        Text("All Tags").tag(Tag?.none)
                        Divider()
                        ForEach(allTags.sorted(by: { $0.name < $1.name })) { tag in
                            Text(tag.name).tag(Tag?.some(tag))
                        }
                    }
                    .frame(width: 140)

                    Button {
                        rebuildScene()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .help("Reset Layout")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                relationshipLegend
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // Graph canvas
            if filteredItems.isEmpty {
                emptyState
            } else {
                ZStack {
                    GraphSceneView(
                        items: filteredItems,
                        connections: filteredConnections,
                        boards: allBoards,
                        selectedItem: $selectedItem,
                        scene: $scene
                    )

                    if filteredConnections.isEmpty {
                        noConnectionsState
                            .padding(20)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .onAppear {
            rebuildScene()
        }
        .onChange(of: filterBoard) {
            rebuildScene()
        }
        .onChange(of: filterTag) {
            rebuildScene()
        }
        .onChange(of: filterRelationshipTypes) {
            rebuildScene()
        }
    }

    private var relationshipLegend: some View {
        HStack(spacing: 8) {
            Text("Relationships")
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(ConnectionType.allCases, id: \.self) { type in
                        ConnectionTypeLegendPill(
                            type: type,
                            isEnabled: filterRelationshipTypes.contains(type)
                        ) {
                            toggleRelationshipType(type)
                        }
                    }

                    if hasRelationshipTypeFilter {
                        Button("Show All") {
                            filterRelationshipTypes = Set(ConnectionType.allCases)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help("Enable every relationship type.")
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 48))
                .foregroundStyle(Color.textSecondary)
            Text(isBoardOrTagFilterActive ? "No Items Match Filters" : "No Items to Graph")
                .font(.groveTitleLarge)
            Text(emptyStateDescription)
                .font(.groveBody)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateDescription: String {
        if isBoardOrTagFilterActive {
            return "Try a different board or tag filter to populate the graph."
        }
        return "Add items and create connections to see your knowledge graph."
    }

    private var noConnectionsState: some View {
        VStack(spacing: 6) {
            Image(systemName: "line.3.crossed.swirl.circle")
                .foregroundStyle(Color.textSecondary)
            Text(noConnectionsTitle)
                .font(.groveBodyMedium)
            Text(noConnectionsDescription)
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.textSecondary.opacity(0.25), lineWidth: 1)
        )
    }

    private var noConnectionsTitle: String {
        if filterRelationshipTypes.isEmpty {
            return "No Relationship Types Selected"
        }
        return "No Connections to Display"
    }

    private var noConnectionsDescription: String {
        if filterRelationshipTypes.isEmpty {
            return "Enable one or more relationship types in the legend to draw edges."
        }
        if hasRelationshipTypeFilter {
            return "No edges match the selected relationship filters with the current board/tag view."
        }
        if isBoardOrTagFilterActive {
            return "These items do not have connections between them yet."
        }
        return "Create connections between items to reveal relationship paths."
    }

    private func toggleRelationshipType(_ type: ConnectionType) {
        if filterRelationshipTypes.contains(type) {
            filterRelationshipTypes.remove(type)
        } else {
            filterRelationshipTypes.insert(type)
        }
    }

    private func rebuildScene() {
        let newScene = GraphScene(size: CGSize(width: 1200, height: 800))
        newScene.scaleMode = .resizeFill
        newScene.backgroundColor = .clear
        newScene.configure(items: filteredItems, connections: filteredConnections, boards: allBoards)
        newScene.onNodeSelected = { item, shouldOpen in
            selectedItem = item
            if shouldOpen {
                openedItem = item
            }
        }
        scene = newScene
    }
}

private struct ConnectionTypeLegendPill: View {
    let type: ConnectionType
    let isEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                ConnectionTypeLegendLine(type: type)
                Text(type.displayLabel)
                    .font(.groveBodySmall)
                    .foregroundStyle(isEnabled ? Color.textPrimary : Color.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isEnabled ? Color.bgCardHover : Color.bgCard, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.textSecondary.opacity(isEnabled ? 0.35 : 0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.72)
        .help(isEnabled ? "Hide \(type.displayLabel) edges." : "Show \(type.displayLabel) edges.")
        .accessibilityLabel("\(type.displayLabel) relationships")
        .accessibilityHint(
            isEnabled
            ? "Currently visible. Activate to hide this relationship type."
            : "Currently hidden. Activate to show this relationship type."
        )
    }
}

private struct ConnectionTypeLegendLine: View {
    let type: ConnectionType

    var body: some View {
        let style = type.graphConnectionStyle
        Canvas { context, size in
            var path = Path()
            let midY = size.height / 2
            path.move(to: CGPoint(x: 0, y: midY))
            path.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(
                path,
                with: .color(Color(style.strokeColor)),
                style: StrokeStyle(
                    lineWidth: style.lineWidth,
                    dash: style.isDashed ? [6, 4] : []
                )
            )
        }
        .frame(width: 24, height: 10)
        .accessibilityHidden(true)
    }
}

// MARK: - SpriteKit Scene View Wrapper

#if os(macOS)
struct GraphSceneView: NSViewRepresentable {
    let items: [Item]
    let connections: [Connection]
    let boards: [Board]
    @Binding var selectedItem: Item?
    @Binding var scene: GraphScene?

    func makeNSView(context: Context) -> SKView {
        let skView = SKView()
        skView.allowsTransparency = true
        skView.ignoresSiblingOrder = true
        if let scene {
            Task { @MainActor in
                skView.presentScene(scene)
            }
        }
        return skView
    }

    func updateNSView(_ skView: SKView, context: Context) {
        if let scene, skView.scene !== scene {
            Task { @MainActor in
                skView.presentScene(scene)
            }
        }
    }
}
#else
struct GraphSceneView: UIViewRepresentable {
    let items: [Item]
    let connections: [Connection]
    let boards: [Board]
    @Binding var selectedItem: Item?
    @Binding var scene: GraphScene?

    func makeUIView(context: Context) -> SKView {
        let skView = SKView()
        skView.allowsTransparency = true
        skView.ignoresSiblingOrder = true
        if let scene {
            Task { @MainActor in
                skView.presentScene(scene)
            }
        }
        return skView
    }

    func updateUIView(_ skView: SKView, context: Context) {
        if let scene, skView.scene !== scene {
            Task { @MainActor in
                skView.presentScene(scene)
            }
        }
    }
}
#endif

// MARK: - Graph Scene (SpriteKit)

class GraphScene: SKScene {
    var onNodeSelected: ((Item, Bool) -> Void)?

    private var graphNodes: [UUID: GraphNodeSprite] = [:]
    private var edgeNodes: [SKShapeNode] = []
    private var itemMap: [UUID: Item] = [:]
    private var boardColors: [UUID: SKColor] = [:]
    private var draggedNode: GraphNodeSprite?
    private var isPanning = false
    private var lastPanLocation: CGPoint = .zero
    private var cameraNode = SKCameraNode()

    // Physics
    private let springLength: CGFloat = 120
    private let springStrength: CGFloat = 0.003
    private let repulsionStrength: CGFloat = 8000
    private let dampingFactor: CGFloat = 0.7
    private let centerGravity: CGFloat = 0.003
    private var velocities: [UUID: CGVector] = [:]
    private var isSimulating = true
    private var simulationSteps = 0
    private let maxSimulationSteps = 100

    // Connections data for drawing edges
    private var connectionData: [(sourceID: UUID, targetID: UUID, type: ConnectionType)] = []

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        backgroundColor = .clear

        #if os(macOS)
        // Set up zoom with scroll wheel
        view.allowedTouchTypes = []
        #endif

        // Start simulation timer
        isPaused = false
    }

    func configure(items: [Item], connections: [Connection], boards: [Board]) {
        removeAllChildren()
        graphNodes.removeAll()
        edgeNodes.removeAll()
        itemMap.removeAll()
        velocities.removeAll()
        connectionData.removeAll()
        simulationSteps = 0
        isSimulating = true

        if cameraNode.parent == nil {
            addChild(cameraNode)
        }
        camera = cameraNode

        // Build board color map
        for board in boards {
            if let hex = board.color {
                boardColors[board.id] = skColor(fromHex: hex)
            }
        }

        // Create nodes
        let sceneCenter = CGPoint(x: size.width / 2, y: size.height / 2)
        for (index, item) in items.enumerated() {
            itemMap[item.id] = item

            let angle = CGFloat(index) / CGFloat(max(items.count, 1)) * 2 * .pi
            let radius: CGFloat = CGFloat.random(in: 80...300)
            let x = sceneCenter.x + cos(angle) * radius
            let y = sceneCenter.y + sin(angle) * radius

            let nodeSprite = GraphNodeSprite(item: item, boardColors: boardColors)
            nodeSprite.position = CGPoint(x: x, y: y)
            addChild(nodeSprite)
            graphNodes[item.id] = nodeSprite
            velocities[item.id] = .zero
        }

        // Store connection data
        for connection in connections {
            guard let sourceID = connection.sourceItem?.id,
                  let targetID = connection.targetItem?.id else { continue }
            connectionData.append((sourceID: sourceID, targetID: targetID, type: connection.type))
        }

        drawEdges()
    }

    // MARK: - Simulation

    override func update(_ currentTime: TimeInterval) {
        guard isSimulating else { return }
        simulationSteps += 1
        if simulationSteps > maxSimulationSteps {
            isSimulating = false
            velocities.removeAll()
            return
        }

        let nodeIDs = Array(graphNodes.keys)
        let nodeArray = nodeIDs.compactMap { graphNodes[$0] }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        // Calculate forces
        for i in 0..<nodeArray.count {
            let nodeA = nodeArray[i]
            let idA = nodeIDs[i]
            var force = CGVector.zero

            // Repulsion from all other nodes
            for j in 0..<nodeArray.count where i != j {
                let nodeB = nodeArray[j]
                let dx = nodeA.position.x - nodeB.position.x
                let dy = nodeA.position.y - nodeB.position.y
                let distSq = max(dx * dx + dy * dy, 1)
                let dist = sqrt(distSq)
                let repForce = repulsionStrength / distSq
                force.dx += (dx / dist) * repForce
                force.dy += (dy / dist) * repForce
            }

            // Spring attraction along edges
            for conn in connectionData {
                let otherID: UUID?
                if conn.sourceID == idA { otherID = conn.targetID }
                else if conn.targetID == idA { otherID = conn.sourceID }
                else { otherID = nil }

                if let otherID, let otherNode = graphNodes[otherID] {
                    let dx = otherNode.position.x - nodeA.position.x
                    let dy = otherNode.position.y - nodeA.position.y
                    let dist = sqrt(dx * dx + dy * dy)
                    let displacement = dist - springLength
                    if dist > 0 {
                        force.dx += (dx / dist) * displacement * springStrength
                        force.dy += (dy / dist) * displacement * springStrength
                    }
                }
            }

            // Center gravity
            let cx = center.x - nodeA.position.x
            let cy = center.y - nodeA.position.y
            force.dx += cx * centerGravity
            force.dy += cy * centerGravity

            // Update velocity with damping
            var vel = velocities[idA] ?? .zero
            vel.dx = (vel.dx + force.dx) * dampingFactor
            vel.dy = (vel.dy + force.dy) * dampingFactor
            velocities[idA] = vel
        }

        // Apply velocities (skip dragged node)
        for i in 0..<nodeArray.count {
            let node = nodeArray[i]
            let id = nodeIDs[i]
            if draggedNode === node { continue }
            let vel = velocities[id] ?? .zero
            node.position.x += vel.dx
            node.position.y += vel.dy
        }

        drawEdges()
    }

    // MARK: - Edge Drawing

    private func drawEdges() {
        for edge in edgeNodes {
            edge.removeFromParent()
        }
        edgeNodes.removeAll()

        for conn in connectionData {
            guard let sourceNode = graphNodes[conn.sourceID],
                  let targetNode = graphNodes[conn.targetID] else { continue }

            let path = CGMutablePath()
            path.move(to: sourceNode.position)
            path.addLine(to: targetNode.position)

            let edgeShape = SKShapeNode(path: path)
            edgeShape.zPosition = -1

            let style = conn.type.graphConnectionStyle
            edgeShape.strokeColor = style.strokeColor
            edgeShape.lineWidth = style.lineWidth
            if style.isDashed {
                edgeShape.path = dashedPath(from: sourceNode.position, to: targetNode.position)
            }

            addChild(edgeShape)
            edgeNodes.append(edgeShape)
        }
    }

    private func dashedPath(from start: CGPoint, to end: CGPoint) -> CGPath {
        let path = CGMutablePath()
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        let dashLength: CGFloat = 6
        let gapLength: CGFloat = 4
        let segmentLength = dashLength + gapLength
        let segments = Int(length / segmentLength)

        for i in 0..<segments {
            let t0 = CGFloat(i) * segmentLength / length
            let t1 = min((CGFloat(i) * segmentLength + dashLength) / length, 1.0)
            path.move(to: CGPoint(x: start.x + dx * t0, y: start.y + dy * t0))
            path.addLine(to: CGPoint(x: start.x + dx * t1, y: start.y + dy * t1))
        }
        return path
    }

    // MARK: - Input Handling

    #if os(macOS)
    override func mouseDown(with event: NSEvent) {
        let location = event.location(in: self)

        // Check if a node was clicked
        for (_, node) in graphNodes {
            if node.contains(location) || node.frame.insetBy(dx: -10, dy: -10).contains(location) {
                draggedNode = node
                node.setHighlighted(true)
                if let item = node.item {
                    onNodeSelected?(item, event.clickCount >= 2)
                }
                return
            }
        }

        // Start panning
        isPanning = true
        lastPanLocation = location
    }

    override func mouseDragged(with event: NSEvent) {
        let location = event.location(in: self)

        if let dragged = draggedNode {
            dragged.position = location
            velocities[dragged.item?.id ?? UUID()] = .zero
        } else if isPanning {
            let dx = location.x - lastPanLocation.x
            let dy = location.y - lastPanLocation.y
            cameraNode.position.x -= dx
            cameraNode.position.y -= dy
            lastPanLocation = location
        }
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragging = draggedNode != nil
        if let dragged = draggedNode {
            dragged.setHighlighted(false)
        }
        draggedNode = nil
        isPanning = false

        // Short settle after drag so neighbors adjust, then freeze
        if wasDragging {
            simulationSteps = maxSimulationSteps - 30
            isSimulating = true
        }
    }

    override func scrollWheel(with event: NSEvent) {
        // Zoom with scroll wheel / trackpad pinch
        let zoomDelta = event.magnification != 0 ? event.magnification : event.deltaY * 0.02
        let newScale = max(0.2, min(3.0, cameraNode.xScale - zoomDelta))
        cameraNode.setScale(newScale)
    }
    #else
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Check if a node was tapped
        for (_, node) in graphNodes {
            if node.contains(location) || node.frame.insetBy(dx: -10, dy: -10).contains(location) {
                draggedNode = node
                node.setHighlighted(true)
                if let item = node.item {
                    onNodeSelected?(item, false)
                }
                return
            }
        }

        // Start panning
        isPanning = true
        lastPanLocation = location
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        if let dragged = draggedNode {
            dragged.position = location
            velocities[dragged.item?.id ?? UUID()] = .zero
        } else if isPanning {
            let dx = location.x - lastPanLocation.x
            let dy = location.y - lastPanLocation.y
            cameraNode.position.x -= dx
            cameraNode.position.y -= dy
            lastPanLocation = location
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasDragging = draggedNode != nil
        if let dragged = draggedNode {
            dragged.setHighlighted(false)
        }
        draggedNode = nil
        isPanning = false

        // Short settle after drag so neighbors adjust, then freeze
        if wasDragging {
            simulationSteps = maxSimulationSteps - 30
            isSimulating = true
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
    #endif

    // MARK: - Helpers

    private func skColor(fromHex hex: String) -> SKColor {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: CGFloat
        switch hex.count {
        case 6:
            r = CGFloat((int >> 16) & 0xFF) / 255
            g = CGFloat((int >> 8) & 0xFF) / 255
            b = CGFloat(int & 0xFF) / 255
        default:
            r = 0.5; g = 0.5; b = 0.5
        }
        return SKColor(red: r, green: g, blue: b, alpha: 1)
    }
}

private struct GraphConnectionStyle {
    let strokeColor: SKColor
    let lineWidth: CGFloat
    let isDashed: Bool
}

private extension ConnectionType {
    var graphConnectionStyle: GraphConnectionStyle {
        switch self {
        case .buildsOn:
            GraphConnectionStyle(
                strokeColor: SKColor.systemGreen.withAlphaComponent(0.72),
                lineWidth: 2,
                isDashed: false
            )
        case .contradicts:
            GraphConnectionStyle(
                strokeColor: SKColor.systemRed.withAlphaComponent(0.8),
                lineWidth: 2,
                isDashed: false
            )
        case .related:
            GraphConnectionStyle(
                strokeColor: SKColor.graphLabel.withAlphaComponent(0.45),
                lineWidth: 1,
                isDashed: true
            )
        case .inspiredBy:
            GraphConnectionStyle(
                strokeColor: SKColor.systemBlue.withAlphaComponent(0.72),
                lineWidth: 1.5,
                isDashed: false
            )
        case .sameTopic:
            GraphConnectionStyle(
                strokeColor: SKColor.systemOrange.withAlphaComponent(0.72),
                lineWidth: 1,
                isDashed: true
            )
        }
    }
}

// MARK: - Graph Node Sprite

class GraphNodeSprite: SKNode {
    private(set) var item: Item?
    private let circle: SKShapeNode
    private let label: SKLabelNode
    private let baseRadius: CGFloat

    init(item: Item, boardColors: [UUID: SKColor]) {
        self.item = item

        // Size based on depth score (min 14, max 36)
        let score = CGFloat(item.depthScore)
        baseRadius = 14 + min(score / 6.0, 10) * 2.2

        // Monochromatic: opacity varies by depth score for visual hierarchy
        let depthOpacity = 0.5 + min(score / 10.0, 0.4)
        let fillColor = SKColor.graphLabel.withAlphaComponent(depthOpacity)
        let strokeColor = SKColor.graphLabel.withAlphaComponent(min(depthOpacity + 0.2, 1.0))

        circle = SKShapeNode(circleOfRadius: baseRadius)
        circle.fillColor = fillColor
        circle.strokeColor = strokeColor
        circle.lineWidth = 2
        circle.glowWidth = 0

        label = SKLabelNode(text: String(item.title.prefix(20)))
        label.fontSize = 10
        label.fontName = "IBMPlexMono-Regular"
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.preferredMaxLayoutWidth = baseRadius * 2.5
        label.numberOfLines = 2

        super.init()

        addChild(circle)

        // Label below the node
        label.position = CGPoint(x: 0, y: -baseRadius - 12)
        label.fontColor = SKColor.graphLabel
        addChild(label)

        // Type icon inside the circle (monospace text symbols)
        let icon = SKLabelNode(text: iconChar(for: item.type))
        icon.fontSize = baseRadius * 0.7
        icon.fontName = "IBMPlexMono-Regular"
        icon.fontColor = .white
        icon.verticalAlignmentMode = .center
        icon.horizontalAlignmentMode = .center
        icon.position = .zero
        addChild(icon)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setHighlighted(_ highlighted: Bool) {
        if highlighted {
            circle.lineWidth = 4
            circle.glowWidth = 0
            let scaleUp = SKAction.scale(to: 1.15, duration: 0.1)
            circle.run(scaleUp)
        } else {
            circle.lineWidth = 2
            circle.glowWidth = 0
            let scaleDown = SKAction.scale(to: 1.0, duration: 0.1)
            circle.run(scaleDown)
        }
    }

    override func contains(_ p: CGPoint) -> Bool {
        let local = convert(p, from: parent!)
        let dist = sqrt(local.x * local.x + local.y * local.y)
        return dist <= baseRadius + 8
    }

    private func iconChar(for type: ItemType) -> String {
        switch type {
        case .article: return "◇"
        case .codebase: return "</>"
        case .video: return "▷"
        case .note: return "∎"
        case .courseLecture: return "◈"
        }
    }
}
