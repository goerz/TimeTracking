// TrackerStatusModel: the tracker's registration and liveness for the Tracker
// pane and the menu bar warning, and the app's "Open at login"
// (spec_activity_tracking.md §4.4, §7.4; spec_menubar.md §3;
// spec_timer.md §8.1, §8.2).

import Foundation
import Observation
import TimeTrackingCore

/// The tracker's status, read every 30 s, at wake, unlock, and launch, and
/// every 5 s while the Tracker pane is visible.
@Observable
final class TrackerStatusModel {
    @ObservationIgnored let agent: AgentService
    @ObservationIgnored let loginItem: AppLoginItemService
    @ObservationIgnored let automation: AutomationPermissionService
    @ObservationIgnored let clock: any Clock
    @ObservationIgnored let readState: () async -> TrackerState?
    /// The bundles the setup steps name and reveal.
    @ObservationIgnored let bundles: TrackerBundles

    private(set) var registration: AgentRegistration = .notRegistered
    /// The app's own login item ("Open at login").
    private(set) var appLoginItem: AgentRegistration
    private(set) var state: TrackerState?
    private(set) var warningActive = false
    /// Since when the Mac has been awake, unlocked, and in the session.
    private(set) var presentSince: Date?
    var confirmDisable = false
    private(set) var lastError: String?
    /// The answers of the last "Ask for Access" as one line; `nil` before the first.
    private(set) var automationOutcome: String?

    init(
        agent: AgentService,
        loginItem: AppLoginItemService = FakeAppLoginItem(),
        automation: AutomationPermissionService = FakeAutomationPermission(),
        clock: any Clock,
        readState: @escaping () async -> TrackerState?,
        bundles: TrackerBundles = .main
    ) {
        self.agent = agent
        self.loginItem = loginItem
        self.automation = automation
        self.clock = clock
        self.readState = readState
        self.bundles = bundles
        self.appLoginItem = loginItem.registration
        self.presentSince = clock.now
    }

    var liveness: TrackerLiveness {
        TrackerLiveness(registration: registration, state: state, now: clock.now)
    }

    /// Re-reads the registration and `current.json`.
    func refresh() async {
        registration = agent.registration
        appLoginItem = loginItem.registration
        state = await readState()
        warningActive = TrackerWarning.isActive(registration: registration, state: state, presentSince: presentSince, now: clock.now)
    }

    /// The Tracker pane's re-read period (spec_activity_tracking.md §7.4).
    static let paneRefreshInterval: Duration = .seconds(5)

    /// While the Tracker pane is visible: refreshes now and after every
    /// `paneRefreshInterval`, until the task is cancelled. `sleep` is the
    /// tests' seam.
    func refreshWhileVisible(sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) async {
        while !Task.isCancelled {
            await refresh()
            do {
                try await sleep(Self.paneRefreshInterval)
            } catch {
                return
            }
        }
    }

    /// Wake, unlock, or session activation.
    func becamePresent(at time: Date) async {
        presentSince = time
        await refresh()
    }

    /// Sleep, lock, or session switch.
    func becameAbsent() {
        presentSince = nil
        warningActive = false
    }

    /// The menu's warning line.
    var warningLine: String {
        guard let tick = state?.health.lastTick else {
            return "⚠ Tracker not running"
        }
        return "⚠ Tracker not running since \(tick.formatted(date: .omitted, time: .shortened))"
    }

    /// The status dot's color name: green, yellow, red, gray.
    var dotColor: String {
        switch liveness {
        case .running: "green"
        case .delayed: "yellow"
        case .notRunning: "red"
        case .off: "gray"
        }
    }

    /// The pane's one button, by `SMAppService` status.
    var buttonTitle: String {
        switch registration {
        case .notRegistered, .notFound: "Enable Tracker"
        case .requiresApproval: "Open Login Items"
        case .enabled: "Disable Tracker"
        }
    }

    /// The button's action; Disable asks for confirmation first.
    func pressButton() async {
        switch registration {
        case .notRegistered, .notFound:
            await enable()
        case .requiresApproval:
            agent.openLoginItems()
        case .enabled:
            confirmDisable = true
        }
    }

    /// "Enable Tracker": the only place that registers the agent.
    func enable() async {
        do {
            try agent.register()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        await refresh()
    }

    /// "Restart Tracker": a privacy grant reaches a running agent only
    /// after a restart.
    func restartTracker() async {
        do {
            try await agent.restart()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        await refresh()
    }

    /// "Ask for Access": asks macOS for each scriptable browser and
    /// terminal that is open, then re-reads the status.
    func askForAutomation() async {
        automationOutcome = await Self.automationOutcomeLine(automation.ask(AutomationTargets.bundleIDs))
        await refresh()
    }

    /// Whether the app opens at login (Settings › General).
    var opensAtLogin: Bool {
        appLoginItem == .enabled
    }

    /// Turns "Open at login" on or off.
    func setOpensAtLogin(_ enabled: Bool) {
        do {
            try loginItem.setOpensAtLogin(enabled)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        appLoginItem = loginItem.registration
    }

    /// "Disable Tracker" after confirmation.
    func disable() async {
        do {
            try await agent.unregister()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        await refresh()
    }
}
