// CalendarToolbar: the Calendar's toolbar, the period items leading and
// days, columns, zoom, options, and Fill Day trailing
// (spec_planner_calendar.md §1.1; spec_design.md §4).

import SwiftUI
import TimeTrackingCore

/// The toolbar of §1.1: the period items leading; days, columns, zoom,
/// options, and Fill Day trailing (spec_design.md §4).
struct CalendarToolbar: ToolbarContent {
    @Bindable var model: CalendarModel
    @Binding var pickedDate: Date

    var body: some ToolbarContent {
        PlannerPeriodToolbar(
            previousTitle: "Previous Day",
            nextTitle: "Next Day",
            identifier: "calendar",
            previous: { shift(-1) },
            next: { shift(1) },
            goToToday: GoToToday(action: { Task { await model.goToToday() } }, currentDay: { model.today }),
            dateControl: { goToDate }
        )
        ToolbarItem(placement: .primaryAction) {
            Picker("Days", selection: Binding { model.visibleDays } set: { count in Task { await model.setVisibleDays(count) } }) {
                ForEach(Self.dayChoices(current: model.visibleDays), id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            .help("Visible Days")
            .fixedSize()
            .accessibilityIdentifier("calendar.days")
        }
        .visibilityPriority(.high)
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Toggle(isOn: Binding { model.showsActivity } set: { _ in Task { await model.toggle(.activity) } }) {
                    Label("Activity Column", systemImage: CalendarColumn.activity.glyph)
                }
                Toggle(isOn: Binding { model.showsCalendar } set: { _ in Task { await model.toggle(.calendar) } }) {
                    Label("Calendar Column", systemImage: CalendarColumn.calendar.glyph)
                }
            } label: {
                Label("Columns", systemImage: SymbolName.calendarColumns)
            }
            .help("Columns")
            .accessibilityIdentifier("calendar.columns")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.zoom(by: -1) } label: { Label("Zoom Out", systemImage: SymbolName.zoomOut) }
                .help("Zoom Out")
            Button { model.zoom(by: 1) } label: { Label("Zoom In", systemImage: SymbolName.zoomIn) }
                .help("Zoom In")
        }
        .visibilityPriority(.low)
        ToolbarItem(placement: .primaryAction) {
            Button { model.showsOptions = true } label: { Label("Calendar Options", systemImage: SymbolName.settings) }
                .help("Calendar Options")
                .accessibilityIdentifier("calendar.options")
                .popover(isPresented: $model.showsOptions) { CalendarOptionsPopover(model: model) }
        }
        .visibilityPriority(.low)
        ToolbarItem(placement: .primaryAction) {
            Button { Task { await model.openFillDay() } } label: { Label("Fill Day…", systemImage: SymbolName.suggestions) }
                .help("Fill Day…")
                .disabled(!model.canFillDay)
                .accessibilityIdentifier("calendar.fillDay")
        }
        .visibilityPriority(.high)
    }

    /// Go to Date…: a month picker whose chosen day becomes the first visible day.
    private var goToDate: some View {
        Button { model.showsMonthPicker = true } label: {
            Label("Go to Date…", systemImage: SymbolName.goToDate)
        }
        .help("Go to Date…")
        .accessibilityIdentifier("calendar.range")
        .popover(isPresented: $model.showsMonthPicker, arrowEdge: .bottom) {
            DatePicker("First day", selection: $pickedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(Design.Spacing.large)
                .onChange(of: pickedDate) { _, date in
                    model.showsMonthPicker = false
                    Task { await model.showDay(model.calendar.day(containing: date)) }
                }
        }
    }

    /// 1, 3, 5, 7, and the current count when it is 2, 4, or 6.
    static func dayChoices(current: Int) -> [Int] {
        ([1, 3, 5, 7] + ([1, 3, 5, 7].contains(current) ? [] : [current])).sorted()
    }

    /// The arrows scroll one day; with ⌥ the number of visible days.
    private func shift(_ direction: Int) {
        let step = ModifierState.optionDown() ? model.visibleDays : 1
        Task { await model.shift(days: direction * step) }
    }
}
