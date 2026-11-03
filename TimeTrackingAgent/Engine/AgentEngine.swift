// AgentEngine: the tick, from presence through resolvers to samples,
// blocks, and current.json (spec_activity_tracking.md §2.4, §5).

import Foundation
import os
import TimeTrackingCore

/// The tracker. Every tick (and every presence event or pushed event)
/// takes a sample, appends it to `samples.sqlite`, forms today's blocks
/// again from everything stored for today (the user's timeline, §2.8),
/// rewrites today's lines of the block and detail logs when they changed,
/// and rewrites `current.json`.
/// Tests drive `tick()` and `handle(_:at:)` under a `ManualClock`.
@MainActor
final class AgentEngine {
    /// The tick interval of §2.1.
    nonisolated static let tickInterval: TimeInterval = 30
    /// How recent a pushed event must be for its source to be `active`.
    static let eventSourceWindow: TimeInterval = 7 * 86_400

    let environment: AgentEnvironment
    let configuration: AgentConfiguration
    let store: SampleStore
    private(set) var choice: SharedFolderChoice
    var monitor: SettingsMonitor
    var presence: PresenceTracker
    var logs: ActivityLogs
    var health = SourceHealthBoard()
    let terminal: TerminalResolver
    let browser: BrowserResolver
    var fileChanges = FileChangeLog()
    var syncedSafari = SyncedSafariCollector()
    /// The presence transitions of the last two days, for the detail log.
    var transitions: [ActivityPresenceTransition] = []
    /// Today's open block as of the last rebuild.
    var openBlock: TrackerOpenBlock?
    /// The day of the last rebuild of today, to close it after midnight.
    var rebuiltDay: String?
    /// The inputs of a day's timeline other than new samples, kept between ticks.
    var timelineCache: TimelineCache?
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
        self.logs = ActivityLogs(blocksFolder: choice.blocksFolder, folders: configuration.folders, device: configuration.device)
        self.terminal = TerminalResolver(environment: environment)
        self.browser = BrowserResolver(environment: environment)
        health.set(.sharedFolder, choice.status, choice.reason)
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
        reloadSettings()
        let now = environment.clock.now
        let reading = environment.presence.read()
        var context = resolveContext()
        let snapshot = await TerminalSnapshot.read(environment: environment)
        updateStaticHealth(snapshot: snapshot, now: now)
        var sample: Sample
        let before = presence.state
        if presence.blockedState(reading) != nil {
            let state = presence.update(reading: reading, now: now, passiveCandidate: false, settings: settings.presence)
            sample = Sample(time: now, state: state, secondaries: awayBackground(state, snapshot: snapshot, now: now, context: &context))
        } else {
            let focus = await resolveFocus(snapshot: snapshot, context: &context)
            let passive = focus
                .map { PresenceTracker.isPassive(bundleID: $0.bundleID, domain: $0.domain, settings: settings.presence) } ?? false
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
                sample = Sample(
                    time: now,
                    state: state,
                    secondaries: awayBackground(state, snapshot: snapshot, now: now, context: &context),
                    bundleID: focus?.bundleID ?? ""
                )
            }
        }
        if presence.state != before || transitions.isEmpty {
            transitions.append(ActivityPresenceTransition(time: presence.since, state: presence.state))
        }
        process(sample)
        runMaintenance(now: now)
        return sample
    }

    /// The background items of a sample without attention (§2.3 step 4):
    /// recorded while the user is away, but not while the Mac sleeps.
    private func awayBackground(
        _ state: TrackerPresenceState,
        snapshot: TerminalSnapshot,
        now: Date,
        context: inout ResolveContext
    ) -> [SampleItem] {
        guard state != .asleep else {
            return []
        }
        return terminal.secondaries(snapshot: snapshot, primary: nil, primaryTarget: "", now: now, context: &context)
    }

    /// Reloads `settings.toml` if it changed (§7: applied from the next tick).
    func reloadSettings() {
        if monitor.reload() {
            timelineCache = nil
        }
    }

    /// Stores a sample, forms today's blocks again, writes `current.json`.
    func process(_ sample: Sample) {
        let offset = environment.timeZone.secondsFromGMT(for: sample.time)
        do {
            try store.insert(sample, utcOffset: offset)
        } catch {
            logger.error("samples: \(error.localizedDescription, privacy: .public)")
        }
        recorder?.record(sample, utcOffset: offset)
        lastSample = sample
        timelineCache?.append(sample)
        rebuildToday()
        writeCurrentState()
    }

    /// Rewrites `current.json` from the open block, the last sample, presence, and health.
    func writeCurrentState() {
        let now = environment.clock.now
        let primary = lastSample.flatMap { $0.isAttentive ? $0.primary : nil }.map { item in
            TrackerPrimaryItem(context: item.context, subject: item.subject, detail: item.detail)
        }
        let state = TrackerState(
            device: configuration.device,
            openBlock: openBlock,
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
        var title = ""
        var tmuxTarget = ""
        var url = ""
        var domain: String?
    }

    /// Resolves the frontmost app's item (§2.4 steps 2 and 3, exclusions of §7.2).
    func resolveFocus(snapshot: TerminalSnapshot, context: inout ResolveContext) async -> Focus? {
        guard let app = environment.focus.frontmostApp() else {
            return nil
        }
        let exclusions = context.exclusions
        if exclusions.excludesApp(app.bundleID) {
            return Focus(item: nil, bundleID: "")
        }
        let contextName = AppResolver.contextName(app)
        let appOnly = SampleItem(context: contextName, subject: "", groupKey: contextName, app: app.bundleID)
        guard environment.focus.isTrusted else {
            health.set(.window, .fallback, "Accessibility is off; only app names are recorded")
            return Focus(item: appOnly, bundleID: app.bundleID)
        }
        health.set(.window, .active)
        if exclusions.isNameOnlyApp(app.bundleID) {
            return Focus(item: appOnly, bundleID: app.bundleID)
        }
        let window = environment.focus.focusedWindow(of: app)
        let title = context.filteredTitle(window?.title ?? "")
        if TerminalApp.known[app.bundleID] != nil {
            let observation = await terminal.resolve(app: app, title: title, snapshot: snapshot, context: &context)
            apply(observation.health)
            return Focus(
                item: observation.item,
                bundleID: app.bundleID,
                title: Self.debugTitle(title, item: observation.item, exclusions: exclusions),
                tmuxTarget: observation.tmuxTarget
            )
        }
        if BrowserApp.known[app.bundleID] != nil {
            let observation = browser.resolve(app: app, window: window, ports: terminal.ports, context: &context)
            apply(observation.health)
            return Focus(
                item: observation.item,
                bundleID: app.bundleID,
                title: Self.debugTitle(observation.title, item: observation.item, exclusions: exclusions),
                url: observation.url,
                domain: observation.domain
            )
        }
        let item = AppResolver(environment: environment).resolve(app: app, window: window, context: &context)
        return Focus(item: item, bundleID: app.bundleID, title: Self.debugTitle(title, item: item, exclusions: exclusions))
    }

    /// The window title kept as a debug field: none for a hidden item or
    /// a title naming an excluded path.
    static func debugTitle(_ title: String, item: SampleItem, exclusions: ExclusionRules) -> String {
        let marker = ExclusionRules.privateMarker
        if item.context.contains(marker) || item.subject.contains(marker) || item.detail.contains(marker) {
            return ""
        }
        let paths = title.split(separator: " ").filter { $0.hasPrefix("/") || $0.hasPrefix("~") || $0.hasPrefix("file://") }
        return paths.contains { exclusions.excludesPath(String($0)) } ? "" : title
    }
}
