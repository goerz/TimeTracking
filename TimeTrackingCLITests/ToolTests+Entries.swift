// The timetracking tool as a subprocess: entries and single-entry commands,
// read-only access, errors (spec_automation.md §3.6, §3.11, §9 items 7 to 11, 34, 36).

import Foundation
import Testing

extension ToolTests {
    @Test("AUTO-49 the entries table subtotals by shown day, while each row keeps its real date")
    func entriesSubtotalsFollowMidnight() throws {
        let fixture = try ToolFixture()
        try fixture.execute("INSERT INTO setting (key, value, modified_at) VALUES ('day.midnightHour', '9', 0)")
        let table = try fixture.run(["entries", "--from", "2026-10-28", "--to", "2026-10-29"])
        #expect(table.status == 0, "\(table.standardError)")
        #expect(table.standardOutput.contains("2026-10-29"))
        #expect(table.standardOutput.contains("Subtotal 2026-10-28"))
        #expect(!table.standardOutput.contains("Subtotal 2026-10-29"))
    }

    @Test("AUTO-7 entries without a range lists today's entries; report --json without a range covers the current week")
    func defaultRanges() throws {
        let fixture = try ToolFixture()
        let entries = try fixture.run(["entries", "--json"])
        #expect(entries.status == 0)
        let ids = (entries.json["entries"] as? [[String: Any]])?.compactMap { $0["id"] as? String }
        #expect(ids == [ToolFixture.entryID(5), ToolFixture.runningEntry])
        #expect(entries.json["from"] as? String == "2026-10-29")
        #expect(entries.json["to"] as? String == "2026-10-30")
        let report = try fixture.run(["report", "--json"])
        #expect(report.json["from"] as? String == "2026-10-26")
        #expect(report.json["to"] as? String == "2026-11-02")
        let table = try fixture.run(["entries"])
        #expect(table.standardOutput.contains("Subtotal 2026-10-29"))
        #expect(table.standardOutput.contains("running"))
    }

    @Test("AUTO-8 entries --from --to returns the half-open range ascending with the summed total")
    func entriesRange() throws {
        let fixture = try ToolFixture()
        let result = try fixture.run(["entries", "--from", "2026-10-20", "--to", "2026-10-27", "--json"])
        #expect(result.status == 0)
        let entries = try #require(result.json["entries"] as? [[String: Any]])
        #expect(entries.compactMap { $0["id"] as? String } == [1, 2, 3].map(ToolFixture.entryID))
        let starts = entries.compactMap { $0["start"] as? String }
        #expect(starts == starts.sorted())
        #expect(result.json["total"] as? Int == entries.compactMap { $0["duration"] as? Int }.reduce(0, +))
        #expect(result.json["total"] as? Int == 7200 + 5400 + 1800)
        let words = try fixture.run(["entries", "--week", "2026-W43", "--json"])
        #expect((words.json["entries"] as? [Any])?.count == 3)
        let desc = try fixture.run(["entries", "--from", "2026-10-20", "--to", "2026-10-27", "--order", "desc", "--limit", "1", "--json"])
        #expect((desc.json["entries"] as? [[String: Any]])?.first?["id"] as? String == ToolFixture.entryID(3))
        let filtered = try fixture.run(["entries", "--from", "2026-10-20", "--to", "2026-10-30", "--project", "Noise paper", "--json"])
        #expect((filtered.json["entries"] as? [Any])?.count == 3)
        let noProject = try fixture.run(["entries", "--from", "2026-10-20", "--to", "2026-10-30", "--no-project", "--json"])
        #expect((noProject.json["entries"] as? [[String: Any]])?.compactMap { $0["task"] as? String } == ["Misc"])
        let running = try fixture.run(["entries", "--running", "--json"])
        #expect((running.json["entries"] as? [[String: Any]])?.first?["id"] as? String == ToolFixture.runningEntry)
        let tooLong = try fixture.run(["entries", "--from", "2024-01-01", "--to", "2026-01-01"])
        #expect(tooLong.status == 2)
        #expect(try fixture.run(["entries", "--from", "2024-01-01", "--to", "2026-01-01", "--all-time"]).status == 0)
        #expect(try fixture.run(["entries", "--day", "yesterday", "--json"]).json["from"] as? String == "2026-10-28")
        #expect(try fixture.run(["entries", "--from", "2026-13-01"]).status == 2)
    }

    @Test("AUTO-9 entry create across midnight creates and prints two entries, listed under their own days")
    func createAcrossMidnight() throws {
        let fixture = try ToolFixture()
        let result = try fixture.run(["entry", "create", "Overnight", "--start", "2026-10-20T23:30", "--end", "2026-10-21T00:30"])
        #expect(result.status == 0, "\(result.standardError)")
        #expect(result.lines.count == 2)
        #expect(result.lines[0].contains("on 2026-10-20 from 23:30 to 00:00"))
        #expect(result.lines[1].contains("on 2026-10-21 from 00:00 to 00:30"))
        let first = try fixture.run(["entries", "--day", "2026-10-20", "--task", "Overnight", "--json"])
        #expect((first.json["entries"] as? [[String: Any]])?.compactMap { $0["duration"] as? Int } == [1800])
        let second = try fixture.run(["entries", "--day", "2026-10-21", "--task", "Overnight", "--json"])
        #expect((second.json["entries"] as? [[String: Any]])?.compactMap { $0["duration"] as? Int } == [1800])
        let future = try fixture.run(["entry", "create", "F", "--start", "2026-10-29T10:30", "--end", "2026-10-29T11:00"])
        #expect(future.status == 4)
        let backwards = try fixture.run(["entry", "create", "B", "--start", "2026-10-22T10:30", "--end", "2026-10-22T10:00"])
        #expect(backwards.status == 4)
    }

    @Test("AUTO-10 entry edit that overlaps another entry exits 4 and changes nothing; --force succeeds")
    func editOverlap() throws {
        let fixture = try ToolFixture()
        let id = ToolFixture.entryID(2)
        let before = try fixture.run(["entry", "show", id, "--json"])
        let refused = try fixture.run(["entry", "edit", id, "--start", "2026-10-20T10:00", "--end", "2026-10-20T12:00"])
        #expect(refused.status == 4)
        #expect(try fixture.run(["entry", "show", id, "--json"]).standardOutput == before.standardOutput)
        let forced = try fixture.run(["entry", "edit", id, "--start", "2026-10-20T10:00", "--end", "2026-10-20T12:00", "--force", "--json"])
        #expect(forced.status == 0)
        let entry = (forced.json["entries"] as? [[String: Any]])?.first
        #expect(entry?["start"] as? String == "2026-10-20T10:00:00+02:00")
        let task = try fixture.run(["entry", "edit", id, "--task", "Mail", "--no-project", "--json"])
        let changed = (task.json["entries"] as? [[String: Any]])?.first
        #expect(changed?["task"] as? String == "Mail")
        #expect(changed?["project"] is NSNull)
    }

    @Test("AUTO-11 entry delete without --yes prints the entry, exits 2, and deletes nothing; with --yes it is gone")
    func deleteNeedsYes() throws {
        let fixture = try ToolFixture()
        let id = ToolFixture.entryID(3)
        let refused = try fixture.run(["entry", "delete", id])
        #expect(refused.status == 2)
        #expect(refused.standardOutput.isEmpty)
        #expect(refused.standardError.contains("Misc"))
        #expect(try fixture.run(["entry", "show", id]).status == 0)
        let deleted = try fixture.run(["entry", "delete", id, "--yes"])
        #expect(deleted.status == 0)
        #expect(try fixture.run(["entry", "show", id]).status == 3)
    }

    @Test("AUTO-34 every read command succeeds on a store in a read-only folder and leaves its modification time unchanged")
    func readOnlyFolder() throws {
        let fixture = try ToolFixture()
        let folder = fixture.folder.appending(path: "readonly")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = folder.appending(path: "store.sqlite")
        try FileManager.default.copyItem(at: fixture.store, to: store)
        let description = try fixture.write(ToolCheckTests.matching, named: "description.toml")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        let modified = try FileManager.default.attributesOfItem(atPath: store.path)[.modificationDate] as? Date
        let commands: [[String]] = [
            ["status"], ["entries"], ["entries", "--json"], ["entry", "show", ToolFixture.entryID(1)], ["report"], ["report", "--csv"],
            ["projects"], ["clients"], ["areas"], ["check", description], ["export"], ["export", "--format", "csv"],
        ]
        for command in commands {
            let result = try ToolProcess.run(
                "timetracking",
                command,
                environment: fixture.environment.merging(["TIMETRACKING_STORE": store.path]) { $1 }
            )
            #expect(result.status == 0, "\(command): \(result.standardError)")
        }
        #expect(try FileManager.default.attributesOfItem(atPath: store.path)[.modificationDate] as? Date == modified)
        let contents = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(contents == ["store.sqlite"])
    }

    @Test("AUTO-36 --json with --csv exits 2, and stdout is empty on every error")
    func errorsKeepStdoutEmpty() throws {
        let fixture = try ToolFixture()
        let both = try fixture.run(["status", "--json", "--csv"])
        #expect(both.status == 2)
        #expect(both.standardOutput.isEmpty)
        #expect((both.errorJSON["error"] as? [String: Any])?["code"] as? Int == 2)
        let failures: [[String]] = [
            ["--json", "--csv", "entries"], ["start", "--project", "Nonexistent"], ["stop", "--at", "2026-10-29T11:00"],
            ["entries", "--from", "nonsense"], ["entry", "show", "not-a-uuid"], ["status", "--unknown-option"],
            ["check", "/nonexistent.toml"], ["area", "set-color", "Research", "--color", "teal"],
        ]
        for arguments in failures {
            let result = try fixture.run(arguments)
            #expect(result.status != 0, "\(arguments)")
            #expect(result.standardOutput.isEmpty, "\(arguments)")
            #expect(result.standardError.hasPrefix("error: ") || result.standardError.hasPrefix("{\"error\""), "\(arguments)")
        }
        #expect(try fixture.run(["status", "--unknown-option"]).status == 2)
        let missing = try ToolFixture(empty: ())
        #expect(try missing.run(["status"]).status == 5)
    }
}
