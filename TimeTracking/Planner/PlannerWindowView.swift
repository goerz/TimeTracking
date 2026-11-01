// PlannerWindowView: the main window, the Timer and the four sections in
// the iPad's adaptable tab view, which the Mac shows as a sidebar
// (spec_planner_projects.md §1.1; experiment).

import SwiftUI
import TimeTrackingCore

/// A sidebar item: the Timer or a Planner section.
enum MainSidebarItem: Hashable {
    case timer
    case section(PlannerSection)
}

/// The same `TabView` as the iPad's (`PadTabsView`): Timer, Projects,
/// Calendar, Reports, Activity. On the Mac `.sidebarAdaptable` is a
/// sidebar; each section owns its toolbar.
struct PlannerWindowView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.undoManager) private var undoManager
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        TabView(selection: selection) {
            Tab("Timer", systemImage: SymbolName.timer, value: MainSidebarItem.timer) {
                TimerWindowView(embedded: true)
                    .navigationTitle("Timer")
                    .frame(minWidth: TimerWindowGeometry.minimumWidth, minHeight: 300)
            }
            .accessibilityIdentifier("planner.sidebar.timer")
            ForEach(PlannerSection.allCases) { section in
                Tab(section.title, systemImage: section.symbol, value: MainSidebarItem.section(section)) {
                    PlannerSectionContent(router: app.planner, section: section, clock: app.clock)
                        .frame(minWidth: 620, minHeight: 560)
                }
                .accessibilityIdentifier("planner.sidebar.\(section.rawValue)")
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .accessibilityIdentifier("planner.sidebar")
        .focusedSceneValue(\.plannerWindowActive, true)
        .background(WindowAccessor { window in
            PlannerWindowSetup.configure(window)
            if app.hidesMainWindowOnAttach {
                app.hidesMainWindowOnAttach = false
                window.close()
            }
        })
        .onAppear { app.plannerOpened() }
        .onDisappear {
            app.plannerClosed()
            app.windowActivated(.mainWindow, isKey: false, undoManager: nil)
        }
        .onChange(of: appearsActive, initial: true) { _, active in
            app.windowActivated(.mainWindow, isKey: active, undoManager: undoManager)
        }
        // The Timer's alerts raised while this window is key, over any item
        // (spec_timer_window.md §1).
        .timerAlert(timer: app.timer, list: app.mainTimer.list, active: app.alertWindow == .mainWindow)
    }

    private var selection: Binding<MainSidebarItem> {
        Binding {
            app.showsTimer ? .timer : .section(app.planner.section)
        } set: { item in
            switch item {
            case .timer:
                app.showsTimer = true
            case let .section(section):
                app.showsTimer = false
                app.planner.select(section)
            }
        }
    }
}

extension FocusedValues {
    // Set by the main window while it is key.
    // swiftlint:disable:next discouraged_optional_boolean
    @Entry var plannerWindowActive: Bool?
}
