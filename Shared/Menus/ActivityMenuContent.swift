// ActivityMenuContent: the Activity menu's items, on the Mac and the iPad
// (activity.md §2, §5).

import SwiftUI
import TimeTrackingCore

/// The Activity menu; its range commands are View › Go to Today, Previous
/// Period, Next Period, and Date Range…. The iPad has
/// no exclusion shortcut (activity.md §5).
struct ActivityMenuContent: View {
    var model: ActivityModel
    var enabled: Bool

    var body: some View {
        // Escape's two steps, titled by the one it takes now.
        Button(model.drill == nil ? "Clear Filter" : "Back") { Task { await model.escape() } }
            .disabled(!enabled || (model.drill == nil && model.apps.isEmpty))
        #if os(macOS)
            Divider()
            Button("Exclude from Tracking…") {
                if let row = model.drill {
                    model.exclude(workspace: row)
                } else if let app = model.apps.first {
                    model.exclude(app: app)
                }
            }
            .disabled(!enabled || (model.apps.count != 1 && model.drill == nil))
        #endif
    }
}
