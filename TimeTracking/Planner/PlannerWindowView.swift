// PlannerWindowView: the Planner window's split view with the four
// sections (spec_planner_projects.md §1.1; mockups/planner_projects.png).

import SwiftUI
import TimeTrackingCore

/// Sidebar and the selected section; each section owns its toolbar.
struct PlannerWindowView: View {
    @Environment(AppModel.self) private var app
    @State private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        @Bindable var router = app.planner
        NavigationSplitView(columnVisibility: $columns) {
            List(selection: sectionSelection) {
                ForEach(PlannerSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                        .accessibilityIdentifier("planner.sidebar.\(section.rawValue)")
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 280)
            .accessibilityIdentifier("planner.sidebar")
        } detail: {
            PlannerSectionContent(router: router, section: router.section, clock: app.clock) {
                ReportPrinter.print(router.reports)
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .focusedSceneValue(\.plannerWindowActive, true)
        .background(WindowAccessor { window in
            window.setFrameAutosaveName("Planner")
            window.identifier = NSUserInterfaceItemIdentifier("planner")
        })
        .onAppear {
            columns = app.settings.device[.plannerSidebarVisible] ? .all : .detailOnly
            app.plannerOpened()
        }
        .onDisappear { app.plannerClosed() }
        .onChange(of: columns) { _, visibility in
            app.settings.device[.plannerSidebarVisible] = visibility != .detailOnly
        }
    }

    private var sectionSelection: Binding<PlannerSection?> {
        Binding {
            app.planner.section
        } set: { section in
            if let section {
                app.planner.select(section)
            }
        }
    }
}

extension FocusedValues {
    // Set by the Planner window while it is key.
    // swiftlint:disable:next discouraged_optional_boolean
    @Entry var plannerWindowActive: Bool?
}
