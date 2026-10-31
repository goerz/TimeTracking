// TimerAlertPresentation: the Timer's confirmation alerts on the Mac and iOS
// (spec_timer_window.md §2.1, §3; spec_ios.md §2.2, §2.5).

import SwiftUI
import TimeTrackingCore

/// Shows `timer.alert`: Discard, Restore Project and Continue, or Delete,
/// each with Cancel.
struct TimerAlertPresentation: ViewModifier {
    @Bindable var timer: TimerModel
    var list: TimerListModel
    /// False in a Timer view that leaves the alert to another (on the Mac,
    /// the view other than the one the action came from); asked once, when
    /// an alert is raised, so it stays where it opened.
    var isActive: @MainActor () -> Bool = { true }
    /// Whether this view shows the current alert.
    @State private var owns = false

    func body(content: Content) -> some View {
        let isPresented: Binding<Bool> = owns ? .isPresent($timer.alert) : .constant(false)
        content
            .alert(timer.alert?.message ?? "", isPresented: isPresented, presenting: timer.alert) { alert in
                buttons(alert)
            }
            .onChange(of: timer.alert != nil, initial: true) { _, raised in
                owns = raised && isActive()
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
    func timerAlert(
        timer: TimerModel,
        list: TimerListModel,
        isActive: @escaping @MainActor () -> Bool = { true }
    ) -> some View {
        modifier(TimerAlertPresentation(timer: timer, list: list, isActive: isActive))
    }
}
