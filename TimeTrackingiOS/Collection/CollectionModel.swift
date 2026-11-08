// CollectionModel: the iOS app's side of the activity collection: the
// master switch, Screen Time authorization, app sets, the flush, and the
// app's own lines (ios.md §2.9, §9, §11 item 3).

import Foundation
import Observation
import os
import TimeTrackingCore

/// Screen Time (Family Controls) authorization as the collection uses it.
enum ScreenTimeStatus: Equatable {
    case notDetermined
    case denied
    case approved
}

/// Where the scene is, for the app's own lines.
enum ScenePlace {
    case foreground
    case background
}

/// Family Controls authorization and the event cap measurement; the live
/// one wraps `AuthorizationCenter` and `DeviceActivityCenter`, tests fake it.
@MainActor
protocol ScreenTimeAuthorizing: AnyObject {
    var status: ScreenTimeStatus { get }
    /// Asks for individual authorization (from the collection screen only).
    func request() async -> ScreenTimeStatus
    /// The largest number of events `startMonitoring` accepts (phase 7).
    func measureCap() -> Int
}

/// Owns the App Group staging file and drives Screen Time; the extensions
/// append to the same file through `CollectionLog`.
@Observable
final class CollectionModel: CollectionFlushing {
    @ObservationIgnored let log: CollectionLog
    @ObservationIgnored let staging: DeviceEventStagingFile
    @ObservationIgnored let shared: WidgetSharedState
    @ObservationIgnored let authorization: ScreenTimeAuthorizing
    @ObservationIgnored let controller: ScreenTimeController
    /// The activity folders, resolved off the main actor (the ubiquity
    /// lookup can block); `nil` skips the settings copy.
    @ObservationIgnored let folders: @Sendable () -> ActivityFolders?
    /// Whether to flush every 5 minutes while in the foreground (live only).
    @ObservationIgnored var flushesPeriodically = false
    @ObservationIgnored private var periodicTask: Task<Void, Never>?
    /// The flush in progress; a second caller waits for it instead of
    /// starting another (the staging file is safe either way, IOS-27).
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    /// The last transition logged; `nil` before the first.
    @ObservationIgnored private var lastTransition: ScenePlace?
    @ObservationIgnored private let logger = Logging.logger(category: "Collection")

    private(set) var isEnabled: Bool
    private(set) var screenTime: ScreenTimeStatus
    private(set) var sets: [ScreenTimeSet]
    private(set) var lastFlushAt: Date?
    private(set) var pendingCount = 0
    private(set) var flushError: String?
    private(set) var screenTimeError: String?
    /// The exclusions of the App Group copy of `settings.toml` (Privacy section).
    private(set) var privacy = TrackerPrivacySettings()

    init(
        log: CollectionLog,
        staging: DeviceEventStagingFile,
        shared: WidgetSharedState,
        authorization: ScreenTimeAuthorizing,
        monitor: any ScreenTimeMonitoring,
        folders: @escaping @Sendable () -> ActivityFolders?
    ) {
        self.log = log
        self.staging = staging
        self.shared = shared
        self.authorization = authorization
        self.controller = ScreenTimeController(store: log.state, monitor: monitor, log: log)
        self.folders = folders
        self.isEnabled = log.state.isEnabled
        self.screenTime = authorization.status
        self.sets = log.state.screenTimeSets
        self.lastFlushAt = shared.lastFlushAt
        refresh()
    }

    var state: CollectionSharedState {
        log.state
    }

    /// Re-reads the shared values and the staging file.
    func refresh() {
        isEnabled = state.isEnabled
        screenTime = authorization.status
        sets = state.screenTimeSets
        lastFlushAt = shared.lastFlushAt
        pendingCount = (try? staging.readAll().count) ?? 0
    }

    // MARK: Switch, authorization, sets

    /// The master switch: on registers the Screen Time when Screen Time allows
    /// it (the other collectors need nothing); off stops it.
    func setEnabled(_ enabled: Bool) {
        state.isEnabled = enabled
        isEnabled = enabled
        if enabled {
            configureScreenTime()
        } else {
            controller.stopAll()
        }
    }

    /// The "Allow Screen Time Access" button; never called at launch.
    func requestAuthorization() async {
        screenTime = await authorization.request()
        configureScreenTime()
    }

    /// Adds a named set with `label`, without a selection yet.
    @discardableResult
    func addSet(label: String) -> ScreenTimeSet {
        let set = ScreenTimeSet(label: label)
        state.screenTimeSets += [set]
        sets = state.screenTimeSets
        configureScreenTime()
        return set
    }

    /// Replaces a set's label or selection ("Everything" keeps its label).
    func updateSet(_ set: ScreenTimeSet) {
        var updated = set
        if set.isEverything {
            updated.label = ScreenTimeSet.everythingLabel
        }
        state.screenTimeSets = state.screenTimeSets.map { $0.id == set.id ? updated : $0 }
        sets = state.screenTimeSets
        configureScreenTime()
    }

    /// Deletes a named set; "Everything" cannot be deleted.
    func removeSet(id: String) {
        guard id != ScreenTimeSet.everythingID else {
            return
        }
        state.screenTimeSets = state.screenTimeSets.filter { $0.id != id }
        sets = state.screenTimeSets
        configureScreenTime(removed: [id])
    }

    /// Registers every set when collecting with Screen Time approved,
    /// measuring the event cap on the first run.
    private func configureScreenTime(removed: [String] = []) {
        guard isEnabled, screenTime == .approved else {
            return
        }
        if state.eventCap == nil {
            let cap = authorization.measureCap()
            state.eventCap = cap > 0 ? cap : nil
            logger.notice("DeviceActivity accepted at most \(cap, privacy: .public) events")
        }
        do {
            try controller.configure(removed: removed)
            screenTimeError = nil
        } catch {
            logger.error("Screen Time refused the app groups: \(error.localizedDescription, privacy: .public)")
            screenTimeError = "Screen Time couldn't start measuring these apps. Try again later."
        }
    }

    // MARK: Flush and the app's own lines

    /// Uploads the staged events now; records the time on success. A call
    /// while a flush runs waits for that flush.
    func flush() async {
        if let running = flushTask {
            await running.value
            return
        }
        let task = Task { await self.flushOnce() }
        flushTask = task
        await task.value
        flushTask = nil
    }

    private func flushOnce() async {
        do {
            try await staging.flush()
            shared.lastFlushAt = log.clock.now
            flushError = nil
        } catch {
            logger.error("The flush failed: \(error.localizedDescription, privacy: .public)")
            flushError = "Couldn't send your activity to iCloud. The app will try again."
        }
        refresh()
    }

    /// The wrapper intents' and the fan-out's flush: only when the last
    /// flush is more than 5 minutes old (IOS-31).
    func flushIfDue() async {
        guard CollectionFlush.isDue(lastFlushAt: shared.lastFlushAt, now: log.clock.now) else {
            return
        }
        await flush()
    }

    /// Logs the transition once per change; the foreground also refreshes
    /// the App Group copy of `settings.toml` and flushes.
    func appMoved(toForeground foreground: Bool) async {
        let place: ScenePlace = foreground ? .foreground : .background
        guard lastTransition != place else {
            return
        }
        lastTransition = place
        do {
            try log.logApp(foreground: foreground)
        } catch {
            logger.error("The app line failed: \(error.localizedDescription, privacy: .public)")
        }
        periodicTask?.cancel()
        periodicTask = nil
        guard foreground else {
            await flushIfDue()
            refresh()
            return
        }
        await refreshSettingsCopy()
        await flush()
        if flushesPeriodically {
            periodicTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(CollectionFlush.interval))
                    await self?.flush()
                }
            }
        }
    }

    /// Copies `settings.toml` from iCloud Drive into the App Group (the
    /// Safari extension's exclusions) and reloads the Privacy lists.
    func refreshSettingsCopy() async {
        let folders = folders
        let privacy = await Task.detached { () -> TrackerPrivacySettings? in
            guard let folders = folders() else {
                return nil
            }
            _ = try? CollectionFlush.refreshSettingsCopy(from: folders.shared, to: folders.local)
            let url = folders.local.appending(path: "settings.toml", directoryHint: .notDirectory)
            return (try? TrackerSettings(contentsOf: url))?.privacy
        }.value
        if let privacy {
            self.privacy = privacy
        }
    }
}
