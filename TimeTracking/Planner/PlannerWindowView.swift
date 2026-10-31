// PlannerWindowView: the main window's split view with the Timer and the
// four sections (spec_planner_projects.md §1.1; experiment: the Timer is
// the sidebar's first item, as on the iPad).

import SwiftUI
import TimeTrackingCore

/// A sidebar item: the Timer or a Planner section.
enum MainSidebarItem: Hashable {
    case timer
    case section(PlannerSection)
}

/// Sidebar and the selected item; each section owns its toolbar.
struct PlannerWindowView: View {
    @Environment(AppModel.self) private var app
    @State private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        @Bindable var router = app.planner
        NavigationSplitView(columnVisibility: $columns) {
            List(selection: sidebarSelection) {
                Label("Timer", systemImage: "timer")
                    .tag(MainSidebarItem.timer)
                    .accessibilityIdentifier("planner.sidebar.timer")
                ForEach(PlannerSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(MainSidebarItem.section(section))
                        .accessibilityIdentifier("planner.sidebar.\(section.rawValue)")
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 280)
            .accessibilityIdentifier("planner.sidebar")
        } detail: {
            if app.showsTimer {
                TimerWindowView(embedded: true)
                    .navigationTitle("Timer")
                    .frame(minWidth: TimerWindowGeometry.minimumWidth, minHeight: 300)
            } else {
                PlannerSectionContent(router: router, section: router.section, clock: app.clock) {
                    ReportPrinter.print(router.reports)
                }
                .frame(minWidth: 620, minHeight: 560)
            }
        }
        .focusedSceneValue(\.plannerWindowActive, true)
        .background(WindowAccessor(onWindow: PlannerWindowSetup.configure))
        .onAppear {
            columns = app.settings.device[.plannerSidebarVisible] ? .all : .detailOnly
            app.plannerOpened()
        }
        .onDisappear { app.plannerClosed() }
        .onChange(of: columns) { _, visibility in
            app.settings.device[.plannerSidebarVisible] = visibility != .detailOnly
        }
    }

    private var sidebarSelection: Binding<MainSidebarItem?> {
        Binding {
            app.showsTimer ? .timer : .section(app.planner.section)
        } set: { item in
            switch item {
            case .timer:
                app.showsTimer = true
            case let .section(section):
                app.showsTimer = false
                app.planner.select(section)
            case nil:
                break
            }
        }
    }
}

extension FocusedValues {
    // Set by the Planner window while it is key.
    // swiftlint:disable:next discouraged_optional_boolean
    @Entry var plannerWindowActive: Bool?
}
