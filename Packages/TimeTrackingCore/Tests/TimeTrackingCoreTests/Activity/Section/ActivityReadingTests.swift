// The Activity section over the file-backed reader: exclusions at read time,
// a read-only view, and the open block replaced by the closed one
// (activity.md §1.9, §4; data_and_sync.md §6).

import Foundation
import Testing
import TimeTrackingCore

struct ActivityReadingTests {
    private static let now = Date(timeIntervalSince1970: 1_710_424_800) // 2024-03-14T10:00:00-04:00

    /// The bytes and modification dates of the files under `folder`.
    private static func snapshot(_ folder: URL) throws -> [String: Data] {
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
        var result: [String: Data] = [:]
        while let url = files?.nextObject() as? URL {
            guard !url.hasDirectoryPath else {
                continue
            }
            let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            result[url.path] = try Data(contentsOf: url) + Data("\(modified.timeIntervalSince1970)".utf8)
        }
        return result
    }

    @Test(
        "PA-19 a saved exclusion removes past items from every total and private ones keep their time, with the log byte-identical"
    )
    func exclusionsAtReadTime() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let folders = folder.folders
        let log = try #require(folders.blockFolders.first)
        let vault = ActivityFixture.app("Vault", appID: "com.example.vault")
        try log.write([
            ActivityFixture.block("2024-03-11", "09:00", "10:00", [
                (ActivityFixture.terminal(), 1800), (vault, 1200), (ActivityFixture.terminal("Secret"), 900),
            ]),
        ], for: SectionFixture.monday)
        try log.write([
            ActivityFixture.block("2024-03-12", "09:00", "09:10", [(vault, 600)]),
        ], for: TrackingDay(year: 2024, month: 3, day: 12))
        let before = try Self.snapshot(log.url)
        let reader = FileActivityStore(folders: folders, homeDirectory: "/Users/alex")
        let interval = SectionFixture.interval(SectionFixture.week)

        let all = await SectionFixture.summary(reader.blocks(in: interval, devices: nil))
        #expect(all.total == 4500)
        #expect(all.ranking.map(\.app) == ["WezTerm", "Vault"])
        #expect(all.activeDays == 2)

        let settings = "[privacy]\nexclude_apps = [\"com.example.vault\"]\nexclude_paths = [\"~/Code/Secret\"]\n"
        try ActivityFixture.write(settings, to: folders.settingsURL, modified: Self.now)
        await reader.refresh()
        let blocks = await reader.blocks(in: interval, devices: nil)
        let after = SectionFixture.summary(blocks, settings: reader.settings, exclusions: reader.exclusions)
        #expect(blocks.count == 1)
        #expect(after.total == 2700)
        #expect(after.ranking.map(\.app) == ["WezTerm"])
        #expect(after.activeDays == 1)
        #expect(after.bars.bars[0].seconds == 2700)
        #expect(after.heatmap.rows[1].isEmpty)
        let rows = after.workspaceRows
        #expect(rows.map(\.workspace) == ["~/Code/MyApp", ActivityItem.privateWorkspace])
        #expect(rows.map(\.seconds) == [1800, 900])
        #expect(rows.map(\.isPrivate) == [false, true])
        #expect(rows.last?.name == "(private)")
        #expect(rows.last?.apps == ["WezTerm"])
        #expect(try Self.snapshot(log.url) == before)
    }

    @Test("PA-20 building every panel never modifies the block log, current.json, or settings.toml")
    func readOnly() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let folders = folder.folders
        let log = try #require(folders.blockFolders.first)
        try log.write([
            ActivityFixture.block(
                "2024-03-14",
                "08:00",
                "09:00",
                [(ActivityFixture.terminal(), 3600)],
                background: [(ActivityFixture.agent, 600)]
            ),
            ActivityFixture.block("2024-03-14", "09:05", "09:35", [], background: [(ActivityFixture.agent, 1800)], reason: .split),
            ActivityFixture.block("2024-03-14", "09:40", "09:50", [(SectionFixture.mail, 600)]),
        ], for: SectionFixture.thursday)
        let open = try SectionFixture.opened(ActivityFixture.block("2024-03-14", "09:52", "09:59", [(SectionFixture.mail, 420)]))
        let state = SectionFixture.trackerState(block: open, lastTick: Self.now - 5)
        try ActivityFixture.write(state.jsonText(timeZone: ActivityFixture.newYork), to: folders.currentStateURL, modified: Self.now)
        try ActivityFixture.write(TrackerSettings.defaultFileContents, to: folders.settingsURL, modified: Self.now)
        let before = try Self.snapshot(folder.url)

        let reader = FileActivityStore(folders: folders, homeDirectory: "/Users/alex")
        await reader.refresh()
        let interval = SectionFixture.interval(SectionFixture.week)
        let summary = await SectionFixture.summary(
            reader.blocks(in: interval, devices: nil),
            background: reader.backgroundBlocks(in: interval, devices: nil),
            settings: reader.settings,
            exclusions: reader.exclusions
        )
        #expect(summary.total == 3600 + 600 + 420)
        #expect(summary.bars.bars[3].openSeconds == 420)
        #expect(summary.away.seconds == 2400)
        #expect(summary.away.backgroundSeconds == 1800)
        let heatmap = summary.heatmap
        _ = summary.cellTooltip(row: heatmap.rows[3], hour: 8)
        _ = (summary.bars, summary.appRows, summary.workspaceRows, summary.backgroundRows, summary.headerDetail)
        let current = await reader.currentState()
        let health = ActivityHealth(registration: .enabled, state: current, now: Self.now)
        #expect(health.dot == .green)
        #expect(try Self.snapshot(folder.url) == before)
    }

    @Test("PA-11 on the Mac the open block of current.json counts until a refresh finds the closed block in the date file")
    func openBlockFromCurrentState() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let folders = folder.folders
        let log = try #require(folders.blockFolders.first)
        let open = try SectionFixture.opened(ActivityFixture.block("2024-03-14", "09:00", "09:20", [(SectionFixture.mail, 1200)]))
        let state = SectionFixture.trackerState(block: open, lastTick: Self.now - 5)
        try ActivityFixture.write(state.jsonText(timeZone: ActivityFixture.newYork), to: folders.currentStateURL, modified: Self.now - 5)
        let reader = FileActivityStore(folders: folders, homeDirectory: "/Users/alex")
        let interval = SectionFixture.interval(SectionFixture.week)
        var changes = reader.changes.makeAsyncIterator()
        let before = await SectionFixture.summary(reader.blocks(in: interval, devices: nil)).bars.bars[3]
        #expect(before.openSeconds == 1200)

        let closed = try ActivityFixture.block("2024-03-14", "09:00", "09:25", [(SectionFixture.mail, 1500)])
        try log.write([closed], for: SectionFixture.thursday)
        await reader.refresh()
        #expect(await changes.next() == .blocks(day: SectionFixture.thursday))
        let read = await reader.blocks(in: interval, devices: nil)
        #expect(read.map(\.isOpen) == [false])
        let after = SectionFixture.summary(read).bars.bars[3]
        #expect(after.seconds == 1500)
        #expect(after.openSeconds == 0)
    }
}
