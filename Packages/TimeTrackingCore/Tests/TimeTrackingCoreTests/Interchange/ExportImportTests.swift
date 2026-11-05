// JSON export and import (spec_data_and_sync.md §5; §9 items 36 to 41).

import Foundation
import Testing
import TimeTrackingCore

struct ExportImportTests {
    /// A store with every kind of record, a tombstone, and settings.
    private func populated() async throws -> TestStore {
        let test = try await TestStore()
        let made = try await test.structure(projects: ["Noise paper", "Archive me"])
        try await test.store.archive(made.projects[1].id)
        _ = try await test.store.create(EntryDraft(
            projectID: made.projects[0].id,
            task: "Clarify",
            start: test.date("2024-03-14T08:00"),
            end: test.date("2024-03-14T09:30")
        ))
        let gone = try await test.store.create(EntryDraft(
            projectID: nil,
            task: "gone",
            start: test.date("2024-03-14T07:00"),
            end: test.date("2024-03-14T07:10")
        ))
        try await test.store.delete([gone.id])
        _ = try await test.store.start(projectID: nil, task: "Running", at: test.date("2024-03-14T09:40"))
        try await test.store.set(.pomodoroFocusMinutes, 30)
        try await test.store.set(.pinnedProjectIDs, [made.projects[0].id])
        return test
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func canonical(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func dropping(_ keys: [String], from data: Data) throws -> [String: Any] {
        var document = try object(data)
        for key in keys {
            document[key] = nil
        }
        return document
    }

    @Test("DATA-36 export lists live records with the stated fields and order; unchanged data differs only in generatedAt")
    func exportFormat() async throws {
        let test = try await populated()
        let first = try await test.store.exportDocument()
        let document = try object(first)
        #expect(document["format"] as? Int == 1)
        let entries = try #require(document["entries"] as? [[String: Any]])
        #expect(entries.count == 2)
        #expect(Set(entries[0].keys) == ["id", "projectID", "task", "start", "end", "timeZone", "deviceID"])
        #expect(entries[0]["start"] as? String == "2024-03-14T07:00:00Z")
        #expect(entries[1]["end"] is NSNull)
        let projects = try #require(document["projects"] as? [[String: Any]])
        #expect(projects.map { $0["name"] as? String } == ["Archive me", "Noise paper"])
        #expect(Set(projects[0].keys) == ["id", "areaID", "name", "archived", "archivedAt", "createdAt"])
        let areas = try #require(document["areas"] as? [[String: Any]])
        #expect(areas.map { $0["sortOrder"] as? Int } == [0, 1])
        let settings = try #require(document["settings"] as? [String: Any])
        #expect(settings["pomodoro.focusMinutes"] as? Int == 30)
        let text = String(decoding: first, as: UTF8.self)
        #expect(text.range(of: "\"areas\"")?.lowerBound ?? text.endIndex < text.range(of: "\"clients\"")?.lowerBound ?? text.startIndex)
        test.clock.advance(by: 60)
        let second = try await test.store.exportDocument()
        #expect(try canonical(dropping(["generatedAt"], from: first)) == canonical(dropping(
            ["generatedAt"],
            from: second
        )))
        let withDeleted = try await object(test.store.exportDocument(includeDeleted: true))
        let all = try #require(withDeleted["entries"] as? [[String: Any]])
        #expect(all.count == 3)
        #expect(all.filter { $0["deletedAt"] != nil }.map { $0["task"] as? String } == ["gone"])
    }

    @Test("DATA-37 export, import into an empty store with settings, and export again round-trips")
    func roundTrip() async throws {
        let source = try await populated()
        let first = try await source.store.exportDocument()
        let target = try await TestStore()
        let report = try await target.store.importDocument(first, options: ImportOptions(includeSettings: true))
        #expect(report[.entry].created == 2)
        let second = try await target.store.exportDocument()
        let keys = ["generatedAt", "storeID"]
        #expect(try canonical(dropping(keys, from: first)) == canonical(dropping(keys, from: second)))
    }

    @Test("DATA-38 re-import changes nothing; a changed task updates one entry; tombstones stay; deletedAt is ignored")
    func reimport() async throws {
        let test = try await populated()
        let full = try await test.store.exportDocument(includeDeleted: true)
        let outbox = try await test.store.outboxCount()
        let again = try await test.store.importDocument(test.store.exportDocument(), options: ImportOptions())
        #expect(again.isNoOp)
        #expect(again[.entry].unchanged == 2)
        #expect(try await test.store.outboxCount() == outbox)
        var document = try object(full)
        var entries = try #require(document["entries"] as? [[String: Any]])
        let gone = try #require(entries.firstIndex { $0["task"] as? String == "gone" })
        entries[gone]["deletedAt"] = nil
        let live = try #require(entries.firstIndex { $0["task"] as? String == "Clarify" })
        entries[live]["task"] = "Clarified"
        document["entries"] = entries
        var projects = try #require(document["projects"] as? [[String: Any]])
        projects[0]["deletedAt"] = "2024-03-14T09:00:00Z"
        projects[0]["name"] = "Should not apply"
        document["projects"] = projects
        let report = try await test.store.importDocument(JSONSerialization.data(withJSONObject: document), options: ImportOptions())
        #expect(report[.entry].updated == 1)
        #expect(report[.entry].skippedDeleted == 1)
        #expect(report[.entry].unchanged == 1)
        #expect(report[.project].unchanged == 1)
        let names = try await test.store.projects(filter: ProjectFilter(state: .all)).map(\.project.name)
        #expect(!names.contains("Should not apply"))
        #expect(try await test.store.entries(on: TrackingDay(year: 2024, month: 3, day: 14)).map(\.task).sorted() == [
            "Clarified",
            "Running",
        ])
    }

    @Test("DATA-39 invalid documents fail with the JSON path and leave the store unchanged", arguments: [
        BadField("entries", 0, "end", "2024-03-14T06:00:00Z", "entries[0].end"),
        BadField("areas", 0, "color", "teal", "areas[0].color"),
        BadField("entries", 0, "end", nil, "entries[1].end"),
        BadField("entries", 0, "projectID", "7d1c4a0e-0000-4000-8000-000000000001", "entries[0].projectID"),
        BadField("entries", 1, "start", "2024-03-15T07:00:00Z", "entries[1].start"),
    ])
    func invalidDocuments(bad: BadField) async throws {
        let source = try await populated()
        var document = try await object(source.store.exportDocument())
        var records = try #require(document[bad.array] as? [[String: Any]])
        records[bad.index][bad.key] = bad.value ?? NSNull()
        document[bad.array] = records
        let data = try JSONSerialization.data(withJSONObject: document)
        let target = try await TestStore()
        let before = try await target.store.exportDocument()
        await #expect {
            try await target.store.importDocument(data, options: ImportOptions())
        } throws: { error in
            guard case let StoreError.invalidDocument(found, _) = error else {
                return false
            }
            return found == bad.path
        }
        let after = try await target.store.exportDocument()
        #expect(try canonical(dropping(["generatedAt"], from: before)) == canonical(dropping(
            ["generatedAt"],
            from: after
        )))
    }

    @Test("DATA-40 a client without a general area gets one with a derived id, once")
    func generalAreaForImportedClient() async throws {
        let client = ClientID()
        let document: [String: Any] = ["format": 1, "clients": [["id": client.rawValue, "name": "Imported"]]]
        let data = try JSONSerialization.data(withJSONObject: document)
        let test = try await TestStore()
        let first = try await test.store.importDocument(data, options: ImportOptions())
        #expect(first[.area].created == 1)
        _ = try await test.store.importDocument(data, options: ImportOptions())
        let areas = try await test.store.areas(of: client, includeRetired: true)
        #expect(areas.map(\.id) == [AreaID(UUID.version5(namespace: client.uuid, name: "general-area"))])
        #expect(areas.first?.isGeneral == true)
        #expect(areas.first?.name == "Imported")
    }

    @Test("DATA-41 imports keep entries whole, stop at the local running start, default zone and device, and dry-run")
    func importRules() async throws {
        let test = try await TestStore()
        let local = try await test.store.start(projectID: nil, task: "local", at: test.date("2024-03-14T09:00"))
        let late = EntryID()
        let running = EntryID()
        let document: [String: Any] = [
            "format": 1,
            "entries": [
                ["id": late.rawValue, "start": "2024-03-12T21:00:00Z", "end": "2024-03-13T01:00:00Z"],
                [
                    "id": running.rawValue,
                    "start": "2024-03-14T07:30:00Z",
                    "end": NSNull(),
                    "timeZone": "Europe/Berlin",
                    "deviceID": DeviceID().rawValue,
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: document)
        let dry = try await test.store.importDocument(data, options: ImportOptions(dryRun: true, defaultTimeZone: "Europe/Berlin"))
        #expect(try await test.store.entry(late) == nil)
        let report = try await test.store.importDocument(data, options: ImportOptions(defaultTimeZone: "Europe/Berlin"))
        #expect(dry == report)
        let imported = try #require(try await test.store.entry(late))
        #expect(imported.timeZone == "Europe/Berlin")
        #expect(imported.deviceID == test.deviceID)
        #expect(try imported.end == (test.date("2024-03-13T02:00")))
        #expect(try await test.store.entry(running)?.end == local.start)
        #expect(try await test.store.runningEntry()?.id == local.id)
    }
}

/// One field to break in DATA-39 and the path the error must name.
struct BadField: Sendable, CustomTestStringConvertible {
    var array: String
    var index: Int
    var key: String
    var value: String?
    var path: String

    init(_ array: String, _ index: Int, _ key: String, _ value: String?, _ path: String) {
        self.array = array
        self.index = index
        self.key = key
        self.value = value
        self.path = path
    }

    var testDescription: String {
        path
    }
}
