// The Knowledge store backfill and synced Safari history
// (spec_activity_tracking.md §3.2, §6.1).

import Foundation
import GRDB
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct KnowledgeTests {
    /// A `knowledgeC.db` with the expected schema, or one without `ZSTREAMNAME`.
    private func knowledgeDatabase(in folder: URL, expected: Bool, apps: [KnowledgeAppInterval]) throws -> String {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appending(path: "knowledgeC.db").path
        let queue = try DatabaseQueue(path: path)
        try queue.write { database in
            let stream = expected ? "ZSTREAMNAME VARCHAR," : ""
            try database.execute(sql: """
            CREATE TABLE ZOBJECT (Z_PK INTEGER PRIMARY KEY, \(stream) ZSTARTDATE TIMESTAMP, ZENDDATE TIMESTAMP,
                ZVALUESTRING VARCHAR, ZVALUEINTEGER INTEGER, ZSTRUCTUREDMETADATA INTEGER);
            CREATE TABLE ZSTRUCTUREDMETADATA (Z_PK INTEGER PRIMARY KEY, Z_DKDIGITALHEALTHMETADATAKEY__WEBPAGEURL VARCHAR);
            """)
            guard expected else {
                return
            }
            for app in apps {
                try database.execute(
                    sql: "INSERT INTO ZOBJECT (ZSTREAMNAME, ZSTARTDATE, ZENDDATE, ZVALUESTRING) VALUES ('/app/usage', ?, ?, ?)",
                    arguments: [app.start.timeIntervalSinceReferenceDate, app.end.timeIntervalSinceReferenceDate, app.bundleID]
                )
            }
        }
        return path
    }

    @Test("TRK-24 an unexpected Knowledge schema sets knowledge to off with a reason and writes no knowledge blocks")
    func unexpectedSchema() async throws {
        let harness = try AgentHarness()
        let path = try knowledgeDatabase(in: harness.root.appending(path: "bad"), expected: false, apps: [])
        let read = KnowledgeStoreReader(databasePath: path).read(from: harness.time(-86_400), to: harness.time(0))
        guard case let .unavailable(reason) = read else {
            Issue.record("expected unavailable, got \(read)")
            return
        }
        #expect(reason.contains("Unexpected Knowledge store schema"))
        harness.knowledge.result = read
        await harness.engine.tick()
        #expect(harness.health("knowledge")?.status == .off)
        #expect(harness.health("knowledge")?.reason == reason)
        #expect(!harness.blockLogText.contains("\"src\":\"knowledge\""))
    }

    @Test("TRK-24 with the expected schema the agent backfills knowledge blocks for the time it was down")
    func expectedSchema() async throws {
        let harness = try AgentHarness()
        let path = try knowledgeDatabase(
            in: harness.root.appending(path: "good"),
            expected: true,
            apps: [KnowledgeAppInterval(start: harness.time(-3 * 3600), end: harness.time(-3 * 3600 + 1200), bundleID: "com.apple.mail")]
        )
        let read = KnowledgeStoreReader(databasePath: path).read(from: harness.time(-7 * 86_400), to: harness.time(0))
        guard case let .data(apps, _, _) = read else {
            Issue.record("expected data, got \(read)")
            return
        }
        #expect(apps.count == 1)
        harness.knowledge.result = read
        await harness.engine.tick()
        #expect(harness.health("knowledge")?.status == .active)
        let block = try #require(harness.blocks.first)
        #expect(block.source == .knowledge)
        #expect(block.items.first?.context == "mail")
        #expect(block.start == harness.time(-3 * 3600))
        #expect(block.activeSeconds == 1200)
    }

    @Test("TRK-27 with synced_safari_history off no remote block is written and CloudTabs.db is not opened")
    func syncedSafariOff() async throws {
        let harness = try AgentHarness()
        harness.history.safari = [(HistoryVisit(time: harness.time(-3600), browser: "safari", url: "https://example.com/a", title: "A"), 1)]
        harness.history.tabs = [CloudTabDevice(name: "iPhone", urls: [])]
        await harness.run(for: 900)
        #expect(harness.history.cloudTabsReads == 0)
        #expect(!harness.blocks.contains { $0.device == "remote" })
        #expect(harness.health("synced_safari")?.status == .off)
    }

    @Test("TRK-27 with synced_safari_history on visits form remote blocks, attributed when exactly one device gained a visited tab")
    func syncedSafariOn() async throws {
        let harness = try AgentHarness(settings: "[devices]\nsynced_safari_history = true\n")
        var visits: [(HistoryVisit, Int)] = []
        for minute in stride(from: 0, to: 6, by: 1) {
            visits.append((
                HistoryVisit(
                    time: harness.time(TimeInterval(-7200 + minute * 60)),
                    browser: "safari",
                    url: "https://example.com/a",
                    title: ""
                ),
                1
            ))
        }
        harness.history.safari = visits
        harness.history.tabs = [CloudTabDevice(name: "iPhone", urls: [])]
        await harness.engine.tick()
        #expect(harness.history.cloudTabsReads == 1)
        let remote = try #require(harness.blocks.first { $0.device == "remote" })
        #expect(remote.items.first?.subject == "example.com")
        #expect(remote.activeSeconds == 300)

        var collector = SyncedSafariCollector()
        let start = harness.time(0)
        let history = FakeHistory()
        history.tabs = [CloudTabDevice(name: "iPhone", urls: []), CloudTabDevice(name: "iPad", urls: [])]
        collector.poll(history: history, now: start)
        history.tabs = [CloudTabDevice(name: "iPhone", urls: ["https://example.com/b"]), CloudTabDevice(name: "iPad", urls: [])]
        collector.poll(history: history, now: start.addingTimeInterval(300))
        let attributed = collector.blocks(
            visits: [
                HistoryVisit(time: start.addingTimeInterval(200), browser: "safari", url: "https://example.com/b", title: ""),
                HistoryVisit(time: start.addingTimeInterval(320), browser: "safari", url: "https://example.com/c", title: ""),
                HistoryVisit(time: start.addingTimeInterval(4000), browser: "safari", url: "https://example.com/d", title: ""),
                HistoryVisit(time: start.addingTimeInterval(4100), browser: "safari", url: "https://example.com/e", title: ""),
            ],
            context: harness.engine.resolveContext(),
            timeZone: AgentHarness.zone
        )
        #expect(attributed.map(\.block.device) == ["iPhone", "remote"])
    }
}
