// CalendarDayColumn: one day's Activity, Tracked, and Calendar columns with
// drawing, the now-line, and drops (calendar.md §1.4, §1.5,
// §2.3, §3, §4).

import SwiftUI
import TimeTrackingCore

/// A day's columns, split by weight.
struct CalendarDayColumn: View {
    var model: CalendarModel
    var day: TrackingDay
    var width: CGFloat

    var body: some View {
        let widths = CalendarColumn.widths(dayWidth: Double(width), visible: model.columns)
        let axis = model.axis(day)
        HStack(spacing: 0) {
            if let activity = widths[.activity] {
                ActivityColumn(model: model, day: day, width: CGFloat(activity))
            }
            TrackedColumn(model: model, day: day, width: CGFloat(widths[.tracked] ?? 0))
                // A dragged entry passes over the columns beside it.
                .zIndex(model.dragsEntry(on: day) ? 1 : 0)
            if let calendar = widths[.calendar] {
                EventsColumn(model: model, day: day, width: CGFloat(calendar))
            }
        }
        .frame(width: width, height: axis.height, alignment: .topLeading)
        .background(HourGrid(pointsPerHour: model.pointsPerHour, height: axis.height))
        .background(day == model.today ? Color.accentColor.opacity(0.03) : day.isWeekend ? Color.weekendTint : .clear)
        .overlay(alignment: .topLeading) { NowLine(model: model, day: day) }
        .overlay(alignment: .leading) { DaySeparator() }
    }
}

/// Hour lines.
private struct HourGrid: View {
    var pointsPerHour: Double
    var height: Double

    var body: some View {
        Canvas { context, size in
            var hour = 1.0
            while hour * pointsPerHour < height {
                let y = hour * pointsPerHour
                context.stroke(Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }, with: .color(.secondary.opacity(0.15)))
                hour += 1
            }
        }
    }
}

/// The 2 pt accent line at the current time on today (§1.5).
private struct NowLine: View {
    var model: CalendarModel
    var day: TrackingDay

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            if let offset = model.axis(day).nowOffset(model.clock.now) {
                Rectangle().fill(Color.accentColor).frame(height: 2).offset(y: offset - 1)
                    .accessibilityIdentifier("calendar.nowLine")
            }
        }
        .allowsHitTesting(false)
    }
}

/// Converts a column's y offsets to times while drawing.
private struct DrawState {
    var start: Date
    var end: Date
}

// MARK: Tracked

/// Entries, the draft, drawing, and drops of blocks and events (§2).
private struct TrackedColumn: View {
    var model: CalendarModel
    var day: TrackingDay
    var width: CGFloat
    @State private var drawing: DrawState?

    var body: some View {
        let axis = model.axis(day)
        let lanes = model.lanes(on: day)
        let left = CalendarColumn.x(of: .tracked, dayWidth: model.dayWidth, visible: model.columns)
        ZStack(alignment: .topLeading) {
            futureHatch(axis)
            drawArea(axis)
            ForEach(model.entries(on: day)) { listing in
                if let frame = axis.frame(of: listing.entry.interval(at: model.clock.now)) {
                    let lane = lanes[listing.entry.id] ?? CalendarLane(index: 0, count: 1)
                    let laneWidth = (width - 4) / CGFloat(lane.count)
                    let x = 2 + laneWidth * CGFloat(lane.index)
                    EntryCard(
                        model: model,
                        listing: listing,
                        day: day,
                        size: CGSize(width: laneWidth, height: max(4, frame.height)),
                        origin: CGPoint(x: CGFloat(left) + x, y: frame.y)
                    )
                    .offset(x: x, y: frame.y)
                    .zIndex(model.cardDrag?.item == .entry(listing.entry.id) ? 1 : 0)
                }
            }
            if let draft = model.draft, draft.day == day, let frame = axis.frame(of: draft.interval) {
                DraftCard(model: model, size: CGSize(width: width - 4, height: max(4, frame.height)))
                    .offset(x: 2, y: frame.y)
            }
            if let drawing, let frame = axis.frame(of: DateInterval(
                start: min(drawing.start, drawing.end),
                end: max(drawing.start, drawing.end)
            )) {
                RoundedRectangle(cornerRadius: Design.Radius.small).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .frame(width: width - 4, height: frame.height)
                    .offset(x: 2, y: frame.y)
            }
        }
        .frame(width: width, height: axis.height, alignment: .topLeading)
        .dropDestination(for: String.self) { items, _ in
            guard let item = items.first else {
                return false
            }
            drop(item)
            return true
        }
        // The cards inside keep their own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar.tracked.\(day)")
    }

    @ViewBuilder
    private func futureHatch(_ axis: CalendarDayAxis) -> some View {
        if let offset = axis.nowOffset(model.clock.now) {
            Rectangle()
                .fill(Hatch.paint(.gray.opacity(0.14)))
                .frame(height: max(0, axis.height - offset))
                .offset(y: offset)
                .allowsHitTesting(false)
        }
    }

    /// The empty slots: tap deselects, a drag draws (§2.3; ios.md §10.2).
    private func drawArea(_ axis: CalendarDayAxis) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .accessibilityAddTraits(.isButton)
            .onTapGesture { model.selection = [] }
            .calendarDrag(minimumDistance: 3) { drag in
                drawing = DrawState(start: axis.date(atY: Double(drag.start.y)), end: axis.date(atY: Double(drag.location.y)))
            } onEnded: { drag in
                drawing = nil
                model.draw(
                    on: day,
                    from: axis.date(atY: Double(drag.start.y)),
                    to: axis.date(atY: Double(drag.location.y)),
                    option: ModifierState.optionDown()
                )
            }
    }

    /// A block or event dragged in; the drop position is ignored. A time
    /// block's own drag finds this column itself (`TimeBlockCard`).
    private func drop(_ item: String) {
        if let id = item.dropPrefix("block:"), let block = model.blocks.first(where: { $0.id == id }) {
            model.createEntry(from: block)
        } else if let id = item.dropPrefix("event:"), let event = model.externalEvents.first(where: { $0.id == id }) {
            model.createEntry(fromEvent: event, timeBlock: nil)
        }
    }
}

// MARK: Activity

/// The tracker's blocks, covered parts dimmed, gap labels, and background
/// stretches (§3.1).
private struct ActivityColumn: View {
    var model: CalendarModel
    var day: TrackingDay
    var width: CGFloat

    var body: some View {
        let axis = model.axis(day)
        ZStack(alignment: .topLeading) {
            Color.clear
            healthAndGaps(axis)
            strips(axis)
            ForEach(model.blocks(on: day)) { block in
                if let frame = axis.frame(of: block.span) {
                    BlockCard(model: model, block: block, day: day, size: CGSize(width: width - 4, height: max(4, frame.height)))
                        .offset(x: 2, y: frame.y)
                }
            }
        }
        .frame(width: width, height: axis.height, alignment: .topLeading)
        // The cards inside keep their own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar.activity.\(day)")
    }

    /// The gap lines, the health lines over them, then the gap texts and
    /// the health labels; a gap's text where a health label sits is left
    /// out, so it never covers the label.
    @ViewBuilder
    private func healthAndGaps(_ axis: CalendarDayAxis) -> some View {
        let gaps = model.isRecordingMac ? model.gapLabels[day] ?? [] : []
        let periods = model.healthPeriods(on: day)
        let labeled = periods.compactMap { period in
            period.labelDay(in: model.calendar) == day ? axis.frame(of: period.interval).map { (period, $0) } : nil
        }
        let labelYs = labeled.map { $0.1.y + $0.1.height / 2 }
        ForEach(Array(gaps.enumerated()), id: \.offset) { _, label in
            if let frame = axis.frame(of: label.0) {
                GapLabel(text: label.1, part: .lines)
                    .frame(width: width, height: frame.height)
                    .offset(y: frame.y)
            }
        }
        ForEach(periods) { period in
            if let frame = axis.frame(of: period.interval) {
                HealthLine(period: period)
                    .frame(width: width, height: max(Design.healthLineWidth, frame.height))
                    .offset(y: frame.y)
            }
        }
        ForEach(Array(gaps.enumerated()), id: \.offset) { _, label in
            if let frame = axis.frame(of: label.0), !labelYs.contains(where: { abs($0 - frame.y - frame.height / 2) < 16 }) {
                GapLabel(text: label.1, part: .text)
                    .frame(width: width, height: frame.height)
                    .offset(y: frame.y)
            }
        }
        ForEach(labeled, id: \.0.id) { period, frame in
            HealthLabel(period: period)
                .frame(width: width, height: max(Design.healthLineWidth, frame.height))
                .offset(y: frame.y)
        }
    }

    /// The day's background stretches at the column's trailing edge.
    private func strips(_ axis: CalendarDayAxis) -> some View {
        ForEach(model.stretches(on: day)) { stretch in
            if let frame = axis.frame(of: DateInterval(start: stretch.start, end: max(stretch.start, stretch.end))) {
                BackgroundStrip(stretch: stretch)
                    .frame(width: Design.healthLineWidth, height: max(Design.healthLineWidth, frame.height))
                    .offset(x: width - Design.healthLineWidth - 2, y: frame.y)
            }
        }
    }
}

/// A gap's duration, centered in the gap, with a thin line above and below
/// it to the gap's ends (§3.1), drawn in two parts so a health line can lie
/// between the lines and the text.
private struct GapLabel: View {
    enum Part {
        case lines
        case text
    }

    var text: String
    var part: Part

    var body: some View {
        switch part {
        case .lines:
            VStack(spacing: 2) {
                Rectangle().frame(width: 1)
                Text(text).font(.caption).fixedSize().hidden()
                Rectangle().frame(width: 1)
            }
            .padding(.vertical, 2)
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
        case .text:
            Text(text)
                .font(.caption)
                .fixedSize()
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 2)
                .background(.background, in: .capsule)
                .accessibilityLabel(text)
        }
    }
}

/// Background work while the user was away: a narrow strip at the column's
/// trailing edge over the stretch, in the block color at half strength (§3.1).
private struct BackgroundStrip: View {
    var stretch: ActivityBackgroundStretch

    var body: some View {
        Capsule()
            .fill(Color.activityBlock.opacity(0.5))
            .help(stretch.summaryText)
            .accessibilityElement()
            .accessibilityLabel(stretch.summaryText)
            .accessibilityIdentifier("calendar.background.\(stretch.id)")
    }
}

/// The whole period's duration, centered on its line on the day it ends,
/// on a background of its own (§3.1).
private struct HealthLabel: View {
    var period: HealthPeriod

    var body: some View {
        Text(period.durationText)
            .font(.caption)
            .monospacedDigit()
            .fixedSize()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.background, in: .capsule)
            .overlay(Capsule().strokeBorder(period.kind == .sleep ? Color.sleepLine : Color.workoutLine, lineWidth: 1))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Sleep (dark blue) or a workout (dark green) from Apple Health: a line
/// centered in the Activity column over the period (§3.1).
private struct HealthLine: View {
    var period: HealthPeriod

    var body: some View {
        Capsule()
            .fill(period.kind == .sleep ? Color.sleepLine : Color.workoutLine)
            .frame(width: Design.healthLineWidth)
            .help(text)
            .accessibilityElement()
            .accessibilityLabel(text)
            .accessibilityIdentifier("calendar.health.\(period.kind.rawValue)")
    }

    /// "Sleep 7h 10m", "Workout 45m".
    private var text: String {
        let name = period.kind == .sleep ? "Sleep" : "Workout"
        return "\(name) \(period.durationText)"
    }
}

// MARK: Calendar

/// Time blocks and external events (§4).
private struct EventsColumn: View {
    var model: CalendarModel
    var day: TrackingDay
    var width: CGFloat
    @State private var drawing: DrawState?

    var body: some View {
        let axis = model.axis(day)
        ZStack(alignment: .topLeading) {
            drawArea(axis)
            notice
            cards(axis)
            if let draft = model.blockDraft, model.calendar.day(containing: draft.interval.start) == day,
               let frame = axis.frame(of: draft.interval)
            {
                RoundedRectangle(cornerRadius: Design.Radius.small)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                    .frame(width: width - 4, height: frame.height)
                    // Before the offset, as on `DraftCard`: after it, no
                    // popover opened.
                    .popover(isPresented: blockEditorShown, arrowEdge: .trailing) { TimeBlockEditor(model: model) }
                    .offset(x: 2, y: frame.y)
            }
            if let drawing, let frame = axis.frame(of: DateInterval(
                start: min(drawing.start, drawing.end),
                end: max(drawing.start, drawing.end)
            )) {
                RoundedRectangle(cornerRadius: Design.Radius.small).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                    .frame(width: width - 4, height: frame.height)
                    .offset(x: 2, y: frame.y)
            }
        }
        .frame(width: width, height: axis.height, alignment: .topLeading)
        // The cards inside keep their own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar.events.\(day)")
    }

    /// The day's pieces, side by side where they overlap.
    private func cards(_ axis: CalendarDayAxis) -> some View {
        let items = pieces()
        let lanes = CalendarLane.assign(items.map { ($0.id, $0.interval) })
        let left = CalendarColumn.x(of: .calendar, dayWidth: model.dayWidth, visible: model.columns)
        return ForEach(items, id: \.self) { piece in
            if let frame = axis.frame(of: piece.interval) {
                let lane = lanes[piece.id] ?? CalendarLane(index: 0, count: 1)
                let laneWidth = (width - 4) / CGFloat(lane.count)
                let x = 2 + laneWidth * CGFloat(lane.index)
                EventCard(
                    model: model,
                    piece: piece,
                    size: CGSize(width: laneWidth, height: max(4, frame.height)),
                    origin: CGPoint(x: CGFloat(left) + x, y: frame.y)
                )
                .offset(x: x, y: frame.y)
                .zIndex(model.cardDrag?.item == .timeBlock(piece.id) ? 1 : 0)
            }
        }
    }

    /// Whether the time-block editor shows; a click outside cancels it.
    private var blockEditorShown: Binding<Bool> {
        Binding { model.blockDraft != nil } set: { shown in
            if !shown {
                model.blockDraft = nil
            }
        }
    }

    /// The empty slots: a drag draws a time block (§4.2; ios.md §10.2).
    private func drawArea(_ axis: CalendarDayAxis) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .calendarDrag(minimumDistance: 3) { drag in
                guard model.canDrawTimeBlocks else {
                    return
                }
                drawing = DrawState(start: axis.date(atY: Double(drag.start.y)), end: axis.date(atY: Double(drag.location.y)))
            } onEnded: { drag in
                drawing = nil
                model.drawTimeBlock(
                    on: day,
                    from: axis.date(atY: Double(drag.start.y)),
                    to: axis.date(atY: Double(drag.location.y)),
                    option: ModifierState.optionDown()
                )
            }
    }

    /// Every time block and event piece on this day (one per day for events crossing midnight).
    private func pieces() -> [CalendarPiece<CalendarEvent.ID>] {
        (model.timeBlocks.map(\.event) + model.externalEvents).filter { !$0.isAllDay }.flatMap { event in
            CalendarPiece.pieces(of: event.interval, id: event.id, calendar: model.calendar).filter { $0.day == day }
        }
    }

    @ViewBuilder private var notice: some View {
        switch model.timeBlockState {
        case .noAccess:
            VStack(alignment: .leading, spacing: Design.Spacing.tight) {
                Text("No calendar access").font(.caption)
                #if os(macOS)
                    Button("Open System Settings") { SystemSettings.openPrivacy("Privacy_Calendars") }
                        .font(.caption)
                #endif
            }
            .padding(Design.Spacing.tight)
            .accessibilityIdentifier("calendar.noAccess")
        case .noICloudAccount:
            Text("Time blocks need an iCloud calendar account").font(.caption).padding(Design.Spacing.tight)
                .accessibilityIdentifier("calendar.noICloud")
        default:
            EmptyView()
        }
    }
}
