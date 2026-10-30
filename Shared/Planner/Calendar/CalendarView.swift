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
    @State private var daysBase: Int?
    @State private var pickedDate = Date()

    static let gutter: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
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
        .navigationSubtitle(model.rangeLabel)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar { CalendarToolbar(model: model, pickedDate: $pickedDate) }
            .accessibilityElement(children: .contain)
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
            .task { await model.followActivity() }
            .task { await model.followEvents() }
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
            .alert(
                "The tracker could not delete the block",
                isPresented: .isPresent($model.trackerError),
                presenting: model.trackerError
            ) { _ in
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
        // The gutter's clear color must not take half the height.
        .fixedSize(horizontal: false, vertical: true)
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
        #if os(iOS)
            // Pinch vertically to zoom, horizontally to change the number of
            // days; two fingers sideways scroll days (spec_ios.md §10.2).
            .gesture(CalendarPinch { scale, horizontal in
                pinch(scale: scale, horizontal: horizontal)
            } onEnd: {
                pinchBase = nil
                daysBase = nil
            })
            .gesture(CalendarTwoFingerSwipe { translation in
                Task { await model.scrolled(dayWidths: -Double(translation / dayWidth)) }
            })
        #else
            .gesture(MagnifyGesture().onChanged { value in
                pinch(scale: value.magnification, horizontal: false)
            }.onEnded { _ in pinchBase = nil })
        #endif
    }

    private func pinch(scale: Double, horizontal: Bool) {
        if horizontal {
            let base = daysBase ?? model.visibleDays
            daysBase = base
            let count = min(7, max(1, Int((Double(base) / max(scale, 0.01)).rounded())))
            if count != model.visibleDays {
                Task { await model.setVisibleDays(count) }
            }
        } else {
            let base = pinchBase ?? model.pointsPerHour
            pinchBase = base
            model.pointsPerHour = CalendarZoom.clamped(base * scale)
        }
    }

    /// On opening, the current time sits one third down the viewport.
    private func scrollToNow() {
        let axis = model.axis(model.today)
        if let offset = axis.nowOffset(model.clock.now) {
            scrollPosition.scrollTo(y: max(0, offset - viewportHeight / 3))
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

/// The toolbar of §1.1: the period items leading; days, columns, zoom,
/// options, and Fill Day trailing (spec_design.md §4).
private struct CalendarToolbar: ToolbarContent {
    @Bindable var model: CalendarModel
    @Binding var pickedDate: Date

    var body: some ToolbarContent {
        PlannerPeriodToolbar(
            previousTitle: "Previous Day",
            nextTitle: "Next Day",
            identifier: "calendar",
            previous: { shift(-1) },
            next: { shift(1) },
            today: { Task { await model.goToToday() } },
            dateMenu: {
                Button("Go to Date…") { model.showsMonthPicker = true }
                    .accessibilityIdentifier("calendar.range")
            },
            showsPopover: $model.showsMonthPicker,
            datePopover: {
                DatePicker("First day", selection: $pickedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(Design.Spacing.large)
                    .onChange(of: pickedDate) { _, date in
                        model.showsMonthPicker = false
                        Task { await model.showDay(model.calendar.day(containing: date)) }
                    }
            }
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
                Label("Columns", systemImage: "rectangle.split.3x1")
            }
            .help("Columns")
            .accessibilityIdentifier("calendar.columns")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.zoom(by: -1) } label: { Label("Zoom Out", systemImage: "minus.magnifyingglass") }
                .help("Zoom Out")
            Button { model.zoom(by: 1) } label: { Label("Zoom In", systemImage: "plus.magnifyingglass") }
                .help("Zoom In")
        }
        .visibilityPriority(.low)
        ToolbarItem(placement: .primaryAction) {
            Button { model.showsOptions = true } label: { Label("Calendar Options", systemImage: "gearshape") }
                .help("Calendar Options")
                .accessibilityIdentifier("calendar.options")
                .popover(isPresented: $model.showsOptions) { CalendarOptionsPopover(model: model) }
        }
        .visibilityPriority(.low)
        ToolbarItem(placement: .primaryAction) {
            Button { Task { await model.openFillDay() } } label: { Label("Fill Day…", systemImage: "sparkles") }
                .help("Fill Day…")
                .disabled(!model.canFillDay)
                .accessibilityIdentifier("calendar.fillDay")
        }
        .visibilityPriority(.high)
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

/// "Tracked ▇▇▇ 18h 51m   Blocks 1h 30m   Activity 25h 02m".
private struct CalendarSummaryStrip: View {
    var model: CalendarModel

    var body: some View {
        HStack(spacing: Design.Spacing.large) {
            if let summary = model.summary {
                HStack(spacing: Design.Spacing.small) {
                    Text("Tracked").foregroundStyle(.secondary)
                    SummaryBar(summary: summary).frame(width: 200, height: 8)
                    value(summary.tracked)
                }
                HStack(spacing: Design.Spacing.tight) {
                    Text("Blocks").foregroundStyle(.secondary)
                    value(summary.blocks)
                }
                HStack(spacing: Design.Spacing.tight) {
                    Text("Activity").foregroundStyle(.secondary)
                    value(summary.activity)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .padding(.horizontal, Design.Spacing.content)
        .padding(.vertical, Design.Spacing.small)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar.summary")
    }

    private func value(_ seconds: Int) -> some View {
        Text(ActivityText.duration(seconds)).fontWeight(.semibold).monospacedDigit()
    }
}

/// The tracked time stacked by project in area colors, each segment
/// proportional, with a hover tooltip.
private struct SummaryBar: View {
    var summary: CalendarSummary

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(summary.segments) { segment in
                    Rectangle()
                        .fill(segment.color.map { Color(hex: $0) } ?? Color.gray)
                        .frame(width: proxy.size.width * CGFloat(segment.seconds) / CGFloat(max(summary.tracked, 1)))
                        .help(CalendarSummary.tooltip(segment))
                }
                Spacer(minLength: 0)
            }
        }
        .background(.quaternary)
        .clipShape(Capsule())
    }
}

/// The weekday and date, overlaps, Fill Day, and above each visible column
/// its total with the column's glyph.
private struct CalendarDayHeader: View {
    var model: CalendarModel
    var day: TrackingDay
    var width: CGFloat
    @State private var hovering = false

    var body: some View {
        let isToday = day == model.today
        let overlaps = model.overlapping(on: day).count
        VStack(alignment: .leading, spacing: Design.Spacing.tight) {
            titleRow(isToday: isToday, overlaps: overlaps)
            totalsRow
            allDayStrip
        }
        .padding(.vertical, Design.Spacing.small)
        .frame(width: width, alignment: .leading)
        .background(isToday ? Color.accentColor.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityAddTraits(.isButton)
        .onTapGesture { Task { await model.showDay(day, alone: ModifierState.optionDown()) } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar.header.\(day)")
    }

    private func titleRow(isToday: Bool, overlaps: Int) -> some View {
        HStack(spacing: Design.Spacing.tight) {
            Text(DayText.shortWeekday(day)).foregroundStyle(isToday ? Color.accentColor : .secondary)
            Text("\(day.day)")
                .fontWeight(.semibold)
                .monospacedDigit()
                .padding(.horizontal, isToday ? 6 : 0)
                .background(isToday ? Capsule().fill(Color.accentColor) : nil)
                .foregroundStyle(isToday ? .white : .primary)
            Spacer(minLength: 0)
            if overlaps > 0 {
                Button { model.selectOverlaps(on: day) } label: {
                    Label("\(overlaps) overlaps", systemImage: "exclamationmark.triangle")
                }
                .buttonStyle(.borderless)
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(.orange)
                .help("Select the overlapping entries")
            }
            Button { Task { await model.openFillDay(day) } } label: { Label("Fill Day…", systemImage: "sparkles") }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .help("Fill Day…")
                .opacity(hovering || EntryCard.touch ? 1 : 0)
        }
        .font(.headline)
        .padding(.horizontal, Design.Spacing.small)
    }

    /// One cell per visible column, as wide as the column below it.
    @ViewBuilder private var totalsRow: some View {
        if let totals = model.summary?.days[day] {
            let columns = model.columns
            let widths = CalendarColumn.widths(dayWidth: Double(width), visible: columns)
            HStack(spacing: 0) {
                ForEach(Array(zip(columns, totals.text(columns: columns))), id: \.0) { column, text in
                    let narrow = (widths[column] ?? 0) < 72
                    HStack(spacing: narrow ? 2 : Design.Spacing.tight) {
                        // The glyph names the column; a narrow column rounds
                        // to whole hours (the exact total is in the tooltip).
                        Image(systemName: column.glyph).imageScale(.small).accessibilityHidden(true)
                        Text(narrow ? Self.compact(totals.seconds(column)) : text)
                            .monospacedDigit()
                            .foregroundStyle(column == .tracked ? .primary : .secondary)
                        if CalendarColumn.showsNames(dayWidth: width), (widths[column] ?? 0) >= 120 {
                            Text(column.title).foregroundStyle(.tertiary)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, (widths[column] ?? 0) >= 96 ? Design.Spacing.small : Design.Spacing.tight)
                    .frame(width: CGFloat(widths[column] ?? 0), alignment: .leading)
                    .help("\(column.title): \(text)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// "4h" (whole hours from one hour on), "45m" below.
    static func compact(_ seconds: Int) -> String {
        seconds < 3600 ? ActivityText.duration(seconds) : "\(Int((Double(seconds) / 3600).rounded()))h"
    }

    @ViewBuilder private var allDayStrip: some View {
        let allDay = (model.externalEvents + model.timeBlocks.map(\.event))
            .filter { $0.isAllDay && model.calendar.interval(of: day).intersects($0.interval) }
        if !allDay.isEmpty, model.showsCalendar {
            HStack(spacing: Design.Spacing.tight) {
                ForEach(allDay) { event in
                    Text(event.title).font(.caption).lineLimit(1)
                        .padding(.horizontal, Design.Spacing.tight)
                        .background(Color(hex: model.color(of: event)).opacity(0.2), in: .rect(cornerRadius: Design.Radius.small))
                }
            }
            .padding(.horizontal, Design.Spacing.small)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

extension CalendarSummary.DayTotals {
    /// The total of one column.
    func seconds(_ column: CalendarColumn) -> Int {
        switch column {
        case .activity: activity
        case .tracked: tracked
        case .calendar: calendar
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
            let now = model.days.contains(model.today) ? axis.nowOffset(model.clock.now) : nil
            ForEach(Array(stride(from: step, to: 24 * 60, by: step)), id: \.self) { minute in
                let y = CGFloat(minute) / 60 * model.pointsPerHour
                Text(ActivityText.clock(hour: minute / 60, minute: minute % 60))
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
                    // The now bubble covers the hour label it would overlap.
                    .opacity(now.map { abs($0 - y) < 14 } == true ? 0 : 1)
                    .offset(x: -6, y: y - 7)
            }
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                if let offset = axis.nowOffset(model.clock.now) {
                    Text(CalendarText.clock(model.clock.now, zone: model.calendar.timeZone))
                        .font(.caption.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .background(Capsule().fill(Color.accentColor))
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
