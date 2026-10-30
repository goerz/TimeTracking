// DeviceActivityMonitorExtension: the DeviceActivity monitor's principal
// class (spec_ios.md §9.2). It forwards the callbacks to the library's
// LadderController and only appends to the collection file.

import DeviceActivity
import Foundation
import os
import TimeTrackingCore

final nonisolated class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private static let logger = Logging.logger(category: "Monitor")

    /// The controller over the App Group's state and collection file.
    private var controller: LadderController? {
        guard let identity = AppIdentity.main, let log = CollectionLog.extensionLog(identity: identity) else {
            return nil
        }
        return LadderController(store: CollectionSharedState(identity: identity), monitor: DeviceActivityLadderMonitor(), log: log)
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        do {
            try controller?.intervalDidStart(setID: activity.rawValue)
        } catch {
            Self.logger.error("Registering the day's ladder failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        do {
            try controller?.thresholdReached(event.rawValue)
        } catch {
            Self.logger.error("Logging a ladder step failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
