// Helpers for the store tests (data_and_sync.md §9).

import Foundation
import Testing
import TimeTrackingCore

/// A store at a fixed time in a fixed zone, with its clock and notifier.
struct TestStore {
    let store: TimeStore
    let clock: ManualClock
    let zone: TimeZone
    let notifier: InMemoryChangeNotifier
    let deviceID: DeviceID

    init(
        now: String = "2024-03-14T10:00",
        zone: String = "Europe/Berlin",
        deviceID: DeviceID = DeviceID(),
        hub: InMemoryChangeNotifier.Hub = .init(),
        clock: ManualClock? = nil
    ) async throws {
        let zone = try #require(TimeZone(identifier: zone))
        self.zone = zone
        let clock = try clock ?? ManualClock(Self.date(now, zone))
        self.clock = clock
        self.notifier = InMemoryChangeNotifier(hub: hub)
        self.deviceID = deviceID
        self.store = try await TimeStore.inMemory(clock: clock, deviceID: deviceID, timeZone: zone, notifier: notifier)
    }

    /// A local time `yyyy-MM-dd'T'HH:mm[:ss]` in `zone`.
    static func date(_ text: String, _ zone: TimeZone) throws -> Date {
        try TestTime.local(text, in: zone)
    }

    /// A local time in this store's zone.
    func date(_ text: String) throws -> Date {
        try Self.date(text, zone)
    }

    /// A client "Client" with one area and the named projects.
    func structure(projects names: [String] = ["Alpha"]) async throws -> TestStructure {
        let (client, _) = try await store.createClient(name: "Client \(UUID().uuidString.prefix(4))")
        let area = try await store.createArea(AreaDraft(clientID: client.id, name: "Research"))
        var projects: [Project] = []
        for name in names {
            try await projects.append(store.createProject(ProjectDraft(areaID: area.id, name: name)))
        }
        return TestStructure(client: client, area: area, projects: projects)
    }
}

/// A client with one area and its projects.
struct TestStructure {
    var client: Client
    var area: Area
    var projects: [Project]
}
