// The timetracking tool as a subprocess: import, export, schema, version,
// completions, the store path (spec_automation.md §3.1, §3.10, §7, §9
// items 24 to 30, 35, 37; spec_architecture.md ARCH-19).

import Foundation
import SQLite3
import Testing

extension ToolTests {
    /// The export document without `generatedAt` and `storeID`, as sorted JSON text.
    private func comparable(_ text: String) throws -> String {
        var object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        object["generatedAt"] = nil
        object["storeID"] = nil
        return try String(decoding: JSONSerialization.data(withJSONObject: object, options: .sortedKeys), as: UTF8.self)
    }

    @Test("AUTO-24 export, import with --include-settings into an empty store, and export again round-trips")
    func exportImportRoundTrip() throws {
        let fixture = try ToolFixture()
        let first = try fixture.run(["export"])
        #expect(first.status == 0)
        let file = try fixture.write(first.standardOutput, named: "export.json")
        let copy = try ToolFixture(empty: ())
        let imported = try copy.run(["import", file, "--include-settings"])
        #expect(imported.status == 0, "\(imported.standardError)")
        #expect(imported.lines.count == 4)
        #expect(imported.lines.last == "entries: 7 created, 0 updated, 0 unchanged, 0 skipped (deleted here)")
        let second = try copy.run(["export"])
        #expect(try comparable(second.standardOutput) == comparable(first.standardOutput))
        let written = fixture.folder.appending(path: "out.json")
        #expect(try fixture.run(["export", "-o", written.path]).standardOutput.isEmpty)
        #expect(try comparable(String(decoding: Data(contentsOf: written), as: UTF8.self)) == comparable(first.standardOutput))
    }

    @Test("AUTO-25 importing the same file twice reports everything unchanged, appends no outbox row, and posts nothing")
    func importTwice() throws {
        let fixture = try ToolFixture()
        let file = try fixture.write(fixture.run(["export"]).standardOutput, named: "export.json")
        let outbox = try fixture.count("SELECT COUNT(*) FROM outbox")
        let posts = ChangeSignalCounter()
        let result = try fixture.run(["import", file, "--json"])
        #expect(result.status == 0)
        for kind in ["clients", "areas", "projects", "entries"] {
            let counts = result.json[kind] as? [String: Int]
            #expect(counts?["created"] == 0 && counts?["updated"] == 0 && counts?["skipped"] == 0, "\(kind)")
        }
        #expect((result.json["entries"] as? [String: Int])?["unchanged"] == 7)
        #expect(try fixture.count("SELECT COUNT(*) FROM outbox") == outbox)
        #expect(posts.count() == 0)
    }

    @Test("AUTO-26 a record id that is a tombstone here is skipped; a record with deletedAt keeps the live record")
    func importTombstones() throws {
        let fixture = try ToolFixture()
        let exported = try fixture.run(["export"]).standardOutput
        #expect(try fixture.run(["entry", "delete", ToolFixture.entryID(3), "--yes"]).status == 0)
        var document = try #require(JSONSerialization.jsonObject(with: Data(exported.utf8)) as? [String: Any])
        var entries = try #require(document["entries"] as? [[String: Any]])
        // Entry 1 arrives deleted; the store's live copy stays.
        if let index = entries.firstIndex(where: { $0["id"] as? String == ToolFixture.entryID(1) }) {
            entries[index]["deletedAt"] = "2026-10-29T08:00:00Z"
        }
        document["entries"] = entries
        let file = fixture.folder.appending(path: "tombstones.json")
        try JSONSerialization.data(withJSONObject: document).write(to: file)
        let result = try fixture.run(["import", file.path, "--json"])
        #expect(result.status == 0, "\(result.standardError)")
        #expect((result.json["entries"] as? [String: Int])?["skipped"] == 1)
        #expect(try fixture.run(["entry", "show", ToolFixture.entryID(3)]).status == 3)
        #expect(try fixture.run(["entry", "show", ToolFixture.entryID(1)]).status == 0)
    }

    @Test("AUTO-27 an unknown areaID or a new project colliding with a name in its client exits 7 and writes nothing")
    func importValidation() throws {
        let fixture = try ToolFixture()
        let outbox = try fixture.count("SELECT COUNT(*) FROM outbox")
        let base = ToolFixture.document(running: false)
        var unknownArea = base
        let lost = ToolFixture.project("b1000000-0000-4000-8000-0000000000aa", area: "a1000000-0000-4000-8000-0000000000ff", "Lost")
        unknownArea["projects"] = [lost]
        var collision = base
        collision["projects"] = (base["projects"] as? [[String: Any]] ?? [])
            + [ToolFixture.project("b1000000-0000-4000-8000-0000000000bb", area: ToolFixture.research, "noise paper")]
        for (name, document) in [("unknown", unknownArea), ("collision", collision)] {
            let file = fixture.folder.appending(path: "\(name).json")
            try JSONSerialization.data(withJSONObject: document).write(to: file)
            let result = try fixture.run(["import", file.path])
            #expect(result.status == 7, "\(name): \(result.standardError)")
            #expect(result.standardError.hasPrefix("error: "))
            #expect(result.standardOutput.isEmpty)
        }
        #expect(try fixture.run(["import", fixture.write("{not json", named: "bad.json")]).status == 7)
        #expect(try fixture.count("SELECT COUNT(*) FROM outbox") == outbox)
        #expect(try fixture.count("SELECT COUNT(*) FROM project") == 6)
    }

    @Test("AUTO-28 import --dry-run prints the real import's summary and leaves the store's modification time unchanged")
    func importDryRun() throws {
        let fixture = try ToolFixture()
        let other = try ToolFixture(empty: ())
        let file = try fixture.write(fixture.run(["export"]).standardOutput, named: "export.json")
        #expect(try other.run(["client", "create", "Someone"]).status == 0)
        let modified = other.modificationDate
        let outbox = try other.count("SELECT COUNT(*) FROM outbox")
        let dry = try other.run(["import", file, "--dry-run"])
        #expect(dry.status == 0)
        #expect(other.modificationDate == modified)
        #expect(try other.count("SELECT COUNT(*) FROM outbox") == outbox)
        #expect(try other.count("SELECT COUNT(*) FROM client") == 1)
        let real = try other.run(["import", file])
        #expect(real.standardOutput == dry.standardOutput)
    }

    @Test("AUTO-29 export with a range or --what but without --format csv exits 2")
    func exportUsage() throws {
        let fixture = try ToolFixture()
        #expect(try fixture.run(["export", "--from", "2026-10-01"]).status == 2)
        #expect(try fixture.run(["export", "--what", "entries"]).status == 2)
        #expect(try fixture.run(["export", "--format", "csv", "--what", "all"]).status == 2)
        #expect(try fixture.run(["export", "--format", "xml"]).status == 2)
    }

    @Test("AUTO-30 export --format csv --what entries writes the Entries CSV with LF, RFC 4180 quoting, and the running entry")
    func exportEntriesCSV() throws {
        let fixture = try ToolFixture()
        let result = try fixture.run(["export", "--format", "csv", "--what", "entries"])
        #expect(result.status == 0)
        let text = result.standardOutput
        #expect(!text.contains("\r"))
        #expect(text.hasPrefix("start,stop,seconds,client,area,project,task,running\n"))
        #expect(text
            .contains(
                "2026-10-29T08:00:00+01:00,2026-10-29T09:00:00+01:00,3600,University,Teaching,Grading,"
                    + "\"Grade \"\"quiz\"\", part 2\",false\n"
            ))
        #expect(text.contains("2026-10-29T09:29:48+01:00,,1812,University,Research,Noise paper,Review,true\n"))
        #expect(text.contains("2026-10-20T09:00:00+02:00,2026-10-20T11:00:00+02:00,7200,"))
        let ranged = try fixture.run(["export", "--format", "csv", "--day", "2026-10-23"])
        #expect(ranged.lines.count == 2)
        let folder = fixture.folder.appending(path: "csv")
        #expect(try fixture.run(["export", "--format", "csv", "--what", "all", "-o", folder.path]).status == 0)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(files == ["areas.csv", "clients.csv", "entries.csv", "projects.csv"])
        let clients = try String(contentsOf: folder.appending(path: "clients.csv"), encoding: .utf8)
        #expect(clients.hasPrefix("id,name\n"))
        let areas = try String(contentsOf: folder.appending(path: "areas.csv"), encoding: .utf8)
        #expect(areas.hasPrefix("id,name,color,retired,client,client_id\n"))
    }

    @Test("AUTO-35 a store whose schema version is one higher exits 5 naming both versions")
    func newerSchema() throws {
        let fixture = try ToolFixture()
        var database: OpaquePointer?
        #expect(sqlite3_open_v2(fixture.store.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
        #expect(sqlite3_exec(database, "UPDATE meta SET value = '3' WHERE key = 'schema_version'", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(database)
        for arguments in [["status"], ["start", "X"]] {
            let result = try fixture.run(arguments)
            #expect(result.status == 5)
            #expect(result.standardError.contains("version 3"))
            #expect(result.standardError.contains("version 2"))
        }
    }

    @Test("AUTO-37 the zsh completion script contains every subcommand")
    func completions() throws {
        let result = try ToolProcess.run("timetracking", ["--generate-completion-script", "zsh"])
        #expect(result.status == 0)
        let subcommands = [
            "status", "start", "stop", "continue", "entries", "entry", "show", "create", "edit", "delete", "report", "projects",
            "clients", "areas", "project", "archive", "unarchive", "rename", "move", "area", "set-color", "client", "check",
            "import", "export",
        ]
        for name in subcommands {
            #expect(result.standardOutput.contains("'\(name):") || result.standardOutput.contains("\(name)"), "\(name)")
            #expect(result.standardOutput.contains(name), "\(name)")
        }
    }

    @Test("--version prints the tool and schema versions; global options work before the subcommand")
    func versionAndOrder() throws {
        let version = try ToolProcess.run("timetracking", ["--version"])
        #expect(version.status == 0)
        #expect(version.standardOutput.wholeMatch(of: /\d+\.\d+ \(\d+\), schema \d+\n/) != nil)
        let fixture = try ToolFixture()
        let before = try fixture.run(["--json", "--store", fixture.store.path, "status"])
        #expect(before.json["pendingChanges"] != nil)
        let quiet = try fixture.run(["-q", "stop"])
        #expect(quiet.status == 0)
        #expect(quiet.standardOutput.isEmpty)
        let path = try fixture.run(["--store-path"])
        #expect(path.standardOutput == fixture.store.path + "\n")
        let option = try fixture.run(["--store", "/tmp/other.sqlite", "--store-path"])
        #expect(option.standardOutput == "/tmp/other.sqlite\n")
    }

    @Test("ARCH-19 the Debug tool resolves the store in the Debug group container, never the Release one")
    func debugStorePath() throws {
        let result = try ToolProcess.run("timetracking", ["--store-path"], removing: ["TIMETRACKING_STORE"])
        #expect(result.status == 0, "\(result.standardError)")
        let path = result.standardOutput.trimmingCharacters(in: .newlines)
        let appID = ToolProcess.appID
        #expect(appID.hasSuffix(".debug"))
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(path.hasPrefix(home + "/Library/Group Containers/"))
        #expect(path.hasSuffix(".\(appID)/Library/Application Support/TimeTracking/store.sqlite"))
        let release = String(appID.dropLast(".debug".count))
        #expect(!path.contains(".\(release)/"))
    }
}
