// AppModel: the Mac app's state and commands, shared by the Timer window,
// the menu bar item, the Dock menu, notifications, and global shortcuts
// (spec_timer_window.md §13, spec_menubar.md §9).

import Foundation
import Observation
import TimeTrackingCore

/// Owns the store and every model; reacts to store changes.
@Observable
final class AppModel {
    @ObservationIgnored let store: TimeStore
    @ObservationIgnored let clock: any Clock
    @ObservationIgnored let notifier: NotificationPosting
    @ObservationIgnored weak var router: AppRouting?
    let settings: AppSettings
    let timer: TimerModel
    let list: TimerListModel
    let pomodoro: PomodoroModel
    let idle: IdleModel
    let reminders: ReminderModel
    let tracker: TrackerStatusModel
    let trackerSettings: TrackerSettingsModel

    /// The first-launch tracker alert (spec_timer_window.md §8.2).
    var showsTrackerOnboarding = false
    /// Bumped on every change the menu bar must render at once.
    private(set) var revision = 0
    /// The recorded show/hide shortcut, for menus.
    var showHideKey: MenuKey? = .command("r", .option)

    @ObservationIgnored private var changeTask: Task<Void, Never>?
    @ObservationIgnored private var lastRunningID: EntryID?

    init(
        store: TimeStore,
        clock: any Clock,
        settings: AppSettings,
        notifier: NotificationPosting,
        agent: AgentService,
        readTrackerState: @escaping () async -> TrackerState? = { nil },
        trackerCommands: TrackerCommandSending = RecordingTrackerCommands(),
        trackerSettingsURL: URL? = nil
    ) {
        self.store = store
        self.clock = clock
        self.settings = settings
        self.notifier = notifier
        self.timer = TimerModel(store: store, clock: clock, notifier: notifier)
        self.list = TimerListModel(store: store, clock: clock)
        self.pomodoro = PomodoroModel(store: store, clock: clock, notifier: notifier, settings: settings)
        self.idle = IdleModel(store: store, clock: clock, notifier: notifier, settings: settings)
        self.reminders = ReminderModel(store: store, clock: clock, notifier: notifier, settings: settings)
        self.tracker = TrackerStatusModel(agent: agent, clock: clock, readState: readTrackerState)
        self.trackerSettings = TrackerSettingsModel(settingsURL: trackerSettingsURL, commands: trackerCommands, clock: clock)
        timer.onChange = { [weak self] in await self?.afterChange() }
        list.onChange = { [weak self] in await self?.afterChange() }
        idle.onChange = { [weak self] in await self?.afterChange() }
        idle.showTimer = { [weak self] focus in self?.router?.showTimer(focusTask: focus) }
        pomodoro.currentTask = { [weak self] in self?.timer.running?.task ?? "" }
    }

    /// Loads everything; with `observing`, follows the store's changes.
    func start(observing: Bool) async {
        await pomodoro.loadSettings()
        await timer.refresh()
        lastRunningID = timer.running?.id
        await list.reload()
        await tracker.refresh()
        trackerSettings.load()
        guard observing else {
            return
        }
        let stream = store.changes
        changeTask = Task { [weak self] in
            for await change in stream {
                await self?.storeChanged(change)
            }
        }
    }

    func stop() {
        changeTask?.cancel()
        changeTask = nil
    }

    /// A change from the store (this process, the tool, or sync).
    func storeChanged(_ change: StoreChange) async {
        switch change {
        case .settings:
            await pomodoro.loadSettings()
            revision += 1
        case .sync, .liveState, .adjusted:
            return
        case .entries, .runningEntry, .structure:
            await afterChange()
        }
    }

    /// Re-reads the timer and list and reacts to a start or stop: the
    /// Pomodoro ends when nothing runs, the idle prompt closes, and the
    /// focus settings of §8.3 apply.
    func afterChange() async {
        await timer.refresh()
        await list.reload()
        let running = timer.running
        if running?.id != lastRunningID {
            pomodoro.runningChanged(isRunning: running != nil)
            idle.runningChanged(running)
            if running != nil, settings.focusOnStart {
                router?.showTimer(focusTask: true)
            } else if running == nil, settings.focusOnStop {
                router?.showTimer(focusTask: true)
            }
            lastRunningID = running?.id
        }
        revision += 1
    }

    // MARK: Commands of the menus, Dock, notifications, and shortcuts

    /// New: starts an empty entry and shows the window with the task field focused.
    func newEntry() async {
        await timer.new()
        router?.showTimer(focusTask: true)
    }

    /// Continue the most recent entry other than the running one, without
    /// showing the window (the restore alert shows it).
    func continueLatest() async {
        await timer.continueEntry()
        if timer.alert != nil {
            router?.showTimer(focusTask: false)
        }
    }

    func stopEntry() async {
        await timer.stop()
    }

    /// The continue/stop shortcut; the window is not shown.
    func continueOrStop() async {
        await timer.continueOrStop()
    }

    func perform(_ action: PomodoroAction) {
        pomodoro.perform(action, isRunning: timer.isRunning)
        revision += 1
    }

    /// A notification action (spec_timer_window.md §10).
    func handle(_ action: NotificationAction) async {
        if let pomodoroAction = Self.pomodoroActions[action] {
            perform(pomodoroAction)
        } else if let option = Self.idleOptions[action] {
            await idle.resolve(option)
        } else if action == .startNew {
            await newEntry()
        } else if action == .continueLatest {
            await continueLatest()
        } else if action == .snooze {
            reminders.snooze()
        }
    }

    private static let pomodoroActions: [NotificationAction: PomodoroAction] = [
        .startBreak: .startBreak, .skipBreak: .skipBreak, .startFocus: .startFocus, .endPomodoro: .cancel,
    ]

    private static let idleOptions: [NotificationAction: IdleOption] = [
        .keep: .keep, .discard: .discard, .discardAndContinue: .discardAndContinue, .split: .split,
    ]

    /// The first launch on a Mac: ask once about activity tracking.
    func showTrackerOnboardingIfNeeded() {
        if !settings.trackerOnboardingPrompted {
            showsTrackerOnboarding = true
        }
    }

    /// "Open Tracker Settings" or "Later"; either marks the alert as shown.
    func answerTrackerOnboarding(openSettings: Bool) {
        settings.trackerOnboardingPrompted = true
        showsTrackerOnboarding = false
        if openSettings {
            router?.openSettings(pane: .tracker)
        }
    }

    /// The menu bar's inputs.
    var statusState: StatusItemState {
        StatusItemState(
            running: timer.running,
            chainStart: timer.chainStart,
            label: timer.runningLabel,
            mostRecentOther: timer.mostRecentOther,
            lastStoppedToday: timer.lastStoppedToday,
            pomodoro: pomodoro.pomodoro,
            showTimer: settings.menuBarShowTimer,
            showSeconds: settings.menuBarShowSeconds,
            showProject: settings.menuBarShowProject,
            warning: tracker.warningActive,
            warningLine: tracker.warningLine,
            showHideKey: showHideKey,
            appName: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "TimeTracking"
        )
    }
}
