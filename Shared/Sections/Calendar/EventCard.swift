// EventCard: a time block or external event piece; the external event's
// hover button, gestures, and menu (spec_calendar.md §4.3, §4.4).

import SwiftUI
import TimeTrackingCore

/// A time block (dashed area-color border) or an external event (calendar
/// color left border) piece.
struct EventCard: View {
    var model: CalendarModel
    var piece: CalendarPiece<CalendarEvent.ID>
    var size: CGSize
    /// The card's top left corner from the day's left edge and the columns' top.
    var origin: CGPoint
    @State private var hovering = false

    var body: some View {
        if let block = model.timeBlocks.first(where: { $0.id == piece.id }) {
            TimeBlockCard(model: model, block: block, day: piece.day, size: size, origin: origin)
        } else if let event = model.externalEvents.first(where: { $0.id == piece.id }) {
            eventCard(event)
        }
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
        .overlay {
            if hovering {
                CreateEntryButton(tint: color) { model.createEntry(fromEvent: event, timeBlock: nil) }
            }
        }
        .clipped()
        .onHover { hovering = $0 }
        .accessibilityAddTraits(.isButton)
        .onTapGesture(count: 2) { model.openEvent(event) }
        .onTapGesture { model.click(.event(event.id)) }
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
