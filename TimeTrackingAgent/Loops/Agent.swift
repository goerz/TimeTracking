// Agent: the tracker's loops over its store and files: the local and
// remote activity loops, the request handler, and the rebuild loop
// (activity_tracking.md §2.1, §2.4 to §2.7, §5).

import Foundation
import os
import TimeTrackingCore

/// The tracker. `AgentRunner` wires it to the system: a timer that calls
/// `runDueWork()` every second, the socket, and the presence events;
/// tests drive it directly under a `ManualClock`.
@MainActor
final class Agent {
    /// A live Sample every 30 seconds (§2.4).
    nonisolated static let tickInterval: TimeInterval = 30
    /// The time the agent didn't run is filled every 15 minutes (§2.4).
    nonisolated static let gapFillInterval: TimeInterval = 15 * 60
    /// DeviceEvents are fetched every 5 minutes (§2.5).
    nonisolated static let remoteInterval: TimeInterval = 5 * 60
    /// How long the rebuild loop waits after a date file couldn't be written.
    nonisolated static let rebuildBackoff: TimeInterval = 60

    let environment: AgentEnvironment
    let configuration: AgentConfiguration
    let store: SampleStore
    let choice: SharedFolderChoice
    var monitor: SettingsMonitor
    let taker: SampleTaker
    let current: CurrentStateWriter
    var deviceEvents: (any DeviceEventSource)?
    var recorder: Recorder?
    /// The status of every source, for `current.json` (§3.5).
    var health = SourceHealthBoard()
    /// Weak references: a queue task may outlive the agent (a test's).
    private(set) lazy var queue = StepQueue(
        tick: { [weak self] in await self?.tick() },
        tickIsDue: { [weak self] in
            guard let self else {
                return false
            }
            return schedule.isDue(at: environment.clock.now)
        },
        rebuild: { [weak self] in self?.rebuildPass() ?? false }
    )
    private var schedule: TickSchedule
    /// Whether this Mac writes the date files (§4.1, `blocks/owner`);
    /// `nil` until the owner file was read once, and rebuild passes wait
    /// until then, so none unmarks a date it didn't write.
    private(set) var records: Bool? // swiftlint:disable:this discouraged_optional_boolean
    private var rebuildWaitsUntil: Date?
    /// Why the owner file couldn't be read last time, logged once.
    private var ownerProblem: String?
    /// When each cadenced step was last queued.
    var lastGapFill: Date?
    var lastDrop: Date?
    var lastFetch: Date?
    /// Whether a remote cycle runs; one at a time.
    var fetching = false
    let logger = Logging.logger(category: "Agent")

    init(environment: AgentEnvironment, configuration: AgentConfiguration, store: SampleStore? = nil) throws {
        self.environment = environment
        self.configuration = configuration
        let store = try store ?? SampleStore(url: configuration.samplesURL)
        self.store = store
        self.choice = SharedFolderChoice.choose(folders: configuration.folders, canWrite: configuration.canWriteShared)
        let monitor = try SettingsMonitor(url: choice.settingsURL, lastText: store.meta(.settingsText))
        self.monitor = monitor
        self.taker = SampleTaker(environment: environment, macDeviceID: configuration.macDeviceID, settings: monitor.settings)
        self.current = CurrentStateWriter(url: configuration.folders.currentStateURL)
        self.schedule = TickSchedule(start: environment.clock.now, interval: Self.tickInterval)
        health.set(.sharedFolder, choice.status, choice.reason)
        health.set(.deviceEvents, .fallback, "Checking…")
    }

    var settings: TrackerSettings {
        monitor.settings
    }

    var rules: SampleRules {
        SampleRules(
            exclusions: settings.exclusions(homeDirectory: environment.homeDirectory),
            zone: environment.timeZone,
            maxPassiveBlock: settings.blocks.maxPassiveBlock
        )
    }

    var redactor: Redactor {
        Redactor(privacy: settings.privacy)
    }

    var today: TrackingDay {
        (try? store.boundaries(rules: rules))?.day(containing: environment.clock.now)
            ?? TrackingDay(ActivityTimestamp.day(environment.clock.now, timeZone: environment.timeZone)) ?? TrackingDay(
                year: 1970,
                month: 1,
                day: 1
            )
    }

    // MARK: Start

    /// Records the first start, starts filling gaps after a disable or the
    /// first start, learns the repositories among the stored workspaces,
    /// marks the dates whose file has an older header, and queues the
    /// device-dates left pending.
    func start() throws {
        try store.recordFirstStart(today: today)
        let disabled = configuration.disabledURL
        let wasDisabled = FileManager.default.fileExists(atPath: disabled.path)
        let firstStart = try store.meta(.fillAfter) == nil
        if wasDisabled || firstStart {
            try store.setMeta(.fillAfter, environment.clock.now)
            try? FileManager.default.removeItem(at: disabled)
        }
        try taker.workspaces.learn(store.workspaces())
        try markOutdatedFiles()
        queuePendingRedos()
    }

    /// Marks the unfrozen dates whose file doesn't start with the current
    /// header, so the rebuild loop writes them in the current format.
    private func markOutdatedFiles() throws {
        let cutoff = try store.meta(.cutoffDay)
        let outdated = choice.log.days().filter { day in
            guard cutoff.map({ day >= $0 }) ?? true, case let .text(text) = choice.log.content(for: day) else {
                return false
            }
            return !BlockLogFile.hasCurrentHeader(text)
        }
        try store.mark(Set(outdated), rules: rules)
    }

    // MARK: Cadence

    /// Queues the cadenced steps that are due (the gap fill every 15
    /// minutes, the daily drop, the remote cycle every 5 minutes) and
    /// wakes the queue for a due tick.
    func runDueWork() {
        let now = environment.clock.now
        if Self.isDue(lastGapFill, every: Self.gapFillInterval, at: now) {
            lastGapFill = now
            queue.enqueue("fill-gaps") { [self] in
                do {
                    try fillGaps()
                } catch {
                    logger.error("app usage: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        if Self.isDue(lastDrop, every: 86_400, at: now) {
            lastDrop = now
            queue.enqueue("daily-drop") { [self] in dropOldData() }
        }
        if !fetching, Self.isDue(lastFetch, every: Self.remoteInterval, at: now) {
            lastFetch = now
            fetching = true
            Task { await fetchDeviceEvents() }
        }
        queue.wake()
    }

    private static func isDue(_ last: Date?, every interval: TimeInterval, at now: Date) -> Bool {
        last.map { now.timeIntervalSince($0) >= interval } ?? true
    }

    // MARK: The tick

    /// Reloads `settings.toml` and keeps its text for a restart while it can't be read.
    func reloadSettings() {
        monitor.reload()
        guard let text = monitor.text, (try? store.meta(.settingsText)) != text else {
            return
        }
        do {
            try store.setMeta(.settingsText, text)
        } catch {
            logger.error("settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// One pass of the local activity loop: a live Sample, `current.json`,
    /// the arrived placeholders, and whether this Mac records.
    func tick() async {
        reloadSettings()
        let now = environment.clock.now
        if schedule.isDue(at: now) {
            schedule.fired(at: now)
        }
        let (sample, reports) = await taker.take(settings: settings)
        for report in reports {
            health.set(report.id, report.status, report.reason)
        }
        do {
            try store.insert([sample], rules: rules)
            try RebuildLoop(store: store, log: choice.log).recheckPlaceholders()
        } catch {
            logger.error("tick: \(error.localizedDescription, privacy: .public)")
        }
        recorder?.record(sample)
        updateOwnership()
        current.update(
            foreground: sample.foreground,
            presence: TrackerPresence(state: taker.presence.state, since: taker.presence.since, lastInput: taker.presence.lastInput),
            health: TrackerHealth(lastTick: sample.time, version: configuration.version, sources: health.listed(settings: settings)),
            rules: rules,
            redactor: redactor
        )
    }

    /// Whether this Mac writes the date files: it owns `blocks/owner`, or
    /// claims it while no Mac does. A Mac that doesn't record keeps taking
    /// Samples and reports `shared_folder` off. A Mac that starts recording
    /// marks every date, since another Mac may have written them. While the
    /// owner file can't be read, the last decision stands.
    private func updateOwnership() {
        let records: Bool
        do {
            records = try BlockLogOwner.mayWrite(choice.ownerLog, deviceID: configuration.macDeviceID, claiming: choice.canClaim)
            self.records = records
            ownerProblem = nil
        } catch {
            // Once per problem, not at every tick.
            if ownerProblem != error.localizedDescription {
                ownerProblem = error.localizedDescription
                logger.error("owner file: \(error.localizedDescription, privacy: .public)")
            }
            return
        }
        if records {
            health.set(.sharedFolder, choice.status, choice.reason)
        } else {
            health.set(.sharedFolder, .off, BlockLogOwner.otherMacReason)
        }
        do {
            guard try store.meta(.recording) != records else {
                return
            }
            if records {
                try store.mark(store.days(rules: rules), rules: rules)
            }
            try store.setMeta(.recording, records)
        } catch {
            logger.error("ownership: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: The rebuild loop

    var rebuildContext: RebuildContext {
        RebuildContext(
            settings: settings.blocks,
            rules: rules,
            macDeviceID: configuration.macDeviceID,
            macName: configuration.macName,
            redactor: redactor
        )
    }

    /// One pass; `false` when no date waits or the loop waits after a failure.
    func rebuildPass() -> Bool {
        let now = environment.clock.now
        if let until = rebuildWaitsUntil, now < until {
            return false
        }
        guard let records else {
            return false
        }
        do {
            guard let result = try RebuildLoop(store: store, log: records ? choice.log : nil).runOnePass(now: now, context: rebuildContext)
            else {
                return false
            }
            switch result {
            case let .formed(_, _, .set(block)):
                current.update(block: block, zone: environment.timeZone)
            case let .failed(day, reason):
                logger.error("date file \(day.description, privacy: .public): \(reason, privacy: .public)")
                rebuildWaitsUntil = now + Self.rebuildBackoff
            case .formed, .frozen, .waiting:
                break
            }
            return true
        } catch {
            logger.error("rebuild: \(error.localizedDescription, privacy: .public)")
            rebuildWaitsUntil = now + Self.rebuildBackoff
            return false
        }
    }
}
