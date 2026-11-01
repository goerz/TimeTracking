// EventCard: a time block or external event piece with its gestures and
// menu (spec_calendar.md §4.2, §4.3, §4.4).

import SwiftUI
import TimeTrackingCore

/// A time block (dashed area-color border) or an external event (calendar
/// color left border) piece.
struct EventCard: View {
    var model: CalendarModel
    var piece: CalendarPiece<CalendarEvent.ID>
    var size: CGSize
    @State private var dragOffset: CGFloat = 0
    @State private var showsMenu = false

    var body: some View {
        if let block = model.timeBlocks.first(where: { $0.id == piece.id }) {
            timeBlockCard(block)
        } else if let event = model.externalEvents.first(where: { $0.id == piece.id }) {
            eventCard(event)
        }
    }

    private func timeBlockCard(_ block: TimeBlock) -> some View {
        let project = model.project(block.link.projectID)
        let area = project.flatMap { project in model.entries.first { $0.project?.id == project.id }?.area?.color }
        let color = area.map { Color(hex: $0) } ?? .gray
        let selected = model.selection.contains(.timeBlock(block.id))
        return VStack(alignment: .leading, spacing: 1) {
            Text(block.title).fontWeight(.semibold)
            if let project {
                Text(project.name)
            }
            HStack(spacing: 2) {
                Image(systemName: SymbolName.calendar).imageScale(.small).accessibilityHidden(true)
                Text(ActivityText.duration(Int(block.event.interval.duration))).monospacedDigit()
            }
        }
        .font(.caption).lineLimit(1).padding(.horizontal, Design.Spacing.tight + 2).padding(.vertical, Design.Spacing.tight)
        .frame(width: size.width - 2, height: size.height, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Design.Radius.small).fill(color.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.small).strokeBorder(color, style: StrokeStyle(lineWidth: 1.5, dash: [4])))
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.small).strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0))
        .clipped()
        .offset(y: dragOffset)
        .accessibilityAddTraits(.isButton)
        .onTapGesture(count: 2) { model.editTimeBlock(block) }
        .onTapGesture { model.select(.timeBlock(block.id)) }
        .calendarDrag(minimumDistance: 4, onLongPress: EntryCard.touch ? { showsMenu = true } : nil) { drag in
            dragOffset = drag.translation.height
        } onEnded: { drag in
            dragOffset = 0
            Task { await model.moveTimeBlock(block.id, by: Double(drag.translation.height) / model.pointsPerHour * 3600) }
        }
        .draggable("timeBlock:\(block.id)")
        .help(timeBlockHelp(block))
        .modifier(EntryMenu(showsMenu: $showsMenu) {
            Button("Create Entry…") { model.createEntry(fromEvent: block.event, timeBlock: block) }
            Button("Edit…") { model.editTimeBlock(block) }
            Button("Delete", role: .destructive) { Task { await model.deleteTimeBlocks([block.id]) } }
        })
        .accessibilityIdentifier("calendar.timeBlock")
    }

    private func timeBlockHelp(_ block: TimeBlock) -> String {
        if case let .unlinked(reason?) = block.link {
            return reason
        }
        return TimeBlockLink.visibleNotes(block.event.notes)
    }

    private func eventCard(_ event: CalendarEvent) -> some View {
        let color = Color(hex: model.color(of: event))
        return HStack(spacing: 0) {
            Rectangle().fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).fontWeight(.semibold).foregroundStyle(color)
                Text(CalendarText.range(event.start, event.end, zone: model.calendar.timeZone)).foregroundStyle(.secondary)
                if let location = event.location {
                    Text(location).foregroundStyle(.secondary)
                }
            }
            .font(.caption).lineLimit(2).padding(.horizontal, Design.Spacing.tight + 2).padding(.vertical, Design.Spacing.tight)
            Spacer(minLength: 0)
        }
        .frame(width: size.width - 2, height: size.height, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Design.Radius.small).fill(color.opacity(0.08)))
        .clipped()
        .accessibilityAddTraits(.isButton)
        .onTapGesture(count: 2) { model.openEvent(event) }
        .onTapGesture { model.select(.event(event.id)) }
        .draggable("event:\(event.id)")
        .help("\(event.notes ?? "")\(event.attendeeCount > 0 ? "\n\(event.attendeeCount) attendees" : "")")
        .contextMenu {
            Button("Create Entry…") { model.createEntry(fromEvent: event, timeBlock: nil) }
            Button("Open in Calendar") { model.openEvent(event) }
            Button("Hide This Calendar") { Task { await model.hideCalendar(of: event) } }
        }
        .accessibilityIdentifier("calendar.event")
    }
}
