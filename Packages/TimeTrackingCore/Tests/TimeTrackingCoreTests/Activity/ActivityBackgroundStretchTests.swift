// Background stretches in the block log (activity_tracking.md §4.2,
// data_and_sync.md §6, TRK-43, DATA-53).

import Foundation
import Testing
import TimeTrackingCore

struct ActivityBackgroundStretchTests {
    private static let contexts = ["textedit": "com.apple.TextEdit", "claude": "claude", "vault": "com.example.vault"]

    private static func item(_ context: String, _ seconds: Int, device: String = "macbook") -> ActivityItem {
        ActivityItem(context: context, subject: "\(context) subject", detail: "", seconds: seconds, device: device)
    }

    private static func stretch(_ start: String, _ end: String, _ items: [ActivityItem]) throws -> ActivityBackgroundStretch {
        try ActivityBackgroundStretch(
            start: ActivityFixture.instant(start),
            end: ActivityFixture.instant(end),
            items: items,
            utcOffset: -4 * 3600
        )
    }

    @Test("TRK-43 a background stretch line carries type, s, e, and bg, reads back, and reapplied exclusions drop excluded items")
    func lineFormat() throws {
        let temporary = try TemporaryFolder()
        defer { temporary.remove() }
        let folder = temporary.url.appending(path: "blocks", directoryHint: .isDirectory)
        let block = try ActivityFixture.block(
            start: "2026-10-28T13:10:00Z",
            end: "2026-10-28T13:40:00Z",
            items: [Self.item("textedit", 1800)]
        )
        let stretch = try Self.stretch("2026-10-28T13:40:00Z", "2026-10-28T14:20:00Z", [Self.item("claude", 2400)])
        var writer = BlockLogWriter(folder: folder, device: "macbook")
        try writer.append(block, contexts: Self.contexts)
        try writer.append(stretch, contexts: Self.contexts)

        let text = try String(contentsOf: writer.fileURL(for: "2026-10"), encoding: .utf8)
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines.count == 4)
        #expect(lines[2].hasPrefix("{\"type\":\"header\"") && lines[2].contains("\"claude\":\"claude\""))
        let expected = #"{"type":"background","s":"2026-10-28T09:40:00","e":"2026-10-28T10:20:00","#
            + #""bg":[["claude","claude subject","",2400,"macbook"]]}"#
        #expect(lines[3] == expected)

        let file = BlockLogFile(data: Data(text.utf8))
        #expect(file.malformedLines == 0)
        #expect(file.blocks == [block])
        #expect(file.backgrounds.map(\.stretch) == [stretch])
        #expect(file.backgrounds.first?.contexts["claude"] == "claude")

        let rules = try TrackerSettings(tomlText: "[privacy]\nexclude_apps = [\"com.example.vault\"]\n").exclusions()
        let mixed = try Self.stretch("2026-10-28T13:40:00Z", "2026-10-28T14:20:00Z", [Self.item("claude", 600), Self.item("vault", 900)])
        #expect(rules.reapplied(to: mixed, contexts: Self.contexts)?.items.map(\.context) == ["claude"])
        let excluded = try Self.stretch("2026-10-28T13:40:00Z", "2026-10-28T14:20:00Z", [Self.item("vault", 900)])
        #expect(rules.reapplied(to: excluded, contexts: Self.contexts) == nil)
    }

    // swiftlint:disable line_length
    @Test(
        "DATA-53 the query backgroundStretches(in:) returns the stretches overlapping the interval, the items of the asked devices, without excluded contexts; blocks(in:) never returns them"
    )
    // swiftlint:enable line_length
    func readerQuery() async throws {
        let temporary = try TemporaryFolder()
        defer { temporary.remove() }
        let folders = temporary.folders
        try ActivityFixture.write(
            "[privacy]\nexclude_apps = [\"com.example.vault\"]\n",
            to: folders.settingsURL,
            modified: Date(timeIntervalSince1970: 1_000_000)
        )
        let morning = try Self.stretch("2026-10-28T12:00:00Z", "2026-10-28T12:40:00Z", [Self.item("claude", 2400)])
        let evening = try Self.stretch(
            "2026-10-28T22:00:00Z",
            "2026-10-28T22:30:00Z",
            [Self.item("vault", 900), Self.item("claude", 600, device: "studio")]
        )
        let hidden = try Self.stretch("2026-10-28T23:00:00Z", "2026-10-28T23:20:00Z", [Self.item("vault", 1200)])
        var writer = BlockLogWriter(folder: folders.sharedBlocks, device: "macbook")
        for stretch in [morning, evening, hidden] {
            try writer.append(stretch, contexts: Self.contexts)
        }
        let store = FileActivityStore(folders: folders, timeZone: ActivityFixture.newYork, homeDirectory: "/Users/example")
        let day = try DateInterval(start: ActivityFixture.instant("2026-10-28T04:00:00Z"), duration: 24 * 3600)

        let all = try await store.backgroundStretches(in: day, devices: nil)
        #expect(all.map(\.id) == [morning.id, evening.id])
        #expect(all.last?.items.map(\.context) == ["claude"])
        let studio = try await store.backgroundStretches(in: day, devices: ["studio"])
        #expect(studio.map(\.id) == [evening.id])
        let late = try DateInterval(start: ActivityFixture.instant("2026-10-28T22:10:00Z"), duration: 600)
        #expect(try await store.backgroundStretches(in: late, devices: nil).map(\.id) == [evening.id])
        #expect(try await store.blocks(in: day, devices: nil).isEmpty)
    }
}
