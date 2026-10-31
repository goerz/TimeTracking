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
                    PlannerSectionContent(router: app.planner, section: section, clock: app.clock) {
                        ReportPrinter.print(app.planner.reports)
                    }
                    .frame(minWidth: 620, minHeight: 560)
                }
                .accessibilityIdentifier("planner.sidebar.\(section.rawValue)")
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .accessibilityIdentifier("planner.sidebar")
        .focusedSceneValue(\.plannerWindowActive, true)
        .background(WindowAccessor(onWindow: PlannerWindowSetup.configure))
        .onAppear { app.plannerOpened() }
        .onDisappear { app.plannerClosed() }
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
