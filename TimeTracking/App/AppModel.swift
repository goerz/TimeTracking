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
    @ObservationIgnored weak var window: TimerWindowControlling?
    /// The Mini Timer's own list, popovers, picker, dialog, and focus.
    let miniTimer: TimerUIState
    /// The main window's Timer's own list, popovers, picker, dialog, and focus.
    let mainTimer: TimerUIState
    /// The Timer view whose window is key, if any (set by the views).
    private(set) var keyTimer: TimerUIState?
    let settings: AppSettings
    let timer: TimerModel
    let pomodoro: PomodoroModel
    let idle: IdleModel
    let reminders: ReminderModel
    let tracker: TrackerStatusModel
    let trackerSettings: TrackerSettingsModel
    /// The Planner's sections and router.
    let planner: PlannerRouter
    /// Whether the Planner window is open (its sections follow store changes).
    var plannerIsOpen = false
    /// Experiment: the one window shows the Timer (the sidebar's first item)
    /// instead of a Planner section.
    var showsTimer = true
    /// Launched as a login item with "Show the main window at login" off:
    /// the main window closes as it appears.
    @ObservationIgnored var hidesMainWindowOnAttach = false

    /// Sync and live updates; `nil` under `-UITesting` and in tests.
    var live: LiveUpdates?
    /// The first-launch tracker alert (spec_timer_window.md §8.2).
    var showsTrackerOnboarding = false
    /// The alert's "Open <APP_NAME> at login" checkbox, on by default.
    var onboardingOpensAtLogin = true
    /// Whether the alert is on screen or was answered in this run.
    @ObservationIgnored var onboardingPresented = false
    /// Shows the alert (`TrackerOnboardingAlert` in the app).
    @ObservationIgnored var onboardingPresenter: TrackerOnboardingPresenter?
    /// Bumped on every change the menu bar must render at once.
    private(set) var revision = 0
    /// The recorded show/hide shortcut, for menus.
    var showHideKey: MenuKey? = .command("r", .option)
    /// Reads the recorded show/hide shortcut (KeyboardShortcuts in the app).
    @ObservationIgnored var shortcutSource: () -> MenuKey? = { .command("r", .option) }
    /// Whether the Timer window is key (menus enable "Timer key" commands).
    private(set) var timerIsKey = false

    @ObservationIgnored private var changeTask: Task<Void, Never>?
    @ObservationIgnored private var lastRunningID: EntryID?

    init(
        store: TimeStore,
        clock: any Clock,
        settings: AppSettings,
        notifier: NotificationPosting,
        agent: AgentService,
        loginItem: AppLoginItemService,
        automation: AutomationPermissionService = FakeAutomationPermission(),
        readTrackerState: @escaping () async -> TrackerState? = { nil },
        trackerCommands: TrackerCommandSending = RecordingTrackerCommands(),
        trackerSettingsURL: URL? = nil,
        activity: any ActivityReading = InMemoryActivityStore(),
        calendarEvents: any CalendarEventStore = InMemoryCalendarEventStore(access: .denied),
        suggestionsCache: URL? = nil
    ) {
        self.store = store
        self.clock = clock
        self.settings = settings
        self.notifier = notifier
        self.timer = TimerModel(store: store, clock: clock, notifier: notifier)
        self.miniTimer = TimerUIState(place: .miniTimer, store: store, clock: clock)
        self.mainTimer = TimerUIState(place: .mainWindow, store: store, clock: clock)
        self.pomodoro = PomodoroModel(store: store, clock: clock, notifier: notifier, settings: settings)
        self.idle = IdleModel(store: store, clock: clock, notifier: notifier, settings: settings)
        self.reminders = ReminderModel(store: store, clock: clock, notifier: notifier, settings: settings)
        self.tracker = TrackerStatusModel(
            agent: agent,
            loginItem: loginItem,
            automation: automation,
            clock: clock,
            readState: readTrackerState
        )
        self.trackerSettings = TrackerSettingsModel(settingsURL: trackerSettingsURL)
        self.planner = PlannerRouter(
            store: store,
            clock: clock,
            device: settings.device,
            activity: activity,
            events: calendarEvents,
            suggestionsCache: suggestionsCache
        )
        timer.onChange = { [weak self] in await self?.afterChange() }
        for view in [miniTimer, mainTimer] {
            view.list.onChange = { [weak self] in await self?.afterChange() }
        }
        idle.onChange = { [weak self] in await self?.afterChange() }
        idle.showTimer = { [weak self] focus in self?.router?.showTimer(focusTask: focus) }
        pomodoro.currentTask = { [weak self] in self?.timer.running?.task ?? "" }
        planner.wireTimer(timer) { [weak self] in await self?.afterChange() }
        planner.openWindow = { [weak self] in self?.router?.openPlanner() }
        wirePlannerSections(trackerCommands: trackerCommands)
        planner.copyText = { Pasteboard.copy($0) }
        ModifierState.optionDown = { ModifierKeys.optionIsDown }
        ModifierState.shiftDown = { ModifierKeys.shiftIsDown }
    }

    /// Loads everything; with `observing`, follows the store's changes.
    func start(observing: Bool) async {
        await pomodoro.loadSettings()
        await timer.refresh()
        lastRunningID = timer.running?.id
        await reloadLists()
        await tracker.refresh()
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
            if plannerIsOpen {
                await planner.projects.reload()
                await planner.reports.reload()
                if planner.section == .calendar {
                    await planner.calendar.reload()
                }
            }
        }
    }

    /// Both Timer views' lists.
    private func reloadLists() async {
        await miniTimer.list.reload()
        await mainTimer.list.reload()
    }

    /// Re-reads the timer and lists and reacts to a start or stop: the
    /// Pomodoro ends when nothing runs, the idle prompt closes, and the
    /// focus settings of §8.3 apply.
    func afterChange() async {
        await timer.refresh()
        await reloadLists()
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

    /// New: starts an empty entry and shows a Timer with the task field
    /// focused: `view` (the main menu passes `activeTimer`), else the Mini
    /// Timer (the menu bar, the Dock, notifications).
    func newEntry(in view: TimerUIState? = nil) async {
        await timer.new()
        if view?.place == .mainWindow {
            router?.showMainTimer()
            mainTimer.focusTaskField()
        } else {
            router?.showTimer(focusTask: true)
        }
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

    // MARK: Timer window commands

    /// A Timer view's window became key (`true`) or resigned.
    func timerViewActivated(_ view: TimerUIState, isKey: Bool, undoManager: UndoManager?) {
        if isKey {
            keyTimer = view
            // Undo of the Timer's commands goes to the window they came from.
            timer.undoManager = undoManager
        } else if keyTimer === view {
            keyTimer = nil
        }
    }

    /// ⌘O: the selection of the key window (a Timer row; a Planner project
    /// or entry), else the most recent entry.
    func continueCommand(timerKey: Bool, plannerKey: Bool = false) async {
        if plannerKey, await planner.continueSelection() {
            return
        }
        if timerKey, let selection = activeTimer.list.selection {
            await timer.continueEntry(selection)
        } else {
            await continueLatest()
        }
    }

    /// ⇧⌘M.
    func toggleCompact() {
        window?.toggleCompact()
    }

    /// The pin and View > Float on Top.
    func setPinned(_ pinned: Bool) {
        settings.timerPinned = pinned
        window?.applyPin(pinned)
    }

    /// The show/hide shortcut was recorded or cleared.
    func refreshShortcutDisplay() {
        showHideKey = shortcutSource()
    }

    /// The Timer window became key or resigned.
    func timerKeyChanged() {
        timerIsKey = window?.isKey ?? false
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
            focusMinutes: pomodoro.focusMinutes,
            breakMinutes: pomodoro.breakMinutes,
            showTimer: settings.menuBarShowTimer,
            showSeconds: settings.menuBarShowSeconds,
            showProject: settings.menuBarShowProject,
            pomodoroDisplay: settings.menuBarPomodoroDisplay,
            warning: tracker.warningActive,
            warningLine: tracker.warningLine,
            showHideKey: showHideKey,
            appName: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "TimeTracking"
        )
    }
}
