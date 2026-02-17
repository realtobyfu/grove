import SwiftUI
import SwiftData

@main
struct GroveApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            Item.self,
            Board.self,
            Tag.self,
            Connection.self,
            Annotation.self,
            Nudge.self
        ])
        .defaultSize(width: 1200, height: 800)
    }
}
