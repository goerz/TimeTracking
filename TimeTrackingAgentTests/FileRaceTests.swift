// Files the agent reads while their owners write them: another app's SQLite
// database, settings.toml, and iCloud Drive placeholders
// (spec_activity_tracking.md §3.2, §3.3, §4.1, §7).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct FileRaceTests {
    @Test("TRK-48 a database copy during which the owner wrote its WAL is made again and matches the files as they are now")
    func snapshotRetriesAfterAWrite() throws {
        let folder = try TemporaryFolder.make("snapshot")
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "History.db")
        try Data("database".utf8).write(to: source)
        try Data("wal one".utf8).write(to: URL(filePath: source.path + "-wal"))
        let target = folder.appending(path: "copy/History.db")
        var copies = 0
        try SQLiteSnapshot.copy(path: source.path, to: target) { from, to in
            copies += 1
            try FileManager.default.copyItem(atPath: from, toPath: to)
            if copies == 1 {
                // The owner writes between the database and its WAL.
                try Data("wal two, longer".utf8).write(to: URL(filePath: source.path + "-wal"))
            }
        }
        #expect(copies == 4)
        #expect(try Data(contentsOf: URL(filePath: target.path + "-wal")) == Data("wal two, longer".utf8))
        #expect(try Data(contentsOf: target) == Data("database".utf8))
    }

    @Test("TRK-49 a second agent finds agent.lock taken and does not start")
    func secondInstanceIsRefused() throws {
        let folder = try TemporaryFolder.make("lock")
        defer { try? FileManager.default.removeItem(at: folder) }
        let lock = folder.appending(path: "agent.lock")
        #expect(InstanceLock.acquire(at: lock))
        // flock locks belong to an open file, so a second open in this
        // process stands for a second agent.
        #expect(!InstanceLock.acquire(at: lock))
    }

    @Test("TRK-50 a file event delivered late is recorded at the file's modification time, within the last minute")
    func fileEventsUseModificationTime() throws {
        let harness = try AgentHarness()
        let saved = "/Users/alex/Documents/Papers/notes.tex"
        let old = "/Users/alex/Documents/Papers/old.tex"
        harness.files.modified[saved] = harness.clock.now.addingTimeInterval(-20)
        harness.files.modified[old] = harness.clock.now.addingTimeInterval(-3600)
        harness.engine.recordFileEvents([saved, old])
        let times = Dictionary(harness.engine.fileChanges.changes.map { ($0.path, $0.time) }) { first, _ in first }
        // The log keeps paths with `~` for the home folder.
        #expect(times["~/Documents/Papers/notes.tex"] == harness.clock.now.addingTimeInterval(-20))
        #expect(times["~/Documents/Papers/old.tex"] == harness.clock.now)
    }

    @Test("TRK-51 a month file iCloud Drive holds only as a placeholder is not written; the day is written once the file is here")
    func placeholderMonthIsLeftAlone() async throws {
        let harness = try AgentHarness()
        let folder = harness.engine.logs.blocksFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let placeholder = folder.appending(path: ".2024-03.jsonl.icloud")
        try Data().write(to: placeholder)
        harness.frontmost("com.apple.TextEdit", name: "TextEdit", title: "Notes")
        await harness.run(for: 300)
        harness.engine.handle(.lock, at: harness.clock.now)
        let month = folder.appending(path: "2024-03.jsonl")
        #expect(!FileManager.default.fileExists(atPath: month.path))

        // The download arrives with another day of the month.
        try FileManager.default.removeItem(at: placeholder)
        let other = """
        {"type":"header","format":1,"tz":"-04:00","dev":"macbook","contexts":{"mail":"com.apple.mail"}}
        {"s":"2024-03-12T08:00:00","e":"2024-03-12T08:30:00","a":1800,"dev":[["macbook",1800]],"rec":0,"g":"mail","gs":1,\
        "items":[["mail","Inbox","",1800,"macbook"]],"bg":[]}

        """
        try Data(other.utf8).write(to: month)
        harness.engine.rebuildToday()
        #expect(harness.blocks.map(\.localDay) == ["2024-03-12", "2024-03-14"])
    }

    @Test("TRK-52 a command still running at its deadline is stopped and answers nothing")
    func hungCommandIsStopped() async {
        let runner = LiveCommandRunner(timeout: .milliseconds(200))
        let start = ContinuousClock.now
        #expect(await runner.run(["/bin/sleep", "30"]) == nil)
        #expect(ContinuousClock.now - start < .seconds(10))
        #expect(await runner.run(["/bin/echo", "ok"]) == "ok\n")
    }

    @Test("TRK-53 a settings.toml evicted to an iCloud Drive placeholder keeps the exclusions in force")
    func evictedSettingsKeepExclusions() async throws {
        let harness = try AgentHarness(settings: "[privacy]\nexclude_apps = [\"com.apple.mail\"]\n")
        #expect(harness.engine.settings.exclusions(homeDirectory: AgentHarness.home).excludesApp("com.apple.mail"))
        let store = FileActivityStore(
            folders: harness.folders,
            timeZone: AgentHarness.zone,
            clock: harness.clock,
            homeDirectory: AgentHarness.home
        )
        #expect(store.exclusions.excludesApp("com.apple.mail"))
        let settings = harness.folders.shared.appending(path: "settings.toml")
        try FileManager.default.removeItem(at: settings)
        try Data().write(to: harness.folders.shared.appending(path: ".settings.toml.icloud"))
        harness.frontmost("com.apple.mail", name: "Mail", title: "Inbox")
        await harness.engine.tick()
        #expect(harness.engine.settings.exclusions(homeDirectory: AgentHarness.home).excludesApp("com.apple.mail"))
        #expect(!harness.sampleLines().joined().contains("Inbox"))
        await store.refresh()
        #expect(store.exclusions.excludesApp("com.apple.mail"))
    }

    @Test("TRK-54 delete-block with an end deletes the whole range shown, also when a tick cut it into two blocks since")
    func deleteBlockRange() async throws {
        let harness = try AgentHarness()
        harness.frontmost("com.apple.TextEdit", name: "TextEdit", title: "Notes")
        await harness.run(for: 300)
        harness.engine.handle(.lock, at: harness.clock.now)
        harness.advance(60)
        harness.engine.handle(.unlock, at: harness.clock.now)
        harness.schedule = TickSchedule(start: harness.clock.now)
        await harness.run(for: 300)
        harness.engine.handle(.lock, at: harness.clock.now)
        let blocks = harness.blocks
        #expect(blocks.count == 2)
        let first = try #require(blocks.first)
        let last = try #require(blocks.last)
        let command = TrackerCommand.deleteBlock(
            start: ActivityTimestamp.text(first.start, utcOffset: first.utcOffset),
            end: ActivityTimestamp.text(last.end, utcOffset: last.utcOffset)
        )
        #expect(command.line.split(separator: " ").count == 3)
        #expect(try TrackerCommand.parse(command.line) == command)
        #expect(harness.engine.rewrite(command) == .success)
        #expect(harness.blocks.isEmpty)
        #expect(try harness.engine.store.rows(from: first.start, to: last.end).isEmpty)
    }
}
