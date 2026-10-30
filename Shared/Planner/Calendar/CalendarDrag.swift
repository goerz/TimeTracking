// CalendarDrag: the Calendar's drags on the Mac and their touch and
// Apple Pencil equivalents on the iPad (spec_planner_calendar.md §2.3,
// §2.4; spec_ios.md §10.2): a mouse drag on the Mac; on the iPad a long
// press, then a drag, or Apple Pencil directly; a long press without a drag
// opens the item's menu.

import SwiftUI

/// One drag over a column or card in the view's local coordinates.
struct CalendarDrag {
    var start: CGPoint
    var location: CGPoint

    var translation: CGSize {
        CGSize(width: location.x - start.x, height: location.y - start.y)
    }
}

/// The long press that lifts an item on the iPad.
enum CalendarTouch {
    static let liftSeconds = 0.35
    /// The resize handles' height (spec_ios.md §10.2).
    static let handleHeight: CGFloat = 44
}

extension View {
    /// A drag that draws, moves, or resizes. `minimumDistance` applies to
    /// the Mac; `onLongPress` is the iPad's long press without a drag.
    func calendarDrag(
        minimumDistance: CGFloat,
        onLongPress: (() -> Void)? = nil,
        onChanged: @escaping (CalendarDrag) -> Void,
        onEnded: @escaping (CalendarDrag) -> Void
    ) -> some View {
        #if os(iOS)
            modifier(TouchDrag(onLongPress: onLongPress, onChanged: onChanged, onEnded: onEnded))
        #else
            gesture(DragGesture(minimumDistance: minimumDistance)
                .onChanged { onChanged(CalendarDrag(start: $0.startLocation, location: $0.location)) }
                .onEnded { onEnded(CalendarDrag(start: $0.startLocation, location: $0.location)) })
        #endif
    }

    /// A drag that starts at once (the iPad's resize handles, the Mac's
    /// 6-point edges).
    func calendarDirectDrag(onChanged: @escaping (CalendarDrag) -> Void, onEnded: @escaping (CalendarDrag) -> Void) -> some View {
        gesture(DragGesture(minimumDistance: 2)
            .onChanged { onChanged(CalendarDrag(start: $0.startLocation, location: $0.location)) }
            .onEnded { onEnded(CalendarDrag(start: $0.startLocation, location: $0.location)) })
    }
}

#if os(iOS)
    /// Long press, then drag (fingers), plus Apple Pencil dragging directly.
    private struct TouchDrag: ViewModifier {
        var onLongPress: (() -> Void)?
        var onChanged: (CalendarDrag) -> Void
        var onEnded: (CalendarDrag) -> Void
        @State private var start: CGPoint?

        func body(content: Content) -> some View {
            content
                .gesture(LongPressGesture(minimumDuration: CalendarTouch.liftSeconds)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        if case let .second(true, drag?) = value {
                            onChanged(CalendarDrag(start: drag.startLocation, location: drag.location))
                        }
                    }
                    .onEnded { value in
                        guard case let .second(true, drag) = value else {
                            return
                        }
                        let ended = drag.map { CalendarDrag(start: $0.startLocation, location: $0.location) }
                        if let ended, hypot(ended.translation.width, ended.translation.height) >= 4 {
                            onEnded(ended)
                        } else if let onLongPress {
                            onLongPress()
                        } else if let ended {
                            onEnded(ended)
                        }
                    })
                .gesture(PencilDrag(onChanged: onChanged, onEnded: onEnded))
        }
    }
#endif
