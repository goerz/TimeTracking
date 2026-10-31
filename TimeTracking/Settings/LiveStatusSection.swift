// LiveStatusSection: the sync and widget update status lines of the General
// pane (spec_data_and_sync.md §3.1, §4.3).

import SwiftUI

/// "iCloud": the `SyncStatus` and the `WidgetPushStatus`.
struct LiveStatusSection: View {
    let live: LiveUpdates

    var body: some View {
        Section {
            LabeledContent("Sync", value: live.syncStatusText)
                .accessibilityIdentifier("settings.syncStatus")
            LabeledContent("Widget updates") {
                HStack(spacing: Design.Spacing.small) {
                    Text(live.pushStatusText)
                        .accessibilityIdentifier("settings.widgetPushStatus")
                    InfoButton(info: Self.widgetUpdatesInfo)
                        .accessibilityIdentifier("settings.widgetPushInfo")
                }
            }
        } header: {
            Text("iCloud")
        }
    }

    /// How widget pushes work and how to install the push key.
    static let widgetUpdatesInfo = SettingsInfo(
        title: "Widget updates",
        paragraphs: [
            "When you start, stop, or change a timer, this Mac sends a push to your iPhone and iPad, and their "
                + "widgets show the change within seconds. The push needs an APNs key from your Apple developer "
                + "account, stored in this Mac's Keychain.",
            "Without the key, widgets show a change only when iOS reloads them, often many minutes later.",
            "To install the key, open Certificates, Identifiers & Profiles › Keys on developer.apple.com, add a "
                + "key with Apple Push Notifications service enabled, and download AuthKey_<KEYID>.p8 (Apple offers "
                + "the download only once, so keep a copy). With the app installed in Applications, run this "
                + "command in Terminal in the project folder, with the path to your file. The next push changes "
                + "the line here to \"Last sent at …\".",
        ],
        snippet: "make apns-key P8=~/Downloads/AuthKey_<KEYID>.p8"
    )
}
