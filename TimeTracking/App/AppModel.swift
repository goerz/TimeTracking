// AppModel: the Mac app's state and commands, shared by the main window,
// the menu bar item, the Dock menu, notifications, and global shortcuts
// (spec_timer.md §1, §2; spec_menubar.md §2).

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
    @ObservationIgnored weak var window: MiniTimerControlling?
    /// The Mini Timer's own list, popovers, picker, dialog, and focus.
    let miniTimer: TimerUIState
    /// The main window's Timer's own list, popovers, picker, dialog, and focus.
    let mainTimer: TimerUIState
    /// The app's key window, if any: the main window or the Mini Timer (set by the windows' views).
    private(set) var keyWindow: TimerUIState.Place?
    /// The window that shows the current alert of the Timer.
    private(set) var alertWindow: TimerUIState.Place = .miniTimer
    let settings: AppSettings
    let timer: TimerModel
    let pomodoro: PomodoroModel
    let idle: IdleModel
    let reminders: ReminderModel
    let tracker: TrackerStatusModel
    let trackerSettings: TrackerSettingsModel
    /// The main window's sections and their router.
    let sections: SectionRouter
    /// Whether the main window is open (its sections follow store changes).
    var mainWindowIsOpen = false
    /// The main window shows the Timer (the sidebar's first item) instead
    /// of a section.
    var showsTimer = true

    /// The main window and the Mini Timer as open now, or at the last quit.
    @ObservationIgnored let openWindows: OpenWindowsRecord

    /// Sync and live updates; `nil` under `-UITesting` and in tests.
    var live: LiveUpdates?
    /// The first-launch tracker alert (spec_timer.md §8.2).
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
    /// Whether the Mini Timer is key.
    private(set) var timerIsKey = false

    @ObservationIgnored var changeTask: Task<Void, Never>?
    /// The coalesced reload after entry and structure changes.
    @ObservationIgnored var reloadLoop: Task<Void, Never>?
    /// Wakes at the running entry's next midnight to run the invariant pass.
    @ObservationIgnored var midnightTask: Task<Void, Never>?
    @ObservationIgnored var reloadRequested = false
    /// The running chain the models last reacted to; a split at real
    /// midnight gives the running entry a new id but keeps this.
    @ObservationIgnored var lastRunningRootID: EntryID?
    /// Timer commands in flight on behalf of a source of §8.3: the global
    /// shortcut, the menu bar, or a notification.
    @ObservationIgnored private var sourceCommands = 0

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
        calendarEvents: any CalendarEventStore = InMemoryCalendarEventStore(access: .denied)
    ) {
        self.store = store
        self.clock = clock
        self.settings = settings
        self.openWindows = OpenWindowsRecord(device: settings.device)
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
        self.sections = SectionRouter(
            store: store,
            clock: clock,
            device: settings.device,
            activity: activity,
            events: calendarEvents
        )
        timer.onChange = { [weak self] in await self?.afterChange() }
        timer.onAlert = { [weak self] in self?.alertRaised() }
        for view in [miniTimer, mainTimer] {
            view.list.onChange = { [weak self] in await self?.afterChange() }
        }
        idle.onChange = { [weak self] in await self?.afterChange() }
        idle.showTimer = { [weak self] focus in self?.router?.showTimer(focusTask: focus) }
        pomodoro.currentTask = { [weak self] in self?.timer.running?.task ?? "" }
        sections.wireTimer(timer) { [weak self] in await self?.afterChange() }
        sections.showMainWindow = { [weak self] section in self?.router?.showMainWindow(item: .section(section)) }
        wireSections(trackerCommands: trackerCommands)
        sections.copyText = { Pasteboard.copy($0) }
        ModifierState.optionDown = { ModifierKeys.optionIsDown }
        ModifierState.shiftDown = { ModifierKeys.shiftIsDown }
        ModifierState.extendDown = { ModifierKeys.extendsSelection }
        ModifierState.readsKeyPresses = true
    }

    func stop() {
        changeTask?.cancel()
        changeTask = nil
        midnightTask?.cancel()
        midnightTask = nil
    }

    /// A change from the store (this process, the tool, or sync).
    func storeChanged(_ change: StoreChange) async {
        switch change {
        case let .settings(keys):
            await pomodoro.loadSettings()
            revision += 1
            if keys.contains(where: { $0.hasPrefix("calendar.") }) {
                await reloadHealthViews()
            }
            await reloadAfterMidnightChange(keys)
        case .sync, .liveState, .adjusted:
            return
        case .health:
            await reloadHealthViews()
        case .entries, .runningEntry, .structure:
            await afterChange()
            if mainWindowIsOpen {
                await sections.projects.reload()
                await sections.reports.reload()
                if sections.section == .calendar {
                    await sections.calendar.reload()
                }
            }
        }
    }

    /// Both Timer views' lists.
    func reloadLists() async {
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
        if running?.rootID != lastRunningRootID {
            pomodoro.runningChanged(isRunning: running != nil)
            idle.runningChanged(running)
            if running != nil {
                // "Nothing is being tracked" no longer holds.
                reminders.trackingStarted()
            }
            if running != nil ? settings.focusOnStart : settings.focusOnStop, !changeIsFromWindow {
                router?.showTimer(focusTask: true)
            }
            lastRunningRootID = running?.rootID
        }
        revision += 1
    }

    /// Whether the change just seen is a Timer command from a window or
    /// the main menu, none of which are sources of §8.3.
    private var changeIsFromWindow: Bool {
        timer.commandsInFlight > 0 && sourceCommands == 0
    }

    /// Runs a Timer command on behalf of a source of §8.3.
    private func fromSource(_ command: () async -> Void) async {
        sourceCommands += 1
        defer { sourceCommands -= 1 }
        await command()
    }

    // MARK: Commands of the menus, Dock, notifications, and shortcuts

    /// New: starts an empty entry and shows a Timer with the task field
    /// focused: `view` (the main menu passes `activeTimer`), else the Mini
    /// Timer (the menu bar, the Dock, notifications).
    func newEntry(in view: TimerUIState? = nil) async {
        await timer.new()
        if view?.place == .mainWindow {
            router?.showMainWindow(item: .timer)
            mainTimer.focusTaskField()
        } else {
            router?.showTimer(focusTask: true)
        }
    }

    /// Continue the most recent entry other than the running one, without
    /// showing a window (the restore alert shows one, `alertRaised`).
    func continueLatest() async {
        await fromSource { await timer.continueEntry() }
    }

    /// The menu bar's Stop; the main menu's calls the Timer directly.
    func stopEntry() async {
        await fromSource { await timer.stop() }
    }

    /// The continue/stop shortcut; only the settings of §8.3 show a window.
    func continueOrStop() async {
        await fromSource { await timer.continueOrStop() }
    }

    func perform(_ action: PomodoroAction) {
        pomodoro.perform(action, isRunning: timer.isRunning)
        revision += 1
    }

    /// A notification action (spec_timer.md §10).
    func handle(_ action: NotificationAction) async {
        if let pomodoroAction = Self.pomodoroActions[action] {
            perform(pomodoroAction)
        } else if let option = Self.idleOptions[action] {
            await idle.resolve(option)
        } else if action == .startNew || action == .continueLatest {
            // The reminder's actions, which stop nothing: an entry started
            // since the reminder (on any device) keeps running.
            await timer.refresh()
            guard !timer.isRunning else {
                return
            }
            if action == .startNew {
                await newEntry()
            } else {
                await continueLatest()
            }
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
}

// MARK: Timer commands

extension AppModel {
    /// The main window or the Mini Timer became key (`true`) or resigned.
    func windowActivated(_ place: TimerUIState.Place, isKey: Bool, undoManager: UndoManager?) {
        if isKey {
            keyWindow = place
            // Undo of the Timer's commands goes to the window they came from.
            timer.undoManager = undoManager
        } else if keyWindow == place {
            keyWindow = nil
        }
    }

    /// An alert of the Timer: the key window shows it, whatever it shows;
    /// with no key window (the menu bar, a global shortcut, a
    /// notification) the Mini Timer comes forward with it.
    private func alertRaised() {
        if let keyWindow {
            alertWindow = keyWindow
        } else {
            alertWindow = .miniTimer
            router?.showTimer(focusTask: false)
        }
    }

    /// ⌘O: the selection of the key window (a Timer row; a section's project
    /// or entry), else the most recent entry.
    func continueCommand(timerKey: Bool, sectionKey: Bool = false) async {
        if sectionKey, await sections.continueSelection() {
            return
        }
        if timerKey, let selection = activeTimer.list.selection {
            await timer.continueEntry(selection)
        } else {
            await timer.continueEntry()
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

    /// The Mini Timer became key or resigned.
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
