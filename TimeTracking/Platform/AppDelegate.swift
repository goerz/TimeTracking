// AppDelegate: launch, the status item, the Dock tile and menu, activation
// policy, global shortcuts, and notifications (timer.md §1.3,
// §8; menubar.md §1, §4).

import AppKit
import KeyboardShortcuts
import Observation
import os
import TimeTrackingCore

/// The app delegate: creates the status item at launch and wires the
/// AppKit side to the `AppModel`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let host = AppHost()
    private(set) var miniTimerWindow: MiniTimerController?
    private(set) var router: WindowRouter?
    private var statusItem: StatusItemController?
    private var systemEvents: SystemEvents?
    private var notifications: UserNotifications?
    private var launchedAsLoginItem = false
    private let urlEvents = URLEventHandler()

    func applicationWillFinishLaunching(_: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let loginItemEvent = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        // UI tests stand in for a login with `-LoginItemLaunch YES`.
        launchedAsLoginItem = loginItemEvent || (host.arguments.uiTesting && host.arguments.loginItemLaunch)
        if !AppHost.isTestHost {
            urlEvents.install()
        }
    }

    func applicationDidFinishLaunching(_: Notification) {
        guard !AppHost.isTestHost else {
            return
        }
        Task { await launch() }
    }

    private static let logger = Logging.logger(category: "App")

    private func launch() async {
        let identity = AppIdentity.main
        let uiTesting = host.arguments.uiTesting
        Self.logger.notice("Launching (UI testing: \(uiTesting, privacy: .public))")
        let notifier: NotificationPosting
        if uiTesting {
            notifier = RecordingNotifier()
        } else {
            let live = UserNotifications()
            notifications = live
            notifier = live
        }
        let agent = Self.agentService(identity: identity, uiTesting: uiTesting, realAgent: host.arguments.realAgent)
        let folders = uiTesting ? nil : await Self.activityFolders(identity)
        let activity = if uiTesting {
            await Self.fixtureActivity(host.arguments, clock: host.arguments.clock(honorFixedNow: identity?.isDebug ?? true))
        } else {
            folders.map { FileActivityStore(folders: $0) }
        }
        let socket = identity?.groupContainerURL.flatMap { container in identity.map { $0.agentSocketURL(in: container) } }
        guard let app = await host.load(
            notifier: notifier,
            agent: agent,
            loginItem: Self.appLoginItem(uiTesting: uiTesting),
            automation: uiTesting ? FakeAutomationPermission() : AutomationPermission(),
            readTrackerState: { await activity?.currentState() },
            trackerCommands: uiTesting || socket == nil ? RecordingTrackerCommands() : TrackerSocket(url: socket ?? URL(filePath: "/")),
            trackerSettingsURL: folders?.settingsURL,
            activity: activity ?? InMemoryActivityStore(),
            calendarEvents: uiTesting ? Self.fixtureCalendar(host.arguments) : EventKitCalendarStore()
        ) else {
            // The main window shows why. No scene opens by itself, and the
            // status item comes only with a model (`wire`), so without this
            // a failed launch would show nothing at all.
            WindowRouter.openWindow(id: MainWindowSetup.sceneID)
            return
        }
        Self.logger.notice("Store open")
        wire(app)
        await activity?.startWatching()
        IntentBridge.shared.attach(app)
        if let identity {
            urlEvents.attach(URLRouter(app: app, scheme: identity.urlScheme))
        }
        await app.start(observing: true)
        if host.startsLiveUpdates, let identity {
            await startLiveUpdates(app, identity: identity, folders: folders, activity: activity)
        }
        Self.logger.notice("Launched")
        app.showTrackerOnboardingIfNeeded()
    }

    /// Sync through CloudKit, `LiveState` publication, widget pushes, and
    /// the block-log copy (never under `-UITesting`).
    private func startLiveUpdates(_ app: AppModel, identity: AppIdentity, folders: ActivityFolders?, activity: FileActivityStore?) async {
        let live = LiveUpdates(
            store: app.store,
            clock: app.clock,
            engineFactory: CloudKitSyncEngineFactory(containerIdentifier: identity.cloudKitContainer),
            pushClient: APNsClient(
                credentials: KeychainAPNsCredentials(service: identity.apnsKeychainService),
                topic: identity.widgetPushTopic,
                clock: app.clock
            ),
            readTrackerState: { await activity?.currentState() },
            mirror: folders.flatMap { $0.isFallback ? nil : ActivityFolderMirror(local: $0.local, container: $0.shared) },
            deviceName: Host.current().localizedName ?? "Mac",
            confirmAccountSwitch: { await MainActor.run { AccountSwitchAlert.confirm() } }
        )
        app.live = live
        await live.start()
    }

    /// `-UITesting` with a store fixture: the block log the same dataset
    /// generates, in a temporary folder; `nil` (an empty in-memory log) for
    /// `empty` and unknown names.
    private static func fixtureCalendar(_ arguments: LaunchArguments) -> InMemoryCalendarEventStore {
        InMemoryCalendarEventStore(access: arguments.calendarAccess ? .fullAccess : .denied)
    }

    private static func fixtureActivity(_ arguments: LaunchArguments, clock: any Clock) async -> FileActivityStore? {
        guard let name = arguments.fixture, name != "empty", let dataset = SyntheticDataset.fixture(named: name) else {
            return nil
        }
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "uitesting-activity-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        do {
            try await dataset.activityLog(to: folder)
        } catch {
            logger.error("UI testing block log: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return FileActivityStore(folders: ActivityFolders(shared: folder, local: folder, isFallback: true), clock: clock)
    }

    private static func activityFolders(_ identity: AppIdentity?) async -> ActivityFolders? {
        guard let identity else {
            return nil
        }
        return await Task.detached { ActivityFolders.resolve(identity: identity) }.value
    }

    private func wire(_ app: AppModel) {
        let window = MiniTimerController(settings: app.settings)
        window.onKeyChange = { [weak app] in app?.timerKeyChanged() }
        window.onOpenChange = { [weak app] open in
            if open {
                app?.openWindows.opened(.miniTimer)
            } else {
                Task { await app?.miniTimerClosed() }
            }
        }
        let router = WindowRouter(miniTimerWindow: window)
        router.app = app
        app.router = router
        app.window = window
        // The alert is a sheet on the main window.
        app.onboardingPresenter = { appName, opensAtLogin, answer in
            let main = NSApp.windows.first { $0.identifier?.rawValue == MainWindowSetup.sceneID }
            TrackerOnboardingAlert.present(on: main, appName: appName, opensAtLogin: opensAtLogin, answer: answer)
        }
        miniTimerWindow = window
        self.router = router
        let status = StatusItemController(app: app)
        statusItem = status
        let events = SystemEvents(app: app, statusItem: status)
        events.start()
        systemEvents = events
        app.reminders.isLocked = { [weak events] in events?.isLocked ?? false }
        app.idle.isAppActive = { NSApp.isActive }
        notifications?.onResponse = { [weak app, weak router] _, action in
            guard let app else {
                return
            }
            if let action {
                Task { await app.handle(action) }
            } else {
                router?.showTimer(focusTask: false)
            }
        }
        GlobalShortcuts.register(
            toggleTimer: { [weak router] in router?.toggleTimer() },
            continueOrStop: { [weak app] in Task { await app?.continueOrStop() } }
        )
        app.shortcutSource = { GlobalShortcuts.showHideKey }
        app.refreshShortcutDisplay()
        followDockIconSetting(app)
        openLaunchWindows(app, router: router)
    }

    /// For a login-item launch the windows open at the last quit (none:
    /// only the menu bar item), for any other the "At launch, show" window.
    private func openLaunchWindows(_ app: AppModel, router: WindowRouter) {
        let loginItem = launchedAsLoginItem
        let windows = LaunchWindow.opened(
            setting: app.settings.launchWindow,
            launchedAsLoginItem: loginItem,
            openAtQuit: app.openWindows.takeOpenAtQuit()
        )
        let names = windows.map(\.rawValue).joined(separator: ", ")
        Self.logger.notice("Launch windows: [\(names, privacy: .public)], login item: \(loginItem, privacy: .public)")
        for window in windows {
            router.show(window)
        }
    }

    /// Applies "Show Dock icon" at launch and on every change.
    private func followDockIconSetting(_ app: AppModel) {
        withObservationTracking {
            // The window that is key now (Settings, when the toggle changes
            // there) stays key, rather than the Mini Timer coming forward.
            ActivationPolicy.apply(showDockIcon: app.settings.showDockIcon, keyWindow: NSApp.keyWindow ?? miniTimerWindow?.window)
        } onChange: { [weak self, weak app] in
            Task { @MainActor in
                if let app {
                    self?.followDockIconSetting(app)
                }
            }
        }
    }

    /// The tracker agent's registration: in memory under `-UITesting`, so
    /// the first-launch alert and the Tracker pane register nothing real,
    /// unless `-RealAgent YES` opts in (the ARCH-8 UI tests).
    static func agentService(identity: AppIdentity?, uiTesting: Bool, realAgent: Bool) -> AgentService {
        guard let identity, !uiTesting || realAgent else {
            return FakeAgentService()
        }
        return LoginItemAgentService(identity: identity)
    }

    /// "Open at login": never the real login item under `-UITesting`.
    static func appLoginItem(uiTesting: Bool) -> AppLoginItemService {
        uiTesting ? FakeAppLoginItem() : MainAppLoginItem()
    }

    /// Activation fetches from CloudKit, whose silent pushes can lag
    /// (data_and_sync.md §3.1).
    func applicationDidBecomeActive(_: Notification) {
        host.model?.live?.activated()
    }

    // MARK: Dock

    /// The Dock tile brings back the main window.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        router?.showMainWindow(item: nil)
        return false
    }

    func applicationDockMenu(_: NSApplication) -> NSMenu? {
        statusItem?.dockMenu()
    }

    /// The app keeps running when its last window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    /// The windows that close while the app quits stay in the record the
    /// next login-item launch reopens.
    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        host.model?.openWindows.freeze()
        return .terminateNow
    }

    func applicationWillTerminate(_: Notification) {
        // Quitting ends the Pomodoro; the running entry keeps running.
        host.model?.pomodoro.reset()
        host.model?.live?.stop()
        host.model?.stop()
    }
}
