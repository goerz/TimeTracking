// LiveStatusSection: the sync and widget update status lines of the General
// pane (spec_data_and_sync.md §3.1, §4.3).

import SwiftUI
import TimeTrackingCore

/// "iCloud": the `SyncStatus` and the `WidgetPushStatus`.
struct LiveStatusSection: View {
    let live: LiveUpdates

    var body: some View {
        Section {
            LabeledContent("Sync", value: live.syncStatusText)
                .accessibilityIdentifier("settings.syncStatus")
            LabeledContent("Widget updates", value: live.pushStatusText)
                .accessibilityIdentifier("settings.widgetPushStatus")
        } header: {
            Text("iCloud")
        } footer: {
            if live.pushStatus == .noKey {
                Text("""
                Without the APNs push key, iPhone and iPad widgets show a change only when iOS reloads them, \
                often many minutes later. Install the key with "make apns-key".
                """)
            }
        }
    }
}
