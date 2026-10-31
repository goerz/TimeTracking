// Launching under -UITesting (spec_architecture.md §2.5, §3.3).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

@MainActor
struct AppHostTests {
    @Test("ARCH-17 -UITesting YES -Fixture small opens the fixture in memory, never the store file, and starts no CloudKit sync")
    func uiTestingLaunch() async throws {
        let arguments = LaunchArguments(arguments: ["app", "-UITesting", "YES", "-Fixture", "small"], environment: [:])
        let host = AppHost(arguments: arguments)
        #expect(!host.startsLiveUpdates)
        #expect(AppHost(arguments: LaunchArguments()).startsLiveUpdates)
        #expect(TimeStore.Location.resolve(arguments: arguments, identity: AppIdentity.main) == .inMemory)
        let loaded = await host.load(
            notifier: RecordingNotifier(),
            agent: FakeAgentService(),
            loginItem: FakeAppLoginItem(),
            automation: FakeAutomationPermission(),
            readTrackerState: { nil },
            trackerCommands: RecordingTrackerCommands(),
            trackerSettingsURL: nil,
            activity: InMemoryActivityStore(),
            calendarEvents: InMemoryCalendarEventStore(access: .denied)
        )
        let model = try #require(loaded)
        #expect(model.store.location == .inMemory)
        #expect(try await model.store.clients(includeRetired: true).count == 3)
        // No LiveUpdates: no sync engine, no LiveState, no widget pushes.
        #expect(model.live == nil)
        await model.store.close()
    }
}
