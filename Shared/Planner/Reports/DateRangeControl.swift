// DateRangeControl: previous-period arrow, the date-range button with its
// popover, next-period arrow (spec_planner_reports.md §2). Activity uses
// the same control on the same model.

import SwiftUI
import TimeTrackingCore

/// The range control of the Reports and Activity toolbars.
struct DateRangeControl: View {
    @Bindable var range: DateRangeModel
    @Binding var showsPopover: Bool
    /// Called after every change (the section reloads).
    var onChange: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button {
                range.previous()
                onChange()
            } label: {
                Image(systemName: "chevron.left").accessibilityLabel("Previous Period")
            }
            .disabled(!range.canShift)
            .accessibilityIdentifier("range.previous")
            Button {
                showsPopover.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text(range.label)
                    Image(systemName: "chevron.down").font(.caption2).accessibilityHidden(true)
                }
            }
            .accessibilityIdentifier("range.button")
            .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
                DateRangePopover(range: range, onChange: onChange)
            }
            Button {
                range.next()
                onChange()
            } label: {
                Image(systemName: "chevron.right").accessibilityLabel("Next Period")
            }
            .disabled(!range.canShift)
            .accessibilityIdentifier("range.next")
        }
    }
}

/// The presets and a two-month calendar.
struct DateRangePopover: View {
    var range: DateRangeModel
    var onChange: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(RangePreset.allCases, id: \.self) { preset in
                    let selected = range.matchingPresets.first == preset
                    Button {
                        range.select(preset)
                        onChange()
                    } label: {
                        Text(preset.title)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Color.accentColor.opacity(0.2) : .clear))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("range.preset.\(preset.rawValue)")
                }
            }
            .frame(width: 150)
            Divider()
            HStack(alignment: .top, spacing: 16) {
                MonthGrid(
                    month: TrackingPeriod(.month, containing: range.days.upperBound).start.adding(days: -1),
                    range: range,
                    onChange: onChange
                )
                MonthGrid(month: range.days.upperBound, range: range, onChange: onChange)
            }
        }
        .padding(14)
    }
}

/// One month; a click sets the first day, a second the last.
private struct MonthGrid: View {
    var month: TrackingDay
    var range: DateRangeModel
    var onChange: () -> Void

    private var first: TrackingDay {
        TrackingDay(year: month.year, month: month.month, day: 1)
    }

    private var days: [TrackingDay?] {
        let count = first.distance(to: TrackingPeriod(.month, containing: first).nextStart ?? first)
        let leading = Array(repeating: TrackingDay?.none, count: first.isoWeekday - 1)
        return leading + (0 ..< count).map { first.adding(days: $0) }
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(DayText.monthYear(first)).font(.headline)
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { index in
                        Text(["M", "T", "W", "T", "F", "S", "S"][index]).font(.caption).foregroundStyle(.secondary).frame(width: 26)
                    }
                }
                ForEach(0 ..< (days.count + 6) / 7, id: \.self) { week in
                    GridRow {
                        ForEach(0 ..< 7, id: \.self) { column in
                            let index = week * 7 + column
                            if index < days.count, let day = days[index] {
                                dayButton(day)
                            } else {
                                Color.clear.frame(width: 26, height: 22)
                            }
                        }
                    }
                }
            }
        }
    }

    private func dayButton(_ day: TrackingDay) -> some View {
        let inRange = range.days.contains(day)
        let pending = range.pendingFirstDay == day
        return Button {
            range.pick(day)
            if range.pendingFirstDay == nil {
                onChange()
            }
        } label: {
            Text(String(day.day))
                .frame(width: 26, height: 22)
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(pending ? Color.accentColor : inRange ? Color.accentColor.opacity(0.25) : .clear))
                .foregroundStyle(pending ? .white : day == range.today ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}
