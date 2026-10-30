// LiveStatusSection: the sync and widget update status lines of the General
// pane (spec_data_and_sync.md §3.1, §4.3).

import SwiftUI

/// "iCloud": the `SyncStatus` and the `WidgetPushStatus`.
struct LiveStatusSection: View {
    let live: LiveUpdates

    var body: some View {
        Section("iCloud") {
            LabeledContent("Sync", value: live.syncStatusText)
                .accessibilityIdentifier("settings.syncStatus")
            LabeledContent("Widget updates", value: live.pushStatusText)
                .accessibilityIdentifier("settings.widgetPushStatus")
        }
    }
}
