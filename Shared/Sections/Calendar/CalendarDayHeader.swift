// CalendarDayHeader: a day's weekday and date, overlaps, the column
// totals with the column toggles, and the all-day events
// (spec_calendar.md §1.2, §1.4, §2.6, §4.3).

import SwiftUI
import TimeTrackingCore

/// The weekday and date, overlaps, and above each visible column
/// its total with the column's glyph.
struct CalendarDayHeader: View {
    var model: CalendarModel
    var day: TrackingDay
    var width: CGFloat

    var body: some View {
        let isToday = day == model.today
        let overlaps = model.overlapping(on: day).count
        VStack(alignment: .leading, spacing: Design.Spacing.tight) {
            titleRow(isToday: isToday, overlaps: overlaps)
                // The weekday and date move the day to the left edge; the
                // totals row below holds the column toggles, so a click
                // that misses a toggle moves nothing.
                .contentShape(Rectangle())
                .accessibilityAddTraits(.isButton)
                .onTapGesture {
                    let alone = ModifierState.optionDown()
                    withAnimation(.smooth(duration: 0.3)) { model.reveal(day, alone: alone) }
                }
                .help("Start the days here (⌥-click: this day alone)")
            totalsRow
            allDayStrip
        }
        .padding(.vertical, Design.Spacing.small)
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(isToday ? Color.accentColor.opacity(0.06) : day.isWeekend ? Color.weekendTint : .clear)
        .overlay(alignment: .leading) { DaySeparator() }
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
                    Label("\(overlaps) \(overlaps == 1 ? "overlap" : "overlaps")", systemImage: SymbolName.warning)
                }
                .buttonStyle(.borderless)
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(.orange)
                .help("Select the overlapping entries")
            }
        }
        .font(.headline)
        .padding(.horizontal, Design.Spacing.small)
    }

    /// One cell per visible column, as wide as the column below it, led by
    /// the column's glyph. The Activity and Calendar glyphs are buttons that
    /// hide their column; a hidden column leaves its glyph, struck through,
    /// at its edge of the Tracked cell, as the button that shows it again.
    private var totalsRow: some View {
        let columns = model.columns
        let widths = CalendarColumn.widths(dayWidth: Double(width), visible: columns)
        let totals = model.dayTotals[day]
        return HStack(spacing: 0) {
            ForEach(columns, id: \.self) { column in
                let columnWidth = widths[column] ?? 0
                let narrow = columnWidth < 72
                // Below 50 points only the glyph fits; the total is in the tooltip.
                HStack(spacing: narrow ? 0 : 2) {
                    if column == .tracked, !model.showsActivity {
                        ColumnToggle(model: model, column: .activity)
                    }
                    if column == .tracked {
                        ColumnGlyph(column: column)
                    } else {
                        ColumnToggle(model: model, column: column)
                    }
                    if let totals, columnWidth >= 50 {
                        total(column, totals: totals, narrow: narrow, columnWidth: columnWidth)
                    }
                    if column == .tracked, !model.showsCalendar {
                        Spacer(minLength: 0)
                        ColumnToggle(model: model, column: .calendar)
                    }
                }
                .padding(.horizontal, columnWidth >= 96 ? Design.Spacing.tight : 0)
                .frame(width: CGFloat(columnWidth), alignment: .leading)
                .clipped()
                .help(totals.map { "\(column.title): \($0.text(columns: [column])[0])" } ?? column.title)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// "6h 38m" with the column's name where there is room; a narrow column
    /// rounds to whole hours (the exact total is in the tooltip).
    private func total(_ column: CalendarColumn, totals: CalendarSummary.DayTotals, narrow: Bool, columnWidth: Double) -> some View {
        let text = totals.text(columns: [column])[0]
        return HStack(spacing: Design.Spacing.tight) {
            Text(narrow ? Self.compact(totals.seconds(column)) : text)
                .monospacedDigit()
                .foregroundStyle(column == .tracked ? .primary : .secondary)
            if CalendarColumn.showsNames(dayWidth: width), columnWidth >= 120 {
                Text(column.title).foregroundStyle(.tertiary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
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

/// A column's glyph at the size of the header's buttons.
private struct ColumnGlyph: View {
    var column: CalendarColumn

    var body: some View {
        Image(systemName: column.glyph)
            .font(.body)
            .frame(width: 22, height: 20)
            .accessibilityHidden(true)
    }
}

/// The Activity or Calendar glyph as the button that hides or shows its
/// column; while the column is hidden the glyph is struck through, the
/// way SF Symbols mark something off.
private struct ColumnToggle: View {
    var model: CalendarModel
    var column: CalendarColumn
    @State private var hovering = false

    var body: some View {
        let shown = column == .activity ? model.showsActivity : model.showsCalendar
        let title = "\(shown ? "Hide" : "Show") \(column.title) Column"
        Button {
            Task { await model.toggle(column) }
        } label: {
            Image(systemName: column.glyph)
                .font(.body)
                .accessibilityHidden(true)
                .overlay {
                    if !shown {
                        Slash().stroke(style: StrokeStyle(lineWidth: 3.5, lineCap: .round)).blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
                .overlay {
                    if !shown {
                        Slash().stroke(style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
                    }
                }
                .foregroundStyle(hovering ? AnyShapeStyle(.primary) : shown ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                .frame(width: 22, height: 20)
                .background(hovering ? Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: Design.Radius.small))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier("calendar.columnToggle.\(column.rawValue)")
    }
}

/// A diagonal from the top leading to the bottom trailing corner.
private nonisolated struct Slash: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
    }
}
