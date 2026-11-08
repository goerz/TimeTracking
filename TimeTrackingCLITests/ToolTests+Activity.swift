// The timetracking tool as a subprocess: the block log, the tracker's
// status, and time blocks (automation.md §3.12 to §3.14, §9 items 50 to 54).

import Foundation
import Testing

extension ToolTests {
    /// A block log beside the fixture store: on 2026-10-28 a block at 09:00
    /// (covered by entry 4) and one at 02:30 on 10-29, before a 04:00 start
    /// of day; on 2026-10-29 a foreground block from 08:30 to 09:40 and a
    /// background block from 09:45; 10-27 only as an iCloud placeholder;
    /// `current.json` with an open block and the last tick `tickAge`
    /// seconds before "now" (10:00).
    struct ActivityFixture {
        let tool: ToolFixture
        var folder: URL {
            tool.folder.appending(path: "Activity")
        }

        init(tickAge: Int? = 30) throws {
            self.tool = try ToolFixture()
            let blocks = folder.appending(path: "blocks")
            try FileManager.default.createDirectory(at: blocks, withIntermediateDirectories: true)
            let header = #"{"format":1,"keys":{"s":"start"}}"#
            let wezterm = #""a":"WezTerm","i":"com.github.wez.wezterm""#
            try write(blocks.appending(path: "2026-10-28.jsonl"), [
                header,
                #"{"s":"2026-10-28T09:00:00+01:00","e":"2026-10-28T09:30:00+01:00","r":"idle","f":[{"d":"Test Mac","t":1800,"#
                    + wezterm + #","ss":"paper:0.0","l":"~/Papers/Noise","c":"nvim notes.tex","ws":"~/Papers/Noise"}]}"#,
            ])
            try write(blocks.appending(path: "2026-10-29.jsonl"), [
                header,
                #"{"s":"2026-10-29T02:30:00+01:00","e":"2026-10-29T02:50:00+01:00","r":"locked","f":[{"d":"Test Mac","t":1200,"#
                    + wezterm + #","ws":"~/Code/MyApp"}]}"#,
                #"{"s":"2026-10-29T08:30:00+01:00","e":"2026-10-29T09:40:00+01:00","r":"idle","rc":120,"f":["#
                    + #"{"d":"Test Mac","t":3000,"# + wezterm
                    + #","w":"Research","ss":"refactor","l":"~/Code/MyApp","dc":["~/Code/MyApp/a.swift"],"#
                    + #""c":"nvim a.swift","ws":"~/Code/MyApp"},"#
                    + #"{"d":"Test iPhone","t":1000,"a":"Social","i":"screenTime","ws":"Social"}],"#
                    + #""b":[{"d":"Test Mac","t":900,"a":"Claude Code","i":"claude","ss":"refactor","ws":"~/Code/MyApp"}]}"#,
                #"{"s":"2026-10-29T09:45:00+01:00","e":"2026-10-29T09:55:00+01:00","r":"split","b":[{"d":"Test Mac","t":600,"#
                    + #""a":"tmux","i":"tmux","ss":"paper:build.0","c":"make test","ws":"~/Code/MyApp"}]}"#,
            ])
            try Data().write(to: blocks.appending(path: ".2026-10-27.jsonl.icloud"))
            if let tickAge {
                let tick = String(format: "2026-10-29T09:%02d:%02d+01:00", (3600 - tickAge) / 60 % 60, (3600 - tickAge) % 60)
                let state = #"{"format":1,"block":{"s":"2026-10-29T09:56:00+01:00","e":"2026-10-29T09:59:00+01:00","#
                    + #""f":[{"d":"Test Mac","t":180,"#
                    + wezterm + #","ws":"~/Code/Other"}]},"foreground":{"# + wezterm + #","ws":"~/Code/Other"},"#
                    + #""presence":{"state":"active","since":"2026-10-29T09:56:00+01:00","last_input":"2026-10-29T09:59:00+01:00"},"#
                    + #""health":{"last_tick":""# + tick + #"","version":"1.0 (7)","sources":["#
                    + #"{"id":"terminal","name":"Terminal tab","status":"active","reason":""},"#
                    + #"{"id":"knowledge","name":"App usage history","status":"off","reason":"Full Disk Access is off"}]}}"#
                try write(folder.appending(path: "current.json"), [state])
            }
        }

        private func write(_ url: URL, _ lines: [String]) throws {
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        }

        func run(_ arguments: [String]) throws -> ToolResult {
            try tool.run(arguments, environment: ["TIMETRACKING_ACTIVITY": folder.path])
        }
    }

    @Test(
        "AUTO-50 activity lists the range's blocks with totals and long-key items; --open adds the open block; files report gaps"
    )
    func activityListing() throws {
        let fixture = try ActivityFixture()
        let result = try fixture.run(["activity", "--json"])
        #expect(result.status == 0, "\(result.standardError)")
        let blocks = try #require(result.json["blocks"] as? [[String: Any]])
        let starts = ["2026-10-29T02:30:00+01:00", "2026-10-29T08:30:00+01:00", "2026-10-29T09:45:00+01:00"]
        #expect(blocks.compactMap { $0["start"] as? String } == starts)
        #expect(blocks.compactMap { $0["kind"] as? String } == ["foreground", "foreground", "background"])
        let block = blocks[1]
        #expect(block["end"] as? String == "2026-10-29T09:40:00+01:00")
        #expect(block["endReason"] as? String == "idle")
        #expect(block["open"] as? Bool == false)
        #expect(block["seconds"] as? Int == 4200)
        #expect(block["activeSeconds"] as? Int == 4000)
        #expect(block["reconstructedSeconds"] as? Int == 120)
        #expect(block["dominantWorkspace"] as? String == "~/Code/MyApp")
        let devices = try #require(block["devices"] as? [[String: Any]])
        #expect(devices.compactMap { $0["device"] as? String } == ["Test Mac", "Test iPhone"])
        let workspaces = try #require(block["workspaces"] as? [[String: Any]])
        #expect(workspaces.first?["name"] as? String == "MyApp")
        #expect(workspaces.first?["seconds"] as? Int == 3000)
        #expect(workspaces.first?["share"] as? Double == 0.75)
        let item = try #require((block["foreground"] as? [[String: Any]])?.first)
        let keys: Set = ["device", "seconds", "app", "appID", "window", "host", "session", "location", "documents", "command", "workspace"]
        #expect(Set(item.keys) == keys)
        #expect(item["session"] as? String == "refactor")
        #expect(item["documents"] as? [String] == ["~/Code/MyApp/a.swift"])
        #expect(item["host"] is NSNull)
        #expect((block["background"] as? [[String: Any]])?.first?["app"] as? String == "Claude Code")
        #expect(blocks[2]["coveredSeconds"] is NSNull)
        #expect((blocks[2]["workspaces"] as? [[String: Any]])?.first?["seconds"] as? Int == 600)

        let open = try fixture.run(["activity", "--open", "--kind", "foreground", "--json"])
        let openBlocks = try #require(open.json["blocks"] as? [[String: Any]])
        #expect(openBlocks.last?["open"] as? Bool == true)
        #expect(openBlocks.last?["start"] as? String == "2026-10-29T09:56:00+01:00")
        #expect(openBlocks.last?["endReason"] is NSNull)
        #expect(openBlocks.allSatisfy { $0["kind"] as? String == "foreground" })

        let range = try fixture.run(["activity", "--from", "2026-10-26", "--to", "2026-10-30", "--json"])
        let files = try #require(range.json["files"] as? [[String: Any]])
        #expect(files.compactMap { $0["status"] as? String } == ["missing", "notDownloaded", "present", "present"])
        let table = try fixture.run(["activity", "--from", "2026-10-26", "--to", "2026-10-30"])
        #expect(table.standardOutput.contains("2026-10-27: the date file is not downloaded from iCloud Drive yet"))
        #expect(try fixture.run(["activity", "--kind", "both"]).status == 2)
        #expect(try fixture.run(["activity", "--csv"]).status == 2)

        // A start of day at 04:00 shows the 02:30 block on October 28, whole.
        try fixture.tool.execute("INSERT OR REPLACE INTO setting (key, value, modified_at) VALUES ('day.startHour', '4', 0);")
        let shifted = try fixture.run(["activity", "--day", "2026-10-28", "--json"])
        let shiftedBlocks = try #require(shifted.json["blocks"] as? [[String: Any]])
        #expect(shiftedBlocks.compactMap { $0["start"] as? String } == ["2026-10-28T09:00:00+01:00", "2026-10-29T02:30:00+01:00"])
        #expect(shiftedBlocks.compactMap { $0["day"] as? String } == ["2026-10-28", "2026-10-28"])
    }

    @Test("AUTO-51 a foreground block lists its covered seconds and uncovered stretches; --untracked --min keeps the long ones")
    func activityCoverage() throws {
        let fixture = try ActivityFixture()
        let result = try fixture.run(["activity", "--json"])
        let blocks = try #require(result.json["blocks"] as? [[String: Any]])
        // Entry 5 runs 08:00 to 09:00, the running entry from 09:29:48.
        let block = blocks[1]
        #expect(block["coveredSeconds"] as? Int == 2412)
        let uncovered = try #require(block["uncovered"] as? [[String: Any]])
        #expect(uncovered.count == 1)
        #expect(uncovered.first?["start"] as? String == "2026-10-29T09:00:00+01:00")
        #expect(uncovered.first?["end"] as? String == "2026-10-29T09:29:48+01:00")
        #expect(uncovered.first?["seconds"] as? Int == 1788)
        #expect(blocks[0]["coveredSeconds"] as? Int == 0)

        let long = try fixture.run(["activity", "--untracked", "--min", "29", "--json"])
        let kept = try #require(long.json["blocks"] as? [[String: Any]])
        #expect(kept.compactMap { $0["start"] as? String } == ["2026-10-29T08:30:00+01:00"])
        let short = try fixture.run(["activity", "--untracked", "--min", "30", "--json"])
        #expect((short.json["blocks"] as? [Any])?.isEmpty == true)
        let defaults = try fixture.run(["activity", "--untracked", "--json"])
        #expect((defaults.json["blocks"] as? [[String: Any]])?.count == 2)
        #expect(try fixture.run(["activity", "--min", "5"]).status == 2)
    }

    @Test("AUTO-52 tracker reports liveness by the last tick, presence, sources, whether this Mac records, and the newest date file")
    func trackerStatus() throws {
        let fixture = try ActivityFixture(tickAge: 30)
        let result = try fixture.run(["tracker", "--json"])
        #expect(result.status == 0, "\(result.standardError)")
        #expect(result.json["status"] as? String == "running")
        #expect(result.json["lastTick"] as? String == "2026-10-29T09:59:30+01:00")
        #expect(result.json["version"] as? String == "1.0 (7)")
        #expect((result.json["presence"] as? [String: Any])?["state"] as? String == "active")
        #expect((result.json["foreground"] as? [String: Any])?["workspace"] as? String == "~/Code/Other")
        let sources = try #require(result.json["sources"] as? [[String: Any]])
        #expect(sources.last?["status"] as? String == "off")
        #expect(sources.last?["reason"] as? String == "Full Disk Access is off")
        #expect(sources.first?["reason"] is NSNull)
        #expect((result.json["newestDateFile"] as? [String: Any])?["date"] as? String == "2026-10-29")
        let recording = try #require(result.json["recording"] as? [String: Any])
        #expect(recording["thisMacRecords"] is NSNull)
        let thisMac = try #require(recording["thisMac"] as? String)

        let owner = fixture.folder.appending(path: "blocks/owner")
        try Data("other-mac\n".utf8).write(to: owner)
        #expect(try (fixture.run(["tracker", "--json"]).json["recording"] as? [String: Any])?["thisMacRecords"] as? Bool == false)
        try Data((thisMac + "\n").utf8).write(to: owner)
        #expect(try (fixture.run(["tracker", "--json"]).json["recording"] as? [String: Any])?["thisMacRecords"] as? Bool == true)

        #expect(try ActivityFixture(tickAge: 100).run(["tracker", "--json"]).json["status"] as? String == "delayed")
        #expect(try ActivityFixture(tickAge: 130).run(["tracker", "--json"]).json["status"] as? String == "notRunning")
        let missing = try ActivityFixture(tickAge: nil).run(["tracker", "--json"])
        #expect(missing.status == 0)
        #expect(missing.json["status"] as? String == "notRunning")
        #expect(missing.json["lastTick"] is NSNull)
    }

    /// A calendar file for `TIMETRACKING_CALENDAR`: the iCloud account with
    /// "Time Blocks", a block linked by notes, one whose URL names no
    /// project, and an event of another calendar.
    static func calendarFile(_ fixture: ToolFixture, access: String = "fullAccess", title: String = "Time Blocks") throws -> String {
        let at = { (local: String) throws -> Double in
            try #require(ISO8601DateFormatter().date(from: local + "+01:00")).timeIntervalSince1970
        }
        let morning = try at("2026-10-29T09:00:00")
        let noon = try at("2026-10-29T12:00:00")
        let content: [String: Any] = [
            "access": access,
            "nextID": 10,
            "sources": [["id": "icloud", "title": "iCloud", "isICloud": true]],
            "calendars": [
                ["id": "cal-blocks", "title": title, "sourceID": "icloud"],
                ["id": "cal-home", "title": "Home", "sourceID": "icloud"],
            ],
            "events": [
                [
                    "id": "event-1|\(morning)", "calendarID": "cal-blocks", "title": "Paper", "start": morning, "end": morning + 3600,
                    "notes": "Project: noise PAPER\nOutline",
                ],
                [
                    "id": "event-2|\(noon)", "calendarID": "cal-blocks", "title": "Gone", "start": noon, "end": noon + 1800,
                    "url": "timetracking-debug://project/b1000000-0000-4000-8000-0000000000ff",
                ],
                ["id": "event-3|\(noon)", "calendarID": "cal-home", "title": "Lunch", "start": noon, "end": noon + 3600],
            ],
        ]
        let url = fixture.folder.appending(path: "calendar.json")
        try JSONSerialization.data(withJSONObject: content).write(to: url)
        return url.path
    }

    @Test("AUTO-53 block list resolves links as the app; create writes the project URL; edit and delete change one block; names exit 3")
    func timeBlocks() throws {
        let fixture = try ToolFixture()
        let calendar = try Self.calendarFile(fixture)
        let run = { (arguments: [String]) throws -> ToolResult in
            try fixture.run(arguments, environment: ["TIMETRACKING_CALENDAR": calendar])
        }
        let list = try run(["block", "list", "--json"])
        #expect(list.status == 0, "\(list.standardError)")
        #expect((list.json["calendar"] as? [String: Any])?["title"] as? String == "Time Blocks")
        let blocks = try #require(list.json["blocks"] as? [[String: Any]])
        #expect(blocks.compactMap { $0["title"] as? String } == ["Paper", "Gone"])
        #expect((blocks[0]["project"] as? [String: Any])?["id"] as? String == ToolFixture.noisePaper)
        #expect((blocks[0]["area"] as? [String: Any])?["name"] as? String == "Research")
        #expect((blocks[0]["client"] as? [String: Any])?["name"] as? String == "University")
        #expect(blocks[0]["unlinkedReason"] is NSNull)
        #expect(blocks[1]["project"] is NSNull)
        #expect(blocks[1]["unlinkedReason"] as? String == "The linked project no longer exists")

        let created = try run([
            "block", "create", "Write", "--start", "2026-10-29T13:00", "--end", "2026-10-29T14:30",
            "--project", "Noise paper", "--notes", "Section 2", "--json",
        ])
        #expect(created.status == 0, "\(created.standardError)")
        let record = try #require((created.json["blocks"] as? [[String: Any]])?.first)
        #expect(record["url"] as? String == "timetracking-debug://project/\(ToolFixture.noisePaper)")
        #expect(record["start"] as? String == "2026-10-29T13:00:00+01:00")
        #expect(record["duration"] as? Int == 5400)
        #expect(record["notes"] as? String == "Section 2")
        let id = try #require(record["id"] as? String)

        let hour = ["block", "create", "X", "--start", "2026-10-29T13:00", "--end", "2026-10-29T14:00"]
        #expect(try run(hour + ["--project", "Admin"]).status == 3)
        #expect(try run(hour + ["--project", "Nope"]).status == 3)
        #expect(try run(hour + ["--project", "Old paper"]).status == 4)
        #expect(try run(["block", "create", "X", "--start", "2026-10-29T14:00", "--end", "2026-10-29T13:00"]).status == 4)

        let edited = try run(["block", "edit", id, "--title", "Write more", "--no-project", "--start", "2026-10-29T13:30", "--json"])
        #expect(edited.status == 0, "\(edited.standardError)")
        let changed = try #require((edited.json["blocks"] as? [[String: Any]])?.first)
        #expect(changed["title"] as? String == "Write more")
        #expect(changed["url"] is NSNull)
        #expect(changed["project"] is NSNull)
        #expect(changed["end"] as? String == "2026-10-29T14:30:00+01:00")
        #expect(changed["notes"] as? String == "Section 2")
        let newID = try #require(changed["id"] as? String)
        #expect(try run(["block", "edit", newID, "--end", "2026-10-29T13:00"]).status == 4)
        #expect(try run(["block", "edit", "event-99|0"]).status == 3)

        let refused = try run(["block", "delete", newID])
        #expect(refused.status == 2)
        #expect(refused.standardOutput.isEmpty)
        #expect(refused.standardError.contains("Write more"))
        #expect(try (run(["block", "list", "--json"]).json["blocks"] as? [Any])?.count == 3)
        let deleted = try run(["block", "delete", newID, "--yes"])
        #expect(deleted.status == 0, "\(deleted.standardError)")
        #expect(try (run(["block", "list", "--json"]).json["blocks"] as? [Any])?.count == 2)
        let file = try String(contentsOf: URL(filePath: calendar), encoding: .utf8)
        #expect(file.contains("Lunch"))
    }

    @Test("AUTO-54 the block commands exit 5 without calendar access or without a time-block calendar")
    func timeBlocksUnavailable() throws {
        let fixture = try ToolFixture()
        let denied = try Self.calendarFile(fixture, access: "denied")
        let result = try fixture.run(["block", "list", "--json"], environment: ["TIMETRACKING_CALENDAR": denied])
        #expect(result.status == 5)
        #expect(result.standardOutput.isEmpty)
        let none = try Self.calendarFile(fixture, title: "Plans")
        let missing = try fixture.run(["block", "create", "X", "--start", "2026-10-29T13:00", "--end", "2026-10-29T14:00"], environment: [
            "TIMETRACKING_CALENDAR": none,
        ])
        #expect(missing.status == 5)
        #expect(missing.standardError.contains("No time-block calendar"))
    }
}
