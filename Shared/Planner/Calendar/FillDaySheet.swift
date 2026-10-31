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
        VStack(alignment: .leading, spacing: Design.Spacing.medium) {
            Text("Fill \(DayText.weekdayShortDate(model.day))").font(.headline).frame(maxWidth: .infinity)
            if model.rows.isEmpty {
                ContentUnavailableView(
                    "Nothing Left to Fill",
                    systemImage: SymbolName.suggestions,
                    description: Text("All activity on this day is tracked or too short to suggest.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: Design.Spacing.small) {
                        ForEach(model.rows) { row in
                            rowView(row)
                        }
                    }
                }
            }
            // The dialog footer of DialogScaffold: Cancel, then the
            // confirming action, at the trailing edge.
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { calendar.cancelFillDay() }
                    .keyboardShortcut(.cancelAction)
                Button(model.logTitle) { Task { await calendar.logFillDay() } }
                    .keyboardShortcut(.defaultAction)
                #if os(macOS)
                    .buttonStyle(.borderedProminent)
                #endif
                    .disabled(!model.rows.contains(where: \.checked))
                    .accessibilityIdentifier("fillDay.log")
            }
        }
        .padding(Design.Spacing.content)
        .frame(minWidth: 640, minHeight: 360)
        .accessibilityIdentifier("fillDay")
    }

    private func rowView(_ row: FillDayRow) -> some View {
        let zone = calendar.calendar.timeZone
        let interval = row.proposal.interval
        return HStack(spacing: Design.Spacing.small) {
            Toggle("", isOn: Binding { row.checked } set: { _ in model.toggle(row.id) }).labelsHidden()
            VStack(alignment: .leading) {
                Text(CalendarText.range(interval.start, interval.end, zone: zone))
                Text(ActivityText.duration(Int(interval.duration))).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            .frame(width: 110, alignment: .leading)
            Text(row.proposal.summary)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)
                .help(row.proposal.itemsText)
            projectButton(row)
            TextField(
                row.proposal.startsChecked ? "Task" : "No suggestion",
                text: Binding { row.task } set: { model.setTask($0, row: row.id) }
            )
            ConfidenceMeter(candidate: row.proposal.top)
            Button("Skip") { model.skip(row.id) }
        }
    }

    private func projectButton(_ row: FillDayRow) -> some View {
        let shown = Binding { pickerRow == row.id } set: { (shown: Bool) in
            if !shown {
                pickerRow = nil
            }
        }
        return ProjectChipButton(label: calendar.label(row.projectID)) { pickerRow = row.id }
            .popover(isPresented: shown) {
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
                    Text(model.timeBlockCalendar?.title ?? "No calendar for time blocks")
                    Spacer()
                    Button("Create New Calendar") { Task { await model.recreateTimeBlockCalendar() } }
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
/// feedback report, and Relearn Suggestions (§5.5, §7).
struct SuggestionsSheet: View {
    @Bindable var model: CalendarModel
    @State private var report: SuggestionFeedbackReport?

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.medium) {
            Text("Suggestions").font(.headline).frame(maxWidth: .infinity)
            Table(model.rules) {
                TableColumn("Rule") { rule in Text(rule.kind.title) }
                TableColumn("Matches") { rule in Text(rule.patternText) }
                TableColumn("Project and task") { rule in
                    Text(rule.ignore ? "Ignore" : [model.project(rule.projectID)?.name, rule.task].compactMap(\.self)
                        .joined(separator: " · "))
                }
                TableColumn("") { rule in
                    Button("Remove") { Task { await model.setRules(model.rules.filter { $0.id != rule.id }) } }
                }
            }
            .frame(minHeight: 160)
            Stepper("Fill Day skips activity under \(model.fillMinMinutes) min", value: fillMinimum, in: 1 ... 30)
            Stepper("Learn from the last \(model.trainDays) days", value: trainDays, in: 30 ... 730, step: 30)
            if let report {
                let rate = Int((report.acceptanceRate * 100).rounded())
                Text(
                    "Last 30 days: \(report.accepted) accepted, \(report.edited) edited, \(report.skipped) skipped; "
                        + "first suggestion used \(rate)% of the time"
                )
                .foregroundStyle(.secondary)
            }
            footer
        }
        .padding(Design.Spacing.content)
        .frame(minWidth: 560, minHeight: 420)
        .task { await loadReport() }
    }

    /// Relearn Suggestions leading; Done, the confirming action, trailing.
    private var footer: some View {
        HStack {
            Button("Relearn Suggestions") { Task { await model.rebuildIndex() } }
            Spacer()
            Button("Done") { model.showsSuggestions = false }
                .keyboardShortcut(.defaultAction)
            #if os(macOS)
                .buttonStyle(.borderedProminent)
            #endif
        }
    }

    private var fillMinimum: Binding<Int> {
        Binding { model.fillMinMinutes } set: { value in Task { await model.setFillMinMinutes(value) } }
    }

    private var trainDays: Binding<Int> {
        Binding { model.trainDays } set: { value in Task { await model.setTrainDays(value) } }
    }

    private func loadReport() async {
        let now = model.clock.now
        let feedback = await (try? model.store.feedback(in: DateInterval(start: now - 30 * 86_400, end: now + 1))) ?? []
        report = SuggestionFeedbackReport(feedback)
    }
}
