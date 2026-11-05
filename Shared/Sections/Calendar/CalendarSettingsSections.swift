// CalendarSettingsSections: the Calendar settings, in the Mac settings
// window's Calendar pane and the iPad's Settings (calendar.md §6).

import SwiftUI
import TimeTrackingCore

/// Snapping, the time-block calendar, Apple Health, and the calendars to
/// show, as sections of a grouped form. All are the same on every device;
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
            timeBlockCalendarRow
        } header: {
            Text("Time blocks")
        } footer: {
            Text("Time blocks are events in this iCloud calendar, so they appear on all your devices and in every calendar app.")
        }
        Section {
            Toggle("Sleep", isOn: health(.sleep))
                .accessibilityIdentifier("settings.calendar.showSleep")
            reportArea(.sleep)
            Toggle("Workouts", isOn: health(.workout))
                .accessibilityIdentifier("settings.calendar.showWorkouts")
            reportArea(.workout)
            if let status = model.healthImportText {
                Text(status)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.calendar.healthImport")
            }
        } header: {
            Text("Apple Health")
        } footer: {
            Text(
                "Sleep and workouts appear as lines in the Activity column, and in Reports as a project of the area you choose. "
                    + "Your iPhone reads them from the Health app; open the app on your iPhone to allow it."
            )
        }
        Section {
            calendarsToShow
        } header: {
            Text("Calendars to show")
        } footer: {
            Text(model.hasCalendarAccess
                ? "Events of these calendars appear in the Calendar column."
                : "The Calendar asks for calendar access the first time it shows its Calendar column.")
        }
    }

    /// A menu of the iCloud account's calendars and "New Calendar…"; the
    /// state's text without access or an iCloud account.
    @ViewBuilder private var timeBlockCalendarRow: some View {
        if let current = model.timeBlockCalendar {
            Picker("Calendar", selection: Binding { current.id } set: { id in choose(id) }) {
                ForEach(choices(including: current)) { calendar in
                    Text(calendar.title).tag(calendar.id)
                }
                Divider()
                Text("New Calendar…").tag(Self.newCalendarTag)
            }
            .accessibilityIdentifier("settings.calendar.timeBlockCalendar")
        } else {
            LabeledContent("Calendar", value: timeBlockCalendarText)
        }
    }

    private static let newCalendarTag = "settings.calendar.new"

    /// The menu's calendars; the current one even when it is not writable.
    private func choices(including current: CalendarInfo) -> [CalendarInfo] {
        let choices = model.timeBlockCalendarChoices
        return choices.contains { $0.id == current.id } ? choices : [current] + choices
    }

    private func choose(_ id: String) {
        if id == Self.newCalendarTag {
            Task { await model.recreateTimeBlockCalendar() }
        } else if let calendar = model.timeBlockCalendarChoices.first(where: { $0.id == id }) {
            Task { await model.chooseTimeBlockCalendar(calendar) }
        }
    }

    /// On the Mac a short scrolling list of checkboxes under their
    /// account, so the pane fits the screen; on the iPad one toggle per
    /// calendar with its account below the title.
    private var calendarsToShow: some View {
        #if os(macOS)
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.tight) {
                    ForEach(model.calendarChoices, id: \.account) { group in
                        Text(group.account)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, Design.Spacing.tight)
                        ForEach(group.calendars) { calendar in
                            Toggle(calendar.title, isOn: shown(calendar)).toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: Self.listHeight)
            .accessibilityIdentifier("settings.calendar.shownCalendars")
        #else
            ForEach(model.calendarChoices, id: \.account) { group in
                ForEach(group.calendars) { calendar in
                    Toggle(isOn: shown(calendar)) {
                        Text(calendar.title)
                        Text(group.account)
                    }
                }
            }
        #endif
    }

    #if os(macOS)
        /// About five calendars, so the Calendar pane stays within the
        /// settings window's tallest pane.
        private static let listHeight: CGFloat = 120
    #endif

    private var timeBlockCalendarText: String {
        switch model.timeBlockState {
        case let .ready(calendar): calendar.title
        case .noICloudAccount: "Time blocks need an iCloud calendar account"
        case .noAccess, nil: "No calendar access"
        }
    }

    /// "In Reports": not counted, or a client or area; off while the kind is.
    private func reportArea(_ kind: HealthPeriod.Kind) -> some View {
        Picker("In Reports", selection: Binding {
            model.healthAreas[kind]
        } set: { area in
            Task { await model.setHealthArea(kind, area) }
        }) {
            Text("Not counted").tag(AreaID?.none)
            Divider()
            ForEach(model.healthAreaChoices, id: \.id) { choice in
                Text(choice.title).tag(AreaID?.some(choice.id))
            }
        }
        .disabled(kind == .sleep ? !model.showSleep : !model.showWorkouts)
        .accessibilityIdentifier("settings.calendar.\(kind.rawValue)Area")
    }

    private func health(_ kind: HealthPeriod.Kind) -> Binding<Bool> {
        Binding {
            kind == .sleep ? model.showSleep : model.showWorkouts
        } set: { isOn in
            Task { await model.setShowHealth(kind, isOn) }
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
