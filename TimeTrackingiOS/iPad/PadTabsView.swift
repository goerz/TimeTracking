// PadTabs: the iPad's tab bar (spec_ios.md §10.1): the Timer, then the
// Calendar, Reports, Projects, and Activity sections, as in the
// Mac's sidebar.

import SwiftUI
import TimeTrackingCore

/// The iPad's tabs.
enum PadTab: String, Hashable, CaseIterable {
    case timer
    case calendar
    case reports
    case projects
    case activity

    /// The tab of a section.
    init(_ section: MainSection) {
        switch section {
        case .calendar: self = .calendar
        case .reports: self = .reports
        case .projects: self = .projects
        case .activity: self = .activity
        }
    }

    /// The tab a section URL selects (spec_ios.md §6.4).
    init(url: TimeTrackingURL) {
        switch url {
        case .calendar: self = .calendar
        case .reports: self = .reports
        case .projects, .project: self = .projects
        case .activity: self = .activity
        case .start, .stop, .continue, .show: self = .timer
        }
    }

    /// The section of the tab; `nil` for the Timer.
    var section: MainSection? {
        switch self {
        case .timer: nil
        case .calendar: .calendar
        case .reports: .reports
        case .projects: .projects
        case .activity: .activity
        }
    }

    var title: String {
        section?.title ?? "Timer"
    }

    var systemImage: String {
        section?.symbol ?? SymbolName.timer
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

    /// A section tab's view exists only once the tab has opened, so the
    /// Calendar asks for calendar access when it first shows (spec_ios.md §11).
    @ViewBuilder
    private func content(_ tab: PadTab) -> some View {
        if tab == .timer {
            TimerScreen(model: model)
        } else if let pad = model.pad, let section = tab.section, pad.opened.contains(section) {
            // Toolbars on the navigation bar.
            NavigationStack {
                SectionContent(router: pad.router, section: section, clock: model.clock)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .accessibilityIdentifier("pad.section.\(section.rawValue)")
        } else {
            Color.clear
        }
    }
}
