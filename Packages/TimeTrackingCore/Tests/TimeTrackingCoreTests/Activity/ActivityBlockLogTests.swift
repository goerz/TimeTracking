// Tests for the block-log format and BlockLogWriter (spec_activity_tracking.md
// §4.2, §4.3; spec_data_and_sync.md §6).

import Foundation
import Testing
import TimeTrackingCore

struct ActivityBlockLogTests {
    private static let monthFile = """
    {"type":"header","format":1,"tz":"-04:00","dev":"macbook","contexts":{"tmux:paper":"com.example.terminal","safari":"com.apple.Safari"}}
    {"s":"2026-10-28T09:10:00","e":"2026-10-28T09:44:30","a":1860,"dev":"macbook","g":"tmux:paper","gs":0.71,\
    "items":[["tmux:paper","draft","nvim (3 files)",1080],["safari","github.com/owner/repo","pull/123",540]],"bg":[],"src":"live"}
    {"type":"note","s":5}
    {"s":"2026-10-29T14:00:00","e":"2026-10-29T14:30:00","a":1800,"dev":"macbook","g":"safari","gs":1.0,\
    "items":[["safari","example.org","",1800]],"src":"knowledge","future_key":true}
    {"s":"2026-10-29T15:00:00","e":
    {"type":"header","format":1,"tz":"+01:00","dev":"macbook","contexts":{"mail":"com.apple.mail"}}

    {"s":"2026-10-30T08:00:00","e":"2026-10-30T08:20:00","a":1200,"dev":"macbook","g":"mail","gs":1,\
    "items":[["mail","Inbox","",1200]],"bg":[["claude","refactor","",600]],"src":"live"}

    """

    // swiftlint:disable line_length
    @Test(
        "DATA-42 a month file with a header, three blocks, a time zone change header, and a malformed line yields three blocks with correct instants and one counted parse error"
    )
    // swiftlint:enable line_length
    func monthFileWithTimeZoneChange() throws {
        let file = BlockLogFile(data: Data(Self.monthFile.utf8))
        #expect(file.malformedLines == 1)
        #expect(file.blocks.count == 3)
        let first = try #require(file.blocks.first)
        #expect(try first.start == (ActivityFixture.instant("2026-10-28T13:10:00Z")))
        #expect(try first.end == (ActivityFixture.instant("2026-10-28T13:44:30Z")))
        #expect(first.id == "macbook/2026-10-28T09:10:00-04:00")
        #expect(first.items.count == 2)
        #expect(first.groupShare == 0.71)
        #expect(file.blocks[1].source == .knowledge)
        #expect(try file.blocks[1].start == (ActivityFixture.instant("2026-10-29T18:00:00Z")))
        let last = file.blocks[2]
        #expect(try last.start == (ActivityFixture.instant("2026-10-30T07:00:00Z")))
        #expect(last.utcOffset == 3600)
        #expect(last.id == "macbook/2026-10-30T08:00:00+01:00")
        #expect(last.background == [ActivityItem(context: "claude", subject: "refactor", detail: "", seconds: 600)])
        #expect(file.contexts["tmux:paper"] == "com.example.terminal")
        #expect(file.contexts["mail"] == "com.apple.mail")
        #expect(file.lastHeader?.utcOffset == 3600)
    }

    @Test func aBlockBeforeAnyHeaderIsMalformed() {
        let line = #"{"s":"2026-10-28T09:10:00","e":"2026-10-28T09:20:00","a":600,"g":"x","gs":1,"items":[]}"#
        #expect(throws: ActivityError.self) {
            try BlockLogLine.parse(Data(line.utf8), header: nil)
        }
        let file = BlockLogFile(data: Data(line.utf8))
        #expect(file.blocks.isEmpty)
        #expect(file.malformedLines == 1)
    }

    @Test func linesRoundTripThroughTheEncoder() throws {
        let block = try ActivityFixture.block(
            start: "2026-10-28T13:10:00Z",
            end: "2026-10-28T13:44:30Z",
            items: [ActivityItem(context: "safari", subject: "github.com/owner/repo", detail: "pull/123", seconds: 540)]
        )
        let header = BlockLogHeader(utcOffset: -4 * 3600, device: "macbook", contexts: ["safari": "com.apple.Safari"])
        let headerText = BlockLogLine.header(header).jsonText
        #expect(headerText.hasPrefix(#"{"type":"header","format":1,"tz":"-04:00","dev":"macbook""#))
        #expect(try BlockLogLine.parse(Data(headerText.utf8), header: nil) == .header(header))
        let blockText = BlockLogLine.block(block, detail: nil).jsonText
        #expect(blockText.hasPrefix(#"{"s":"2026-10-28T09:10:00","e":"2026-10-28T09:44:30","a":540,"dev":"macbook""#))
        #expect(try BlockLogLine.parse(Data(blockText.utf8), header: header) == .block(block, detail: nil))
    }

    @Test func detailLinesCarryURLsFilesAndPresence() throws {
        let block = try ActivityFixture.block(
            start: "2026-10-28T13:10:00Z",
            end: "2026-10-28T13:44:30Z",
            items: [ActivityItem(context: "safari", subject: "example.org", detail: "", seconds: 60)]
        )
        let detail = try ActivityBlockDetail(
            blockID: block.id,
            items: block.items + [ActivityItem(context: "mail", subject: "Inbox", detail: "", seconds: 10)],
            urls: [ActivityURLVisit(time: block.start, browser: "safari", url: "https://example.org/a", title: "A")],
            files: [ActivityFileChange(time: ActivityFixture.instant("2026-10-28T13:20:00Z"), path: "~/Documents/a.txt")],
            presence: [ActivityPresenceTransition(time: block.start, state: .active)]
        )
        let header = BlockLogHeader(utcOffset: -4 * 3600, device: "macbook", contexts: [:])
        let text = BlockLogLine.block(block, detail: detail).jsonText
        #expect(text.contains(#""files":[["2026-10-28T09:20:00","~/Documents/a.txt"]]"#))
        guard case let .block(parsed, parsedDetail) = try BlockLogLine.parse(Data(text.utf8), header: header) else {
            Issue.record("not a block line")
            return
        }
        #expect(parsed.items.count == 2)
        #expect(parsedDetail == detail)
    }

    @Test func theWriterWritesHeadersAtTheStartAfterATimeZoneChangeAndForNewContexts() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        var writer = BlockLogWriter(folder: folder.url.appending(path: "blocks"), device: "macbook")
        let contexts = ["safari": "com.apple.Safari", "mail": "com.apple.mail"]
        let safari = ActivityItem(context: "safari", subject: "example.org", detail: "", seconds: 600)
        let mail = ActivityItem(context: "mail", subject: "Inbox", detail: "", seconds: 300)
        try writer.append(
            ActivityFixture.block(start: "2026-10-01T13:00:00Z", end: "2026-10-01T13:10:00Z", items: [safari]),
            contexts: contexts
        )
        try writer.append(
            ActivityFixture.block(start: "2026-10-01T14:00:00Z", end: "2026-10-01T14:10:00Z", items: [safari]),
            contexts: contexts
        )
        try writer.append(
            ActivityFixture.block(start: "2026-10-01T15:00:00Z", end: "2026-10-01T15:10:00Z", items: [mail]),
            contexts: contexts
        )
        let travel = try ActivityFixture.block(start: "2026-10-02T08:00:00Z", end: "2026-10-02T08:10:00Z", items: [mail], utcOffset: 3600)
        try writer.append(travel, contexts: contexts)
        try writer.append(
            ActivityFixture.block(start: "2026-11-01T14:00:00Z", end: "2026-11-01T14:10:00Z", items: [safari]),
            contexts: contexts
        )

        let october = try String(contentsOf: writer.fileURL(forMonth: "2026-10"), encoding: .utf8)
        let lines = october.split(separator: "\n")
        let headers = lines.filter { $0.contains(#""type":"header""#) }
        #expect(lines.count == 7)
        #expect(headers.count == 3)
        #expect(lines[0].contains(#""tz":"-04:00""#) && lines[0].contains(#""contexts":{"safari":"com.apple.Safari"}"#))
        #expect(lines[3].contains(#""contexts":{"mail":"com.apple.mail","safari":"com.apple.Safari"}"#))
        #expect(lines[5].contains(#""tz":"+01:00""#))
        let file = BlockLogFile(data: Data(october.utf8))
        #expect(file.malformedLines == 0)
        #expect(file.blocks.map(\.id).last == "macbook/2026-10-02T09:00:00+01:00")
        let november = try BlockLogFile(data: Data(contentsOf: writer.fileURL(forMonth: "2026-11")))
        #expect(november.lastHeader != nil)
        #expect(november.blocks.count == 1)
    }

    @Test func aNewWriterContinuesAnExistingFileWithoutARepeatedHeader() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let blocks = folder.url.appending(path: "blocks")
        let item = ActivityItem(context: "safari", subject: "example.org", detail: "", seconds: 600)
        var first = BlockLogWriter(folder: blocks, device: "macbook")
        try first.append(ActivityFixture.block(start: "2026-10-01T13:00:00Z", end: "2026-10-01T13:10:00Z", items: [item]), contexts: [:])
        var second = BlockLogWriter(folder: blocks, device: "macbook")
        try second.append(ActivityFixture.block(start: "2026-10-01T14:00:00Z", end: "2026-10-01T14:10:00Z", items: [item]), contexts: [:])
        let text = try String(contentsOf: second.fileURL(forMonth: "2026-10"), encoding: .utf8)
        #expect(text.split(separator: "\n").count == 3)
    }
}
