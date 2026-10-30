// The timetracking tool as a subprocess: status, start, stop, continue,
// concurrency, notifications (spec_automation.md §3.5, §9 items 1 to 6, 32, 33).

import Darwin
import Foundation
import notify
import SQLite3
import Testing

/// Every tool suite runs serially: the tools post one shared Darwin
/// notification, which AUTO-33 counts.
@Suite(.serialized)
struct ToolTests {
    @Test("AUTO-1 status --json reports the running entry's duration and a null end, or running null; both exit 0")
    func statusJSON() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        let result = try fixture.run(["status", "--json"])
        #expect(result.status == 0)
        let running = try #require(result.json["running"] as? [String: Any])
        #expect(running["duration"] as? Int == 1812)
        #expect(running["end"] is NSNull)
        #expect(running["running"] as? Bool == true)
        #expect((running["project"] as? [String: Any])?["name"] as? String == "Noise paper")
        #expect((running["area"] as? [String: Any])?["color"] as? String == "#0A9396")
        #expect(running["start"] as? String == "2026-10-29T09:29:48+01:00")
        #expect((result.json["today"] as? [String: Any])?["date"] as? String == "2026-10-29")
        #expect(result.json["asOf"] as? String == "2026-10-29T10:00:00+01:00")

        let idle = try ToolFixture(running: false)
        defer { idle.remove() }
        let stopped = try idle.run(["--json", "status"])
        #expect(stopped.status == 0)
        #expect(stopped.json["running"] is NSNull)
        let text = try idle.run(["status"])
        #expect(text.standardOutput.hasPrefix("No entry running."))
    }

    @Test("AUTO-2 start while an entry runs stops it at the new start, names both, and leaves one running entry")
    func startStopsRunning() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        let result = try fixture.run(["start", "Task", "--project", "Noise paper"])
        #expect(result.status == 0, "\(result.standardError)")
        #expect(result.lines.count == 1)
        #expect(result.standardOutput.contains("Started \"Task\" on Noise paper at 10:00."))
        #expect(result.standardOutput.contains("Stopped \"Review\" on Noise paper"))
        #expect(try fixture.count("SELECT COUNT(*) FROM time_entry WHERE \"end\" IS NULL AND deleted_at IS NULL") == 1)
        let stopped = try fixture.run(["entry", "show", ToolFixture.runningEntry, "--json"])
        let entry = try #require((stopped.json["entries"] as? [[String: Any]])?.first)
        #expect(entry["end"] as? String == "2026-10-29T10:00:00+01:00")
    }

    @Test("AUTO-3 start never infers a project from an earlier entry with the same task")
    func startNeverInfers() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        let result = try fixture.run(["start", "Clarify noise model", "--json"])
        #expect(result.status == 0)
        #expect(result.json["project"] is NSNull)
        #expect(result.json["task"] as? String == "Clarify noise model")
    }

    @Test("AUTO-4 an archived project, a future --at, and stop with nothing running exit 4 and write nothing")
    func refusals() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        let outbox = try fixture.count("SELECT COUNT(*) FROM outbox")
        let archived = try fixture.run(["start", "--project", "Old paper"])
        #expect(archived.status == 4)
        #expect(archived.standardError == "error: Project \"Old paper\" is archived; unarchive it first.\n")
        #expect(archived.standardOutput.isEmpty)
        let future = try fixture.run(["start", "--at", "2026-10-29T10:05"])
        #expect(future.status == 4)
        let before = try fixture.run(["start", "--at", "2026-10-29T09:00"])
        #expect(before.status == 4)
        let overlap = try ToolFixture(running: false)
        defer { overlap.remove() }
        let overlapping = try overlap.run(["start", "--at", "2026-10-29T08:30"])
        #expect(overlapping.status == 4)
        #expect(overlapping.standardError.contains("--force"))
        #expect(try overlap.run(["stop"]).status == 4)
        #expect(try overlap.run(["stop"]).standardError == "error: No entry running.\n")
        #expect(try fixture.count("SELECT COUNT(*) FROM outbox") == outbox)
        #expect(try overlap.count("SELECT COUNT(*) FROM time_entry WHERE \"end\" IS NULL") == 0)
        #expect(try overlap.run(["start", "--at", "2026-10-29T08:30", "--force"]).status == 0)
    }

    @Test("AUTO-5 an ambiguous project exits 3 listing both; Client/Project resolves it; case and diacritics are folded")
    func projectNames() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        let ambiguous = try fixture.run(["start", "--project", "Admin"])
        #expect(ambiguous.status == 3)
        #expect(ambiguous.standardError.contains("University/Admin"))
        #expect(ambiguous.standardError.contains("Side business/Admin"))
        let json = try fixture.run(["start", "--project", "Admin", "--json"])
        let candidates = (json.errorJSON["error"] as? [String: Any])?["candidates"] as? [String]
        #expect(candidates == ["Side business/Admin", "University/Admin"])
        #expect(json.standardOutput.isEmpty)
        let qualified = try fixture.run(["start", "--project", "University/Admin", "--json"])
        #expect(qualified.status == 0)
        #expect((qualified.json["client"] as? [String: Any])?["name"] as? String == "University")
        let withClient = try fixture.run(["start", "--project", "Admin", "--client", "Side business", "--json"])
        #expect((withClient.json["client"] as? [String: Any])?["name"] as? String == "Side business")
        let folded = try fixture.run(["start", "--project", "noise PAPER", "--json"])
        #expect((folded.json["project"] as? [String: Any])?["name"] as? String == "Noise paper")
        let diacritic = try fixture.run(["start", "--project", "emile Notes", "--json"])
        #expect((diacritic.json["project"] as? [String: Any])?["name"] as? String == "Émile notes")
    }

    @Test("AUTO-6 continue repeats the latest non-running entry's task and project and leaves its end unchanged")
    func continueLatest() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        let before = try fixture.run(["entry", "show", ToolFixture.entryID(5), "--json"])
        let result = try fixture.run(["continue", "--json"])
        #expect(result.status == 0, "\(result.standardError)")
        #expect(result.json["task"] as? String == "Grade \"quiz\", part 2")
        #expect((result.json["project"] as? [String: Any])?["name"] as? String == "Grading")
        let after = try fixture.run(["entry", "show", ToolFixture.entryID(5), "--json"])
        #expect(after.standardOutput == before.standardOutput)
        let running = try fixture.run(["continue", "--entry-id", result.json["id"] as? String ?? ""])
        #expect(running.status == 4)
    }

    @Test("AUTO-32 a write waits out another process's 2-second write lock and exits 5 after a 10-second one")
    func busyTimeout() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        let short = try runWhileLocked(fixture, holding: 2)
        #expect(short.status == 0, "\(short.standardError)")
        let long = try runWhileLocked(fixture, holding: 10)
        #expect(long.status == 5)
        #expect(long.standardError.hasPrefix("error: "))
    }

    /// Runs `start` while this process holds the write lock for `duration`.
    private func runWhileLocked(_ fixture: ToolFixture, holding seconds: TimeInterval) throws -> ToolResult {
        var database: OpaquePointer?
        guard sqlite3_open_v2(fixture.store.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            throw ToolFixture.FixtureError.sqlite
        }
        defer { sqlite3_close(database) }
        #expect(sqlite3_exec(database, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK)
        let tool = try ToolProcess.start("timetracking", ["start", "Locked"], environment: fixture.environment)
        // The other writer holds the lock for a wall-clock time. This stays
        // on one thread: Process.waitUntilExit needs the launching thread.
        Thread.sleep(forTimeInterval: seconds)
        sqlite3_exec(database, "COMMIT", nil, nil, nil)
        return ToolProcess.finish(tool)
    }

    @Test("AUTO-33 a successful write posts <APP_ID>.changed once and appends one outbox row per changed record; a failed one neither")
    func notificationAndOutbox() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        let posts = ChangeSignalCounter()
        let outbox = try fixture.count("SELECT COUNT(*) FROM outbox")
        // Stops the running entry and starts one: two changed records.
        #expect(try fixture.run(["start", "Next"]).status == 0)
        #expect(posts.count() == 1)
        #expect(try fixture.count("SELECT COUNT(*) FROM outbox") == outbox + 2)
        #expect(try fixture.run(["start", "--project", "Old paper"]).status == 4)
        #expect(posts.count() == 0)
        #expect(try fixture.count("SELECT COUNT(*) FROM outbox") == outbox + 2)
    }
}

/// Counts the posts of `<APP_ID>.changed` since creation or the last count.
final class ChangeSignalCounter {
    private var descriptor: Int32 = -1
    private var token: Int32 = 0

    init() {
        let name = ToolProcess.appID + ".changed"
        #expect(notify_register_file_descriptor(name, &descriptor, 0, &token) == NOTIFY_STATUS_OK)
        _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
    }

    deinit {
        notify_cancel(token)
    }

    func count() -> Int {
        var count = 0
        var value: Int32 = 0
        while read(descriptor, &value, MemoryLayout<Int32>.size) == MemoryLayout<Int32>.size {
            count += 1
        }
        return count
    }
}
