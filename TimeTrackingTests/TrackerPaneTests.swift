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

    @Test("TRK-32 the pane writes settings.toml only to create the default file and to add a drafted exclusion, keeping every other byte")
    func settingsFile() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "TrackerPaneTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "settings.toml")
        let model = TrackerSettingsModel(settingsURL: url)
        #expect(model.entries(.excludeDomains).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        // Opening the file creates the commented defaults.
        #expect(model.ensureFile())
        #expect(try String(contentsOf: url, encoding: .utf8) == TrackerSettings.defaultFileContents)
        // A hand edit is never overwritten.
        let handEdited = TrackerSettings.defaultFileContents + "\n# My own note\n"
        try Data(handEdited.utf8).write(to: url)
        #expect(model.ensureFile())
        #expect(try String(contentsOf: url, encoding: .utf8) == handEdited)
        // An exclusion from Activity is inserted, and nothing else changes.
        model.prepare(.domain("example.com"))
        model.addPendingExclusion()
        #expect(model.pendingExclusion == nil)
        #expect(model.lastAdded == PendingExclusion(list: .excludeDomains, value: "example.com"))
        #expect(model.entries(.excludeDomains) == ["example.com"])
        let saved = try String(contentsOf: url, encoding: .utf8)
        #expect(saved.replacingOccurrences(of: "\"example.com\"", with: "") == handEdited)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["settings.toml"])
    }

    @Test("TRK-32 a settings file still in iCloud Drive is downloaded, never replaced by the defaults")
    func settingsFilePlaceholder() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "TrackerPaneTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appending(path: ".settings.toml.icloud"))
        let model = TrackerSettingsModel(settingsURL: folder.appending(path: "settings.toml"))
        #expect(!model.ensureFile())
        #expect(model.message != nil)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "settings.toml").path))
    }

    @Test("TRK-36 each hook of the snippets names its event, so the tracker accepts it, runs in the background, and stays silent on errors")
    func snippets() throws {
        let lines = TrackerSnippets.tmux.split(separator: "\n").map(String.init)
        #expect(lines.first == "set -g focus-events on")
        #expect(lines.count == TrackerSnippets.tmuxHooks.count + 1)
        #expect(!TrackerSnippets.tmux.contains("pane-focus-in"))
        for hook in TrackerSnippets.tmuxHooks {
            let line = try #require(lines.first { $0.hasPrefix("set-hook -g \(hook) ") })
            #expect(line.contains("'run-shell -b \""))
            let command = try #require(line.split(separator: "\"").dropFirst().first)
            #expect(command.hasSuffix(" >/dev/null 2>&1 || true"))
            let event = command.replacingOccurrences(of: "tracker-event ", with: "").replacingOccurrences(
                of: " >/dev/null 2>&1 || true",
                with: ""
            )
            #expect(try TrackerCommand.parse(event + "\n") == .tmuxEvent(hook: hook, arguments: []))
        }
        let json = try JSONSerialization.jsonObject(with: Data(TrackerSnippets.agentHooks.utf8)) as? [String: Any]
        let hooks = try #require(json?["hooks"] as? [String: [[String: Any]]])
        #expect(Set(hooks.keys) == ["UserPromptSubmit", "Stop", "SessionEnd"])
        for (name, entries) in hooks {
            let inner = try #require(entries.first?["hooks"] as? [[String: String]])
            let command = try #require(inner.first?["command"])
            #expect(command.hasSuffix(" >/dev/null 2>&1 &"))
            let event = command.replacingOccurrences(of: "tracker-event ", with: "").replacingOccurrences(
                of: " >/dev/null 2>&1 &",
                with: ""
            )
            #expect(try TrackerCommand.parse(event + "\n") == .agentEvent(hook: name, arguments: []))
        }
    }

    @Test("TRK-33 Full Disk Access names and reveals the app bundle (Debug: <APP_NAME> Debug); Accessibility names and reveals the agent")
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

    @Test("TRK-34 while the tracker runs without Full Disk Access, Restart Tracker restarts the agent and re-reads the status")
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

    @Test("TRK-35 the Open at login step is done when the app opens at login; otherwise its action turns it on")
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
