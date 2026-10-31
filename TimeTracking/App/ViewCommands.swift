// ViewCommands: the main menu's View menu (spec_timer_window.md §9;
// spec_planner_projects.md §1.2).

import SwiftUI
import TimeTrackingCore

/// The Planner's sections, which open the Planner from either window; the
/// shown range's navigation (shared with the iPad); then the Timer window's
/// view options.
struct ViewCommands: Commands {
    var host: AppHost
    @FocusedValue(\.timerWindowActive) private var timerActive
    @FocusedValue(\.plannerWindowActive) private var plannerActive

    private var app: AppModel? {
        host.model
    }

    private var router: PlannerRouter? {
        host.model?.planner
    }

    private var state: MenuState {
        MenuState(router: router, timerKey: timerActive ?? false, plannerKey: plannerActive ?? false)
    }

    var body: some Commands {
        SidebarCommands()
        CommandGroup(before: .sidebar) {
            sectionItems
            Divider()
            if let router {
                PlannerNavigationItems(router: router, state: state)
            }
            Divider()
            timerItems
            Divider()
        }
    }

    /// ⌘1 to ⌘4 and Clients & Areas: the section, in the Planner brought forward.
    @ViewBuilder private var sectionItems: some View {
        ForEach(PlannerSection.allCases) { section in
            Button(section.title) {
                router?.select(section)
                app?.router?.openPlanner()
            }
            .keyboardShortcut(KeyEquivalent(section.key))
        }
        Button("Clients & Areas") {
            router?.showClientsAndAreas()
            app?.router?.openPlanner()
        }
        .keyboardShortcut("1", modifiers: [.command, .option])
    }

    /// Compact Mode, Float on Top, and Scroll to Today, while the Timer
    /// window is key.
    @ViewBuilder private var timerItems: some View {
        Toggle("Compact Mode", isOn: Binding(
            get: { app?.window?.isCompact ?? false },
            set: { _ in app?.toggleCompact() }
        ))
        .contextCommand(KeyboardShortcut("m", modifiers: [.command, .shift]), enabled: state.timerKey)
        Toggle("Float on Top", isOn: Binding(
            get: { app?.settings.timerPinned ?? false },
            set: { app?.setPinned($0) }
        ))
        .disabled(!state.timerKey)
        Button("Scroll to Today") { app?.list.scrollToTop() }
            .contextCommand(KeyboardShortcut(.upArrow), enabled: state.timerKey)
    }
}
