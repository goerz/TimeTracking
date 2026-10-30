// Tests for FileActivityStore (spec_data_and_sync.md §6, §9 DATA-43 to DATA-45).

import Foundation
import Testing
import TimeTrackingCore

struct FileActivityStoreTests {
    private static let contexts = [
        "tmux:paper": "com.example.terminal",
        "tmux:private": "com.example.terminal",
        "safari": "com.apple.Safari",
        "vault": "com.example.vault",
    ]

    private static func item(_ context: String, _ seconds: Int) -> ActivityItem {
        ActivityItem(context: context, subject: "\(context) subject", detail: "", seconds: seconds)
    }

    private static func writeBlocks(_ blocks: [ActivityBlock], to folder: URL, device: String = "macbook") throws {
        var writer = BlockLogWriter(folder: folder, device: device)
        for block in blocks {
            try writer.append(block, contexts: contexts)
        }
    }

    /// A store whose clock reads 2026-10-28T10:00 in New York.
    private static func store(_ folders: ActivityFolders) throws -> FileActivityStore {
        try FileActivityStore(
            folders: folders,
            timeZone: ActivityFixture.newYork,
            clock: ManualClock(ActivityFixture.instant("2026-10-28T14:00:00Z")),
            homeDirectory: "/Users/example"
        )
    }

    /// The New York day `date` (`YYYY-MM-DD`), midnight to midnight in EDT.
    private static func day(_ date: String) throws -> DateInterval {
        let start = try ActivityFixture.instant("\(date)T04:00:00Z")
        return DateInterval(start: start, duration: 24 * 3600)
    }

    private static func currentJSON(lastTick: String, activeSeconds: Int) -> String {
        """
        {"format":1,"dev":"macbook","block":{"s":"2026-10-28T09:10:00","a":\(activeSeconds),"g":"tmux:paper","gs":0.71,\
        "items":[["tmux:paper","draft","nvim (3 files)",\(activeSeconds)]],"bg":[]},"primary":["tmux:paper","draft","nvim notes.tex"],\
        "presence":{"state":"active","since":"2026-10-28T09:10:00","last_input":"2026-10-28T09:44:27"},\
        "health":{"last_tick":"\(lastTick)","version":"1.0 (42)","sources":[]}}
        """
    }

    // swiftlint:disable line_length
    @Test(
        "DATA-43 the query blocks(in:) across a month boundary reads both files and returns blocks by start, filtered by device when asked, without excluded contexts"
    )
    // swiftlint:enable line_length
    func blocksAcrossAMonthBoundary() async throws {
        let temporary = try TemporaryFolder()
        defer { temporary.remove() }
        let folders = temporary.folders
        try ActivityFixture.write(
            "[privacy]\nexclude_apps = [\"COM.example.vault\"]\nexclude_tmux_sessions = [\"private\"]\n",
            to: folders.settingsURL,
            modified: Date(timeIntervalSince1970: 1_000_000)
        )
        let october = try ActivityFixture.block(
            start: "2026-10-01T04:10:00Z",
            end: "2026-10-01T04:50:00Z",
            items: [Self.item("tmux:paper", 1800), Self.item("tmux:private", 600)]
        )
        let september = try ActivityFixture.block(
            start: "2026-10-01T03:00:00Z", end: "2026-10-01T03:40:00Z", items: [Self.item("safari", 2400)]
        )
        let vaultOnly = try ActivityFixture.block(
            start: "2026-10-01T02:00:00Z", end: "2026-10-01T02:10:00Z", items: [Self.item("vault", 600)]
        )
        let other = try ActivityFixture.block(
            start: "2026-10-01T03:30:00Z", end: "2026-10-01T03:50:00Z", items: [Self.item("safari", 1200)], device: "imac"
        )
        #expect(september.month == "2026-09")
        #expect(october.month == "2026-10")
        try Self.writeBlocks([vaultOnly, september, october], to: folders.sharedBlocks)
        try Self.writeBlocks([other], to: folders.sharedBlocks, device: "imac")
        let store = try Self.store(folders)

        let interval = try DateInterval(
            start: ActivityFixture.instant("2026-09-30T04:00:00Z"),
            end: ActivityFixture.instant("2026-10-02T04:00:00Z")
        )
        let all = try await store.blocks(in: interval)
        #expect(all.map(\.id) == [september.id, other.id, october.id])
        let cut = try #require(all.last)
        #expect(cut.items.map(\.context) == ["tmux:paper"])
        #expect(cut.activeSeconds == 1800)
        let mine = try await store.blocks(in: interval, devices: ["macbook"])
        #expect(mine.map(\.id) == [september.id, october.id])
        #expect(store.bundleIdentifier(forContext: "safari") == "com.apple.Safari")
        #expect(store.exclusions.excludesApp("com.example.vault"))
        #expect(await store.malformedLineCount == 0)
    }

    @Test("DATA-44 aggregating by hour of day a block from 09:50 to 10:20 gives 600 s to hour 9 and 1200 s to hour 10")
    func aggregateByHourOfDay() async throws {
        let temporary = try TemporaryFolder()
        defer { temporary.remove() }
        let folders = temporary.folders
        let block = try ActivityFixture.block(
            start: "2026-10-27T13:50:00Z", end: "2026-10-27T14:20:00Z", items: [Self.item("safari", 1800)]
        )
        try Self.writeBlocks([block], to: folders.sharedBlocks)
        let store = try Self.store(folders)
        let day = try Self.day("2026-10-27")
        let hours = try await store.aggregate(in: day, by: .hourOfDay, device: nil)
        #expect(hours == [
            ActivityAggregate(bucket: .hour(9), seconds: 600, blockCount: 1),
            ActivityAggregate(bucket: .hour(10), seconds: 1200, blockCount: 1),
        ])
        let days = try await store.aggregate(in: day, by: .day, device: "macbook")
        #expect(days == [ActivityAggregate(bucket: .day("2026-10-27"), seconds: 1800, blockCount: 1)])
        #expect(try await store.aggregate(in: day, by: .day, device: "imac").isEmpty)
    }

    @Test func hourSharesAreWholeSecondsAddingUpToTheTotal() async throws {
        let temporary = try TemporaryFolder()
        defer { temporary.remove() }
        let folders = temporary.folders
        // 09:59:59 to 12:00:01, 7001 active seconds over a span of 7202.
        var block = try ActivityFixture.block(
            start: "2026-10-27T13:59:59Z", end: "2026-10-27T16:00:01Z", items: [Self.item("safari", 7000)]
        )
        block.activeSeconds = 7001
        try Self.writeBlocks([block], to: folders.sharedBlocks)
        let store = try Self.store(folders)
        let day = try Self.day("2026-10-27")
        let hours = try await store.aggregate(in: day, by: .hourOfDay, device: nil)
        #expect(hours.map(\.bucket) == [.hour(9), .hour(10), .hour(11), .hour(12)])
        #expect(hours.reduce(0) { $0 + $1.seconds } == 7001)
        let byContext = try await store.aggregate(in: day, by: .context, device: nil)
        #expect(byContext == [ActivityAggregate(bucket: .value("safari"), seconds: 7000, blockCount: 1)])
    }

    // swiftlint:disable line_length
    @Test(
        "DATA-45 the call currentState() is nil without current.json; a rewrite produces a change event and today's blocks(in:) includes one block with isOpen; detail(for:) is nil without the detail log"
    )
    // swiftlint:enable line_length
    func currentStateAndOpenBlock() async throws {
        let temporary = try TemporaryFolder()
        defer { temporary.remove() }
        let folders = temporary.folders
        let store = try Self.store(folders)
        #expect(await store.currentState() == nil)
        var changes = store.changes.makeAsyncIterator()

        let url = folders.currentStateURL
        let first = Self.currentJSON(lastTick: "2026-10-28T09:59:30", activeSeconds: 1080)
        try ActivityFixture.write(first, to: url, modified: Date(timeIntervalSince1970: 1000))
        await store.refresh()
        #expect(await changes.next() == .currentState)
        let second = Self.currentJSON(lastTick: "2026-10-28T10:00:00", activeSeconds: 1110)
        try ActivityFixture.write(second, to: url, modified: Date(timeIntervalSince1970: 2000))
        await store.refresh()
        #expect(await changes.next() == .currentState)

        let state = try #require(await store.currentState())
        #expect(state.openBlock?.activeSeconds == 1110)
        let blocks = try await store.blocks(in: Self.day("2026-10-28"))
        #expect(blocks.count == 1)
        let open = try #require(blocks.first)
        #expect(open.isOpen)
        #expect(open.id == "macbook/2026-10-28T09:10:00-04:00")
        #expect(try open.end == ActivityFixture.instant("2026-10-28T14:00:00Z"))
        #expect(try await store.detail(for: open.id) == nil)
        #expect(try await store.blocks(in: Self.day("2026-10-27")).isEmpty)
    }

    @Test func detailIsReadFromTheLocalDetailLog() async throws {
        let temporary = try TemporaryFolder()
        defer { temporary.remove() }
        let folders = temporary.folders
        try ActivityFixture.write("[privacy]\nexclude_domains = [\"private.example\"]\n", to: folders.settingsURL, modified: Date())
        let block = try ActivityFixture.block(
            start: "2026-10-27T13:00:00Z", end: "2026-10-27T13:30:00Z", items: [Self.item("safari", 1800)]
        )
        let detail = ActivityBlockDetail(
            blockID: block.id,
            items: block.items,
            urls: [
                ActivityURLVisit(time: block.start, browser: "safari", url: "https://www.private.example/x", title: "X"),
                ActivityURLVisit(time: block.start, browser: "safari", url: "https://example.org/", title: "Y"),
            ]
        )
        var writer = BlockLogWriter(folder: folders.detailFolder, device: "macbook")
        try writer.append(block, contexts: Self.contexts, detail: detail)
        let store = try Self.store(folders)
        let read = try #require(try await store.detail(for: block.id))
        #expect(read.urls.map(\.title) == ["Y"])
        #expect(try await store.detail(for: "macbook/2026-10-27T10:00:00-04:00") == nil)
    }

    @Test func aBlockInBothFoldersCountsOnceAndChangedFilesAreReread() async throws {
        let temporary = try TemporaryFolder()
        defer { temporary.remove() }
        let folders = temporary.folders
        let first = try ActivityFixture.block(
            start: "2026-10-27T13:00:00Z", end: "2026-10-27T13:30:00Z", items: [Self.item("safari", 1800)]
        )
        try Self.writeBlocks([first], to: folders.sharedBlocks)
        try Self.writeBlocks([first], to: folders.localBlocks)
        let store = try Self.store(folders)
        let day = try Self.day("2026-10-27")
        #expect(try await store.blocks(in: day).count == 1)

        var changes = store.changes.makeAsyncIterator()
        let second = try ActivityFixture.block(
            start: "2026-10-27T15:00:00Z", end: "2026-10-27T15:30:00Z", items: [Self.item("safari", 1800)]
        )
        try Self.writeBlocks([second], to: folders.sharedBlocks)
        try ActivityFixture.append("not json\n", to: folders.sharedBlocks.appending(path: "2026-10.jsonl"))
        await store.refresh()
        #expect(await changes.next() == .blocks(month: "2026-10"))
        #expect(try await store.blocks(in: day).map(\.id) == [first.id, second.id])
        #expect(await store.malformedLineCount == 1)
    }

    @Test func aSettingsChangeReloadsTheExclusions() async throws {
        let temporary = try TemporaryFolder()
        defer { temporary.remove() }
        let folders = temporary.folders
        let block = try ActivityFixture.block(
            start: "2026-10-27T13:00:00Z", end: "2026-10-27T13:30:00Z", items: [Self.item("vault", 1800)]
        )
        try Self.writeBlocks([block], to: folders.sharedBlocks)
        let store = try Self.store(folders)
        let day = try Self.day("2026-10-27")
        #expect(try await store.blocks(in: day).count == 1)
        var changes = store.changes.makeAsyncIterator()
        try ActivityFixture.write("[privacy]\nexclude_apps = [\"com.example.vault\"]\n", to: folders.settingsURL, modified: Date())
        await store.refresh()
        #expect(await changes.next() == .settings)
        #expect(try await store.blocks(in: day).isEmpty)
    }
}
