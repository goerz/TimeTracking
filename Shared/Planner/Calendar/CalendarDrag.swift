// CalendarDrag: the Calendar's drags on the Mac and their touch and
// Apple Pencil equivalents on the iPad (spec_planner_calendar.md §2.3,
// §2.4; spec_ios.md §10.2): a mouse drag on the Mac; on the iPad a long
// press, then a drag, or Apple Pencil directly; a long press without a drag
// opens the item's menu.

import SwiftUI
#if os(iOS)
    import UIKit
#endif

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

    /// A pan of Apple Pencil only; while it runs, the enclosing scroll view
    /// does not scroll.
    private struct PencilDrag: UIGestureRecognizerRepresentable {
        var onChanged: (CalendarDrag) -> Void
        var onEnded: (CalendarDrag) -> Void

        final class Coordinator {
            var start: CGPoint?
            weak var scrollPan: UIGestureRecognizer?
        }

        func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
            Coordinator()
        }

        func makeUIGestureRecognizer(context _: Context) -> UIPanGestureRecognizer {
            let recognizer = UIPanGestureRecognizer()
            recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)] // swiftlint:disable:this legacy_objc_type
            recognizer.maximumNumberOfTouches = 1
            return recognizer
        }

        func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
            let location = context.converter.localLocation
            let coordinator = context.coordinator
            switch recognizer.state {
            case .began:
                let translation = recognizer.translation(in: recognizer.view)
                let start = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
                coordinator.start = start
                coordinator.scrollPan = Self.scrollPan(above: recognizer.view)
                coordinator.scrollPan?.isEnabled = false
                onChanged(CalendarDrag(start: start, location: location))
            case .changed:
                if let start = coordinator.start {
                    onChanged(CalendarDrag(start: start, location: location))
                }
            case .ended:
                if let start = coordinator.start {
                    onEnded(CalendarDrag(start: start, location: location))
                }
                finish(coordinator)
            case .cancelled, .failed:
                finish(coordinator)
            default:
                break
            }
        }

        private func finish(_ coordinator: Coordinator) {
            coordinator.start = nil
            coordinator.scrollPan?.isEnabled = true
            coordinator.scrollPan = nil
        }

        /// The pan of the nearest enclosing scroll view.
        private static func scrollPan(above view: UIView?) -> UIGestureRecognizer? {
            var current = view
            while let candidate = current {
                if let scroll = candidate as? UIScrollView {
                    return scroll.panGestureRecognizer
                }
                current = candidate.superview
            }
            return nil
        }
    }

    /// A pinch whose axis follows the fingers' spread (vertical zoom or the
    /// number of days) and a two-finger horizontal pan that scrolls days.
    struct CalendarPinch: UIGestureRecognizerRepresentable {
        /// The scale since the pinch began and whether the fingers spread horizontally.
        var onPinch: (_ scale: Double, _ horizontal: Bool) -> Void
        var onEnd: () -> Void

        final class Coordinator {
            var horizontal = false
        }

        func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
            Coordinator()
        }

        func makeUIGestureRecognizer(context _: Context) -> UIPinchGestureRecognizer {
            UIPinchGestureRecognizer()
        }

        func handleUIGestureRecognizerAction(_ recognizer: UIPinchGestureRecognizer, context: Context) {
            switch recognizer.state {
            case .began:
                if recognizer.numberOfTouches >= 2 {
                    let first = recognizer.location(ofTouch: 0, in: recognizer.view)
                    let second = recognizer.location(ofTouch: 1, in: recognizer.view)
                    context.coordinator.horizontal = abs(first.x - second.x) > abs(first.y - second.y)
                }
                onPinch(Double(recognizer.scale), context.coordinator.horizontal)
            case .changed:
                onPinch(Double(recognizer.scale), context.coordinator.horizontal)
            case .ended, .cancelled, .failed:
                onEnd()
            default:
                break
            }
        }
    }

    /// Two fingers swiping sideways: the days scroll by the translation.
    struct CalendarTwoFingerSwipe: UIGestureRecognizerRepresentable {
        var onEnded: (_ translation: CGFloat) -> Void

        func makeUIGestureRecognizer(context _: Context) -> UIPanGestureRecognizer {
            let recognizer = UIPanGestureRecognizer()
            recognizer.minimumNumberOfTouches = 2
            recognizer.maximumNumberOfTouches = 2
            return recognizer
        }

        func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context _: Context) {
            if recognizer.state == .ended {
                let translation = recognizer.translation(in: recognizer.view)
                if abs(translation.x) > abs(translation.y) {
                    onEnded(translation.x)
                }
            }
        }
    }
#endif
