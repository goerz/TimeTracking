// CalendarView: the Calendar section's toolbar, summary strip, day headers,
// and day columns (spec_planner_calendar.md §1; mockups/planner_calendar.png).

import SwiftUI
import TimeTrackingCore

/// The Calendar section.
struct CalendarView: View {
    @Bindable var model: CalendarModel
    @Environment(\.undoManager) private var undoManager
    @State private var scrollPosition = ScrollPosition(y: 0)
    @State private var viewportHeight: CGFloat = 600
    @State private var pinchBase: Double?

    static let gutter: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            CalendarToolbar(model: model)
            Divider()
            CalendarSummaryStrip(model: model)
            Divider()
            GeometryReader { proxy in
                let dayWidth = max(60, (proxy.size.width - Self.gutter) / CGFloat(model.visibleDays))
                VStack(spacing: 0) {
                    headers(dayWidth: dayWidth)
                    Divider()
                    columns(dayWidth: dayWidth)
                }
                .onAppear { viewportHeight = proxy.size.height }
                .onChange(of: proxy.size.height) { _, height in viewportHeight = height }
            }
        }
        .navigationTitle("Calendar")
        .accessibilityIdentifier("planner.calendar")
        .task {
            model.undoManager = undoManager
            await model.reload()
            await model.router?.consumeCalendarRequest()
            scrollToNow()
        }
        .task(id: model.router?.calendarRequest) {
            await model.router?.consumeCalendarRequest()
        }
        .task { await followActivity() }
        .task { await followEvents() }
        .onChange(of: model.scrollRequest?.serial) { _, _ in
            if let hour = model.scrollRequest?.hour {
                scrollPosition.scrollTo(y: hour * model.pointsPerHour)
            }
        }
        .sheet(item: fillDayBinding) { fillDay in
            FillDaySheet(model: fillDay, calendar: model)
        }
        .sheet(isPresented: $model.showsSuggestions) {
            SuggestionsSheet(model: model)
        }
        .alert("Discard the running entry?", isPresented: $model.confirmsRunningDelete) {
            Button("Discard", role: .destructive) { Task { await model.deleteSelection(confirmed: true) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete this block from the activity log?", isPresented: blockDeleteBinding, presenting: model.blockToDelete) { _ in
            Button("Delete", role: .destructive) { Task { await model.deleteBlockFromLog(confirmed: true) } }
            Button("Cancel", role: .cancel) { Task { await model.deleteBlockFromLog(confirmed: false) } }
                .keyboardShortcut(.defaultAction)
        } message: { block in
            let range = CalendarText.range(block.start, block.end, zone: model.calendar.timeZone)
            Text("\(range) · \(block.groupKey)\nThis removes it on every device and cannot be undone.")
        }
        .alert("The tracker could not delete the block", isPresented: trackerErrorBinding, presenting: model.trackerError) { _ in
            Button("OK") { model.trackerError = nil }
        } message: { Text($0) }
        .overlay(alignment: .bottom) { CalendarNoticeView(model: model) }
    }

    private func headers(dayWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.gutter)
            ForEach(model.days, id: \.self) { day in
                CalendarDayHeader(model: model, day: day, width: dayWidth)
            }
        }
        .gesture(DragGesture(minimumDistance: 20).onEnded { value in
            Task { await model.scrolled(dayWidths: -Double(value.translation.width / dayWidth)) }
        })
    }

    private func columns(dayWidth: CGFloat) -> some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                CalendarTimeAxis(model: model)
                    .frame(width: Self.gutter)
                ForEach(model.days, id: \.self) { day in
                    CalendarDayColumn(model: model, day: day, width: dayWidth)
                }
            }
        }
        .scrollPosition($scrollPosition)
        .gesture(MagnifyGesture().onChanged { value in
            let base = pinchBase ?? model.pointsPerHour
            pinchBase = base
            model.pointsPerHour = CalendarZoom.clamped(base * value.magnification)
        }.onEnded { _ in pinchBase = nil })
    }

    /// On opening, the current time sits one third down the viewport.
    private func scrollToNow() {
        let axis = model.axis(model.today)
        if let offset = axis.nowOffset(model.clock.now) {
            scrollPosition.scrollTo(y: max(0, offset - viewportHeight / 3))
        }
    }

    /// Follows the block log.
    private func followActivity() async {
        for await _ in model.activity.changes {
            await model.reload()
        }
    }

    /// Follows EventKit (`EKEventStoreChanged`).
    private func followEvents() async {
        for await _ in model.events.changes {
            await model.reload()
        }
    }

    private var fillDayBinding: Binding<FillDayModel?> {
        Binding { model.fillDay } set: { value in
            if value == nil {
                model.cancelFillDay()
            }
        }
    }

    private var blockDeleteBinding: Binding<Bool> {
        Binding { model.blockToDelete != nil } set: { shown in
            if !shown, model.blockToDelete != nil {
                Task { await model.deleteBlockFromLog(confirmed: false) }
            }
        }
    }

    private var trackerErrorBinding: Binding<Bool> {
        Binding { model.trackerError != nil } set: { shown in
            if !shown {
                model.trackerError = nil
            }
        }
    }
}

extension FillDayModel: Identifiable {
    var id: TrackingDay {
        day
    }
}

/// Times and ranges in the zone.
enum CalendarText {
    static func clock(_ date: Date, zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return ActivityText.clock(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    /// "09:10 – 09:44".
    static func range(_ start: Date, _ end: Date, zone: TimeZone) -> String {
        "\(clock(start, zone: zone)) – \(clock(end, zone: zone))"
    }
}

/// The toolbar of §1.1.
private struct CalendarToolbar: View {
    @Bindable var model: CalendarModel
    @State private var pickedDate = Date()

    var body: some View {
        HStack(spacing: 10) {
            navigation
            Button("Today") { Task { await model.goToToday() } }
                .accessibilityIdentifier("calendar.today")
            daysControl
            Toggle(isOn: Binding { model.showsActivity } set: { _ in Task { await model.toggle(.activity) } }) {
                Label("Activity", systemImage: "desktopcomputer")
            }
            .toggleStyle(.button)
            Toggle(isOn: Binding { model.showsCalendar } set: { _ in Task { await model.toggle(.calendar) } }) {
                Label("Calendar", systemImage: "calendar")
            }
            .toggleStyle(.button)
            Button { Task { await model.openFillDay() } } label: { Label("Fill Day…", systemImage: "sparkles") }
                .disabled(!model.canFillDay)
                .accessibilityIdentifier("calendar.fillDay")
            Spacer()
            ControlGroup {
                Button { model.zoom(by: -1) } label: { Image(systemName: "minus") }.accessibilityLabel("Zoom Out")
                Button { model.zoom(by: 1) } label: { Image(systemName: "plus") }.accessibilityLabel("Zoom In")
            }
            .fixedSize()
            Button { model.showsOptions = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Options")
                .popover(isPresented: $model.showsOptions) { CalendarOptionsPopover(model: model) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var navigation: some View {
        ControlGroup {
            Button { Task { await model.shift(days: -1) } } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous Day")
            Button { Task { await model.shift(days: 1) } } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Next Day")
        }
        .fixedSize()
        Button(model.rangeLabel) { model.showsMonthPicker = true }
            .accessibilityIdentifier("calendar.range")
            .popover(isPresented: $model.showsMonthPicker) {
                DatePicker("First day", selection: $pickedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding()
                    .onChange(of: pickedDate) { _, date in
                        model.showsMonthPicker = false
                        Task { await model.showDay(model.calendar.day(containing: date)) }
                    }
            }
    }

    private var daysControl: some View {
        HStack(spacing: 2) {
            Picker("Days", selection: Binding { model.visibleDays } set: { count in Task { await model.setVisibleDays(count) } }) {
                ForEach([1, 3, 5, 7], id: \.self) { Text("\($0)").tag($0) }
                if [2, 4, 6].contains(model.visibleDays) {
                    Text("\(model.visibleDays)").tag(model.visibleDays)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Menu {
                ForEach([2, 4, 6], id: \.self) { count in
                    Button("\(count) Days") { Task { await model.setVisibleDays(count) } }
                }
            } label: { Image(systemName: "chevron.down").accessibilityHidden(true) }
                .menuIndicator(.hidden)
                .fixedSize()
        }
        .accessibilityIdentifier("calendar.days")
    }
}

/// "Tracked ▇▇▇ 18h 51m   Blocks 1h 30m   Activity 25h 02m".
private struct CalendarSummaryStrip: View {
    var model: CalendarModel

    var body: some View {
        HStack(spacing: 16) {
            if let summary = model.summary {
                HStack(spacing: 8) {
                    Text("Tracked").foregroundStyle(.secondary)
                    GeometryReader { proxy in
                        HStack(spacing: 1) {
                            ForEach(summary.segments) { segment in
                                Rectangle()
                                    .fill(segment.color.map { Color(hex: $0) } ?? .gray)
                                    .frame(width: max(2, proxy.size.width * CGFloat(segment.seconds) / CGFloat(max(summary.tracked, 1))))
                                    .help(CalendarSummary.tooltip(segment))
                            }
                        }
                        .clipShape(Capsule())
                    }
                    .frame(width: 220, height: 8)
                    Text(ActivityText.duration(summary.tracked)).bold()
                }
                HStack(spacing: 6) {
                    Text("Blocks").foregroundStyle(.secondary)
                    Text(ActivityText.duration(summary.blocks)).bold()
                }
                HStack(spacing: 6) {
                    Text("Activity").foregroundStyle(.secondary)
                    Text(ActivityText.duration(summary.activity)).bold()
                }
            }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityIdentifier("calendar.summary")
    }
}

/// The weekday, date, column totals, overlaps, and Fill Day sparkle of a day.
private struct CalendarDayHeader: View {
    var model: CalendarModel
    var day: TrackingDay
    var width: CGFloat

    var body: some View {
        let isToday = day == model.today
        let overlaps = model.overlapping(on: day).count
        VStack(alignment: .leading, spacing: 4) {
            titleRow(isToday: isToday, overlaps: overlaps)
            totalsRow
            allDayStrip
        }
        .padding(6)
        .frame(width: width, alignment: .leading)
        .background(isToday ? Color.red.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
        .onTapGesture { Task { await model.showDay(day, alone: ModifierState.optionDown()) } }
        .accessibilityIdentifier("calendar.header.\(day)")
    }

    private func titleRow(isToday: Bool, overlaps: Int) -> some View {
        HStack(spacing: 6) {
            Text(DayText.shortWeekday(day))
            Text("\(day.day)")
                .bold()
                .padding(.horizontal, isToday ? 5 : 0)
                .background(isToday ? Capsule().fill(Color.red) : nil)
                .foregroundStyle(isToday ? .white : .primary)
            Spacer()
            if overlaps > 0 {
                Button("⚠ \(overlaps) overlaps") { model.selectOverlaps(on: day) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
            Button { Task { await model.openFillDay(day) } } label: { Image(systemName: "sparkles").accessibilityHidden(true) }
                .buttonStyle(.plain)
                .help("Fill Day…")
        }
    }

    @ViewBuilder private var totalsRow: some View {
        if let totals = model.summary?.days[day] {
            let columns = model.columns
            HStack(spacing: 4) {
                ForEach(Array(zip(columns, totals.text(columns: columns))), id: \.0) { column, text in
                    Image(systemName: column.glyph).accessibilityHidden(true)
                    Text(text)
                    if CalendarColumn.showsNames(dayWidth: width) {
                        Text(column.title).foregroundStyle(.tertiary)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var allDayStrip: some View {
        let allDay = (model.externalEvents + model.timeBlocks.map(\.event))
            .filter { $0.isAllDay && model.calendar.interval(of: day).intersects($0.interval) }
        if !allDay.isEmpty, model.showsCalendar {
            HStack {
                ForEach(allDay) { event in
                    Text(event.title).font(.caption).lineLimit(1)
                        .padding(.horizontal, 4)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color(hex: model.color(of: event)).opacity(0.2)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

extension CalendarColumn {
    var glyph: String {
        switch self {
        case .activity: "desktopcomputer"
        case .tracked: "stopwatch"
        case .calendar: "calendar"
        }
    }

    var title: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

/// The hour labels and the now bubble.
private struct CalendarTimeAxis: View {
    var model: CalendarModel

    var body: some View {
        let axis = model.axis(model.today)
        let step = CalendarZoom.labelMinutes(pointsPerHour: model.pointsPerHour)
        ZStack(alignment: .topTrailing) {
            Color.clear.frame(height: axis.height)
            ForEach(Array(stride(from: step, to: 24 * 60, by: step)), id: \.self) { minute in
                Text(ActivityText.clock(hour: minute / 60, minute: minute % 60))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .offset(x: -6, y: CGFloat(minute) / 60 * model.pointsPerHour - 7)
            }
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                if let offset = axis.nowOffset(model.clock.now) {
                    Text(CalendarText.clock(model.clock.now, zone: model.calendar.timeZone))
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .background(Capsule().fill(Color.red))
                        .offset(x: -4, y: offset - 8)
                }
            }
        }
    }
}

/// The transient notice (future refusal, deletion with Undo).
private struct CalendarNoticeView: View {
    @Bindable var model: CalendarModel
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        if let notice = model.notice {
            HStack {
                Text(notice.text)
                if !notice.deleted.isEmpty {
                    Button("Undo") {
                        undoManager?.undo()
                        model.notice = nil
                    }
                }
            }
            .padding(10)
            .background(.regularMaterial, in: Capsule())
            .padding()
            .accessibilityIdentifier("calendar.notice")
            .task(id: notice) {
                try? await Task.sleep(for: .seconds(notice.duration))
                if model.notice == notice {
                    model.notice = nil
                }
            }
        }
    }
}
