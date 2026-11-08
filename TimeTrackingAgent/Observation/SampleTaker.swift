// SampleTaker: one live Sample of the Mac: presence, the front app's Item,
// background Items, and their workspaces (activity_tracking.md §2.4, §3).

import Foundation
import TimeTrackingCore

/// Takes the live Samples of the local activity loop, keeps the presence
/// between them, and reports what it found of each source.
@MainActor
final class SampleTaker {
    /// How recent a pushed event must be for its source to be `active` (§3.1).
    static let eventSourceWindow: TimeInterval = 7 * 86_400

    let environment: AgentEnvironment
    let macDeviceID: String
    private(set) var presence: PresenceTracker
    let terminal: TerminalObserver
    let browser: BrowserObserver
    let workspaces: WorkspaceResolver
    /// When a `tmux` or `agent` event last arrived through the socket.
    var lastEvents: [SourceID: Date] = [:]

    init(environment: AgentEnvironment, macDeviceID: String, settings: TrackerSettings) {
        self.environment = environment
        self.macDeviceID = macDeviceID
        self.presence = PresenceTracker(start: environment.clock.now)
        self.terminal = TerminalObserver(environment: environment)
        self.browser = BrowserObserver(environment: environment)
        self.workspaces = WorkspaceResolver(environment: environment, settings: settings.workspaces)
    }

    /// Records a lock, sleep, wake, or user switch at its time, so the
    /// presence's `since` is the event's time, not the tick's.
    func handle(_ event: PresenceEvent, at time: Date) {
        _ = presence.apply(event, at: time)
    }

    /// The live Sample at the current time, with exclusions not yet
    /// applied beyond those only the live tracker can apply (tmux sessions,
    /// coding agent folders, excluded sites), and the sources' status.
    func take(settings: TrackerSettings) async -> (sample: Sample, reports: [SourceReport]) {
        let exclusions = settings.exclusions(homeDirectory: environment.homeDirectory)
        let snapshot = await TerminalSnapshot.read(environment: environment)
        var front: FrontObservation?
        var reports: [SourceReport] = []
        if presence.blockedState(environment.presence.read()) == nil {
            front = await observeFront(snapshot: snapshot, settings: settings, exclusions: exclusions)
            reports += front?.health ?? []
        }
        // Time and presence after the awaits, so a lock or sleep handled
        // meanwhile isn't overwritten by an older reading.
        let now = environment.clock.now
        let reading = environment.presence.read()
        // After the front pane, so a remote shell's report counts at once.
        reports += eventHealth(snapshot: snapshot, now: now)
        let passive = front
            .map { PresenceTracker.isPassive(bundleID: $0.bundleID, domain: $0.domain, settings: settings.presence) } ?? false
        let state = presence.update(reading: reading, now: now, passiveCandidate: passive, settings: settings.presence)
        let attentive = state.isAttentive ? front?.item.map { withWorkspace($0, settings: settings) } : nil
        // Background work is recorded while the user is away too, not while the Mac sleeps.
        let background = state == .asleep ? [] : terminal.background(
            snapshot: snapshot,
            focusedPane: attentive == nil ? "" : front?.paneTarget ?? "",
            now: now,
            settings: settings,
            exclusions: exclusions
        ).map { withWorkspace($0, settings: settings) }
        let sample = Sample(time: now, deviceID: macDeviceID, source: .live, state: state, foreground: attentive, background: background)
        return (sample, reports)
    }

    // MARK: The front app

    private func observeFront(
        snapshot: TerminalSnapshot,
        settings: TrackerSettings,
        exclusions: ExclusionRules
    ) async -> FrontObservation? {
        guard let app = environment.focus.frontmostApp() else {
            return nil
        }
        if exclusions.excludesApp(app.bundleID) {
            return FrontObservation(item: nil, bundleID: app.bundleID)
        }
        guard environment.focus.isTrusted else {
            var observation = FrontObservation(item: ActivityItem(app: app.name, appID: app.bundleID), bundleID: app.bundleID)
            observation.health.append(SourceReport(.window, .fallback, "Accessibility is off; only app names are recorded"))
            return observation
        }
        let window = environment.focus.focusedWindow(of: app)
        var observation: FrontObservation = if TerminalApp.known[app.bundleID] != nil {
            await terminal.observe(app: app, title: window?.title ?? "", snapshot: snapshot, settings: settings, exclusions: exclusions)
        } else if BrowserApp.known[app.bundleID] != nil {
            browser.observe(app: app, window: window, exclusions: exclusions)
        } else {
            FrontObservation(item: AppObserver(environment: environment).observe(app: app, window: window), bundleID: app.bundleID)
        }
        observation.health.insert(SourceReport(.window, .active), at: 0)
        return observation
    }

    private func withWorkspace(_ item: ActivityItem, settings: TrackerSettings) -> ActivityItem {
        guard item.workspace != ActivityItem.privateWorkspace else {
            return item
        }
        var result = item
        result.workspace = workspaces.workspace(of: item, settings: settings.workspaces, ports: terminal.ports)
        return result
    }

    // MARK: Health

    /// Coding agents, and the hook and remote shell sources, which are
    /// `active` when they reported in the last 7 days.
    private func eventHealth(snapshot: TerminalSnapshot, now: Date) -> [SourceReport] {
        var reports = [
            snapshot.sessions == nil
                ? SourceReport(.agents, .fallback, "Claude Code not found; when it is working can't be told")
                : SourceReport(.agents, .active),
        ]
        func report(_ id: SourceID, last: Date?, otherwise reason: String) {
            let recent = last.map { now.timeIntervalSince($0) < Self.eventSourceWindow } ?? false
            reports.append(recent ? SourceReport(id, .active) : SourceReport(id, .fallback, reason))
        }
        report(
            .tmuxEvents,
            last: lastEvents[.tmuxEvents],
            otherwise: "No tmux hook event in the last 7 days; switches are noticed up to 30 seconds late"
        )
        report(
            .agentEvents,
            last: lastEvents[.agentEvents],
            otherwise: "No Claude Code hook event in the last 7 days; changes are noticed up to 30 seconds late"
        )
        report(
            .remoteShell,
            last: terminal.lastRemoteReport,
            otherwise: "No remote shell reported its folder in the last 7 days; work over ssh is recorded by host only"
        )
        return reports
    }
}
