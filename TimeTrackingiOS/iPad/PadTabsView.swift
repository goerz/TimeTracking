// PadTabs: the iPad's tab bar (spec_ios.md §10.1). The Timer is the first
// tab; the Planner tabs are placeholders until step 8c.

import SwiftUI
import TimeTrackingCore

/// The iPad's tabs.
enum PadTab: String, Hashable, CaseIterable {
    case timer
    case projects
    case calendar
    case reports
    case activity

    var title: String {
        switch self {
        case .timer: "Timer"
        case .projects: "Projects"
        case .calendar: "Calendar"
        case .reports: "Reports"
        case .activity: "Activity"
        }
    }

    var systemImage: String {
        switch self {
        case .timer: "timer"
        case .projects: "folder"
        case .calendar: "calendar"
        case .reports: "chart.bar"
        case .activity: "waveform.path.ecg"
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
}

struct PadTabsView: View {
    @Bindable var model: PhoneModel

    var body: some View {
        TabView(selection: $model.padTab) {
            ForEach(PadTab.allCases, id: \.self) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    if tab == .timer {
                        TimerScreen(model: model)
                    } else {
                        ContentUnavailableView(tab.title, systemImage: tab.systemImage, description: Text("Coming with the iPad Planner."))
                            .accessibilityIdentifier("pad.placeholder.\(tab.rawValue)")
                    }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}
