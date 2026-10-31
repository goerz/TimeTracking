// ViewCommands: the View menu (experiment: one window, object menus).

import SwiftUI
import TimeTrackingCore

/// The sidebar's items (⌘1 to ⌘5), the sidebar, the shown range's
/// navigation, then each view's display options under its own header,
/// enabled while that view shows.
struct ViewCommands: Commands {
    var host: AppHost
    @FocusedValue(\.plannerWindowActive) private var windowActive
    @FocusedValue(\.timerWindowActive) private var timerActive

    private var app: AppModel? {
        host.model
    }

    private var router: PlannerRouter? {
        host.model?.planner
    }

    private var state: MenuState {
        MenuState(app: app, mainKey: windowActive == true, timerViewKey: timerActive == true)
    }

    var body: some Commands {
        SidebarCommands()
        CommandGroup(before: .sidebar) {
            sidebarItems
            Divider()
        }
        CommandGroup(after: .sidebar) {
            Divider()
            if let router {
                // Shared with the iPad, then the Mac's own Mini Timer options.
                ViewDisplayItems(router: router, state: state) { app?.activeTimer.list.scrollToTop() }
                Section("Mini Timer") {
                    miniTimerItems
                }
            }
        }
    }

    /// The Mini Timer is key (not the main window's Timer tab).
    private var miniKey: Bool {
        timerActive == true && windowActive != true
    }

    /// Compact Mode and Float on Top, as for the former Timer window.
    @ViewBuilder private var miniTimerItems: some View {
        Toggle("Compact Mode", isOn: Binding(
            get: { app?.window?.isCompact ?? false },
            set: { _ in app?.toggleCompact() }
        ))
        .contextCommand(KeyboardShortcut("m", modifiers: [.command, .shift]), enabled: miniKey)
        Toggle("Float on Top", isOn: Binding(
            get: { app?.settings.timerPinned ?? false },
            set: { app?.setPinned($0) }
        ))
        .disabled(!miniKey)
    }

    /// Timer ⌘1 (the main window's tab), then Calendar ⌘2 to Activity ⌘5.
    @ViewBuilder private var sidebarItems: some View {
        Button("Timer") { (app?.router as? WindowRouter)?.showMainTimer() }
            .keyboardShortcut("1")
        ForEach(PlannerSection.allCases) { section in
            Button(section.title) {
                router?.select(section)
                app?.router?.openPlanner()
            }
            .keyboardShortcut(section.mainWindowKey)
        }
    }
}
