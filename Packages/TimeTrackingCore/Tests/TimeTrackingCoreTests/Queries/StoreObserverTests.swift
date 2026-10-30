// StoreObserver (spec_data_and_sync.md §7.4).

import Foundation
import Testing
import TimeTrackingCore

@MainActor
struct StoreObserverTests {
    @Test func followsTheStore() async throws {
        let test = try await TestStore()
        let observer = StoreObserver()
        let stream = test.store.changes
        let entry = try await test.store.start(projectID: nil, task: "Write", at: test.clock.now)
        test.store.publish(.waitingForNetwork)
        await test.store.close()
        await observer.consume(stream)
        #expect(observer.runningEntry?.id == entry.id)
        #expect(observer.entriesRevision == 1)
        #expect(observer.syncStatus == .waitingForNetwork)
        observer.apply(.adjusted([]))
        #expect(observer.takeAdjustments().isEmpty)
    }
}
