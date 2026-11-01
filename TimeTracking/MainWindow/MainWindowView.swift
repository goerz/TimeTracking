// MainWindowView: the main window, the Timer and the four sections in
// the iPad's adaptable tab view, which the Mac shows as a sidebar
// (spec_projects.md §1.1).

import SwiftUI
import TimeTrackingCore

/// A sidebar item: the Timer or a section.
enum MainSidebarItem: Hashable {
    case timer
    case section(MainSection)
}

/// The same `TabView` as the iPad's (`PadTabsView`): Timer, Projects,
/// Calendar, Reports, Activity. On the Mac `.sidebarAdaptable` is a
/// sidebar; each section owns its toolbar.
struct MainWindowView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.undoManager) private var undoManager
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        TabView(selection: selection) {
            Tab("Timer", systemImage: SymbolName.timer, value: MainSidebarItem.timer) {
                TimerView(embedded: true)
                    .navigationTitle("Timer")
                    .frame(minWidth: MiniTimerGeometry.minimumWidth, minHeight: 300)
            }
            .accessibilityIdentifier("main.sidebar.timer")
            ForEach(MainSection.allCases) { section in
                Tab(section.title, systemImage: section.symbol, value: MainSidebarItem.section(section)) {
                    SectionContent(router: app.sections, section: section, clock: app.clock)
                        .frame(minWidth: 620, minHeight: 560)
                }
                .accessibilityIdentifier("main.sidebar.\(section.rawValue)")
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .accessibilityIdentifier("main.sidebar")
        .focusedSceneValue(\.mainWindowActive, true)
        .background(WindowAccessor { window in
            MainWindowSetup.configure(window)
            if app.hidesMainWindowOnAttach {
                app.hidesMainWindowOnAttach = false
                window.close()
            }
        })
        .onAppear { app.mainWindowOpened() }
        .onDisappear {
            app.mainWindowClosed()
            app.windowActivated(.mainWindow, isKey: false, undoManager: nil)
        }
        .onChange(of: appearsActive, initial: true) { _, active in
            app.windowActivated(.mainWindow, isKey: active, undoManager: undoManager)
        }
        // The Timer's alerts raised while this window is key, over any item
        // (spec_timer.md §1).
        .timerAlert(timer: app.timer, list: app.mainTimer.list, active: app.alertWindow == .mainWindow)
    }

    private var selection: Binding<MainSidebarItem> {
        Binding { app.mainItem } set: { app.mainItem = $0 }
    }
}

extension FocusedValues {
    // Set by the main window while it is key.
    // swiftlint:disable:next discouraged_optional_boolean
    @Entry var mainWindowActive: Bool?
}
