// The block log's per-Mac folders, whole-file day replacement, and days
// closed after the agent was not running (activity_tracking.md §2.8,
// §4.1).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct BlockLogStorageTests {
    /// Another Mac's month file: a header naming `imac` and one block on the fixture day.
    private static let otherMacLines = """
    {"type":"header","format":1,"tz":"-04:00","dev":"imac","contexts":{"mail":"com.apple.mail"}}
    {"s":"2024-03-14T08:00:00","e":"2024-03-14T08:30:00","a":1800,"dev":[["imac",1800]],"rec":0,"g":"mail","gs":1,\
    "items":[["mail","Inbox","",1800,"imac"]],"bg":[]}

    """

    /// A month file from before the per-Mac folders, with this Mac's block
    /// (`macbook`) between two of the other Mac's.
    private static let sharedMonthLines = """
    {"type":"header","format":1,"tz":"-04:00","dev":"imac","contexts":{"mail":"com.apple.mail"}}
    {"s":"2024-03-12T08:00:00","e":"2024-03-12T08:30:00","a":1800,"dev":[["imac",1800]],"rec":0,"g":"mail","gs":1,\
    "items":[["mail","Inbox","",1800,"imac"]],"bg":[]}
    {"type":"header","format":1,"tz":"-04:00","dev":"macbook","contexts":{"textedit":"com.apple.TextEdit"}}
    {"s":"2024-03-12T09:00:00","e":"2024-03-12T09:30:00","a":1800,"dev":[["macbook",1800]],"rec":0,"g":"textedit","gs":1,\
    "items":[["textedit","Notes","",1800,"macbook"]],"bg":[]}
    {"type":"header","format":1,"tz":"-04:00","dev":"imac","contexts":{"mail":"com.apple.mail"}}
    {"s":"2024-03-13T08:00:00","e":"2024-03-13T08:30:00","a":1800,"dev":[["imac",1800]],"rec":0,"g":"mail","gs":1,\
    "items":[["mail","Inbox","",1800,"imac"]],"bg":[]}

    """

    private static func work(_ harness: AgentHarness, for seconds: TimeInterval) async {
        harness.engine.handle(.unlock, at: harness.clock.now)
        harness.schedule = TickSchedule(start: harness.clock.now)
        harness.frontmost("com.apple.TextEdit", name: "TextEdit", title: "Notes")
        await harness.run(for: seconds)
        harness.engine.handle(.lock, at: harness.clock.now)
    }

    @Test("TRK-44 each Mac writes only its own blocks/ subfolder, so forming a day again leaves another Mac's blocks of that day")
    func eachMacWritesItsOwnFolder() async throws {
        let harness = try AgentHarness()
        let other = harness.folders.sharedBlocks.appending(path: "mac-2/2024-03.jsonl")
        try FileManager.default.createDirectory(at: other.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(Self.otherMacLines.utf8).write(to: other)
        #expect(BlockLogFile(data: Data(Self.otherMacLines.utf8)).blocks.count == 1)

        await Self.work(harness, for: 300)
        harness.advance(600)
        await Self.work(harness, for: 300)

        let ownFolder = harness.folders.sharedBlocks.appending(path: AgentHarness.macFolder, directoryHint: .isDirectory)
        #expect(harness.engine.logs.blocksFolder == ownFolder)
        #expect(harness.blocks.count == 2)
        #expect(try Data(contentsOf: other) == Data(Self.otherMacLines.utf8))
        let store = FileActivityStore(folders: harness.folders, timeZone: AgentHarness.zone, clock: harness.clock)
        let day = DateInterval(start: harness.time(-10 * 3600), duration: 86_400)
        let read = try await store.blocks(in: day, devices: nil)
        #expect(read.count == 3)
        #expect(read.first?.deviceNames == ["imac"])
    }

    @Test("TRK-44 on start the agent moves its own lines out of a month file directly in blocks/ and leaves another Mac's")
    func ownLinesMoveToTheMacFolder() throws {
        let harness = try AgentHarness()
        let shared = harness.folders.sharedBlocks.appending(path: "2024-03.jsonl")
        try FileManager.default.createDirectory(at: harness.folders.sharedBlocks, withIntermediateDirectories: true)
        try Data(Self.sharedMonthLines.utf8).write(to: shared)
        try harness.restart()

        let left = try BlockLogFile(contentsOf: shared)
        #expect(left.blocks.map(\.localDay) == ["2024-03-12", "2024-03-13"])
        #expect(Set(left.blocks.flatMap(\.deviceNames)) == ["imac"])
        let moved = harness.blocks
        #expect(moved.map(\.id) == ["2024-03-12T09:00:00-04:00"])
        #expect(moved.first?.deviceNames == ["macbook"])

        // A file left with another Mac's lines only stays; with none it goes.
        try harness.restart()
        #expect(try BlockLogFile(contentsOf: shared).blocks.count == 2)
        let ownOnly = harness.folders.sharedBlocks.appending(path: "2024-02.jsonl")
        let february = Self.sharedMonthLines.split(separator: "\n").dropFirst(2).prefix(2).joined(separator: "\n") + "\n"
        try Data(february.replacing("2024-03-12", with: "2024-02-12").utf8).write(to: ownOnly)
        try harness.restart()
        #expect(!FileManager.default.fileExists(atPath: ownOnly.path))
        #expect(FileManager.default.fileExists(atPath: harness.engine.logs.blocksFolder.appending(path: "2024-02.jsonl").path))
    }

    @Test(
        "TRK-45 a day's rewrite replaces the detail file, then the month file, each in one step; a failed write leaves the block log"
    )
    func aDayIsReplacedWhole() async throws {
        let harness = try AgentHarness()
        await Self.work(harness, for: 300)
        let month = harness.engine.logs.monthURL("2024-03-14")
        let before = try Data(contentsOf: month)
        #expect(harness.blocks.count == 1)

        // The detail file cannot be replaced while a folder stands in its place.
        let detail = harness.engine.logs.detailURL("2024-03-14")
        try FileManager.default.removeItem(at: detail)
        try FileManager.default.createDirectory(at: detail.appending(path: "blocked"), withIntermediateDirectories: true)
        harness.advance(600)
        await Self.work(harness, for: 300)
        #expect(try Data(contentsOf: month) == before)

        try FileManager.default.removeItem(at: detail)
        harness.engine.rebuildToday()
        #expect(harness.blocks.count == 2)
        #expect(harness.details.count == 2)
    }

    @Test("TRK-46 a block still open when the agent stopped is closed on its own day when the agent starts days later")
    func anOpenBlockClosesAfterARestart() async throws {
        let harness = try AgentHarness()
        harness.frontmost("com.apple.TextEdit", name: "TextEdit", title: "Notes")
        await harness.run(for: 600)
        #expect(harness.blocks.isEmpty)
        #expect(harness.engine.openBlock != nil)

        // Killed without a chance to stop; started again two days later.
        harness.clock.set(harness.time(2 * 86_400 - 3600))
        try harness.restart()
        await harness.run(for: 60)

        let closed = harness.blocks.filter { $0.localDay == "2024-03-14" }
        #expect(closed.count == 1)
        #expect(closed.first.map { $0.end <= harness.time(600) && $0.end > harness.time(0) } == true)
        #expect(try harness.engine.store.value(AgentEngine.rebuiltDayKey) == "2024-03-16")
    }
}
