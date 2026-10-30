// The busy timeout between writers (spec_data_and_sync.md §2.2;
// spec_automation.md §9 item 32).

import Foundation
import SQLite3
import Testing
import TimeTrackingCore

struct StoreBusyTests {
    @Test("AUTO-32 the busy timeout is 5 seconds, between the 2-second and 10-second locks; past it a write fails busy")
    func busyTimeout() async throws {
        #expect(TimeStore.defaultBusyTimeout == 5)
        #expect(TimeStore.defaultBusyTimeout > 2 && TimeStore.defaultBusyTimeout < 10)
        let folder = FileManager.default.temporaryDirectory.appending(path: "busy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "store.sqlite")
        let clock = ManualClock(Date(timeIntervalSince1970: 1_800_000_000))
        let configuration = TimeStore.Configuration(location: .file(url), clock: clock, deviceID: DeviceID())
        #expect(configuration.busyTimeout == TimeStore.defaultBusyTimeout)
        var impatient = configuration
        impatient.busyTimeout = 0
        let store = try await TimeStore.open(impatient)
        var database: OpaquePointer?
        #expect(sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
        #expect(sqlite3_exec(database, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK)
        await #expect(throws: StoreError.busy) {
            try await store.start(projectID: nil, task: "Blocked", at: clock.now)
        }
        sqlite3_exec(database, "COMMIT", nil, nil, nil)
        sqlite3_close(database)
        _ = try await store.start(projectID: nil, task: "Free", at: clock.now)
        #expect(try await store.runningEntry()?.task == "Free")
        await store.close()
    }

    @Test func busyTimeoutVariable() {
        #expect(LaunchArguments(arguments: [], environment: ["TIMETRACKING_BUSY_TIMEOUT": "0.5"]).busyTimeout == 0.5)
        #expect(LaunchArguments(arguments: [], environment: ["TIMETRACKING_BUSY_TIMEOUT": "soon"]).busyTimeout == nil)
        #expect(LaunchArguments(arguments: [], environment: ["TIMETRACKING_BUSY_TIMEOUT": "-1"]).busyTimeout == nil)
        #expect(LaunchArguments(arguments: [], environment: [:]).busyTimeout == nil)
    }
}
