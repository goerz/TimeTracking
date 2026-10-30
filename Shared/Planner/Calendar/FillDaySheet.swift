// FillDaySheet, the options popover, and the Suggestions sheet
// (spec_planner_calendar.md §3.5, §5.5, §7).

import SwiftUI
import TimeTrackingCore

/// The Fill Day review sheet.
struct FillDaySheet: View {
    @Bindable var model: FillDayModel
    var calendar: CalendarModel
    @State private var pickerRow: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fill \(DayText.weekdayShortDate(model.day))").font(.title3.bold())
            if model.rows.isEmpty {
                Text("Nothing left to fill.").foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.rows) { row in
                        rowView(row)
                    }
                }
            }
            HStack {
                Button("Cancel") { calendar.cancelFillDay() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(model.logTitle) { Task { await calendar.logFillDay() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.rows.contains(where: \.checked))
                    .accessibilityIdentifier("fillDay.log")
            }
        }
        .padding()
        .frame(minWidth: 640, minHeight: 360)
        .accessibilityIdentifier("fillDay")
    }

    private func rowView(_ row: FillDayRow) -> some View {
        let zone = calendar.calendar.timeZone
        let interval = row.proposal.interval
        return HStack(spacing: 8) {
            Toggle("", isOn: Binding { row.checked } set: { _ in model.toggle(row.id) }).labelsHidden()
            VStack(alignment: .leading) {
                Text(CalendarText.range(interval.start, interval.end, zone: zone))
                Text(DurationText.hoursMinutes(Int(interval.duration))).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 110, alignment: .leading)
            Text(row.proposal.summary)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)
                .help(row.proposal.items.map { "\($0.context) \($0.subject) \(ActivityText.duration($0.seconds))" }.joined(separator: "\n"))
            Button(calendar.project(row.projectID)?.name ?? "No project") { pickerRow = row.id }
                .popover(isPresented: Binding { pickerRow == row.id } set: {
                    if !$0 {
                        pickerRow = nil
                    }
                }) {
                    ProjectPickerView(model: ProjectPickerModel(
                        store: calendar.store,
                        currentProject: row.projectID,
                        taskMatching: false
                    )) { choice in
                        if case let .project(id) = choice {
                            model.setProject(id, row: row.id)
                        }
                        pickerRow = nil
                    }
                }
            TextField(
                row.proposal.startsChecked ? "Task" : "No confident suggestion",
                text: Binding { row.task } set: { model.setTask($0, row: row.id) }
            )
            ConfidenceMeter(candidate: row.proposal.top)
            Button("Skip") { model.skip(row.id) }
        }
    }
}

/// The options popover (§7).
struct CalendarOptionsPopover: View {
    @Bindable var model: CalendarModel

    var body: some View {
        Form {
            Picker("Snap to", selection: Binding { model.snapMinutes } set: { minutes in Task { await model.setSnapMinutes(minutes) } }) {
                ForEach(CalendarSnap.choices, id: \.self) { Text("\($0) min").tag($0) }
            }
            Section("Calendars to show") {
                ForEach(model.calendarChoices, id: \.account) { group in
                    Text(group.account).font(.caption).foregroundStyle(.secondary)
                    ForEach(group.calendars) { calendar in
                        Toggle(calendar.title, isOn: Binding {
                            model.shownCalendars.contains(calendar.choice)
                        } set: { shown in
                            Task { await model.setShown(calendar, shown) }
                        })
                    }
                }
            }
            Section("Time blocks") {
                HStack {
                    Text(model.timeBlockCalendar?.title ?? "No time-block calendar")
                    Spacer()
                    Button("Recreate") { Task { await model.recreateTimeBlockCalendar() } }
                }
            }
            Button("Suggestions…") {
                model.showsOptions = false
                model.showsSuggestions = true
            }
        }
        .padding()
        .frame(width: 340)
    }
}

/// The Suggestions sheet: rules, Fill Day minimum, training window, the
/// feedback report, and Rebuild (§5.5, §7).
struct SuggestionsSheet: View {
    @Bindable var model: CalendarModel
    @State private var report: SuggestionFeedbackReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggestions").font(.title3.bold())
            Table(model.rules) {
                TableColumn("Kind") { rule in Text(rule.kind.title) }
                TableColumn("Pattern") { rule in Text(rule.pattern) }
                TableColumn("Project and task") { rule in
                    Text(rule.ignore ? "Ignore" : [model.project(rule.projectID)?.name, rule.task].compactMap(\.self)
                        .joined(separator: " · "))
                }
                TableColumn("") { rule in
                    Button("Remove") { Task { await model.setRules(model.rules.filter { $0.id != rule.id }) } }
                }
            }
            .frame(minHeight: 160)
            Stepper("Fill Day minimum: \(model.fillMinMinutes) min", value: Binding { model.fillMinMinutes } set: { value in
                Task { await model.setFillMinMinutes(value) }
            }, in: 1 ... 30)
            Stepper("Training window: \(model.trainDays) days", value: Binding { model.trainDays } set: { value in
                Task { await model.setTrainDays(value) }
            }, in: 30 ... 730, step: 30)
            if let report {
                Text(
                    "Last 30 days: \(report.accepted) accepted, \(report.edited) edited, \(report.skipped) skipped; top-1 acceptance \(Int((report.acceptanceRate * 100).rounded()))%"
                )
                .foregroundStyle(.secondary)
            }
            HStack {
                Button("Rebuild Suggestions Index") { Task { await model.rebuildIndex() } }
                Spacer()
                Button("Done") { model.showsSuggestions = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 420)
        .task {
            let now = model.clock.now
            let feedback = await (try? model.store.feedback(in: DateInterval(start: now - 30 * 86_400, end: now + 1))) ?? []
            report = SuggestionFeedbackReport(feedback)
        }
    }
}
