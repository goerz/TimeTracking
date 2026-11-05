// CalendarModel+CardDrag: a card's drag under way, Escape during it, and what
// lies under its pointer (spec_calendar.md §2.4, §4.2).

import Foundation
import TimeTrackingCore

extension CalendarModel {
    /// Every change of a drag of `item` in the column `day`; false once
    /// Escape cancelled it. A drag the system ended leaves no trace, because
    /// the next one starts somewhere else.
    func continueCardDrag(_ item: CalendarItemID, on day: TrackingDay, from start: CGPoint) -> Bool {
        if cardDrag?.item != item || cardDrag?.start != start {
            cardDrag = CalendarCardDrag(item: item, day: day, start: start)
        }
        return !cardDragCancelled
    }

    /// The end of a card's drag; false when Escape cancelled it.
    func finishCardDrag() -> Bool {
        defer { cardDrag = nil }
        return !cardDragCancelled
    }

    /// Escape during a drag; false without one to cancel.
    func cancelCardDrag() -> Bool {
        guard cardDrag != nil, !cardDragCancelled else {
            return false
        }
        cardDrag?.cancelled = true
        return true
    }

    var cardDragCancelled: Bool {
        cardDrag?.cancelled ?? false
    }

    /// Whether an entry is being dragged from the column of `day`.
    func dragsEntry(on day: TrackingDay) -> Bool {
        if case .entry = cardDrag?.item {
            return cardDrag?.day == day
        }
        return false
    }

    /// The column under a drag's pointer, given from the left edge of `day`
    /// and the columns' top; `nil` outside the columns in view.
    func dropTarget(from day: TrackingDay, at point: CGPoint) -> CalendarDropTarget? {
        if let visibleColumnsY, !visibleColumnsY.contains(Double(point.y)) {
            return nil
        }
        return viewport.target(atX: viewport.x(of: day) + Double(point.x), columns: columns)
    }
}
