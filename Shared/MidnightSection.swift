// MidnightSection: the Midnight setting, in the Mac's General pane and the
// iOS Settings (spec_data_and_sync.md §8).

import SwiftUI
import TimeTrackingCore

/// When the app's days change. The setting is synced, so it is the same on
/// every device.
struct MidnightSection: View {
    let store: TimeStore
    @State private var hour = SyncedSettingKey<Int>.midnightHour.defaultValue

    var body: some View {
        Section {
            Picker("Midnight", selection: Binding { hour } set: { choose($0) }) {
                ForEach(0 ..< 24, id: \.self) { Text(ActivityText.clock(hour: $0)).tag($0) }
            }
            .accessibilityIdentifier("settings.midnight")
        } footer: {
            Text(
                "The Calendar, reports, and totals change to the next day at this time. Choose the middle of your night, "
                    + "when you are least likely to be active. What is recorded doesn't change."
            )
        }
        .task { hour = await (try? store.value(.midnightHour)) ?? hour }
    }

    private func choose(_ value: Int) {
        hour = value
        Task { try? await store.set(.midnightHour, value) }
    }
}
