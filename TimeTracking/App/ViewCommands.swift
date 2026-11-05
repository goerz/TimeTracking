// ViewCommands: the View menu (timer.md §9).

import SwiftUI
import TimeTrackingCore

/// The sidebar's items (⌘1 to ⌘5), the sidebar, the shown range's
/// navigation, then each view's display options under its own header,
/// enabled while that view shows.
struct ViewCommands: Commands {
    var host: AppHost
    @FocusedValue(\.mainWindowActive) private var windowActive
    @FocusedValue(\.timerViewActive) private var timerActive

    private var app: AppModel? {
        host.model
    }

    private var router: SectionRouter? {
        host.model?.sections
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

    /// The Mini Timer's Compact Mode and Float on Top.
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
        Button("Timer") { app?.router?.showMainWindow(item: .timer) }
            .keyboardShortcut("1")
        ForEach(MainSection.allCases) { section in
            Button(section.title) { app?.router?.showMainWindow(item: .section(section)) }
                .keyboardShortcut(section.mainWindowKey)
        }
    }
}
