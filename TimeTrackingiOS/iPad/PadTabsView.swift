// PadTabs: the iPad's tab bar (spec_ios.md §10.1): the Timer, then the
// Planner's Projects, Calendar, Reports, and Activity sections.

import SwiftUI
import TimeTrackingCore

/// The iPad's tabs.
enum PadTab: String, Hashable, CaseIterable {
    case timer
    case projects
    case calendar
    case reports
    case activity

    /// The tab of a Planner section.
    init(_ section: PlannerSection) {
        switch section {
        case .projects: self = .projects
        case .calendar: self = .calendar
        case .reports: self = .reports
        case .activity: self = .activity
        }
    }

    /// The tab a Planner URL selects (spec_ios.md §6.4).
    init(url: TimeTrackingURL) {
        switch url {
        case .calendar: self = .calendar
        case .reports: self = .reports
        case .projects, .project: self = .projects
        case .activity: self = .activity
        case .start, .stop, .continue, .show: self = .timer
        }
    }

    /// The Planner section of the tab; `nil` for the Timer.
    var section: PlannerSection? {
        switch self {
        case .timer: nil
        case .projects: .projects
        case .calendar: .calendar
        case .reports: .reports
        case .activity: .activity
        }
    }

    var title: String {
        section?.title ?? "Timer"
    }

    var systemImage: String {
        section?.symbol ?? "stopwatch"
    }
}

struct PadTabsView: View {
    @Bindable var model: PhoneModel

    var body: some View {
        TabView(selection: $model.padTab) {
            ForEach(PadTab.allCases, id: \.self) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    content(tab)
                }
                .accessibilityIdentifier("pad.tab.\(tab.rawValue)")
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    /// A Planner tab's view exists only once the tab has opened, so the
    /// Calendar asks for calendar access when it first shows (spec_ios.md §11).
    @ViewBuilder
    private func content(_ tab: PadTab) -> some View {
        if tab == .timer {
            TimerScreen(model: model)
        } else if let pad = model.pad, let section = tab.section, pad.opened.contains(section) {
            // Toolbars on the navigation bar.
            NavigationStack {
                PlannerSectionContent(router: pad.router, section: section, clock: model.clock)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .accessibilityIdentifier("pad.section.\(section.rawValue)")
        } else {
            Color.clear
        }
    }
}
