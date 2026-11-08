// CollectionModel+Factory: the live collection (App Group staging file,
// CloudKit upload, DeviceActivity, Family Controls) and the one for tests
// and UI testing (a temporary folder, an in-memory server, fakes)
// (ios.md §9; architecture.md §3.3).

import Foundation
import Synchronization
import TimeTrackingCore

extension CollectionModel {
    /// The live collection of `identity`, or `nil` without an App Group.
    static func live(identity: AppIdentity, device: DeviceSettings, shared: WidgetSharedState, clock: any Clock) -> CollectionModel? {
        guard let folder = CollectionLog.folder(identity: identity) else {
            return nil
        }
        let systemName = DeviceInfo.systemName
        let uploader = CloudKitDeviceEventUploader(containerIdentifier: identity.cloudKitContainer)
        let staging = DeviceEventStagingFile(folder: folder) { events in
            let name = device[.deviceName]
            try await uploader.upload(CollectionFlush.stamped(events, deviceName: name.isEmpty ? systemName : name))
        }
        let log = CollectionLog(
            state: CollectionSharedState(identity: identity),
            sink: staging,
            deviceID: device.deviceID.rawValue,
            clock: clock
        )
        let model = CollectionModel(
            log: log,
            staging: staging,
            shared: shared,
            authorization: FamilyControlsAuthorization(),
            monitor: DeviceActivityScreenTimeMonitor()
        ) {
            ActivityFolders.resolve(identity: identity)
        }
        model.flushesPeriodically = true
        return model
    }

    /// A collection in `folder` over `server` with fixed Screen Time
    /// authorization and a recording Screen Time monitor.
    static func local(
        folder: URL,
        defaults: UserDefaults,
        shared: WidgetSharedState,
        clock: any Clock,
        server: InMemoryDeviceEventServer = InMemoryDeviceEventServer(),
        screenTime: ScreenTimeStatus = .denied,
        monitor: RecordingScreenTimeMonitor = RecordingScreenTimeMonitor(),
        folders: ActivityFolders? = nil
    ) -> CollectionModel {
        let staging = DeviceEventStagingFile(folder: folder) { events in
            try await server.upload(CollectionFlush.stamped(events, deviceName: "iPhone"))
        }
        let log = CollectionLog(state: CollectionSharedState(defaults: defaults), sink: staging, deviceID: "test-device", clock: clock)
        return CollectionModel(
            log: log,
            staging: staging,
            shared: shared,
            authorization: FixedScreenTime(status: screenTime),
            monitor: monitor
        ) {
            folders
        }
    }
}

/// Records Screen Time registrations (tests, UI testing).
final nonisolated class RecordingScreenTimeMonitor: ScreenTimeMonitoring {
    private let registrations = Mutex<[ScreenTimeRegistration]>([])
    private let stopped = Mutex<[String]>([])

    var all: [ScreenTimeRegistration] {
        registrations.withLock { $0 }
    }

    var stops: [String] {
        stopped.withLock { $0 }
    }

    func startMonitoring(_ registration: ScreenTimeRegistration, for _: ScreenTimeSet) {
        registrations.withLock { $0.append(registration) }
    }

    func stopMonitoring(_ setIDs: [String]) {
        stopped.withLock { $0 += setIDs }
    }
}
