// The one Mac that records: `blocks/owner` decides which agent writes the
// date files (activity_tracking.md §4.1).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct OwnershipTests {
    @Test(
        "TRK-67 while blocks/owner names another Mac, the agent writes no date file and reports shared_folder off, and the other way round"
    )
    func oneMacRecords() async throws {
        let harness = try AgentHarness()
        let log = harness.agent.choice.log
        try FileManager.default.createDirectory(at: log.url, withIntermediateDirectories: true)
        try BlockLogOwner.claim(log, for: "other-mac")
        harness.textEdit()
        await harness.workThenLock(for: 720)
        #expect(harness.dateFileText(AgentHarness.today) == nil)
        #expect(harness.liveSamples().count > 25)
        let folder = try #require(harness.health(.sharedFolder))
        #expect(folder.status == .off)
        #expect(folder.reason == "Another Mac records activity; choose Record on This Mac to record here")

        // "Record on This Mac".
        try BlockLogOwner.claim(log, for: AgentHarness.macID)
        await harness.unlock()
        await harness.workThenLock(for: 720)
        #expect(harness.blocks(AgentHarness.today).count == 2)
        #expect(harness.health(.sharedFolder)?.status == .active)

        // The other Mac's agent keeps taking Samples but writes no date file.
        var configuration = harness.agent.configuration
        configuration.macDeviceID = "other-mac"
        let other = try Agent(environment: harness.agent.environment, configuration: configuration, store: SampleStore(url: nil))
        try other.start()
        let written = harness.blockLogText
        harness.advance(30)
        other.queue.requestTick()
        await other.queue.drain()
        harness.advance(900)
        other.queue.requestTick()
        await other.queue.drain()
        #expect(harness.blockLogText == written)
        #expect(other.health.status(.sharedFolder) == .off)
    }

    @Test("TRK-67 an agent that writes the local folder reads blocks/owner in the shared folder and never claims it there")
    func fallbackReadsSharedOwner() async throws {
        let harness = try AgentHarness(canWriteShared: false)
        let shared = harness.agent.choice.ownerLog
        try FileManager.default.createDirectory(at: shared.url, withIntermediateDirectories: true)
        try BlockLogOwner.claim(shared, for: "other-mac")
        harness.textEdit()
        await harness.workThenLock(for: 720)
        #expect(harness.dateFileText(AgentHarness.today) == nil)
        #expect(harness.health(.sharedFolder)?.status == .off)

        // Without an owner file the agent records locally, both blocks since
        // it now records, and leaves the claim to the Mac app.
        try FileManager.default.removeItem(at: BlockLogOwner.url(in: shared))
        await harness.unlock()
        await harness.workThenLock(for: 720)
        #expect(harness.blocks(AgentHarness.today).count == 2)
        #expect(harness.health(.sharedFolder)?.status == .fallback)
        #expect(try BlockLogOwner.owner(of: shared) == nil)
    }

    @Test("TRK-67 while blocks/owner can't be read, the agent keeps recording as before")
    func unreadableOwnerKeepsDecision() async throws {
        let harness = try AgentHarness()
        harness.textEdit()
        await harness.workThenLock(for: 720)
        #expect(harness.blocks(AgentHarness.today).count == 1)
        let owner = BlockLogOwner.url(in: harness.agent.choice.ownerLog)
        try FileManager.default.removeItem(at: owner)
        try Data().write(to: ActivityFile.placeholderURL(for: owner))
        await harness.unlock()
        await harness.workThenLock(for: 720)
        #expect(harness.blocks(AgentHarness.today).count == 2)
        #expect(harness.health(.sharedFolder)?.status == .active)
    }

    @Test("TRK-67 an agent that starts while blocks/owner can't be read writes no date and unmarks none until it can")
    func ownershipUnknownAtStart() async throws {
        let harness = try AgentHarness()
        harness.textEdit()
        await harness.workThenLock(for: 720)
        let day = try #require(TrackingDay(AgentHarness.today))
        let owner = BlockLogOwner.url(in: harness.agent.choice.ownerLog)
        let ownerText = try String(contentsOf: owner, encoding: .utf8)
        try FileManager.default.removeItem(at: owner)
        try Data().write(to: ActivityFile.placeholderURL(for: owner))
        // A file in an older format, which the agent marks at start.
        let outdated = "{\"format\":0}\n"
        try outdated.write(to: harness.agent.choice.log.fileURL(for: day), atomically: true, encoding: .utf8)
        try harness.restart()
        await harness.tick()
        #expect(harness.dateFileText(AgentHarness.today) == outdated)

        // The owner file arrives: the marked date is written.
        try FileManager.default.removeItem(at: ActivityFile.placeholderURL(for: owner))
        try ownerText.write(to: owner, atomically: true, encoding: .utf8)
        await harness.tick()
        #expect(harness.blocks(AgentHarness.today).count == 1)
    }
}
