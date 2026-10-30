// The timetracking tool as a subprocess: report and the structure commands
// (spec_automation.md §3.7 to §3.9, §9 items 12 to 18, 31).

import Foundation
import Testing

extension ToolTests {
    @Test("AUTO-12 report --week 2026-W43 by day and project has the fixture's rows, seven periods, and consistent totals")
    func reportByDay() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        let result = try fixture.run(["report", "--week", "2026-W43", "--granularity", "day", "--group-by", "project", "--json"])
        #expect(result.status == 0, "\(result.standardError)")
        #expect(result.json["groupBy"] as? [String] == ["project"])
        let rows = try #require(result.json["rows"] as? [[String: Any]])
        let summary = rows.map { "\($0["period"] ?? "") \($0["project"] ?? "") \($0["duration"] ?? "") \($0["entries"] ?? "")" }
        #expect(summary == ["2026-10-20 Noise paper 7200 1", "2026-10-21 Admin 5400 1", "2026-10-23 <null> 1800 1"])
        #expect(rows.allSatisfy { Set($0.keys) == ["period", "project", "duration", "entries"] })
        let periods = try #require(result.json["periods"] as? [[String: Any]])
        #expect(periods.count == 7)
        let total = result.json["total"] as? Int
        #expect(total == periods.compactMap { $0["duration"] as? Int }.reduce(0, +))
        #expect(total == rows.compactMap { $0["duration"] as? Int }.reduce(0, +))
        #expect(!rows.contains { $0["duration"] as? Int == 0 })
        let table = try fixture.run(["report", "--week", "2026-W43", "--granularity", "day", "--group-by", "project", "--hours"])
        #expect(table.standardOutput.contains("2.00"))
        #expect(try fixture.run(["report", "--group-by", "client,bogus"]).status == 2)
    }

    @Test("AUTO-13 report --week 2026-W44 by day lists 2026-10-30 to 2026-11-01 with duration 0")
    func reportFutureDays() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        let result = try fixture.run(["report", "--week", "2026-W44", "--granularity", "day", "--json"])
        let periods = try #require(result.json["periods"] as? [[String: Any]])
        #expect(periods.compactMap { $0["period"] as? String } == (26 ... 31).map { "2026-10-\($0)" } + ["2026-11-01"])
        for period in periods.suffix(3) {
            #expect(period["duration"] as? Int == 0)
        }
        // The running entry counts up to now.
        #expect(periods[3]["duration"] as? Int == 3600 + 1812)
    }

    @Test("AUTO-31 report --csv by client, area, project writes the Breakdown CSV header and rows")
    func reportCSV() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        let result = try fixture.run([
            "report",
            "--week",
            "2026-W43",
            "--csv",
            "--granularity",
            "total",
            "--group-by",
            "client,area,project",
        ])
        #expect(result.status == 0)
        #expect(result.lines.first == "client,area,project,seconds,duration,share,entries")
        #expect(result.lines.contains("University,Research,Noise paper,7200,2:00:00,50.0,1"))
        #expect(result.lines.contains(",,,1800,0:30:00,12.5,1"))
        let daily = try fixture.run(["report", "--week", "2026-W43", "--csv", "--granularity", "day", "--group-by", "project"])
        #expect(daily.lines.first == "period,project,seconds,duration,share,entries")
    }

    @Test("AUTO-14 projects lists active by default, archived with --archived, both with --all; clients are sorted by name")
    func projectListings() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        func names(_ arguments: [String]) throws -> [String] {
            let projects = try fixture.run(arguments + ["--json"]).json["projects"] as? [[String: Any]] ?? []
            return projects.compactMap { $0["name"] as? String }
        }
        let active = try names(["projects"])
        #expect(Set(active) == ["Noise paper", "Admin", "Grading", "Émile notes"])
        #expect(active.count == 5)
        #expect(try names(["projects", "--archived"]) == ["Old paper"])
        #expect(try names(["projects", "--all"]).count == 6)
        #expect(try names(["projects", "--client", "University"]) == ["Noise paper", "Admin", "Grading"])
        let project = try #require((fixture.run(["projects", "--json"]).json["projects"] as? [[String: Any]])?.first)
        #expect(Set(project.keys) == ["id", "name", "state", "area", "client", "createdAt", "archivedAt", "lastEntryAt"])
        let clients = try fixture.run(["clients", "--json"]).json["clients"] as? [[String: Any]] ?? []
        #expect(clients.compactMap { $0["name"] as? String } == ["Personal", "Side business", "University"])
        #expect(clients.last?["areaCount"] as? Int == 3)
        let areas = try fixture.run(["areas", "--client", "University", "--json"]).json["areas"] as? [[String: Any]] ?? []
        #expect(areas.compactMap { $0["name"] as? String } == ["University", "Research", "Teaching"])
        #expect(try fixture.run(["projects", "--csv"]).lines
            .first == "id,name,state,client,area,color,created_at,archived_at,area_id,client_id")
    }

    @Test("AUTO-15 project create exits 4 for a name taken in the client, active or archived, and succeeds in another client")
    func projectCreate() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        #expect(try fixture.run(["project", "create", "Grading", "--area", "Research"]).status == 4)
        #expect(try fixture.run(["project", "create", "old PAPER", "--area", "Research"]).status == 4)
        let created = try fixture.run(["project", "create", "Émile notes", "--area", "Research", "--json"])
        #expect(created.status == 0, "\(created.standardError)")
        #expect((created.json["client"] as? [String: Any])?["name"] as? String == "University")
        #expect(try fixture.run(["project", "create", "X", "--area", "Nowhere"]).status == 3)
    }

    @Test("AUTO-16 project archive, unarchive, rename, and move change only their fields and keep the entry ids")
    func projectWrites() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        func entryIDs() throws -> [String] {
            let entries = try fixture.run(["entries", "--from", "2026-10-01", "--to", "2026-11-01", "--project", "Noise paper", "--json"])
            return (entries.json["entries"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        }
        let ids = try entryIDs()
        #expect(ids.count == 3)
        let archived = try fixture.run(["project", "archive", "Noise paper", "--json"])
        #expect(archived.json["state"] as? String == "archived")
        #expect(try fixture.run(["project", "archive", "Noise paper"]).status == 4)
        let restored = try fixture.run(["project", "unarchive", "Noise paper", "--json"])
        #expect(restored.json["state"] as? String == "active")
        #expect(try fixture.run(["project", "unarchive", "Noise paper"]).status == 4)
        let moved = try fixture.run(["project", "move", "Noise paper", "--area", "Garden", "--client", "Personal", "--json"])
        #expect((moved.json["area"] as? [String: Any])?["name"] as? String == "Garden")
        #expect(moved.json["name"] as? String == "Noise paper")
        let renamed = try fixture.run(["project", "rename", "Noise paper", "Signal paper", "--json"])
        #expect(renamed.json["name"] as? String == "Signal paper")
        #expect((renamed.json["area"] as? [String: Any])?["name"] as? String == "Garden")
        #expect(renamed.json["id"] as? String == ToolFixture.noisePaper)
        let entries = try fixture.run(["entries", "--from", "2026-10-01", "--to", "2026-11-01", "--project", "Signal paper", "--json"])
        #expect((entries.json["entries"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String } == ids)
        #expect(try fixture.run(["project", "rename", "Grading", "Admin"]).status == 4)
    }

    @Test("AUTO-17 area set-color shows the upper-case color for its projects; a named or short color exits 2")
    func areaColor() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        #expect(try fixture.run(["area", "set-color", "Research", "--color", "#3d5a80"]).status == 0)
        let projects = try fixture.run(["projects", "--json"]).json["projects"] as? [[String: Any]] ?? []
        let noise = projects.first { $0["name"] as? String == "Noise paper" }
        #expect((noise?["area"] as? [String: Any])?["color"] as? String == "#3D5A80")
        #expect(try fixture.run(["area", "set-color", "Research", "--color", "teal"]).status == 2)
        #expect(try fixture.run(["area", "set-color", "Research", "--color", "#3d5a8"]).status == 2)
        #expect(try fixture.run(["area", "create", "Lab", "--client", "University", "--color", "teal"]).status == 2)
    }

    @Test("AUTO-18 area create without --color uses the default color; renaming the general area exits 4")
    func areaCreateRename() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        let created = try fixture.run(["area", "create", "Health", "--client", "Personal", "--json"])
        #expect(created.status == 0, "\(created.standardError)")
        // The library's default (spec_data_and_sync.md §1.2): the fixture's
        // area hues are 5, 39, 173, 181, 208, 208; the largest circular gap
        // runs from 208 to 365, so hue 208 + 157 / 2 = 286 at saturation
        // 0.65 and brightness 0.80, which is #AD47CC.
        #expect(created.json["color"] as? String == "#AD47CC")
        #expect(try fixture.run(["area", "rename", "Personal", "Home", "--client", "Personal"]).status == 4)
        #expect(try fixture.run(["area", "create", "garden", "--client", "Personal"]).status == 4)
        let renamed = try fixture.run(["area", "rename", "Garden", "Yard", "--client", "Personal", "--json"])
        #expect(renamed.json["name"] as? String == "Yard")
        let client = try fixture.run(["client", "create", "Nonprofit", "--color", "#112233", "--json"])
        #expect(client.json["areaCount"] as? Int == 1)
        #expect(try fixture.run(["client", "create", "nonprofit"]).status == 4)
        let renamedClient = try fixture.run(["client", "rename", "Nonprofit", "Charity", "--json"])
        #expect(renamedClient.json["name"] as? String == "Charity")
        #expect(try fixture.run(["areas", "--client", "Charity", "--json"]).standardOutput.contains("\"Charity\""))
    }
}
