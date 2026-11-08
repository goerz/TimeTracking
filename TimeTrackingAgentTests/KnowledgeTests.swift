// Samples rebuilt from macOS app usage for the time the agent didn't run
// (activity_tracking.md §2.4, §3.2).

import Foundation
import GRDB
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct KnowledgeTests {
    /// A `knowledgeC.db` with the expected schema, or one without `ZSTREAMNAME`.
    private func knowledgeDatabase(in folder: URL, expected: Bool, apps: [KnowledgeAppInterval] = []) throws -> String {
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
            for app in apps where expected {
                try database.execute(
                    sql: "INSERT INTO ZOBJECT (ZSTREAMNAME, ZSTARTDATE, ZENDDATE, ZVALUESTRING) VALUES ('/app/usage', ?, ?, ?)",
                    arguments: [app.start.timeIntervalSinceReferenceDate, app.end.timeIntervalSinceReferenceDate, app.bundleID]
                )
            }
        }
        return path
    }

    /// Five minutes of ticks, then the agent doesn't run until 11:00, when it ticks and fills the gap.
    private func gapUntilEleven(_ harness: AgentHarness, apps: [KnowledgeAppInterval]) async throws {
        harness.textEdit()
        await harness.run(for: 300)
        let path = try knowledgeDatabase(in: harness.root.appending(path: "knowledge"), expected: true, apps: apps)
        harness.knowledge.result = KnowledgeStoreReader(databasePath: path).read(from: harness.time(-86_400), to: harness.time(7200))
        harness.clock.set(harness.time(3600))
        try harness.restart()
        await harness.drain()
        try harness.agent.fillGaps()
        await harness.drain()
    }

    @Test(
        "TRK-14 a gap longer than idle_close gets an appUsage Sample every 30 seconds of each app interval; reading again marks no date"
    )
    func gapFill() async throws {
        let harness = try AgentHarness()
        let mail = KnowledgeAppInterval(start: harness.time(1200), end: harness.time(2400), bundleID: "com.apple.mail")
        // Before the agent's first start: never filled.
        let early = KnowledgeAppInterval(start: harness.time(-3600), end: harness.time(-1800), bundleID: "com.apple.Notes")
        try await gapUntilEleven(harness, apps: [early, mail])
        let usage = harness.samples.filter { $0.source == .appUsage }
        #expect(usage.map(\.time) == stride(from: 1200, to: 2400, by: 30).map { harness.time($0) })
        #expect(usage.allSatisfy { $0.state == .active && $0.foreground == ActivityItem(app: "Mail", appID: "com.apple.mail") })
        #expect(harness.agent.health.status(.knowledge) == .active)
        let block = try #require(harness.blocks(AgentHarness.today).first { $0.foreground.first?.item.app == "Mail" })
        #expect(block.start == harness.time(1200))
        #expect(block.reconstructedSeconds == block.activeSeconds)
        #expect(block.activeSeconds >= 1200)

        #expect(try harness.agent.store.meta(.changedDays)?.isEmpty ?? true)
        try harness.agent.fillGaps()
        #expect(try harness.agent.store.meta(.changedDays)?.isEmpty ?? true)
        #expect(harness.samples.filter { $0.source == .appUsage } == usage)
    }

    @Test("TRK-15 an unexpected Knowledge schema sets knowledge to off with a reason and inserts nothing")
    func unexpectedSchema() async throws {
        let harness = try AgentHarness()
        let path = try knowledgeDatabase(in: harness.root.appending(path: "bad"), expected: false)
        let read = KnowledgeStoreReader(databasePath: path).read(from: harness.time(-86_400), to: harness.time(0))
        #expect(read == .unavailable(KnowledgeStoreReader.unexpectedSchemaReason))
        harness.knowledge.result = read
        await harness.run(for: 60)
        harness.clock.set(harness.time(3600))
        try harness.restart()
        try harness.agent.fillGaps()
        await harness.drain()
        let knowledge = try #require(harness.health(.knowledge))
        #expect(knowledge.status == .off)
        #expect(knowledge.reason == "macOS changed how it stores app usage; this version can't read it")
        #expect(!harness.samples.contains { $0.source == .appUsage })
    }

    @Test(
        "TRK-57 the gap between Disable Tracker and Enable Tracker gets no appUsage Samples; a gap while the agent didn't run does"
    )
    func disabledGapStaysEmpty() async throws {
        let harness = try AgentHarness()
        harness.textEdit()
        await harness.run(for: 300)
        let path = try knowledgeDatabase(
            in: harness.root.appending(path: "knowledge"),
            expected: true,
            apps: [
                KnowledgeAppInterval(start: harness.time(1800), end: harness.time(3000), bundleID: "com.apple.mail"),
                KnowledgeAppInterval(start: harness.time(9000), end: harness.time(10_200), bundleID: "com.apple.mail"),
            ]
        )
        harness.knowledge.result = KnowledgeStoreReader(databasePath: path).read(from: harness.time(-86_400), to: harness.time(86_400))

        // "Disable Tracker" writes the file; the agent stops.
        let disabled = harness.agent.configuration.disabledURL
        try Data().write(to: disabled)
        harness.clock.set(harness.time(7200))
        try harness.restart()
        #expect(!FileManager.default.fileExists(atPath: disabled.path))
        #expect(try harness.agent.store.meta(.fillAfter) == harness.time(7200))
        await harness.run(for: 300)
        try harness.agent.fillGaps()
        #expect(!harness.samples.contains { $0.source == .appUsage })

        // The agent is not running from 12:05 to 14:00, without a disable.
        harness.clock.set(harness.time(14_400))
        try harness.restart()
        await harness.drain()
        try harness.agent.fillGaps()
        let usage = harness.samples.filter { $0.source == .appUsage }
        #expect(usage.map(\.time) == stride(from: 9000, to: 10_200, by: 30).map { harness.time($0) })
    }
}
