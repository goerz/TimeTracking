// TimeTrackingWidgetPushHandler: stores the widget push token for the app to
// put on this device's Device record (spec_ios.md §4 item 1).

import Foundation
import TimeTrackingCore
import WidgetKit

/// Keeps the token (hex) in the App Group, or nil when no widget is installed.
nonisolated struct TimeTrackingWidgetPushHandler: WidgetPushHandler {
    func pushTokenDidChange(_ pushInfo: WidgetPushInfo, widgets: [WidgetInfo]) {
        let shared = WidgetSharedState(identity: AppIdentity.main)
        shared.pushToken = .some(Self.token(pushInfo.token, widgetCount: widgets.count))
    }

    /// The stored value: the hex token, or nil without widgets.
    static func token(_ data: Data, widgetCount: Int) -> String? {
        widgetCount == 0 ? nil : data.hexString
    }
}
