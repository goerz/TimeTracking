// PhoneModel: the iOS app's state and commands, shared by the Timer screen,
// Settings, intents, widget buttons, notifications, and the background
// handlers (spec_ios.md §2, §4, §7, §8).

import Foundation
import Observation
import TimeTrackingCore

/// What the Timer screen presents.
enum PhoneSheet: Identifiable {
    case picker(ProjectPickerModel)
    case editor(EntryID)
    case settings

    var id: String {
        switch self {
        case let .picker(model): "picker-\(ObjectIdentifier(model).hashValue)"
        case let .editor(id): "editor-\(id)"
        case .settings: "settings"
        }
    }
}

/// The banner of an adjustment after syncing (spec_ios.md §7 item 3).
struct AdjustmentBanner: Equatable {
    var entryID: EntryID
    var explanation: String
}

/// Owns the store and every model; reacts to store changes with the
/// fan-out of spec_ios.md §7 item 4.
@Observable
final class PhoneModel {
    @ObservationIgnored let store: TimeStore
    @ObservationIgnored let clock: any Clock
    @ObservationIgnored let settings: PhoneSettings
    @ObservationIgnored let notifications: NotificationScheduling
    @ObservationIgnored let widgets: WidgetReloading
    @ObservationIgnored let shortcuts: ShortcutsUpdating
    @ObservationIgnored let shared: WidgetSharedState
    @ObservationIgnored let collection: CollectionFlushing
    /// The iPad's section tabs; `nil` on the iPhone.
    @ObservationIgnored let pad: PadSections?
    @ObservationIgnored var sync: SyncDriving?
    /// Apple Health on the iPhone; `nil` on the iPad, without HealthKit, and in tests.
    @ObservationIgnored var health: (any HealthAccess)?
    /// Bounds a wrapper intent's fetch (spec_ios.md §4 item 3); tests replace it.
    @ObservationIgnored var boundedFetch: @Sendable (@escaping @Sendable () async -> Void) async -> Void = { fetch in
        await Bounded.run(seconds: WidgetIntentActions.fetchTimeout, fetch)
    }

    let timer: TimerModel
    let taskField: TaskFieldModel
    let list: TimerListModel
    let pomodoro: PhonePomodoroModel

    var sheet: PhoneSheet?
    /// The project dialog pushed inside the picker sheet.
    var dialogModel: ProjectDialogModel?
    var banner: AdjustmentBanner?
    /// Entries badged until their sheet opens once.
    var badged: Set<EntryID>
    /// The explanation line per adjusted entry, for its edit sheet.
    var explanations: [EntryID: String] = [:]
    private(set) var macLines: [String] = []
    private(set) var syncStatus: SyncStatus = .idle
    private(set) var outboxCount = 0
    /// When `sending` began, for the 10-second rule of the sync pill.
    private(set) var sendingSince: Date?
    /// Whether the scene is in the foreground (adjustments notify otherwise).
    var isActive = true
    /// An alert after a URL that did nothing.
    var urlAlert: String?
    /// The iPad's selected tab; a section tab opens its section.
    var padTab: PadTab = .timer {
        didSet {
            if let section = padTab.section {
                pad?.open(section)
            }
        }
    }

    @ObservationIgnored private var changeTask: Task<Void, Never>?
    @ObservationIgnored private var midnightTask: Task<Void, Never>?
    @ObservationIgnored private var lastRunningID: EntryID?
    @ObservationIgnored var lastLongRunningKey: String?

    init(
        store: TimeStore,
        clock: any Clock,
        settings: PhoneSettings,
        notifications: NotificationScheduling,
        widgets: WidgetReloading,
        shortcuts: ShortcutsUpdating,
        shared: WidgetSharedState,
        collection: CollectionFlushing = NoCollection(),
        pad: PadSections? = nil
    ) {
        self.store = store
        self.clock = clock
        self.settings = settings
        self.notifications = notifications
        self.widgets = widgets
        self.shortcuts = shortcuts
        self.shared = shared
        self.collection = collection
        self.pad = pad
        self.timer = TimerModel(store: store, clock: clock, notifier: notifications)
        self.taskField = TaskFieldModel(store: store)
        self.list = TimerListModel(store: store, clock: clock)
        self.pomodoro = PhonePomodoroModel(store: store, clock: clock, scheduler: notifications, settings: settings)
        self.badged = Set(settings.device[.badgedEntries].compactMap { EntryID($0) })
        timer.onChange = { [weak self] in await self?.localWrite() }
        list.onChange = { [weak self] in await self?.localWrite() }
        pomodoro.currentTask = { [weak self] in self?.timer.running?.task ?? "" }
        pomodoro.onTransition = { [weak self] in self?.widgets.reloadTimelines() }
        wirePad()
    }

    // MARK: Lifecycle

    /// Loads everything and replays the Pomodoro; with `observing`, follows
    /// the store's changes.
    /// The stream is created before the first read, so a change committed
    /// while loading (or by a sync started before) is not missed.
    func start(observing: Bool) async {
        let stream = observing ? store.changes : nil
        await pomodoro.loadSettings()
        _ = try? await store.checkInvariants()
        await timer.refresh()
        lastRunningID = timer.running?.id
        pomodoro.replay(isRunning: timer.isRunning)
        await list.reload()
        await refreshLive()
        rescheduleLongRunning()
        if let stream {
            changeTask = Task { [weak self] in
                for await change in stream {
                    await self?.storeChanged(change)
                }
            }
            midnightTask = Task { [weak self] in
                await self?.splitAtMidnights()
            }
        }
    }

    /// The midnight split while the app runs (spec_ios.md §7 item 5): wake
    /// at the running entry's next midnight, run the pass, and fan out.
    private func splitAtMidnights() async {
        while !Task.isCancelled {
            guard let midnight = try? await store.nextMidnightSplit() else {
                try? await Task.sleep(for: .seconds(60))
                continue
            }
            try? await Task.sleep(for: .seconds(max(1, midnight.timeIntervalSince(clock.now))))
            try? await store.checkInvariants()
            await fanOut(structureChanged: false)
        }
    }

    func stop() {
        changeTask?.cancel()
        changeTask = nil
        midnightTask?.cancel()
        midnightTask = nil
        sync?.stop()
    }

    /// The scene came to the foreground (and at launch): the app's own
    /// `foreground` line and flush (spec_ios.md §9.6, §9.7), then as a wake.
    func foreground() async {
        await collection.appMoved(toForeground: true)
        await wake(interactive: true)
    }

    /// The scene went to the background: the app's `background` line.
    func background() async {
        await collection.appMoved(toForeground: false)
    }

    /// The `BGAppRefreshTask`: a wake and a flush, without UI.
    func refreshTask() async {
        await wake(interactive: false)
        await collection.flush()
    }

    /// Register the device, upload the push token, sync, import from Apple
    /// Health, and run the fan-out.
    private func wake(interactive: Bool) async {
        await registerDevice()
        await uploadPushToken()
        await sync?.fetchNow()
        _ = try? await store.checkInvariants()
        await importHealth(interactive: interactive)
        await fanOut(structureChanged: false)
    }

    // MARK: Changes

    /// A change from the store (this process, an extension, or sync).
    func storeChanged(_ change: StoreChange) async {
        switch change {
        case let .settings(keys):
            await pomodoro.loadSettings()
            widgets.reloadTimelines()
            if isActive, !keys.isDisjoint(with: Self.healthSettingNames) {
                await importHealth(interactive: true)
            }
            if keys.contains(where: { $0.hasPrefix("calendar.") }) {
                await pad?.storeChanged()
            }
        case .health:
            await pad?.storeChanged()
        case let .sync(status):
            await syncStatusChanged(status)
        case .liveState:
            await refreshLive()
        case let .adjusted(adjustments):
            await showAdjustments(adjustments)
        case .structure:
            await fanOut(structureChanged: true)
            await pad?.storeChanged()
        case .entries, .runningEntry:
            await fanOut(structureChanged: false)
            await pad?.storeChanged()
        }
    }

    /// A write of this app's own UI or intents: record it for the widget
    /// providers' 5-second rule, send at once, and fan out.
    func localWrite() async {
        if let state = try? await store.liveState() {
            shared.recordAppWrite(state, at: clock.now)
        }
        await sync?.sendNow()
        await fanOut(structureChanged: false)
        if let running = timer.running, running.id != donatedID {
            donatedID = running.id
            shortcuts.donate(running)
        }
    }

    @ObservationIgnored private var donatedID: EntryID?

    /// The fan-out of spec_ios.md §7 item 4.
    func fanOut(structureChanged: Bool) async {
        await timer.refresh()
        await list.reload()
        let running = timer.running
        if running?.id != lastRunningID {
            pomodoro.runningChanged(isRunning: running != nil)
            lastRunningID = running?.id
        }
        widgets.reloadControls()
        widgets.reloadTimelines()
        rescheduleLongRunning()
        await uploadPushToken()
        if structureChanged {
            let projects = await (try? store.projects(filter: ProjectFilter(state: .all))) ?? []
            shortcuts.projectsChanged(projects)
        }
        await collection.flushIfDue()
        await refreshOutbox()
    }

    // MARK: Live state and sync status

    func refreshLive() async {
        let state = await (try? store.liveState()) ?? LiveState()
        macLines = MacActivityLine.lines(state, timeZone: .current)
    }

    private func syncStatusChanged(_ status: SyncStatus) async {
        if case .sending = status {
            if sendingSince == nil {
                sendingSince = clock.now
            }
        } else {
            sendingSince = nil
        }
        syncStatus = status
        await refreshOutbox()
    }

    func refreshOutbox() async {
        outboxCount = await (try? store.outboxCount()) ?? 0
    }

    /// The pill under the card (spec_ios.md §7 item 2): waiting, sending for
    /// over 10 s, or an error, while the outbox holds changes.
    func syncPill(at now: Date) -> String? {
        guard outboxCount > 0 else {
            return nil
        }
        switch syncStatus {
        case .waitingForNetwork:
            return "Waiting for the network"
        case let .sending(count):
            guard let since = sendingSince, now.timeIntervalSince(since) > 10 else {
                return nil
            }
            return "Sending \(count) change\(count == 1 ? "" : "s")…"
        case let .error(message):
            return message
        case .idle, .fetching, .noAccount:
            return nil
        }
    }
}
