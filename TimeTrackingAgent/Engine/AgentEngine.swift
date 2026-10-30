// AgentEngine: the tick, from presence through resolvers to samples,
// blocks, and current.json (spec_activity_tracking.md §2.4, §5).

import Foundation
import os
import TimeTrackingCore

/// The tracker. Every tick (and every presence event or pushed event)
/// takes a sample, appends it to `samples.sqlite`, runs the Blocker, writes
/// closed blocks to the block and detail logs, and rewrites `current.json`.
/// Tests drive `tick()` and `handle(_:at:)` under a `ManualClock`.
@MainActor
final class AgentEngine {
    /// The tick interval of §2.1.
    static let tickInterval: TimeInterval = 30
    /// How recent a pushed event must be for its source to be `active`.
    static let eventSourceWindow: TimeInterval = 7 * 86400

    let environment: AgentEnvironment
    let configuration: AgentConfiguration
    let store: SampleStore
    private(set) var choice: SharedFolderChoice
    var monitor: SettingsMonitor
    var presence: PresenceTracker
    var blocker: Blocker
    var logs: ActivityLogs
    var health = SourceHealthBoard()
    let terminal: TerminalResolver
    let browser: BrowserResolver
    var fileChanges = FileChangeLog()
    var syncedSafari = SyncedSafariCollector()
    /// Presence transitions not yet written to a detail line.
    var transitions: [ActivityPresenceTransition] = []
    /// The end of the last block written to the detail log.
    var lastDetailEnd: Date?
    private(set) var lastSample: Sample?
    var recorder: Recorder?
    var deviceEvents: (any DeviceEventSource)?
    var lastMaintenance: [String: Date] = [:]
    let logger = Logging.logger(category: "Agent")

    var settings: TrackerSettings {
        monitor.settings
    }

    init(environment: AgentEnvironment, configuration: AgentConfiguration, store: SampleStore? = nil) throws {
        self.environment = environment
        self.configuration = configuration
        self.store = try store ?? SampleStore(url: configuration.samplesURL)
        let choice = SharedFolderChoice.choose(folders: configuration.folders, canWrite: configuration.canWriteShared)
        self.choice = choice
        self.monitor = SettingsMonitor(url: choice.settingsURL)
        let now = environment.clock.now
        self.presence = PresenceTracker(start: now)
        self.blocker = Blocker(settings: monitor.settings.blocks, timeZone: environment.timeZone, device: configuration.device)
        self.logs = ActivityLogs(blocksFolder: choice.blocksFolder, localFolder: configuration.folders.local, device: configuration.device)
        self.terminal = TerminalResolver(environment: environment)
        self.browser = BrowserResolver(environment: environment)
        health.set("shared_folder", choice.status, choice.reason)
        terminal.recentFile = { [weak self] folder in
            guard let self else {
                return nil
            }
            return fileChanges.recentFile(
                under: folder,
                since: environment.clock.now.addingTimeInterval(-Self.tickInterval),
                context: resolveContext()
            )
        }
    }

    // MARK: The tick

    /// Takes one sample now and processes it; returns the sample.
    @discardableResult
    func tick() async -> Sample {
        if monitor.reload() {
            blocker.settings = settings.blocks
        }
        let now = environment.clock.now
        let reading = environment.presence.read()
        var context = resolveContext()
        let snapshot = await TerminalSnapshot.read(environment: environment, settings: settings)
        updateStaticHealth(snapshot: snapshot, now: now)
        var sample: Sample
        let before = presence.state
        if presence.blockedState(reading) != nil {
            let state = presence.update(reading: reading, now: now, passiveCandidate: false, settings: settings.presence)
            sample = Sample(time: now, state: state)
        } else {
            let focus = await resolveFocus(snapshot: snapshot, context: &context)
            let passive = focus.map { PresenceTracker.isPassive(bundleID: $0.bundleID, domain: $0.domain, settings: settings.presence) } ?? false
            let state = presence.update(reading: reading, now: now, passiveCandidate: passive, settings: settings.presence)
            if let focus, state == .active || state == .passive {
                let secondaries = terminal.secondaries(
                    snapshot: snapshot,
                    primary: focus.item,
                    primaryTarget: focus.tmuxTarget,
                    now: now,
                    context: &context
                )
                sample = Sample(
                    time: now,
                    state: state,
                    primary: focus.item,
                    secondaries: secondaries,
                    bundleID: focus.bundleID,
                    title: focus.title,
                    tmuxTarget: focus.tmuxTarget,
                    url: focus.url
                )
            } else {
                sample = Sample(time: now, state: state, bundleID: focus?.bundleID ?? "")
            }
        }
        if presence.state != before || transitions.isEmpty {
            transitions.append(ActivityPresenceTransition(time: presence.since, state: presence.state))
        }
        process(sample)
        await runMaintenance(now: now)
        return sample
    }

    /// Stores a sample, runs the Blocker, writes closed blocks and `current.json`.
    func process(_ sample: Sample) {
        let offset = environment.timeZone.secondsFromGMT(for: sample.time)
        do {
            try store.insert(sample, utcOffset: offset)
        } catch {
            logger.error("samples: \(error.localizedDescription, privacy: .public)")
        }
        recorder?.record(sample, utcOffset: offset, device: configuration.device)
        lastSample = sample
        for closed in blocker.add(sample) {
            write(closed)
        }
        writeCurrentState()
    }

    /// Appends a closed block and its detail to the logs.
    func write(_ closed: ClosedBlock) {
        let detail = detail(for: closed)
        do {
            try logs.append(closed, detail: detail)
        } catch {
            logger.error("block log: \(error.localizedDescription, privacy: .public)")
        }
        lastDetailEnd = closed.block.end
        // The state in effect at the end stays: it opens the next gap.
        let current = transitions.last { $0.time < closed.block.end }
        transitions.removeAll { $0.time < closed.block.end }
        if let current {
            transitions.insert(current, at: 0)
        }
    }

    /// Rewrites `current.json` from the open block, the last sample, presence, and health.
    func writeCurrentState() {
        let now = environment.clock.now
        let primary = lastSample.flatMap { $0.isAttentive ? $0.primary : nil }.map {
            TrackerPrimaryItem(context: $0.context, subject: $0.subject, detail: $0.detail)
        }
        let state = TrackerState(
            device: configuration.device,
            openBlock: blocker.openSummary,
            primary: primary,
            presence: TrackerPresence(state: presence.state, since: presence.since, lastInput: presence.lastInput),
            health: TrackerHealth(lastTick: lastSample?.time ?? now, version: configuration.version, sources: health.all)
        )
        do {
            try logs.writeCurrentState(state, timeZone: environment.timeZone)
        } catch {
            logger.error("current.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The resolve context of the current settings.
    func resolveContext() -> ResolveContext {
        ResolveContext(settings: settings, homeDirectory: environment.homeDirectory, files: environment.files)
    }

    // MARK: Focus

    /// The resolved frontmost item.
    struct Focus {
        var item: SampleItem?
        var bundleID: String
        var title: String
        var tmuxTarget: String
        var url: String
        var domain: String?
    }

    /// Resolves the frontmost app's item (§2.4 steps 2 and 3, exclusions of §7.2).
    func resolveFocus(snapshot: TerminalSnapshot, context: inout ResolveContext) async -> Focus? {
        guard let app = environment.focus.frontmostApp() else {
            return nil
        }
        let exclusions = context.exclusions
        if exclusions.excludesApp(app.bundleID) {
            return Focus(item: nil, bundleID: "", title: "", tmuxTarget: "", url: "", domain: nil)
        }
        let contextName = AppResolver.contextName(app)
        let appOnly = SampleItem(context: contextName, subject: "", groupKey: contextName, app: app.bundleID)
        guard environment.focus.isTrusted else {
            health.set("window", .fallback, "Accessibility not granted; app names only")
            return Focus(item: appOnly, bundleID: app.bundleID, title: "", tmuxTarget: "", url: "", domain: nil)
        }
        health.set("window", .active)
        if exclusions.isNameOnlyApp(app.bundleID) {
            return Focus(item: appOnly, bundleID: app.bundleID, title: "", tmuxTarget: "", url: "", domain: nil)
        }
        let window = environment.focus.focusedWindow(of: app)
        let title = context.filteredTitle(window?.title ?? "")
        if TerminalApp.known[app.bundleID] != nil {
            let observation = await terminal.resolve(app: app, title: title, snapshot: snapshot, context: &context)
            apply(observation.health)
            return Focus(item: observation.item, bundleID: app.bundleID, title: title, tmuxTarget: observation.tmuxTarget, url: "", domain: nil)
        }
        if BrowserApp.known[app.bundleID] != nil {
            let observation = browser.resolve(app: app, window: window, ports: terminal.ports, context: &context)
            apply(observation.health)
            return Focus(
                item: observation.item,
                bundleID: app.bundleID,
                title: observation.title,
                tmuxTarget: "",
                url: observation.url,
                domain: observation.domain
            )
        }
        let item = AppResolver(environment: environment).resolve(app: app, window: window, context: &context)
        return Focus(item: item, bundleID: app.bundleID, title: title, tmuxTarget: "", url: "", domain: nil)
    }

    func apply(_ entries: [(id: String, status: TrackerSourceStatus, reason: String)]) {
        for entry in entries {
            health.set(entry.id, entry.status, entry.reason)
        }
    }

    /// Health of the sources checked at every tick.
    private func updateStaticHealth(snapshot: TerminalSnapshot, now: Date) {
        if snapshot.sessions == nil {
            health.set("agents", .fallback, "No Claude Code sessions folder; busy state unknown")
        } else {
            health.set("agents", .active)
        }
        for (id, key, reason) in [
            ("tmux_events", "event.tmux", "No tmux hook event in the last 7 days; the tick alone"),
            ("agent_events", "event.agent", "No agent hook event in the last 7 days; the tick alone"),
        ] {
            let seen = (try? store.date(key)) ?? nil
            if let seen, now.timeIntervalSince(seen) < Self.eventSourceWindow {
                health.set(id, .active)
            } else {
                health.set(id, .fallback, reason)
            }
        }
        if environment.history.canReadSafari {
            health.set("history", .active)
        } else {
            health.set("history", .fallback, "Full Disk Access not granted; Safari URLs keep only the domain")
        }
        let roots = settings.files.roots.map { resolveContext().expand($0) }
        if roots.contains(where: environment.files.exists) {
            health.set("files", .active)
        } else {
            health.set("files", .off, "No watched folder exists")
        }
        if !settings.devices.syncedSafariHistory {
            health.set("synced_safari", .off, "Turned off in the settings")
        } else if !environment.history.canReadSafari {
            health.set("synced_safari", .off, "Full Disk Access not granted")
        } else {
            health.set("synced_safari", .active)
        }
    }
}
