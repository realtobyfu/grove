import SwiftUI
import SwiftData
import SpriteKit

// MARK: - Graph Visualization View

struct GraphVisualizationView: View {
    @Binding var selectedItem: Item?
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [Item]
    @Query private var allConnections: [Connection]
    @Query(sort: \Board.sortOrder) private var allBoards: [Board]
    @Query private var allTags: [Tag]

    @State private var filterBoard: Board?
    @State private var filterTag: Tag?
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
            guard let sourceID = conn.sourceItem?.id, let targetID = conn.targetItem?.id else { return false }
            return itemIDs.contains(sourceID) && itemIDs.contains(targetID)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // Graph canvas
            if filteredItems.isEmpty {
                emptyState
            } else {
                GraphSceneView(
                    items: filteredItems,
                    connections: filteredConnections,
                    boards: allBoards,
                    selectedItem: $selectedItem,
                    scene: $scene
                )
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
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 48))
                .foregroundStyle(Color.textSecondary)
            Text("No Items to Graph")
                .font(.groveTitleLarge)
            Text("Add items and create connections to see your knowledge graph.")
                .font(.groveBody)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rebuildScene() {
        let newScene = GraphScene(size: CGSize(width: 1200, height: 800))
        newScene.scaleMode = .resizeFill
        newScene.backgroundColor = .clear
        newScene.configure(items: filteredItems, connections: filteredConnections, boards: allBoards)
        newScene.onNodeSelected = { item in
            selectedItem = item
        }
        scene = newScene
    }
}

// MARK: - SpriteKit Scene View Wrapper

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
            // Defer to avoid presenting scene during layout pass
            Task { @MainActor in
                skView.presentScene(scene)
            }
        }
        return skView
    }

    func updateNSView(_ skView: SKView, context: Context) {
        if let scene, skView.scene !== scene {
            // Defer to avoid re-entrant layout from SpriteKit's presentScene
            Task { @MainActor in
                skView.presentScene(scene)
            }
        }
    }
}

// MARK: - Graph Scene (SpriteKit)

class GraphScene: SKScene {
    var onNodeSelected: ((Item) -> Void)?

    private var graphNodes: [UUID: GraphNodeSprite] = [:]
    private var edgeNodes: [SKShapeNode] = []
    private var itemMap: [UUID: Item] = [:]
    private var boardColors: [UUID: NSColor] = [:]
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

        // Set up zoom with scroll wheel
        view.allowedTouchTypes = []

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
                boardColors[board.id] = nsColor(fromHex: hex)
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

            switch conn.type {
            case .buildsOn:
                edgeShape.strokeColor = NSColor.labelColor.withAlphaComponent(0.6)
                edgeShape.lineWidth = 2
            case .contradicts:
                edgeShape.strokeColor = NSColor.labelColor.withAlphaComponent(0.8)
                edgeShape.lineWidth = 2
            case .related:
                edgeShape.strokeColor = NSColor.labelColor.withAlphaComponent(0.3)
                edgeShape.lineWidth = 1
                edgeShape.path = dashedPath(from: sourceNode.position, to: targetNode.position)
            case .inspiredBy:
                edgeShape.strokeColor = NSColor.labelColor.withAlphaComponent(0.4)
                edgeShape.lineWidth = 1.5
            case .sameTopic:
                edgeShape.strokeColor = NSColor.labelColor.withAlphaComponent(0.3)
                edgeShape.lineWidth = 1
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

    override func mouseDown(with event: NSEvent) {
        let location = event.location(in: self)

        // Check if a node was clicked
        for (_, node) in graphNodes {
            if node.contains(location) || node.frame.insetBy(dx: -10, dy: -10).contains(location) {
                draggedNode = node
                node.setHighlighted(true)
                if let item = node.item {
                    onNodeSelected?(item)
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

    // MARK: - Helpers

    private func nsColor(fromHex hex: String) -> NSColor {
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
        return NSColor(red: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - Graph Node Sprite

class GraphNodeSprite: SKNode {
    private(set) var item: Item?
    private let circle: SKShapeNode
    private let label: SKLabelNode
    private let baseRadius: CGFloat

    init(item: Item, boardColors: [UUID: NSColor]) {
        self.item = item

        // Size based on depth score (min 14, max 36)
        let score = CGFloat(item.depthScore)
        baseRadius = 14 + min(score / 6.0, 10) * 2.2

        // Monochromatic: opacity varies by depth score for visual hierarchy
        let depthOpacity = 0.5 + min(score / 10.0, 0.4)
        let fillColor = NSColor.labelColor.withAlphaComponent(depthOpacity)
        let strokeColor = NSColor.labelColor.withAlphaComponent(min(depthOpacity + 0.2, 1.0))

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
        label.fontColor = NSColor.labelColor
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
        case .video: return "▷"
        case .note: return "∎"
        case .courseLecture: return "◈"
        }
    }
}
