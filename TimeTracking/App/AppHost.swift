// AppHost: opens the store and creates the AppModel at launch
// (spec_architecture.md §2.5, §3.3; spec_data_and_sync.md §7).

import Foundation
import Observation
import os
import TimeTrackingCore

/// Holds the `AppModel` once the store is open; scenes wait for it.
@Observable
final class AppHost {
    private(set) var model: AppModel?
    private(set) var failure: String?
    @ObservationIgnored let arguments = LaunchArguments.current

    /// Whether the process hosts unit tests (no store, no status item).
    static var isTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Device settings: the App Group suite, or a separate suite under
    /// `-UITesting YES` that `-ResetState YES` clears.
    func deviceSettings(identity: AppIdentity?) -> DeviceSettings {
        guard arguments.uiTesting else {
            return DeviceSettings(identity: identity)
        }
        let name = (identity?.appGroup ?? "TimeTracking") + ".uitesting"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        if arguments.resetState {
            defaults.removePersistentDomain(forName: name)
            UserDefaults.standard.removeObject(forKey: SettingsPane.storageKey)
        }
        return DeviceSettings(defaults: defaults)
    }

    /// Opens the store (in memory with the fixture under `-UITesting YES`)
    /// and builds the model with the live services.
    func load( // swiftlint:disable:this function_parameter_count
        notifier: NotificationPosting,
        agent: AgentService,
        readTrackerState: @escaping () async -> TrackerState?,
        trackerCommands: TrackerCommandSending,
        trackerSettingsURL: URL?,
        activity: any ActivityReading,
        calendarEvents: any CalendarEventStore
    ) async -> AppModel? {
        let identity = AppIdentity.main
        let device = deviceSettings(identity: identity)
        let clock = arguments.clock(honorFixedNow: identity?.isDebug ?? true)
        do {
            let store = try await TimeStore.open(arguments: arguments, identity: identity, deviceID: device.deviceID, clock: clock)
            let model = AppModel(
                store: store,
                clock: clock,
                settings: AppSettings(device: device),
                notifier: notifier,
                agent: agent,
                readTrackerState: readTrackerState,
                trackerCommands: trackerCommands,
                trackerSettingsURL: trackerSettingsURL,
                activity: activity,
                calendarEvents: calendarEvents,
                suggestionsCache: identity.flatMap { identity in
                    identity.groupContainerURL.map { identity.supportDirectory(in: $0).appending(path: "suggestions-index.json") }
                }
            )
            self.model = model
            return model
        } catch {
            failure = error.localizedDescription
            Logging.logger(category: "App").error("Opening the store failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
