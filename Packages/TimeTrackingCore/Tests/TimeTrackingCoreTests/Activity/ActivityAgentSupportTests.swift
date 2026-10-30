// The library parts the agent shares with the app: the socket grammar,
// browser items, recorded-item exclusions, the detail log's dwell times,
// and the container mirror (spec_activity_tracking.md §3.3, §4.1, §7.2, §7.3).

import Foundation
import Testing
@testable import TimeTrackingCore

struct ActivityAgentSupportTests {
    @Test func commandsRoundTripWithQuotes() throws {
        let command = TrackerCommand.deleteBlock(device: "Alex's \"Mac\"", start: "2024-03-14T09:10:00")
        #expect(command.line == #"delete-block "Alex's \"Mac\"" 2024-03-14T09:10:00"#)
        #expect(try TrackerCommand.parse(command.line) == command)
        #expect(try TrackerCommand.parse("tmux after-select-pane %3\n") == .tmuxEvent(hook: "after-select-pane", arguments: ["%3"]))
        #expect(try TrackerCommand.parse("reapply-exclusions 2024-03-01 2024-03-14") == .reapplyExclusions(
            from: "2024-03-01",
            to: "2024-03-14"
        ))
        #expect(throws: TrackerCommand.ParseError.unknownCommand("frobnicate")) { try TrackerCommand.parse("frobnicate") }
        #expect(throws: TrackerCommand.ParseError.wrongArguments("forget-day")) { try TrackerCommand.parse("forget-day 2024-13-01") }
        #expect(throws: TrackerCommand.ParseError.unbalancedQuote) { try TrackerCommand.parse("tmux \"open") }
        #expect(TrackerReply(line: "error no such block\n") == .error("no such block"))
        #expect(TrackerReply.success.line == "ok")
    }

    @Test func browserItems() throws {
        var privacy = TrackerPrivacySettings()
        privacy.privateDomains = ["bank.example"]
        privacy.excludeDomains = ["health.example"]
        let rules = BrowserItemRules(exclusions: ExclusionRules(privacy: privacy, homeDirectory: "/Users/alex"))
        let pull = try #require(rules.parts(for: "https://github.com/owner/repo/pull/123/files?w=1#top"))
        #expect([pull.subject, pull.detail, pull.groupKey] == ["github.com/owner/repo", "pull/123", "github.com/owner"])
        let forum = try #require(rules.parts(for: "https://www.forum.example.org/viewtopic.php?t=42&sid=abc"))
        #expect([forum.subject, forum.detail, forum.groupKey] == ["forum.example.org", "viewtopic.php?t=42", "forum.example.org"])
        let search = try #require(rules.parts(for: "https://www.google.com/search?q=secret"))
        #expect([search.subject, search.detail] == ["google.com", ""])
        let bank = try #require(rules.parts(for: "https://online.bank.example/accounts/1"))
        #expect([bank.subject, bank.detail] == ["online.bank.example", ""])
        #expect(bank.loggedURL == "https://online.bank.example")
        let health = try #require(rules.parts(for: "https://portal.health.example/results"))
        #expect(health.isExcluded && health.loggedURL == nil)
        #expect(rules.parts(for: "about:blank") == nil)
    }

    @Test func reappliedBlocksAndDetails() {
        var privacy = TrackerPrivacySettings()
        privacy.excludeDomains = ["news.example.com"]
        privacy.excludeApps = ["com.apple.Notes"]
        privacy.excludePaths = ["~/Documents/Medical"]
        let rules = ExclusionRules(privacy: privacy, homeDirectory: "/Users/alex")
        let start = Date(timeIntervalSince1970: 1_710_410_400)
        let block = ActivityBlock(
            start: start,
            end: start.addingTimeInterval(1800),
            activeSeconds: 1500,
            device: "macbook",
            groupKey: "news.example.com",
            groupShare: 0.6,
            items: [
                ActivityItem(context: "safari", subject: "news.example.com", detail: "story/42", seconds: 900),
                ActivityItem(context: "notes", subject: "Diary", detail: "", seconds: 300),
                ActivityItem(context: "preview", subject: "~/Documents/Medical", detail: "scan.pdf", seconds: 300),
            ],
            utcOffset: -14_400
        )
        let result = rules.reapplied(to: block, contexts: ["notes": "com.apple.Notes", "safari": "com.apple.Safari"])
        #expect(result?.items.map(\.subject) == ["(private)", "(private)"])
        #expect(result?.activeSeconds == 1200)
        #expect(result?.groupKey == "safari")
        let detail = ActivityBlockDetail(
            blockID: block.id,
            items: block.items,
            urls: [ActivityURLVisit(time: start, browser: "safari", url: "https://news.example.com/story/42", title: "Story")],
            files: [ActivityFileChange(time: start, path: "~/Documents/Medical/scan.pdf")],
            dwell: [ActivityDwell(time: start, url: "https://news.example.com/story/42", seconds: 60)]
        )
        let cleaned = rules.reapplied(to: detail, contexts: [:])
        #expect(cleaned.urls.isEmpty && cleaned.files.isEmpty && cleaned.dwell.isEmpty)
    }

    @Test func dwellRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_710_410_400)
        let block = ActivityBlock(
            start: start,
            end: start.addingTimeInterval(600),
            activeSeconds: 600,
            device: "macbook",
            groupKey: "safari",
            groupShare: 1,
            items: [ActivityItem(context: "safari", subject: "example.com", detail: "", seconds: 600)],
            utcOffset: -14_400
        )
        let detail = ActivityBlockDetail(
            blockID: block.id,
            items: block.items,
            dwell: [ActivityDwell(time: start, url: "https://example.com", seconds: 120)]
        )
        let line = BlockLogLine.block(block, detail: detail).jsonText
        #expect(line.hasSuffix(#""dwell":[["2024-03-14T06:00:00","https://example.com",120]]}"#))
        let header = BlockLogHeader(utcOffset: -14_400, device: "macbook", contexts: [:])
        guard case let .block(_, parsed) = try BlockLogLine.parse(Data(line.utf8), header: header) else {
            Issue.record("not a block")
            return
        }
        #expect(parsed?.dwell == detail.dwell)
        let plain = BlockLogLine.block(block, detail: ActivityBlockDetail(blockID: block.id, items: block.items)).jsonText
        #expect(!plain.contains("dwell"))
    }

    @Test func mirrorCopiesChangedMonthsAndNewerSettings() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "mirror-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let local = root.appending(path: "local")
        let container = root.appending(path: "container")
        try FileManager.default.createDirectory(at: local.appending(path: "blocks"), withIntermediateDirectories: true)
        try Data("a\n".utf8).write(to: local.appending(path: "blocks/2024-03.jsonl"))
        try "[presence]\nidle_after = \"3m\"\n".write(to: local.appending(path: "settings.toml"), atomically: true, encoding: .utf8)
        let mirror = ActivityFolderMirror(local: local, container: container)
        let first = try mirror.sync()
        #expect(first.months == ["2024-03.jsonl"] && first.settingsFrom == "local")
        #expect(try Data(contentsOf: container.appending(path: "blocks/2024-03.jsonl")) == Data("a\n".utf8))
        #expect(try mirror.sync() == ActivityFolderMirror.Report())
        try Data("a\nb\n".utf8).write(to: local.appending(path: "blocks/2024-03.jsonl"))
        #expect(try mirror.sync().months == ["2024-03.jsonl"])
    }
}
