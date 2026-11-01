// CalendarDayHeader: a day's weekday and date, overlaps, Fill Day, the
// column totals, and the all-day events (spec_calendar.md §1.2,
// §1.4, §2.6, §4.3).

import SwiftUI
import TimeTrackingCore

/// The weekday and date, overlaps, Fill Day, and above each visible column
/// its total with the column's glyph.
struct CalendarDayHeader: View {
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
                    Label("\(overlaps) \(overlaps == 1 ? "overlap" : "overlaps")", systemImage: SymbolName.warning)
                }
                .buttonStyle(.borderless)
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(.orange)
                .help("Select the overlapping entries")
            }
            Button { Task { await model.openFillDay(day) } } label: { Label("Fill Day…", systemImage: SymbolName.suggestions) }
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
