import Foundation
import SwiftData

/// The app doubles as the unit tests' host. While it is one, it must not open
/// the person's real library, sync, migrate, index or reach the network: the
/// tests bring their own in-memory stores, and the host only has to launch.
///
/// Debug builds only. A Release build is never a test host.
enum TestHost {
    static var isActive: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
        #else
        false
        #endif
    }

    /// An empty in-memory library with no CloudKit, for the host to hold.
    static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: SharedModelContainer.schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: SharedModelContainer.schema, configurations: [configuration])
    }
}
