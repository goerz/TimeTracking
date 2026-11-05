// The fixture moved to today for `make demo` (architecture.md §2.5, §7 item 23).

import Foundation
import Testing
import TimeTrackingCore

struct FixtureShiftTests {
    private static let newYork = TestTime.newYork

    /// `text` (`2026-10-30T15:00`) as local time in New York.
    private func local(_ text: String) throws -> Date {
        try TestTime.local(text, in: Self.newYork)
    }

    /// `date` as `yyyy-MM-ddTHH:mm` in New York.
    private func text(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.newYork
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d-%02d-%02dT%02d:%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0,
            parts.hour ?? 0,
            parts.minute ?? 0
        )
    }

    /// A document generated at 2024-03-14T10:00 New York with `entries` as
    /// `(start, end)` local times (`nil` end: running).
    private func document(_ entries: [(String, String?)]) throws -> Data {
        let records = try entries.enumerated().map { index, entry in
            try [
                "id": UUID().uuidString.lowercased(), "projectID": NSNull(), "task": "Entry \(index)",
                "start": rfc3339(local(entry.0)), "end": entry.1.map { try rfc3339(local($0)) } ?? NSNull(),
                "timeZone": "America/New_York", "deviceID": UUID().uuidString.lowercased(),
            ] as [String: Any]
        }
        let object: [String: Any] = try [
            "format": 1, "generatedAt": rfc3339(local("2024-03-14T10:00")), "clients": [], "areas": [], "projects": [],
            "entries": records, "settings": [:], "devices": [],
        ]
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func rfc3339(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .gmt))
    }

    /// The moved entries as `start…end` local texts (`…running` when open).
    private func spans(_ result: FixtureShift.Result) throws -> [String] {
        let object = try #require(try JSONSerialization.jsonObject(with: result.document) as? [String: Any])
        let entries = try #require(object["entries"] as? [[String: Any]])
        return entries.map { entry in
            let start = (entry["start"] as? String).flatMap { try? Date.ISO8601FormatStyle().parse($0) }
            let end = (entry["end"] as? String).flatMap { try? Date.ISO8601FormatStyle().parse($0) }
            return "\(start.map(text) ?? "?")…\(end.map(text) ?? "running")"
        }
    }

    @Test("Whole calendar days move the fixture's today to today at the same local times")
    func dayShift() throws {
        let data = try document([("2024-03-13T09:15", "2024-03-13T10:40"), ("2024-02-29T23:00", "2024-03-01T00:00")])
        let shift = try FixtureShift(document: data, now: local("2026-10-30T15:00"), timeZone: Self.newYork)
        #expect(shift.days == 960)
        #expect(shift.fixtureZone == Self.newYork)
        let result = try shift.apply(to: data)
        #expect(try spans(result) == ["2026-10-29T09:15…2026-10-29T10:40", "2026-10-16T23:00…2026-10-17T00:00"])
        #expect(result.clipped == 0)
        #expect(result.dropped == 0)
        let object = try #require(try JSONSerialization.jsonObject(with: result.document) as? [String: Any])
        #expect(try object["generatedAt"] as? String == rfc3339(local("2026-10-30T15:00")))
    }

    @Test("Entries of today after now end at now when under way and are dropped when they start later")
    func clipAndDrop() throws {
        let data = try document([
            ("2024-03-14T08:00", "2024-03-14T09:00"),
            ("2024-03-14T09:10", "2024-03-14T09:50"),
            ("2024-03-14T09:40", "2024-03-14T09:55"),
        ])
        let result = try FixtureShift(document: data, now: local("2026-10-30T09:30"), timeZone: Self.newYork).apply(to: data)
        #expect(try spans(result) == ["2026-10-30T08:00…2026-10-30T09:00", "2026-10-30T09:10…2026-10-30T09:30"])
        #expect(result.clipped == 1)
        #expect(result.dropped == 1)
    }

    @Test("A running entry keeps its age; finished entries end before it starts")
    func runningAge() throws {
        let data = try document([("2024-03-14T09:00", "2024-03-14T09:30"), ("2024-03-14T09:35", nil)])
        let early = try FixtureShift(document: data, now: local("2026-10-30T09:40"), timeZone: Self.newYork).apply(to: data)
        #expect(try spans(early) == ["2026-10-30T09:00…2026-10-30T09:15", "2026-10-30T09:15…running"])
        #expect(early.clipped == 1)
        let late = try FixtureShift(document: data, now: local("2026-10-30T15:00"), timeZone: Self.newYork).apply(to: data)
        #expect(try spans(late) == ["2026-10-30T09:00…2026-10-30T09:30", "2026-10-30T14:35…running"])
        let object = try #require(try JSONSerialization.jsonObject(with: late.document) as? [String: Any])
        let running = try #require((object["entries"] as? [[String: Any]])?.last)
        let start = try Date.ISO8601FormatStyle().parse(#require(running["start"] as? String))
        #expect(try local("2026-10-30T15:00").timeIntervalSince(start) == 25 * 60)
    }

    @Test("Across DST (America/New_York) local times stay: EST days land in EDT and EDT days in EST")
    func daylightSaving() throws {
        // 2024-03-10 starts EDT; 2026-11-01 ends it. Moving to 2026-11-05
        // puts 2024-03-08 (EST) on 2026-10-30 (EDT) and 2024-03-13 (EDT) on 2026-11-04 (EST).
        let data = try document([("2024-03-08T09:00", "2024-03-08T10:30"), ("2024-03-13T09:00", "2024-03-13T10:30")])
        let result = try FixtureShift(document: data, now: local("2026-11-05T12:00"), timeZone: Self.newYork).apply(to: data)
        #expect(try spans(result) == ["2026-10-30T09:00…2026-10-30T10:30", "2026-11-04T09:00…2026-11-04T10:30"])
        let object = try #require(try JSONSerialization.jsonObject(with: result.document) as? [String: Any])
        let starts = try #require(object["entries"] as? [[String: Any]]).compactMap { $0["start"] as? String }
        #expect(starts == ["2026-10-30T13:00:00Z", "2026-11-04T14:00:00Z"])
    }

    @Test("Another zone: the entries move into the seeding device's zone at the same wall-clock times")
    func otherZone() throws {
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let data = try document([("2024-03-13T09:15", "2024-03-13T10:40")])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyo
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 15)))
        let result = try FixtureShift(document: data, now: now, timeZone: tokyo).apply(to: data)
        let object = try #require(try JSONSerialization.jsonObject(with: result.document) as? [String: Any])
        let entry = try #require((object["entries"] as? [[String: Any]])?.first)
        #expect(entry["timeZone"] as? String == "Asia/Tokyo")
        #expect(entry["start"] as? String == "2026-10-29T00:15:00Z")
    }

    @Test("ARCH-23 seeding running at 15:00: 2024-03-13 is yesterday at its times, running since 14:35, nothing after now; Release refused")
    func seedRunning() async throws {
        let fixture = try #require(StoreFixture.url(named: "running"))
        let data = try Data(contentsOf: fixture)
        let dataset = try #require(SyntheticDataset.fixture(named: "running"))
        let temporary = try TemporaryFolder()
        defer { temporary.remove() }
        // A Debug group container: a folder whose name ends in `.debug`.
        let folder = temporary.url.appending(path: "demo.debug", directoryHint: .isDirectory)
        let storeURL = folder.appending(path: "Library/Application Support/TimeTracking/store.sqlite")
        let activity = folder.appending(path: "Library/Application Support/TimeTracking/Activity", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: activity.appending(path: "blocks"), withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: activity.appending(path: "blocks/2020-01.jsonl"))
        let now = try local("2026-10-30T15:00")

        let report = try await DemoSeed.seed(
            document: data,
            dataset: dataset,
            store: storeURL,
            activity: activity,
            now: now,
            timeZone: Self.newYork
        )
        #expect(report.days == 960)
        #expect(report.blocks > 0)

        let store = try await TimeStore.open(TimeStore.Configuration(
            location: .file(storeURL),
            clock: ManualClock(now),
            deviceID: DeviceID(),
            timeZone: { Self.newYork }
        ))
        let source = try await dataset.populatedStore(withTombstones: false)
        let before = try await source.entries(on: TrackingDay(year: 2024, month: 3, day: 13))
            .map { "\($0.task) \(text($0.start).suffix(5))" }
        let after = try await store.entries(on: TrackingDay(year: 2026, month: 10, day: 29))
            .map { "\($0.task) \(text($0.start).suffix(5))" }
        #expect(!before.isEmpty)
        #expect(after.sorted() == before.sorted())
        let running = try #require(try await store.runningEntry())
        #expect(text(running.start) == "2026-10-30T14:35")
        let all = try await store.entries(in: DateInterval(start: .distantPast, end: .distantFuture))
        #expect(all.allSatisfy { ($0.end ?? $0.start) <= now })
        #expect(all.count == report.entries)
        let months = try FileManager.default.contentsOfDirectory(atPath: activity.appending(path: "blocks").path).sorted()
        #expect(months == ["2026-10.jsonl"])

        let releaseFolder = try TemporaryFolder()
        defer { releaseFolder.remove() }
        let release = releaseFolder.url.appending(path: "TEAM000000.com.example.timetracking")
        let releaseStore = release.appending(path: "Library/Application Support/TimeTracking/store.sqlite")
        try FileManager.default.createDirectory(at: releaseStore.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("real".utf8).write(to: releaseStore)
        await #expect(throws: DemoSeedError.notDevelopmentStore(releaseStore.path)) {
            try await DemoSeed.seed(document: data, dataset: dataset, store: releaseStore, now: now, timeZone: Self.newYork)
        }
        #expect(try Data(contentsOf: releaseStore) == Data("real".utf8))
    }

    @Test("Development stores are Debug group containers and simulator folders only")
    func developmentStores() {
        let support = "Library/Application Support/TimeTracking/store.sqlite"
        #expect(DemoSeed.isDevelopmentStore(URL(filePath: "/Users/a/Library/Group Containers/T.com.example.app.debug/\(support)")))
        #expect(DemoSeed
            .isDevelopmentStore(
                URL(filePath: "/Users/a/Library/Developer/CoreSimulator/Devices/D/data/Containers/Shared/AppGroup/G/\(support)")
            ))
        #expect(!DemoSeed.isDevelopmentStore(URL(filePath: "/Users/a/Library/Group Containers/T.com.example.app/\(support)")))
        #expect(!DemoSeed
            .isDevelopmentStore(URL(filePath: "/Users/a/Library/Group Containers/T.com.example.app.debug/../T.com.example.app/\(support)")))
        #expect(!DemoSeed.isDevelopmentStore(URL(filePath: "/tmp/store.debug")))
    }
}
