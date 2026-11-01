// CalendarDayColumn: one day's Activity, Tracked, and Calendar columns with
// drawing, the now-line, and drops (spec_calendar.md §1.4, §1.5,
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
            if let calendar = widths[.calendar] {
                EventsColumn(model: model, day: day, width: CGFloat(calendar))
            }
        }
        .frame(width: width, height: axis.height, alignment: .topLeading)
        .background(HourGrid(pointsPerHour: model.pointsPerHour, height: axis.height))
        .background(day == model.today ? Color.accentColor.opacity(0.03) : .clear)
        .overlay(alignment: .topLeading) { NowLine(model: model, day: day) }
        .overlay(alignment: .leading) { Divider() }
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
        ZStack(alignment: .topLeading) {
            futureHatch(axis)
            drawArea(axis)
            ForEach(model.entries(on: day)) { listing in
                if let frame = axis.frame(of: listing.entry.interval(at: model.clock.now)) {
                    let lane = lanes[listing.entry.id] ?? CalendarLane(index: 0, count: 1)
                    let laneWidth = (width - 4) / CGFloat(lane.count)
                    EntryCard(model: model, listing: listing, size: CGSize(width: laneWidth, height: max(4, frame.height)), dayWidth: width)
                        .offset(x: 2 + laneWidth * CGFloat(lane.index), y: frame.y)
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

    /// The empty slots: tap deselects, a drag draws (§2.3; spec_ios.md §10.2).
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

    /// A block, time block, or event dragged in; the drop position is ignored.
    private func drop(_ item: String) {
        if let id = item.dropPrefix("block:"), let block = model.blocks.first(where: { $0.id == id }) {
            model.createEntry(from: block)
        } else if let id = item.dropPrefix("timeBlock:"), let block = model.timeBlocks.first(where: { $0.id == id }) {
            model.createEntry(fromEvent: block.event, timeBlock: block)
        } else if let id = item.dropPrefix("event:"), let event = model.externalEvents.first(where: { $0.id == id }) {
            model.createEntry(fromEvent: event, timeBlock: nil)
        }
    }
}

// MARK: Activity

/// The tracker's blocks, covered parts dimmed, gap labels (§3.1).
private struct ActivityColumn: View {
    var model: CalendarModel
    var day: TrackingDay
    var width: CGFloat

    var body: some View {
        let axis = model.axis(day)
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(model.blocks.filter { $0.localDay == day.description }) { block in
                if let frame = axis.frame(of: DateInterval(start: block.start, end: max(block.start, block.end))) {
                    BlockCard(model: model, block: block, size: CGSize(width: width - 4, height: max(4, frame.height)))
                        .offset(x: 2, y: frame.y)
                }
            }
            if model.isRecordingMac {
                ForEach(Array((model.gapLabels[day] ?? []).enumerated()), id: \.offset) { _, label in
                    if let frame = axis.frame(of: label.0) {
                        GapLabel(text: label.1)
                            .frame(width: width, height: frame.height)
                            .offset(y: frame.y)
                    }
                }
            }
        }
        .frame(width: width, height: axis.height, alignment: .topLeading)
        // The cards inside keep their own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar.activity.\(day)")
    }
}

/// A gap's cause, centered in the gap between vertical em dashes; a gap too
/// short for the dashes shows the text alone (§3.1).
private struct GapLabel: View {
    var text: String

    var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 0) {
                Text(verbatim: "\u{FE31}")
                Text(text)
                Text(verbatim: "\u{FE31}")
            }
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
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
        let items = pieces()
        let lanes = CalendarLane.assign(items.map { ($0.id, $0.interval) })
        ZStack(alignment: .topLeading) {
            drawArea(axis)
            notice
            ForEach(items, id: \.self) { piece in
                if let frame = axis.frame(of: piece.interval) {
                    let lane = lanes[piece.id] ?? CalendarLane(index: 0, count: 1)
                    let laneWidth = (width - 4) / CGFloat(lane.count)
                    EventCard(model: model, piece: piece, size: CGSize(width: laneWidth, height: max(4, frame.height)))
                        .offset(x: 2 + laneWidth * CGFloat(lane.index), y: frame.y)
                }
            }
            if let draft = model.blockDraft, model.calendar.day(containing: draft.interval.start) == day,
               let frame = axis.frame(of: draft.interval)
            {
                RoundedRectangle(cornerRadius: Design.Radius.small)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                    .frame(width: width - 4, height: frame.height)
                    .offset(x: 2, y: frame.y)
                    .popover(isPresented: .constant(true)) { TimeBlockEditor(model: model) }
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

    /// The empty slots: a drag draws a time block (§4.2; spec_ios.md §10.2).
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
