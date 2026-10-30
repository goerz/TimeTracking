// The store, query, activity, and interchange targets of
// spec_data_and_sync.md §7.5 on the large dataset (§9.1: ten years, about
// 24,000 entries; the import target's 300,000 entries become its rate).
// Slow: only with TIMETRACKING_TEST_SLOW=1 (make test).

import Foundation
import Testing
import TimeTrackingCore

@Suite(.tags(.slow), .enabled(if: ProcessInfo.processInfo.environment["TIMETRACKING_TEST_SLOW"] == "1"))
struct StorePerformanceTests {
    /// §7.5: `importDocument` of 300,000 entries in under 60 s.
    static let importSecondsPerEntry = 60.0 / 300_000

    @Test("Store targets on the large dataset: open, running entry, write, day and week reads, task prefix, export, import")
    func storeTargets() async throws {
        var dataset = SyntheticDataset.large()
        dataset.runningMinutes = 25
        let document = try await dataset.exportDocument()
        let folder = FileManager.default.temporaryDirectory.appending(path: "perf-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let zone = try #require(TimeZone(identifier: dataset.timeZone))
        let configuration = TimeStore.Configuration(
            location: .file(folder.appending(path: "store.sqlite")),
            clock: ManualClock(dataset.nowDate),
            deviceID: dataset.deviceID,
            timeZone: { zone }
        )
        let store = try await TimeStore.open(configuration)

        let start = ContinuousClock.now
        let report = try await store.importDocument(document, options: ImportOptions(includeSettings: true))
        let importSeconds = Self.seconds(ContinuousClock.now - start)
        let entries = try #require(report.counts[.entry]).created
        #expect(entries > 20_000)
        #expect(importSeconds < Double(entries) * Self.importSecondsPerEntry, "import of \(entries) entries: \(importSeconds) s")

        let openTime = try await ReportPerformanceTests.milliseconds { _ = try await TimeStore.open(configuration) }
        #expect(openTime < 50, "opening the store: \(openTime) ms")
        let runningTime = try await ReportPerformanceTests.milliseconds { _ = try await store.runningEntry() }
        #expect(try await store.runningEntry() != nil)
        #expect(runningTime < 1, "runningEntry: \(runningTime) ms")

        let last = dataset.days.upperBound
        let calendar = TrackingCalendar(timeZone: zone)
        let week = calendar.interval(of: last.adding(days: -6) ... last)
        let dayTime = try await ReportPerformanceTests.milliseconds { _ = try await store.entries(on: last) }
        let daysTime = try await ReportPerformanceTests.milliseconds { _ = try await store.days(ending: last, count: 7) }
        let weekTime = try await ReportPerformanceTests.milliseconds { _ = try await store.entries(in: week) }
        #expect(dayTime < 10, "entries(on:): \(dayTime) ms")
        #expect(daysTime < 10, "days(ending:count: 7): \(daysTime) ms")
        #expect(weekTime < 10, "entries(in:) for 7 days: \(weekTime) ms")
        let prefixTime = try await ReportPerformanceTests.milliseconds {
            _ = try await store.distinctTasks(projectID: nil, prefix: "Re", limit: 10)
        }
        #expect(prefixTime < 20, "distinctTasks with a 2-character prefix: \(prefixTime) ms")

        let writeStart = calendar.startOfDay(last) + 20 * 3600
        let writeTime = try await ReportPerformanceTests.milliseconds(runs: 1) {
            _ = try await store.create(EntryDraft(projectID: nil, task: "Timing", start: writeStart, end: writeStart + 600))
        }
        #expect(writeTime < 5, "single-entry write: \(writeTime) ms")

        let exportStart = ContinuousClock.now
        _ = try await store.exportDocument()
        let exportSeconds = Self.seconds(ContinuousClock.now - exportStart)
        #expect(exportSeconds < 10, "export: \(exportSeconds) s")
    }

    @Test("blocks(in:) for 7 days under 50 ms with the month files cached, on the large dataset's block log")
    func blockTargets() async throws {
        let dataset = SyntheticDataset.large()
        let folder = FileManager.default.temporaryDirectory.appending(path: "perf-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await dataset.activityLog(to: folder)
        let zone = try #require(TimeZone(identifier: dataset.timeZone))
        let reader = FileActivityStore(folders: ActivityFolders(shared: folder, local: folder, isFallback: true), timeZone: zone)
        let last = dataset.days.upperBound
        let week = TrackingCalendar(timeZone: zone).interval(of: last.adding(days: -6) ... last)
        #expect(try await !reader.blocks(in: week, devices: nil).isEmpty)
        let time = try await ReportPerformanceTests.milliseconds { _ = try await reader.blocks(in: week, devices: nil) }
        #expect(time < 50, "blocks(in:) for 7 days: \(time) ms")
    }

    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
