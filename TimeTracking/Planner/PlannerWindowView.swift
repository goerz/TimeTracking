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
            PlannerDetailView(router: router)
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

/// The selected section. Calendar and Activity are step 7b's seams.
struct PlannerDetailView: View {
    @Environment(AppModel.self) private var app
    var router: PlannerRouter

    var body: some View {
        switch router.section {
        case .projects:
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                ProjectsView(model: router.projects, now: app.clock.now)
            }
        case .reports:
            ReportsView(model: router.reports) {
                ReportPrinter.print(router.reports)
            }
        case .calendar, .activity:
            PlannerSectionPlaceholder(section: router.section)
        }
    }
}

/// Calendar and Activity until step 7b fills them in.
struct PlannerSectionPlaceholder: View {
    var section: PlannerSection

    var body: some View {
        ContentUnavailableView(section.title, systemImage: section.symbol)
            .navigationTitle(section.title)
            .accessibilityIdentifier("planner.\(section.rawValue)")
    }
}

extension FocusedValues {
    // Set by the Planner window while it is key.
    // swiftlint:disable:next discouraged_optional_boolean
    @Entry var plannerWindowActive: Bool?
}
