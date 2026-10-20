import Foundation
import Testing
@testable import grove

@MainActor
struct SyncServiceTests {
    @Test func enabledDoesNotClaimCompletedSync() {
        let service = SyncService(syncEnabled: true, startsMonitoring: false)
        #expect(service.status == .waiting)
        #expect(service.lastCompletedAt == nil)
        service.refresh()
        #expect(service.status == .waiting)
        service.stopMonitoring()
    }

    @Test func completingOneConcurrentEventDoesNotHideAnother() {
        let service = SyncService(syncEnabled: true, startsMonitoring: false)
        let first = UUID(), second = UUID()
        service.recordEvent(id: first, completedAt: nil, errorDescription: nil)
        service.recordEvent(id: second, completedAt: nil, errorDescription: nil)
        service.recordEvent(id: first, completedAt: .now, errorDescription: nil)
        #expect(service.status == .syncing)
        service.recordEvent(id: second, completedAt: .now, errorDescription: nil)
        #expect(service.status == .synced)
    }

    @Test func setupCompletionDoesNotAcknowledgeDataTransfer() {
        let service = SyncService(syncEnabled: true, startsMonitoring: false)
        service.recordEvent(id: UUID(), completedAt: .now, errorDescription: nil, isDataTransfer: false)
        #expect(service.status == .waiting)
    }

    @Test func errorRemainsVisibleUntilSuccessfulTransfer() {
        let service = SyncService(syncEnabled: true, startsMonitoring: false)
        service.recordEvent(id: UUID(), completedAt: .now, errorDescription: "Offline")
        #expect(service.status == .error("Offline"))
        service.refresh()
        #expect(service.status == .error("Offline"))
        service.stopMonitoring()
        service.recordEvent(id: UUID(), completedAt: .now, errorDescription: nil, isDataTransfer: false)
        #expect(service.status == .error("Offline"))
        service.recordEvent(id: UUID(), completedAt: .now, errorDescription: nil)
        #expect(service.status == .synced)
    }
}
