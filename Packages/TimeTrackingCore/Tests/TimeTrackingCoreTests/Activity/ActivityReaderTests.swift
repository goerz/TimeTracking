// The date files of the block log, current.json, and the file-backed reader
// (data_and_sync.md §6; activity_tracking.md §4.2, §4.4).

import Foundation
import Testing
@testable import TimeTrackingCore

struct ActivityReaderTests {
    private static let myApp = ActivityFixture.terminal("MyApp")

    @Test(
        "TRK-29 a date file: header first, a block per line by start, no empty values; reads back as written, skips unknown lines and keys"
    )
    func dateFileFormat() throws {
        let later = try ActivityFixture.block("2024-03-14", "11:00", "11:30", [(Self.myApp, 1800)])
        let earlier = try ActivityFixture.block(
            "2024-03-14",
            "09:00",
            "09:30",
            [(ActivityFixture.app("Mail"), 1800)],
            background: [(ActivityFixture.agent, 600)]
        )
        let text = BlockLogFile.text(of: [later, earlier])
        let lines = text.split(separator: "\n")
        #expect(lines.first == Substring(BlockLogFile.header))
        let mailLine = #"{"s":"2024-03-14T09:00:00-04:00","e":"2024-03-14T09:30:00-04:00","r":"idle","#
            + #""f":[{"d":"MacBook","t":1800,"a":"Mail""#
        #expect(lines[1].hasPrefix(mailLine))
        let blockLines = lines.dropFirst().joined()
        #expect(!blockLines.contains(#""rc""#) && !blockLines.contains(#""w":"""#))
        #expect(BlockLogFile.parse(text).blocks == [earlier, later])
        let unknownKeys = #"{"s":"2024-03-14T12:00:00-04:00","e":"2024-03-14T12:20:00-04:00","x":1,"#
            + #""f":[{"d":"MacBook","t":1200,"a":"Mail","zz":true}]}"#
        let extended = text + #"{"note":"a line a later version writes"}"# + "\n" + unknownKeys + "\n"
        let parsed = BlockLogFile.parse(extended)
        #expect(parsed.blocks.count == 3 && parsed.malformedLines == 0)
        #expect(parsed.blocks.last?.foreground.first?.item.workspace == "Mail")
    }

    @Test(
        "DATA-42 a date file with blocks at two UTC offsets and a malformed line gives three blocks with their instants and one parse error"
    )
    func offsetsAndMalformedLines() throws {
        let text = BlockLogFile.header + "\n"
            + #"{"s":"2024-03-10T01:30:00-05:00","e":"2024-03-10T01:50:00-05:00","f":[{"d":"MacBook","t":1200,"a":"Mail"}]}"# + "\n"
            + #"{"s":"2024-03-10T03:10:00-04:00","e":"2024-03-10T03:40:00-04:00","f":[{"d":"MacBook","t":1800,"a":"Mail"}]}"# + "\n"
            + #"{"s":"2024-03-10T09:00:00-04:00","e":"# + "\n"
            + #"{"s":"2024-03-10T10:00:00-04:00","e":"2024-03-10T10:20:00-04:00","f":[{"d":"MacBook","t":1200,"a":"Mail"}]}"# + "\n"
        let parsed = BlockLogFile.parse(text)
        #expect(parsed.blocks.count == 3 && parsed.malformedLines == 1)
        #expect(try parsed.blocks[0].start == ActivityFixture.instant("2024-03-10T06:30:00Z"))
        #expect(try parsed.blocks[1].start == ActivityFixture.instant("2024-03-10T07:10:00Z"))
        #expect(parsed.blocks.map(\.utcOffset) == [-5 * 3600, -4 * 3600, -4 * 3600])
    }

    @Test(
        "DATA-43 blocks(in:) across two dates reads both files, a block past 00:00 once on its start date, a device's part, no exclusions"
    )
    func blocksAcrossDates() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let folders = folder.folders
        let log = try #require(folders.blockFolders.first)
        try log.write([
            ActivityFixture.block(
                "2024-03-14",
                "23:30",
                "23:59",
                [(Self.myApp, 1500), (ActivityFixture.app("Social", appID: "screenTime"), 240)]
            )
            .withDevice("iPhone", forItemAt: 1),
        ], for: TrackingDay(year: 2024, month: 3, day: 14))
        try log.write([
            ActivityFixture.block("2024-03-15", "09:00", "09:30", [(ActivityFixture.app("Vault", appID: "com.example.vault"), 1800)]),
        ], for: TrackingDay(year: 2024, month: 3, day: 15))
        try ActivityFixture.write("[privacy]\nexclude_apps = [\"com.example.vault\"]\n", to: folders.settingsURL, modified: .now)
        let reader = FileActivityStore(folders: folders, homeDirectory: "/Users/alex")
        let interval = try DateInterval(
            start: ActivityFixture.instant("2024-03-14T23:45:00-04:00"),
            end: ActivityFixture.instant("2024-03-15T10:00:00-04:00")
        )
        let all = await reader.blocks(in: interval, devices: nil)
        #expect(all.map(\.id) == ["2024-03-14T23:30:00-04:00"])
        let phone = await reader.blocks(in: interval, devices: ["iPhone"])
        #expect(phone.first?.activeSeconds == 240)
    }

    @Test(
        "DATA-45 currentState() is nil without current.json; a rewrite is a change; blocks(in:) has the open block, even from yesterday"
    )
    func currentState() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let folders = folder.folders
        let reader = FileActivityStore(folders: folders, homeDirectory: "/Users/alex")
        #expect(await reader.currentState() == nil)
        var changes = reader.changes.makeAsyncIterator()
        let open = try ActivityFixture.block("2024-03-14", "23:30", "23:50", [(Self.myApp, 1200)], reason: nil)
        let state = try TrackerState(
            block: open,
            foreground: Self.myApp,
            presence: TrackerPresence(state: .active, since: ActivityFixture.instant("2024-03-14T23:30:00-04:00")),
            health: TrackerHealth(lastTick: ActivityFixture.instant("2024-03-15T00:10:00-04:00"), version: "1.0", sources: [])
        )
        try ActivityFixture.write(state.jsonText(timeZone: ActivityFixture.newYork), to: folders.currentStateURL, modified: .now)
        await reader.refresh()
        #expect(await changes.next() == .currentState)
        let read = try #require(await reader.currentState())
        #expect(read.foreground == Self.myApp && read.block?.isOpen == true && read.block?.end == open.end)
        let today = try DateInterval(start: ActivityFixture.instant("2024-03-15T00:00:00-04:00"), duration: 86_400)
        let yesterday = try DateInterval(start: ActivityFixture.instant("2024-03-14T00:00:00-04:00"), duration: 86_400 * 2)
        #expect(await reader.blocks(in: yesterday, devices: nil).map(\.isOpen) == [true])
        #expect(await reader.blocks(in: today, devices: nil).isEmpty)
    }

    @Test(
        "DATA-53 backgroundBlocks(in:) gives background blocks with the devices' items, no exclusions; blocks(in:) only foreground ones"
    )
    func backgroundBlocks() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let folders = folder.folders
        let log = try #require(folders.blockFolders.first)
        let background = try ActivityFixture.block("2024-03-14", "10:00", "11:00", [], background: [(ActivityFixture.agent, 3600)])
        try log.write([
            ActivityFixture.block("2024-03-14", "09:00", "10:00", [(Self.myApp, 3600)]),
            background,
        ], for: TrackingDay(year: 2024, month: 3, day: 14))
        let reader = FileActivityStore(folders: folders, homeDirectory: "/Users/alex")
        let day = try DateInterval(start: ActivityFixture.instant("2024-03-14T00:00:00-04:00"), duration: 86_400)
        #expect(await reader.backgroundBlocks(in: day, devices: nil) == [background])
        #expect(await reader.backgroundBlocks(in: day, devices: ["iPhone"]).isEmpty)
        #expect(await reader.blocks(in: day, devices: nil).map(\.isBackgroundBlock) == [false])
    }
}

extension ActivityBlock {
    /// The block with the item at `index` on `device`.
    func withDevice(_ device: String, forItemAt index: Int) -> Self {
        var result = self
        result.foreground[index].device = device
        return result
    }
}
