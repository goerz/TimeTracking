// CalendarToolbar: the Calendar's toolbar, the period items and Filters, as
// in Reports and Projects (calendar.md §1.1; design.md §4).

import SwiftUI
import TimeTrackingCore

/// The toolbar of §1.1: the arrows and the date menu leading, Filters
/// trailing, then the search field (`CalendarView`). The day width, the
/// columns, and the hours' zoom sit in the content (design.md §4).
struct CalendarToolbar: ToolbarContent {
    @Bindable var model: CalendarModel
    @Binding var pickedDate: Date

    var body: some ToolbarContent {
        PeriodToolbar(
            previousTitle: "Previous Day",
            nextTitle: "Next Day",
            identifier: "calendar",
            previous: { shift(-1) },
            next: { shift(1) },
            dateControl: { dateMenu }
        )
        ToolbarItem(placement: .primaryAction) {
            CalendarFiltersButton(model: model)
        }
        .visibilityPriority(.high)
    }

    /// The date menu, titled by what is shown ("Today", "Oct 19 – 23"), with
    /// Go to Today and Go to Date… (a month picker whose chosen day becomes
    /// the first visible day); the counterpart of the range menu.
    private var dateMenu: some View {
        Menu {
            Button("Go to Today") { Task { await model.goToToday() } }
            Button("Go to Date…") { model.showsMonthPicker = true }
        } label: {
            Text(model.menuTitle)
        }
        .help("Date")
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

    /// The arrows step one day, snapped so a day starts at the left edge;
    /// with ⌥ by the whole days in view.
    private func shift(_ direction: Int) {
        let step = ModifierState.optionDown() ? model.viewport.wholeDays : 1
        withAnimation(.smooth(duration: 0.3)) { model.step(days: direction * step) }
    }
}
