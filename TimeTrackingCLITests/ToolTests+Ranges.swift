// The timetracking tool as a subprocess: instant bounds, dash-led date
// values, report health time, the strict check, and `tomorrow`
// (spec_automation.md §3.2, §3.7, §4.2, §9 items 41 to 45).

import Foundation
import Testing

extension ToolTests {
    @Test("AUTO-41 entries --from/--to with a time lists the entries starting in that instant range and echoes the instants")
    func instantRange() throws {
        let fixture = try ToolFixture()
        let result = try fixture.run(["entries", "--from", "2026-10-28T09:30", "--to", "2026-10-29T09:00", "--json"])
        #expect(result.status == 0, "\(result.standardError)")
        let ids = (result.json["entries"] as? [[String: Any]])?.compactMap { $0["id"] as? String }
        #expect(ids == [ToolFixture.entryID(5)])
        #expect(result.json["from"] as? String == "2026-10-28T09:30:00+01:00")
        #expect(result.json["to"] as? String == "2026-10-29T09:00:00+01:00")
        let open = try fixture.run(["entries", "--from", "2026-10-29T09:00", "--json"])
        #expect((open.json["entries"] as? [[String: Any]])?.compactMap { $0["id"] as? String } == [ToolFixture.runningEntry])
        #expect(open.json["to"] as? String == "2026-10-30")
        let report = try fixture.run(["report", "--from", "2026-10-28T09:30", "--to", "2026-10-29T09:00", "--json"])
        #expect(report.json["total"] as? Int == 3600)
        #expect(report.json["from"] as? String == "2026-10-28T09:30:00+01:00")
        #expect(try fixture.run(["entries", "--from", "2026-10-29T09:00", "--to", "2026-10-29T08:00"]).status == 2)
    }

    @Test("AUTO-42 date options take a value starting with a dash: --from -3d, --day -1d, --week -1w")
    func dashValues() throws {
        let fixture = try ToolFixture()
        let from = try fixture.run(["entries", "--from", "-3d", "--json"])
        #expect(from.status == 0, "\(from.standardError)")
        #expect(from.json["from"] as? String == "2026-10-26")
        #expect(from.json["to"] as? String == "2026-10-30")
        #expect(try fixture.run(["entries", "--day", "-1d", "--json"]).json["from"] as? String == "2026-10-28")
        #expect(try fixture.run(["report", "--week", "-1w", "--json"]).json["from"] as? String == "2026-10-19")
        #expect(try fixture.run(["entries", "--from", "-2w", "--to", "-1w", "--json"]).json["to"] as? String == "2026-10-19")
    }

    @Test("AUTO-43 report counts mapped sleep only with --health")
    func reportHealth() throws {
        let fixture = try ToolFixture()
        // Sleep from 2026-10-27T23:00 to 2026-10-28T07:00 local (UTC+1),
        // shown and mapped to Personal.
        let start = try #require(ISO8601DateFormatter().date(from: "2026-10-27T22:00:00Z")).timeIntervalSince1970
        try fixture.execute("""
        INSERT INTO health_period (id, kind, start, "end", created_at, modified_at)
          VALUES ('f2000000-0000-4000-8000-000000000001', 'sleep', \(Int(start)), \(Int(start) + 8 * 3600), 0, 0);
        INSERT OR REPLACE INTO setting (key, value, modified_at) VALUES ('calendar.showSleep', 'true', 0);
        INSERT OR REPLACE INTO setting (key, value, modified_at)
          VALUES ('calendar.sleepAreaID', '"\(ToolFixture.personalGeneral)"', 0);
        """)
        let plain = try fixture.run(["report", "--day", "2026-10-28", "--group-by", "project", "--json"])
        #expect(plain.json["total"] as? Int == 3600)
        let health = try fixture.run(["report", "--day", "2026-10-28", "--group-by", "project", "--health", "--json"])
        #expect(health.status == 0, "\(health.standardError)")
        #expect(health.json["total"] as? Int == 3600 + 7 * 3600)
        let projects = (health.json["rows"] as? [[String: Any]])?.compactMap { $0["project"] as? String }
        #expect(projects?.contains("Sleep") == true)
    }

    @Test("AUTO-44 check --strict reports an active project of a listed area that the file omits, and --fix leaves it")
    func checkStrict() throws {
        let fixture = try ToolFixture()
        let text = ToolCheckTests.matching.replacingOccurrences(of: "[\"Admin\", { name = \"Grading\" }]", with: "[\"Admin\"]")
        let file = try fixture.write(text, named: "strict.toml")
        let plain = try fixture.run(["check", file])
        #expect(plain.status == 0)
        #expect(plain.standardOutput.isEmpty)
        let strict = try fixture.run(["check", file, "--strict"])
        #expect(strict.status == 6)
        #expect(strict.lines == ["unlisted project: University / Teaching / Grading"])
        let json = try fixture.run(["check", file, "--strict", "--json"])
        let item = (json.json["inconsistencies"] as? [[String: Any]])?.first
        #expect(item?["kind"] as? String == "unlisted-project")
        #expect(item?["rule"] as? Int == 7)
        #expect(item?["project"] as? String == "Grading")
        let fixed = try fixture.run(["check", file, "--strict", "--fix"])
        #expect(fixed.status == 6)
        #expect(fixed.lines == ["unlisted project: University / Teaching / Grading"])
        #expect(try fixture.count("SELECT COUNT(*) FROM project WHERE name = 'Grading' AND archived = 0") == 1)
        #expect(try fixture.run(["check", fixture.write(ToolCheckTests.matching, named: "m.toml"), "--strict"]).status == 0)
    }

    @Test("AUTO-45 tomorrow is a date word: --from today --to tomorrow is today")
    func tomorrowWord() throws {
        let fixture = try ToolFixture()
        let result = try fixture.run(["entries", "--from", "today", "--to", "tomorrow", "--json"])
        #expect(result.status == 0, "\(result.standardError)")
        #expect(result.json["to"] as? String == "2026-10-30")
        #expect((result.json["entries"] as? [Any])?.count == 2)
    }
}
