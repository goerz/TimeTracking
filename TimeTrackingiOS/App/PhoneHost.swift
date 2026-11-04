// PhoneHost: opens the store and builds the PhoneModel with the live
// services at launch, or with recording stand-ins under `-UITesting YES`
// (spec_ios.md §1, §11; spec_architecture.md §3.3).

import CloudKit
import Foundation
import Observation
import os
import TimeTrackingCore

/// Holds the model once the store is open; the scene waits for it.
@Observable
final class PhoneHost {
    private(set) var model: PhoneModel?
    private(set) var onboarding: OnboardingModel?
    private(set) var failure: String?
    @ObservationIgnored let arguments = LaunchArguments.current

    /// Whether the process hosts unit tests (nothing launches).
    static var isTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// The `-UITesting` suite for device settings and the shared state,
    /// cleared by `-ResetState YES`.
    private func uiTestingDefaults(identity: AppIdentity?) -> UserDefaults {
        let name = (identity?.appGroup ?? "TimeTracking") + ".uitesting"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        if arguments.resetState {
            defaults.removePersistentDomain(forName: name)
        }
        return defaults
    }

    /// The load in progress or done; every window's `.task` awaits the same one.
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    /// Opens the store and builds the model once: on the iPad each restored
    /// window calls this, and a second call waits for the first instead of
    /// opening a second store and sync engine.
    func load() async {
        guard !Self.isTestHost else {
            return
        }
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { await self.loadOnce() }
        loadTask = task
        await task.value
        if model == nil {
            // Opening failed: the next window tries again.
            loadTask = nil
        }
    }

    private func loadOnce() async {
        let identity = AppIdentity.main
        let testing = arguments.uiTesting
        let defaults = testing ? uiTestingDefaults(identity: identity) : nil
        let device = defaults.map(DeviceSettings.init(defaults:)) ?? DeviceSettings(identity: identity)
        let shared = defaults.map(WidgetSharedState.init(defaults:)) ?? WidgetSharedState(identity: identity)
        let clock = arguments.clock(honorFixedNow: identity?.isDebug ?? true)
        let store: TimeStore
        do {
            store = try await TimeStore.open(arguments: arguments, identity: identity, deviceID: device.deviceID, clock: clock)
        } catch {
            failure = UserMessage.openingFailed(error)
            Logging.logger(category: "App").error("Opening the store failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        let settings = PhoneSettings(device: device, isPad: DeviceInfo.isPad)
        let model = testing
            ? testingModel(store: store, clock: clock, settings: settings, shared: shared, defaults: defaults ?? .standard)
            : await liveModel(store: store, clock: clock, settings: settings, shared: shared, identity: identity)
        let container = testing ? nil : identity?.cloudKitContainer
        let onboarding = OnboardingModel(settings: settings, shared: shared) {
            await AccountStatus.check(containerIdentifier: container)
        }
        self.model = model
        self.onboarding = onboarding
        if testing, model.pad != nil, let tab = UITestingOptions.padTab {
            model.padTab = tab
        }
        PhoneIntentBridge.shared.attach(model)
        await model.sync?.start()
        await model.start(observing: true)
        await onboarding.check()
        await model.foreground()
    }

    /// Recording services, no sync; set up and onboarded unless asked.
    private func testingModel(
        store: TimeStore,
        clock: any Clock,
        settings: PhoneSettings,
        shared: WidgetSharedState,
        defaults: UserDefaults
    ) -> PhoneModel {
        shared.setupComplete = true
        settings.onboarded = !UITestingOptions.forcesOnboarding
        let folder = FileManager.default.temporaryDirectory.appending(path: "collection-uitesting", directoryHint: .isDirectory)
        if arguments.resetState {
            try? FileManager.default.removeItem(at: folder)
        }
        return PhoneModel(
            store: store,
            clock: clock,
            settings: settings,
            notifications: RecordingScheduler(),
            widgets: RecordingWidgetReloader(),
            shortcuts: RecordingShortcuts(),
            shared: shared,
            collection: CollectionModel.local(folder: folder, defaults: defaults, shared: shared, clock: clock),
            // The iPad's tabs over in-memory activity and calendars; never EventKit.
            pad: settings.isPad ? PadSections.testing(store: store, clock: clock, device: settings.device) : nil
        )
    }

    /// Notifications, WidgetKit, App Shortcuts, CloudKit sync, and the
    /// activity collection.
    private func liveModel(
        store: TimeStore,
        clock: any Clock,
        settings: PhoneSettings,
        shared: WidgetSharedState,
        identity: AppIdentity?
    ) async -> PhoneModel {
        // Only the iPad creates a calendar store (spec_ios.md §10.2).
        let pad = settings.isPad ? await PadSections.live(store: store, clock: clock, device: settings.device, identity: identity) : nil
        let notifications = UserNotifications()
        let widgets = WidgetCenterReloader()
        let collection = identity.flatMap { CollectionModel.live(identity: $0, device: settings.device, shared: shared, clock: clock) }
        let model = PhoneModel(
            store: store,
            clock: clock,
            settings: settings,
            notifications: notifications,
            widgets: widgets,
            shortcuts: AppShortcutsUpdater(),
            shared: shared,
            collection: collection ?? NoCollection(),
            pad: pad
        )
        // Only the iPhone imports from Apple Health (spec_ios.md §7 item 6).
        model.health = settings.isPad ? nil : HealthKitAccess.available()
        if let container = identity?.cloudKitContainer {
            model.sync = CoordinatorSync(store: store, containerIdentifier: container) {
                await widgets.reloadTimelines()
                await widgets.reloadControls()
            }
        }
        notifications.onResponse = { [weak model] category, action, entryID in
            await model?.handleNotification(category, action, entryID: entryID)
        }
        return model
    }
}

/// Test seams read only under `-UITesting YES` (launch arguments in the
/// `-Key value` form land in the standard defaults).
enum UITestingOptions {
    /// `-iCloudAccount none`: onboarding sees no account.
    static var hasNoAccount: Bool {
        UserDefaults.standard.string(forKey: "iCloudAccount") == "none"
    }

    /// `-PadTab calendar`: the iPad's first tab (screenshots).
    static var padTab: PadTab? {
        UserDefaults.standard.string(forKey: "PadTab").flatMap(PadTab.init(rawValue:))
    }

    /// `-Onboarding YES`: run onboarding as on a first launch.
    static var forcesOnboarding: Bool {
        UserDefaults.standard.bool(forKey: "Onboarding")
    }
}

/// The iCloud account status (spec_ios.md §11 item 1).
enum AccountStatus {
    /// `nil` container: UI testing, where only `-iCloudAccount none` says no.
    static func check(containerIdentifier: String?) async -> AccountState {
        guard let containerIdentifier else {
            return UITestingOptions.hasNoAccount ? .unavailable : .available
        }
        let status = try? await CKContainer(identifier: containerIdentifier).accountStatus()
        return status == .available ? .available : .unavailable
    }
}
