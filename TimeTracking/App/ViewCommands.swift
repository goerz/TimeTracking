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
        MenuState(router: router, timerKey: timerActive ?? false, plannerKey: plannerActive == true && timerActive != true)
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

    /// The sidebar's items, as on the iPad: Timer (the recorded show/hide
    /// shortcut), ⌘1 to ⌘4, Clients & Areas, and Planner (the last section).
    @ViewBuilder private var sectionItems: some View {
        timerButton
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
        Button("Planner") { app?.router?.openPlanner() }
            .keyboardShortcut("p", modifiers: [.command, .option])
    }

    /// View › Timer displays the recorded show/hide shortcut.
    @ViewBuilder private var timerButton: some View {
        let button = Button("Timer") { app?.router?.showTimer(focusTask: false) }
        if let key = app?.showHideKey, let character = key.key.first {
            button.keyboardShortcut(KeyEquivalent(character), modifiers: key.eventModifiers)
        } else {
            button
        }
    }

    /// Scroll to Today, while the Timer shows. Compact Mode and Float on Top
    /// belong to a separate mini window (not in this experiment).
    private var timerItems: some View {
        Button("Scroll to Today") { app?.list.scrollToTop() }
            .contextCommand(KeyboardShortcut(.upArrow), enabled: state.timerKey)
    }
}
