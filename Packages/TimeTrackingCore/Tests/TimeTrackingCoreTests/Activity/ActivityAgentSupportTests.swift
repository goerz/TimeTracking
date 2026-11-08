// The library parts the agent shares with the app: the socket grammar,
// exclusions applied to stored blocks, and the container mirror
// (activity_tracking.md §4.1, §7.2, §7.3).

import Foundation
import Testing
@testable import TimeTrackingCore

struct ActivityAgentSupportTests {
    @Test("TRK-35 the socket grammar: quoted words round-trip, an unknown command is an error")
    func commandsRoundTripWithQuotes() throws {
        let command = TrackerCommand.deleteBlock(start: "2024-03-14T09:10:00-04:00", end: "2024-03-14T09:44:00-04:00")
        #expect(command.line == "delete-block 2024-03-14T09:10:00-04:00 2024-03-14T09:44:00-04:00")
        #expect(try TrackerCommand.parse(command.line) == command)
        let quoted = TrackerCommand.tmuxEvent(hook: "after-select-pane", arguments: ["Alex's \"pane\""])
        #expect(quoted.line == #"tmux after-select-pane "Alex's \"pane\"""#)
        #expect(try TrackerCommand.parse(quoted.line) == quoted)
        #expect(try TrackerCommand.parse("tmux after-select-pane %3\n") == .tmuxEvent(hook: "after-select-pane", arguments: ["%3"]))
        #expect(try TrackerCommand.parse("reapply-exclusions 2024-03-01 2024-03-14") == .reapplyExclusions(
            from: "2024-03-01",
            to: "2024-03-14"
        ))
        #expect(throws: TrackerCommand.ParseError.unknownCommand("tick")) { try TrackerCommand.parse("tick") }
        #expect(throws: TrackerCommand.ParseError.wrongArguments("delete-block")) {
            try TrackerCommand.parse("delete-block 2024-03-14T09:10:00")
        }
        #expect(throws: TrackerCommand.ParseError.wrongArguments("forget-day")) { try TrackerCommand.parse("forget-day 2024-13-01") }
        #expect(throws: TrackerCommand.ParseError.unbalancedQuote) { try TrackerCommand.parse("tmux \"open") }
        #expect(TrackerReply(line: "error no such block\n") == .error("no such block"))
        #expect(TrackerReply.success.line == "ok")
    }

    @Test func mirrorCopiesNewerDateFilesAndNewerSettings() throws {
        let root = try TemporaryFolder()
        defer { root.remove() }
        let local = root.url.appending(path: "local")
        let container = root.url.appending(path: "container")
        try FileManager.default.createDirectory(at: local.appending(path: "blocks"), withIntermediateDirectories: true)
        let file = local.appending(path: "blocks/2024-03-14.jsonl")
        try Data("a\n".utf8).write(to: file)
        try "[presence]\nidle_after = \"3m\"\n".write(to: local.appending(path: "settings.toml"), atomically: true, encoding: .utf8)
        let mirror = ActivityFolderMirror(local: local, container: container)
        let first = try mirror.sync()
        #expect(first.days == [TrackingDay(year: 2024, month: 3, day: 14)] && first.settingsFrom == "local")
        #expect(try Data(contentsOf: container.appending(path: "blocks/2024-03-14.jsonl")) == Data("a\n".utf8))
        #expect(try mirror.sync() == ActivityFolderMirror.Report())
        try Data("a\nb\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date() + 60], ofItemAtPath: file.path)
        #expect(try mirror.sync().days == [TrackingDay(year: 2024, month: 3, day: 14)])
        // An older local file, left from an earlier fallback period, never replaces the container's.
        try Data("old\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date() - 3600], ofItemAtPath: file.path)
        #expect(try mirror.sync().days.isEmpty)
    }
}
