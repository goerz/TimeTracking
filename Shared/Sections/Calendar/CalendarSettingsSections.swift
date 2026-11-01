// CalendarSettingsSections: the Calendar settings, in the Mac settings
// window's Calendar pane and the iPad's Settings (spec_calendar.md §6).

import SwiftUI
import TimeTrackingCore

/// Snapping, the time-block calendar, and the calendars to show, as
/// sections of a grouped form. All three are the same on every device;
/// they load when the sections appear.
struct CalendarSettingsSections: View {
    var model: CalendarModel

    var body: some View {
        sections
            .task { await model.loadSettings() }
    }

    @ViewBuilder private var sections: some View {
        Section {
            Picker("Snap to", selection: Binding { model.snapMinutes } set: { minutes in Task { await model.setSnapMinutes(minutes) } }) {
                ForEach(CalendarSnap.choices, id: \.self) { Text("\($0) min").tag($0) }
            }
            .accessibilityIdentifier("settings.calendar.snap")
        } footer: {
            Text("Entries and time blocks you draw, move, or resize start and end on this step.")
        }
        Section {
            LabeledContent("Calendar", value: timeBlockCalendarText)
            Button("Create New Calendar") { Task { await model.recreateTimeBlockCalendar() } }
                .disabled(!model.hasCalendarAccess)
        } header: {
            Text("Time blocks")
        } footer: {
            Text("Time blocks are events in this iCloud calendar, so they appear on all your devices and in every calendar app.")
        }
        Section {
            ForEach(model.calendarChoices, id: \.account) { group in
                ForEach(group.calendars) { calendar in
                    Toggle(isOn: shown(calendar)) {
                        Text(calendar.title)
                        Text(group.account)
                    }
                }
            }
        } header: {
            Text("Calendars to show")
        } footer: {
            Text(model.hasCalendarAccess
                ? "Events of these calendars appear in the Calendar column."
                : "The Calendar asks for calendar access the first time it shows its Calendar column.")
        }
    }

    private var timeBlockCalendarText: String {
        switch model.timeBlockState {
        case let .ready(calendar): calendar.title
        case .noICloudAccount: "Time blocks need an iCloud calendar account"
        case .noAccess, nil: "No calendar access"
        }
    }

    private func shown(_ calendar: CalendarInfo) -> Binding<Bool> {
        Binding {
            model.shownCalendars.contains(calendar.choice)
        } set: { shown in
            Task { await model.setShown(calendar, shown) }
        }
    }
}
