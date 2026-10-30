// The Tracker pane and the agent's registration (spec_activity_tracking.md
// §7.4, spec_architecture.md §1.4).

import Foundation
import ServiceManagement
import Testing
import TimeTrackingCore
@testable import TimeTracking

@MainActor
struct TrackerPaneTests {
    private static func state(lastTick: Date, sources: [TrackerSourceHealth]) -> TrackerState {
        TrackerState(
            device: "mac",
            openBlock: nil,
            primary: nil,
            presence: TrackerPresence(state: .active, since: lastTick),
            health: TrackerHealth(lastTick: lastTick, version: "1.0 (42)", sources: sources)
        )
    }

    @Test("TRK-31 the dot, button, and setup marks follow the registration and health; nothing registers before Enable Tracker")
    func paneStatus() async throws {
        let now = try TestApp.date("2024-03-14T10:00")
        let sources = [
            TrackerSourceHealth(id: "window", name: "Window", status: .active),
            TrackerSourceHealth(id: "browser", name: "Browsers", status: .active),
            TrackerSourceHealth(id: "terminal", name: "Terminal", status: .fallback, reason: "No adapter"),
            TrackerSourceHealth(id: "knowledge", name: "Knowledge store", status: .off, reason: "Full Disk Access not granted"),
        ]
        let test = try await TestApp(trackerState: Self.state(lastTick: now - 12, sources: sources))
        let tracker = test.app.tracker
        await tracker.refresh()
        #expect(tracker.dotColor == "gray")
        #expect(tracker.liveness.statusLine(now: now) == "Tracker off")
        #expect(tracker.buttonTitle == "Enable Tracker")
        #expect(tracker.setupSteps.first?.mark == .attention)
        #expect(tracker.setupSteps.first?.actions == [.enableTracker])
        #expect(test.agent.registerCalls == 0)
        await tracker.pressButton()
        #expect(test.agent.registerCalls == 1)
        #expect(tracker.dotColor == "green")
        #expect(tracker.liveness.statusLine(now: now) == "Tracker running · last tick 12 s ago")
        #expect(tracker.buttonTitle == "Disable Tracker")
        let marks = Dictionary(uniqueKeysWithValues: tracker.setupSteps.map { ($0.id, $0.mark) })
        #expect(marks["background"] == .done)
        #expect(marks["accessibility"] == .done)
        #expect(marks["automation"] == .attention)
        #expect(marks["fullDisk"] == .attention)
        #expect(marks["icloud"] == .unknown)
        // Disable asks first.
        await tracker.pressButton()
        #expect(tracker.confirmDisable)
        await tracker.disable()
        #expect(tracker.registration == .notRegistered)
        // Requires approval: Open Login Items.
        test.agent.registration = .requiresApproval
        await tracker.refresh()
        #expect(tracker.buttonTitle == "Open Login Items")
        await tracker.pressButton()
        #expect(test.agent.openedLoginItems == 1)
    }

    @Test("TRK-31 while the pane is visible the status is re-read every 5 seconds, so a change shows within 5 seconds")
    func paneRefreshLoop() async throws {
        let now = try TestApp.date("2024-03-14T10:00")
        let test = try await TestApp(trackerState: Self.state(lastTick: now - 12, sources: []))
        let tracker = test.app.tracker
        let gate = SleepGate()
        let loop = Task { await tracker.refreshWhileVisible(sleep: { try await gate.sleep($0) }) }
        await gate.waitForSleep(1)
        #expect(tracker.dotColor == "gray")
        #expect(tracker.buttonTitle == "Enable Tracker")
        // Registered elsewhere (Login Items): the next pass, one period later, shows it.
        test.agent.registration = .enabled
        #expect(tracker.dotColor == "gray")
        gate.release()
        await gate.waitForSleep(2)
        #expect(tracker.dotColor == "green")
        #expect(tracker.buttonTitle == "Disable Tracker")
        #expect(gate.durations == [.seconds(5), .seconds(5)])
        #expect(TrackerStatusModel.paneRefreshInterval <= .seconds(5))
        loop.cancel()
        gate.cancel()
        await loop.value
    }

    @Test("TRK-32 the pane writes only settings.toml; confirming Also remove it from past logs sends one reapply-exclusions")
    func exclusions() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "TrackerPaneTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "settings.toml")
        let commands = RecordingTrackerCommands()
        let clock = try ManualClock(TestApp.date("2024-03-14T10:00"))
        let model = try TrackerSettingsModel(
            settingsURL: url,
            commands: commands,
            clock: clock,
            firstLogDay: TestApp.date("2024-01-01T00:00")
        )
        model.add("example.com", to: .excludeDomains)
        #expect(model.offerReapply == .excludeDomains)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["settings.toml"])
        let saved = try TrackerSettings(contentsOf: url)
        #expect(saved.privacy.excludeDomains == ["example.com"])
        await model.reapplyExclusions()
        #expect(commands.commands == ["reapply-exclusions 2024-01-01 2024-03-14"])
        #expect(model.offerReapply == nil)
    }

    /// An app in /Applications reports `notRegistered`; the test host runs
    /// from derived data, where the system reports `notFound` for the same
    /// unregistered agent. Both offer "Enable Tracker"; neither is enabled.
    @Test("ARCH-8 the launched Debug app has not registered the agent; the pane offers Enable Tracker")
    func agentNotRegistered() async throws {
        let identity = try AppIdentity(infoDictionary: Bundle.main.infoDictionary ?? [:])
        let plist = Bundle.main.bundleURL.appending(path: "Contents/Library/LaunchAgents/\(identity.agentPlistName)")
        #expect(FileManager.default.fileExists(atPath: plist.path))
        let service = LoginItemAgentService(identity: identity)
        let status = SMAppService.agent(plistName: identity.agentPlistName).status
        #expect([.notRegistered, .notFound].contains(status))
        #expect([.notRegistered, .notFound].contains(service.registration))
        #expect(LoginItemAgentService.registration(of: .notRegistered) == .notRegistered)
        let model = TrackerStatusModel(agent: service, clock: ManualClock.fixture(), readState: { nil })
        await model.refresh()
        #expect(model.buttonTitle == "Enable Tracker")
        #expect(model.dotColor == "gray")
    }
}
