// The Tracker pane and the agent's registration (activity_tracking.md
// §7.4, architecture.md §1.4).

import Foundation
import ServiceManagement
import Testing
import TimeTrackingCore
@testable import TimeTracking

@MainActor
struct TrackerPaneTests {
    private static func state(lastTick: Date, sources: [TrackerSourceHealth]) -> TrackerState {
        TrackerState(
            block: nil,
            foreground: nil,
            presence: TrackerPresence(state: .active, since: lastTick),
            health: TrackerHealth(lastTick: lastTick, version: "1.0 (42)", sources: sources)
        )
    }

    @Test("TRK-49 the dot, button, and setup marks follow the registration and health; nothing registers before Enable Tracker")
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
        #expect(tracker.liveness.statusLine(now: now) == "Tracker running · checked 12 s ago")
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

    @Test("TRK-67 while another Mac records, the iCloud Drive row offers Record on This Mac; it and Enable Tracker claim the log")
    func recordHere() async throws {
        let now = try TestApp.date("2024-03-14T10:00")
        let source = TrackerSourceHealth(id: "shared_folder", name: "iCloud Drive", status: .off, reason: BlockLogOwner.otherMacReason)
        let test = try await TestApp(trackerState: Self.state(lastTick: now - 12, sources: [source]))
        let tracker = test.app.tracker
        await tracker.refresh()
        let row = try #require(tracker.setupSteps.first { $0.id == "icloud" })
        #expect(row.actions == [.recordHere])
        #expect(row.detail == "Off: another Mac records activity.")
        await tracker.recordHere()
        #expect(test.agent.recordHereCalls == 1)
        await tracker.pressButton()
        #expect(test.agent.registerCalls == 1)
        #expect(test.agent.recordHereCalls == 2)
    }

    @Test("TRK-57 Disable Tracker and a login item found off leave the disabled marker; an enabled tracker leaves none")
    func disabledMarker() async throws {
        let now = try TestApp.date("2024-03-14T10:00")
        let test = try await TestApp(trackerState: Self.state(lastTick: now - 12, sources: []))
        let tracker = test.app.tracker
        test.agent.registration = .enabled
        let before = test.agent.disabledMarks
        await tracker.refresh()
        #expect(test.agent.disabledMarks == before)
        // Turned off in System Settings › Login Items.
        test.agent.registration = .notRegistered
        await tracker.refresh()
        #expect(test.agent.disabledMarks == before + 1)
        test.agent.registration = .enabled
        await tracker.refresh()
        await tracker.disable()
        #expect(test.agent.disabledMarks > before + 1)
        #expect(tracker.registration == .notRegistered)
    }

    @Test("TRK-49 while the pane is visible the status is re-read every 5 seconds, so a change shows within 5 seconds")
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

    @Test("TRK-51 Full Disk Access names and reveals the app bundle (Debug: <APP_NAME> Debug); Accessibility names and reveals the agent")
    func setupNamesTheBundles() async throws {
        let test = try await TestApp()
        let tracker = test.app.tracker
        await tracker.refresh()
        // The hosted app is the Debug build: both names end in " Debug".
        let bundles = tracker.bundles
        #expect(bundles == TrackerBundles.main)
        #expect(bundles.app == Bundle.main.bundleURL)
        #expect(bundles.appName == Bundle.main.bundleURL.deletingPathExtension().lastPathComponent)
        #expect(bundles.appName.hasSuffix(" Debug"))
        #expect(bundles.agentName == "TimeTrackingAgent Debug")
        let steps = Dictionary(uniqueKeysWithValues: tracker.setupSteps.map { ($0.id, $0) })
        let fullDisk = try #require(steps["fullDisk"])
        #expect(fullDisk.actions.contains(.showInFinder(name: bundles.appName, url: Bundle.main.bundleURL)))
        #expect(fullDisk.actions.map(\.title).contains("Show \(bundles.appName) in Finder"))
        #expect(fullDisk.guidance.first == "Open System Settings › Privacy & Security › Full Disk Access.")
        #expect(fullDisk.guidance.contains("Drag \(bundles.appName) from the Finder window into the list, or click + and choose it."))
        #expect(fullDisk.note.contains("on behalf of \(bundles.appName)"))
        #expect(!fullDisk.guidance.joined().contains("TimeTrackingAgent"))
        let accessibility = try #require(steps["accessibility"])
        let agentURL = try #require(bundles.agent)
        #expect(agentURL.lastPathComponent == "TimeTrackingAgent Debug.app")
        #expect(accessibility.actions.contains(.showInFinder(name: "TimeTrackingAgent Debug", url: agentURL)))
        #expect(accessibility.guidance.contains("Turn TimeTrackingAgent Debug on."))
        let automation = try #require(steps["automation"])
        #expect(automation.guidance.contains("Under \(bundles.appName), turn on each browser and terminal."))
        #expect(automation.note.hasPrefix("Automation belongs to \(bundles.appName)"))
        #expect(!automation.guidance.joined().contains("TimeTrackingAgent"))
        // Release names: the installed app's file name, without " Debug".
        let release = TrackerBundles(
            app: URL(filePath: "/Applications/TimeTracking.app"),
            agent: URL(filePath: "/Applications/TimeTracking.app/Contents/Library/LoginItems/TimeTrackingAgent.app")
        )
        let model = TrackerStatusModel(agent: FakeAgentService(), clock: test.clock, readState: { nil }, bundles: release)
        let releaseSteps = Dictionary(uniqueKeysWithValues: model.setupSteps.map { ($0.id, $0) })
        #expect(releaseSteps["fullDisk"]?.actions.map(\.title).contains("Show TimeTracking in Finder") == true)
        #expect(releaseSteps["fullDisk"]?.guidance.contains("Turn TimeTracking on.") == true)
        #expect(releaseSteps["accessibility"]?.actions.map(\.title).contains("Show TimeTrackingAgent in Finder") == true)
        // No step keeps the old label that did not say which bundle it shows.
        #expect(!model.setupSteps.flatMap(\.actions).map(\.title).contains("Show Tracker in Finder"))
    }

    @Test("TRK-52 while the tracker runs without Full Disk Access, Restart Tracker restarts the agent and re-reads the status")
    func restartTracker() async throws {
        let now = try TestApp.date("2024-03-14T10:00")
        let denied = [
            TrackerSourceHealth(id: "history", name: "History", status: .fallback, reason: "Full Disk Access not granted"),
            TrackerSourceHealth(id: "knowledge", name: "Knowledge store", status: .off, reason: "Full Disk Access not granted"),
        ]
        let box = StateBox(Self.state(lastTick: now - 12, sources: denied))
        let agent = FakeAgentService()
        let tracker = TrackerStatusModel(agent: agent, clock: ManualClock(now), readState: { await box.value })
        await tracker.refresh()
        func fullDisk() throws -> TrackerSetupStep {
            try #require(tracker.setupSteps.first { $0.id == "fullDisk" })
        }
        // Not registered: nothing to restart.
        #expect(try !fullDisk().actions.contains(.restartTracker))
        #expect(try !fullDisk().guidance.joined().contains("Restart Tracker"))
        await tracker.enable()
        #expect(try fullDisk().actions.contains(.restartTracker))
        #expect(try fullDisk().guidance.last == "Click Restart Tracker, so the running tracker gets the access.")
        // The restarted agent reports the grant; the pane re-reads at once.
        let granted = denied.map { TrackerSourceHealth(id: $0.id, name: $0.name, status: .active) }
        await box.set(Self.state(lastTick: now, sources: granted))
        await tracker.restartTracker()
        #expect(agent.restartCalls == 1)
        #expect(try fullDisk().mark == .done)
        #expect(try !fullDisk().actions.contains(.restartTracker))
        #expect(tracker.lastError == nil)
    }

    @Test("TRK-53 the Open at login step is done when the app opens at login; otherwise its action turns it on")
    func openAtLoginStep() async throws {
        let test = try await TestApp()
        let tracker = test.app.tracker
        await tracker.refresh()
        func step() throws -> TrackerSetupStep {
            try #require(tracker.setupSteps.first { $0.id == "openAtLogin" })
        }
        #expect(try step().title == "Open \(tracker.bundles.appName) at login")
        #expect(try step().mark == .attention)
        #expect(try step().actions == [.openAtLogin])
        #expect(!tracker.opensAtLogin)
        tracker.setOpensAtLogin(true)
        #expect(test.loginItem.changes == [true])
        #expect(try step().mark == .done)
        #expect(try step().actions == [.noAction])
        #expect(tracker.opensAtLogin)
        // Turned off in Login Items: approval needed; the pane follows on its next read.
        test.loginItem.registration = .requiresApproval
        await tracker.refresh()
        #expect(try step().mark == .attention)
        #expect(try step().actions == [.openLoginItems])
        // The second row, after the background tracker.
        #expect(Array(tracker.setupSteps.map(\.id).prefix(2)) == ["background", "openAtLogin"])
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

/// A tracker state the test changes between reads.
private actor StateBox {
    private(set) var value: TrackerState?

    init(_ value: TrackerState?) {
        self.value = value
    }

    func set(_ value: TrackerState?) {
        self.value = value
    }
}
