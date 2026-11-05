// TimeBlockCard: a time block's piece with its gestures and menu
// (spec_calendar.md §4.2, §4.4).

import SwiftUI
import TimeTrackingCore

/// A light tint of the area color with a dashed border, showing title,
/// "Project · Client", and duration; drag to move, top and bottom 6 pt to
/// resize, as an entry card.
struct TimeBlockCard: View {
    var model: CalendarModel
    var block: TimeBlock
    /// The column: a block across the day change has a card on each of its days.
    var day: TrackingDay
    var size: CGSize
    /// The card's top left corner from the day's left edge and the columns' top.
    var origin: CGPoint
    @State private var dragOffset: CGSize = .zero
    /// The start a drag would give, the card's time label.
    @State private var dragStart: Date?
    @State private var hovering = false
    @State private var showsMenu = false
    /// The iPad's resize preview offsets of the top and bottom edges.
    @State private var edgeOffsets: (top: CGFloat, bottom: CGFloat) = (0, 0)

    var body: some View {
        let label = model.label(of: block)
        let color = label?.color.map { Color(hex: $0) } ?? .gray
        let selected = model.selection.contains(.timeBlock(block.id))
        ZStack(alignment: .topLeading) {
            // On the text, not the card: the card's would replace the
            // identifiers of the "+" and the handles.
            text(label).accessibilityIdentifier("calendar.timeBlock")
            if !EntryCard.touch {
                edgeHandles
            }
            if hovering {
                CreateEntryButton(tint: color) { model.createEntry(fromEvent: block.event, timeBlock: block) }
            }
        }
        .frame(width: size.width - 2, height: max(4, size.height - edgeOffsets.top + edgeOffsets.bottom), alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Design.Radius.small).fill(color.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.small).strokeBorder(color, style: StrokeStyle(lineWidth: 1.5, dash: [4])))
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.small).strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0))
        .clipped()
        .offset(y: edgeOffsets.top)
        .overlay {
            if EntryCard.touch, selected {
                touchHandles
            }
        }
        .overlay(alignment: .topLeading) {
            if let dragStart, !model.cardDragCancelled {
                CalendarDragTime(time: dragStart, zone: model.calendar.timeZone)
            }
        }
        .offset(model.cardDragCancelled ? .zero : dragOffset)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(.isButton)
        .cardClicks { model.click(.timeBlock(block.id)) } onDoubleClick: { model.editTimeBlock(block) }
        .calendarDrag(minimumDistance: 4, onLongPress: EntryCard.touch ? { showsMenu = true } : nil) { drag in
            guard model.continueCardDrag(.timeBlock(block.id), on: day, from: drag.start) else {
                return
            }
            dragOffset = drag.translation
            dragStart = moveTarget(under: drag).map { target in
                model.movedInterval(of: block, by: seconds(drag), to: target, from: day, option: ModifierState.optionDown()).start
            }
        } onEnded: { drag in
            dragOffset = .zero
            dragStart = nil
            if model.finishCardDrag() {
                drop(drag)
            }
        }
        .help(help)
        .modifier(EntryMenu(showsMenu: $showsMenu) {
            Button("Create Entry…") { model.createEntry(fromEvent: block.event, timeBlock: block) }
            Button("Edit…") { model.editTimeBlock(block) }
            Button("Delete", role: .destructive) { Task { await model.deleteTimeBlocks([block.id]) } }
        })
    }

    private func text(_ label: ProjectLabel?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(block.title).fontWeight(.semibold)
            if let label {
                Text(label.projectAndClient)
            }
            HStack(spacing: 2) {
                Image(systemName: SymbolName.calendar).imageScale(.small).accessibilityHidden(true)
                Text(ActivityText.duration(Int(block.event.interval.duration))).monospacedDigit()
            }
        }
        .font(.caption).lineLimit(1).padding(.horizontal, Design.Spacing.tight + 2).padding(.vertical, Design.Spacing.tight)
    }

    private var help: String {
        if case let .unlinked(reason?) = block.link {
            return reason
        }
        return TimeBlockLink.visibleNotes(block.event.notes)
    }

    // MARK: Moving

    /// The seconds a drag moves the card by.
    private func seconds(_ drag: CalendarDrag) -> TimeInterval {
        Double(drag.translation.height) / model.pointsPerHour * 3600
    }

    private func column(under drag: CalendarDrag) -> CalendarDropTarget? {
        model.dropTarget(from: day, at: CGPoint(x: origin.x + drag.location.x, y: origin.y + drag.location.y))
    }

    /// The day whose Calendar column lies under the pointer, if one does.
    private func moveTarget(under drag: CalendarDrag) -> TrackingDay? {
        column(under: drag).flatMap { $0.column == .calendar ? $0.day : nil }
    }

    /// A Calendar column takes the block, a Tracked column makes an entry
    /// of it (§4.4), and anywhere else nothing changes.
    private func drop(_ drag: CalendarDrag) {
        switch column(under: drag) {
        case let target? where target.column == .calendar:
            let option = ModifierState.optionDown()
            Task { await model.moveTimeBlock(block.id, by: seconds(drag), to: target.day, from: day, option: option) }
        case let target? where target.column == .tracked:
            model.createEntry(fromEvent: block.event, timeBlock: block)
        default:
            break
        }
    }

    // MARK: Resizing

    /// The top and bottom 6 points resize.
    private var edgeHandles: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 6).contentShape(Rectangle()).gesture(resizeGesture(top: true))
            Spacer(minLength: 0)
            Color.clear.frame(height: 6).contentShape(Rectangle()).gesture(resizeGesture(top: false))
        }
    }

    private func resizeGesture(top: Bool) -> some Gesture {
        DragGesture(minimumDistance: 2).onChanged { value in
            _ = model.continueCardDrag(.timeBlock(block.id), on: day, from: value.startLocation)
        }.onEnded { value in
            if model.finishCardDrag() {
                resize(top: top, by: value.translation.height)
            }
        }
    }

    /// The iPad's 44-point handles centered on the top and bottom edges.
    private var touchHandles: some View {
        VStack(spacing: 0) {
            handle(top: true).offset(y: -CalendarTouch.handleHeight / 2 + edgeOffsets.top)
            Spacer(minLength: 0)
            handle(top: false).offset(y: CalendarTouch.handleHeight / 2 + edgeOffsets.bottom)
        }
    }

    private func handle(top: Bool) -> some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(width: 28, height: 6)
            .frame(maxWidth: .infinity)
            .frame(height: CalendarTouch.handleHeight)
            .contentShape(Rectangle())
            .calendarDirectDrag { drag in
                guard model.continueCardDrag(.timeBlock(block.id), on: day, from: drag.start) else {
                    edgeOffsets = (0, 0)
                    return
                }
                if top {
                    edgeOffsets.top = drag.translation.height
                } else {
                    edgeOffsets.bottom = drag.translation.height
                }
            } onEnded: { drag in
                edgeOffsets = (0, 0)
                if model.finishCardDrag() {
                    resize(top: top, by: drag.translation.height)
                }
            }
            .accessibilityIdentifier(top ? "calendar.timeBlock.topHandle" : "calendar.timeBlock.bottomHandle")
    }

    private func resize(top: Bool, by translation: CGFloat) {
        // The card's edge, which is the column's where the block goes on.
        let interval = block.event.interval
        let column = model.axis(day).interval
        let edge = top ? max(interval.start, column.start) : min(interval.end, column.end)
        let date = edge + Double(translation) / model.pointsPerHour * 3600
        let option = ModifierState.optionDown()
        Task { await model.resizeTimeBlock(block.id, top: top, to: date, on: day, option: option) }
    }
}
