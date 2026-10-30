// TrackerStatusModel: the tracker's registration and liveness for the Tracker
// pane and the menu bar warning (spec_activity_tracking.md §4.4, §7.4;
// spec_menubar.md §3).

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
        case copySnippet(String)
        case noAction
    }

    var id: String
    var title: String
    var enables: String
    var mark: Mark
    var actions: [Action]
}

/// The tracker's status, read every 30 s, at wake, unlock, and launch, and
/// every 5 s while the Tracker pane is visible.
@Observable
final class TrackerStatusModel {
    @ObservationIgnored let agent: AgentService
    @ObservationIgnored let clock: any Clock
    @ObservationIgnored let readState: () async -> TrackerState?

    private(set) var registration: AgentRegistration = .notRegistered
    private(set) var state: TrackerState?
    private(set) var warningActive = false
    /// Since when the Mac has been awake, unlocked, and in the session.
    private(set) var presentSince: Date?
    var confirmDisable = false
    private(set) var lastError: String?

    init(agent: AgentService, clock: any Clock, readState: @escaping () async -> TrackerState?) {
        self.agent = agent
        self.clock = clock
        self.readState = readState
        self.presentSince = clock.now
    }

    var liveness: TrackerLiveness {
        TrackerLiveness(registration: registration, state: state, now: clock.now)
    }

    /// Re-reads the registration and `current.json`.
    func refresh() async {
        registration = agent.registration
        state = await readState()
        warningActive = TrackerWarning.isActive(registration: registration, state: state, presentSince: presentSince, now: clock.now)
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
            step("accessibility", "Accessibility (required)", "Titles, documents, URLs / app names", ["window"], [
                .openSettings(anchor: "Privacy_Accessibility"),
            ]),
            step("automation", "Automation", "Exact tabs and panes / guesses", ["browser", "terminal"], [
                .openSettings(anchor: "Privacy_Automation"),
            ]),
            step("fullDisk", "Full Disk Access (optional)", "Safari history, backfill / Safari domains", ["history", "knowledge"], [
                .openSettings(anchor: "Privacy_AllFiles"),
            ]),
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
