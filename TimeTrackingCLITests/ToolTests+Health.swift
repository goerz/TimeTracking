// The timetracking tool as a subprocess: the health listing
// (spec_automation.md §3.8, §9 item 46).

import Foundation
import Testing

extension ToolTests {
    @Test("AUTO-46 health lists the periods starting in the range with activity, distance, and the last import; --kind filters")
    func healthListing() throws {
        let fixture = try ToolFixture()
        let parse = { (text: String) throws -> Int in
            try Int(#require(ISO8601DateFormatter().date(from: text)).timeIntervalSince1970)
        }
        // A run on 2026-10-28 at 17:00 local (UTC+1), a walk without a
        // distance right after it, and the night before.
        let run = try parse("2026-10-28T16:00:00Z")
        let night = try parse("2026-10-27T22:00:00Z")
        let imported = try #require(ISO8601DateFormatter().date(from: "2026-10-29T07:30:00Z")).timeIntervalSinceReferenceDate
        try fixture.execute("""
        INSERT INTO health_period (id, kind, start, "end", activity, distance, created_at, modified_at) VALUES
          ('f2000000-0000-4000-8000-000000000001', 'workout', \(run), \(run + 2700), 'running', 7012, 0, 0),
          ('f2000000-0000-4000-8000-000000000002', 'workout', \(run + 2700), \(run + 3600), 'walking', NULL, 0, 0),
          ('f2000000-0000-4000-8000-000000000003', 'sleep', \(night), \(night + 8 * 3600), NULL, NULL, 0, 0);
        INSERT OR REPLACE INTO setting (key, value, modified_at)
          VALUES ('calendar.healthImport', '{"device":"Test iPhone","date":\(imported),"kinds":["sleep","workout"]}', 0);
        """)
        let result = try fixture.run(["health", "--from", "2026-10-28", "--to", "2026-10-29", "--json"])
        #expect(result.status == 0, "\(result.standardError)")
        #expect(result.json["from"] as? String == "2026-10-28")
        let periods = try #require(result.json["periods"] as? [[String: Any]])
        #expect(periods.compactMap { $0["kind"] as? String } == ["workout", "workout"])
        #expect(periods.first?["activity"] as? String == "running")
        #expect(periods.first?["start"] as? String == "2026-10-28T17:00:00+01:00")
        #expect(periods.first?["end"] as? String == "2026-10-28T17:45:00+01:00")
        #expect(periods.first?["duration"] as? Int == 2700)
        #expect(periods.first?["distance"] as? Int == 7012)
        #expect(periods.last?["distance"] is NSNull)
        let keys: Set = ["id", "kind", "activity", "start", "end", "duration", "distance"]
        #expect(periods.allSatisfy { Set($0.keys) == keys })
        let last = try #require(result.json["lastImport"] as? [String: Any])
        #expect(last["device"] as? String == "Test iPhone")
        #expect(last["at"] as? String == "2026-10-29T08:30:00+01:00")
        #expect(last["kinds"] as? [String] == ["sleep", "workout"])
        let sleep = try fixture.run(["health", "--from", "-2d", "--kind", "sleep", "--json"])
        #expect((sleep.json["periods"] as? [[String: Any]])?.compactMap { $0["kind"] as? String } == ["sleep"])
        let instant = try fixture.run(["health", "--from", "2026-10-28T17:30", "--to", "2026-10-29", "--json"])
        #expect((instant.json["periods"] as? [[String: Any]])?.compactMap { $0["activity"] as? String } == ["walking"])
        let csv = try fixture.run(["health", "--from", "2026-10-28", "--to", "2026-10-29", "--csv"])
        #expect(csv.lines.first == "id,kind,activity,start,end,seconds,distance")
        #expect(csv.lines.dropFirst().first?.hasSuffix(",running,2026-10-28T17:00:00+01:00,2026-10-28T17:45:00+01:00,2700,7012") == true)
        let table = try fixture.run(["health", "--from", "2026-10-28", "--to", "2026-10-29"])
        #expect(table.standardOutput.contains("7.01 km"))
        #expect(table.standardOutput.contains("Last import: 2026-10-29 08:30 on Test iPhone (sleep, workout)"))
        #expect(try fixture.run(["health", "--kind", "nap"]).status == 2)
        let empty = try ToolFixture()
        let none = try empty.run(["health", "--json"])
        #expect(none.json["lastImport"] is NSNull)
        #expect((none.json["periods"] as? [Any])?.isEmpty == true)
    }
}
