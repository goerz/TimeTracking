// TimerAlertPresentation: the Timer's confirmation alerts on the Mac and iOS
// (spec_timer_window.md §2.1, §3; spec_ios.md §2.2, §2.5).

import SwiftUI
import TimeTrackingCore

/// Shows `timer.alert`: Discard, Restore Project and Continue, or Delete,
/// each with Cancel.
struct TimerAlertPresentation: ViewModifier {
    @Bindable var timer: TimerModel
    var list: TimerListModel
    /// Off in a Timer view that leaves the alert to another (the Mac's
    /// main window while the Mini Timer shows).
    var active = true

    func body(content: Content) -> some View {
        let isPresented: Binding<Bool> = active ? .isPresent($timer.alert) : .constant(false)
        content.alert(timer.alert?.message ?? "", isPresented: isPresented, presenting: timer.alert) { alert in
            buttons(alert)
        }
    }

    @ViewBuilder
    private func buttons(_ alert: TimerAlert) -> some View {
        switch alert {
        case .discard:
            Button("Discard", role: .destructive) { Task { await timer.discard() } }
                .accessibilityIdentifier("alert.discard")
        case let .restoreProject(id, _):
            Button("Restore Project and Continue") { Task { await timer.restoreProjectAndContinue(id) } }
                .accessibilityIdentifier("alert.restore")
        case let .deleteEntry(id, _):
            Button("Delete", role: .destructive) { Task { await list.delete(id) } }
                .accessibilityIdentifier("alert.delete")
        }
        Button("Cancel", role: .cancel) {}
            .accessibilityIdentifier("alert.cancel")
    }
}

extension View {
    /// The Timer's confirmation alerts (`TimerModel.alert`).
    func timerAlert(timer: TimerModel, list: TimerListModel, active: Bool = true) -> some View {
        modifier(TimerAlertPresentation(timer: timer, list: list, active: active))
    }
}
