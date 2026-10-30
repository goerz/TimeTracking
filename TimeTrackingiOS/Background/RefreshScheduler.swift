// RefreshScheduler: the BGAppRefreshTask, rescheduled 15 minutes after
// each run (spec_ios.md §7 item 1).

import BackgroundTasks
import Foundation
import TimeTrackingCore

enum RefreshScheduler {
    /// `BGTaskSchedulerPermittedIdentifiers` in the Info.plist: `<APP_ID>.refresh`.
    static var identifier: String {
        (AppIdentity.main?.appID ?? "TimeTracking") + ".refresh"
    }

    static let interval: TimeInterval = 15 * 60

    /// Asks for the next refresh 15 minutes from now.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        BGTaskScheduler.shared.submitTaskRequest(request) { _ in }
    }

    /// One refresh: sync, token upload, fan-out; then the next request.
    static func run() async {
        schedule()
        let model = await PhoneIntentBridge.shared.awaitModel()
        await model.refreshTask()
    }
}
