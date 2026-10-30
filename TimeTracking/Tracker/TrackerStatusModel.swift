// TrackerStatusModel: the tracker's registration and liveness for the Tracker
// pane and the menu bar warning, and the app's "Open at login"
// (spec_activity_tracking.md §4.4, §7.4; spec_menubar.md §3;
// spec_timer_window.md §8.1, §8.2).

import Foundation
import Observation
import TimeTrackingCore

/// One setup step of the Tracker pane.
struct TrackerSetupStep: Identifiable, Equatable {
    /// The mark: ✓ active, ! fallback or off, – no health record yet.
    enum Mark: String {
        case done = "✓"
        case attention = "!"
        case unknown = "–"
    }

    enum Action: Equatable {
        case enableTracker
        case openLoginItems
        case openSettings(anchor: String)
        /// "Show <name> in Finder": reveals that bundle.
        case showInFinder(name: String, url: URL)
        case restartTracker
        case openAtLogin
        case copySnippet(String)
        case noAction

        /// The button title.
        var title: String {
            switch self {
            case .enableTracker: "Enable Tracker"
            case .openLoginItems: "Open Login Items"
            case .openSettings: "Open System Settings"
            case let .showInFinder(name, _): "Show \(name) in Finder"
            case .restartTracker: "Restart Tracker"
            case .openAtLogin: "Open at Login"
            case .copySnippet: "Copy Snippet"
            case .noAction: ""
            }
        }

        /// The last part of the button's accessibility identifier,
        /// `tracker.action.<step>.<suffix>`.
        var identifierSuffix: String {
            switch self {
            case .enableTracker: "enable"
            case .openLoginItems: "loginItems"
            case .openSettings: "settings"
            case .showInFinder: "finder"
            case .restartTracker: "restart"
            case .openAtLogin: "openAtLogin"
            case .copySnippet: "copy"
            case .noAction: "none"
            }
        }
    }

    var id: String
    var title: String
    var enables: String
    var mark: Mark
    var actions: [Action]
    /// Numbered steps, shown while the step is not done.
    var guidance: [String] = []
    /// Why the grant goes to this bundle.
    var note = ""
}

/// The tracker's status, read every 30 s, at wake, unlock, and launch, and
/// every 5 s while the Tracker pane is visible.
@Observable
final class TrackerStatusModel {
    @ObservationIgnored let agent: AgentService
    @ObservationIgnored let loginItem: AppLoginItemService
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

    init(
        agent: AgentService,
        loginItem: AppLoginItemService = FakeAppLoginItem(),
        clock: any Clock,
        readState: @escaping () async -> TrackerState?,
        bundles: TrackerBundles = .main
    ) {
        self.agent = agent
        self.loginItem = loginItem
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

    /// The setup checklist of §7.4.
    var setupSteps: [TrackerSetupStep] {
        let registered = registration == .enabled
        return [
            TrackerSetupStep(
                id: "background",
                title: "Background tracker (required)",
                enables: "Recording / nothing",
                mark: registered ? .done : .attention,
                actions: [registration == .requiresApproval ? .openLoginItems : registered ? .noAction : .enableTracker]
            ),
            openAtLoginStep,
            accessibilityStep,
            automationStep,
            fullDiskAccessStep,
            step("icloud", "iCloud Drive", "Activity on iPhone and iPad / this Mac only", ["shared_folder"], [.noAction]),
            step("editor", "Editor title (optional)", "Exact file / RPC, arguments, cwd", ["editor"], [
                .copySnippet(TrackerSnippets.editor),
            ]),
            step("tmux", "tmux hooks (optional)", "Exact switch times / next tick", ["tmux_events"], [
                .copySnippet(TrackerSnippets.tmux),
            ]),
            step("agentHooks", "Agent hooks (optional)", "Exact agent start and stop / next tick", ["agent_events"], [
                .copySnippet(TrackerSnippets.agentHooks),
            ]),
        ]
    }

    /// The app's own login item; the tracker records without it.
    private var openAtLoginStep: TrackerSetupStep {
        let action: TrackerSetupStep.Action = switch appLoginItem {
        case .enabled: .noAction
        case .requiresApproval: .openLoginItems
        case .notRegistered, .notFound: .openAtLogin
        }
        return TrackerSetupStep(
            id: "openAtLogin",
            title: "Open \(bundles.appName) at login",
            enables: "Timer and menu bar after you log in / open it yourself",
            mark: appLoginItem == .enabled ? .done : .attention,
            actions: [action],
            note: "The tracker records either way; it starts at login on its own."
        )
    }

    /// Accessibility is checked for the agent process itself.
    private var accessibilityStep: TrackerSetupStep {
        let agent = bundles.agentName
        var result = step("accessibility", "Accessibility (required)", "Titles, documents, URLs / app names", ["window"], [
            .openSettings(anchor: "Privacy_Accessibility"),
            .showInFinder(name: agent, url: bundles.agentOrFolder),
        ])
        result.guidance = [
            "Open System Settings › Privacy & Security › Accessibility.",
            "Drag \(agent) from the Finder window into the list.",
            "Turn \(agent) on.",
        ]
        result.note = "Accessibility belongs to \(agent), the tracker itself, which reads the window titles."
        return result
    }

    /// Automation is asked for at first use, once per browser and terminal.
    private var automationStep: TrackerSetupStep {
        var result = step("automation", "Automation", "Exact tabs and panes / guesses", ["browser", "terminal"], [
            .openSettings(anchor: "Privacy_Automation"),
        ])
        result.guidance = [
            "When macOS asks to allow control of Safari, another browser, or a terminal, click Allow.",
            "If you declined: open System Settings › Privacy & Security › Automation.",
            "Under \(bundles.appName) (or \(bundles.agentName)), turn on each browser and terminal.",
        ]
        result.note = "macOS asks once per app, the first time the tracker reads its tab or pane."
        return result
    }

    /// Full Disk Access is checked for the app: the agent runs on its behalf.
    private var fullDiskAccessStep: TrackerSetupStep {
        let app = bundles.appName
        var result = step(
            "fullDisk",
            "Full Disk Access (optional)",
            "Safari history, backfill / Safari domains",
            ["history", "knowledge"],
            [
                .openSettings(anchor: "Privacy_AllFiles"),
                .showInFinder(name: app, url: bundles.app),
            ]
        )
        result.guidance = [
            "Open System Settings › Privacy & Security › Full Disk Access.",
            "Drag \(app) from the Finder window into the list, or click + and choose it.",
            "Turn \(app) on.",
        ]
        // A grant reached the running agent only after a restart.
        if registration == .enabled, result.mark != .done {
            result.actions.append(.restartTracker)
            result.guidance.append("Click Restart Tracker, so the running tracker gets the access.")
        }
        result.note = "The tracker runs on behalf of \(app), so macOS checks \(app)'s Full Disk Access, not \(bundles.agentName)'s."
        return result
    }

    private func step(
        _ id: String,
        _ title: String,
        _ enables: String,
        _ sources: [String],
        _ actions: [TrackerSetupStep.Action]
    ) -> TrackerSetupStep {
        let statuses = sources.compactMap { source in state?.health.sources.first { $0.id == source }?.status }
        let mark: TrackerSetupStep.Mark = if statuses.isEmpty {
            .unknown
        } else if statuses.allSatisfy({ $0 == .active }) {
            .done
        } else {
            .attention
        }
        return TrackerSetupStep(id: id, title: title, enables: enables, mark: mark, actions: actions)
    }
}

/// The snippets of the setup steps.
enum TrackerSnippets {
    static let editor = "set title titlestring=nvim\\ %F"

    static let tmux = """
    set-hook -g client-session-changed 'run-shell -b "tracker-event tmux"'
    set-hook -g after-select-window 'run-shell -b "tracker-event tmux"'
    set-hook -g after-select-pane 'run-shell -b "tracker-event tmux"'
    set-hook -g pane-focus-in 'run-shell -b "tracker-event tmux"'
    """

    static let agentHooks = """
    {
      "hooks": {
        "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "tracker-event agent busy"}]}],
        "Stop": [{"hooks": [{"type": "command", "command": "tracker-event agent idle"}]}],
        "SessionEnd": [{"hooks": [{"type": "command", "command": "tracker-event agent end"}]}]
      }
    }
    """
}
