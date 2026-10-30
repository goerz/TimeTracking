// PencilDrag: the iPad Calendar's Apple Pencil pan, which SwiftUI does not
// provide (spec_planner_calendar.md §2.3, §2.4; spec_ios.md §10.2).

import SwiftUI
import UIKit

/// A pan of Apple Pencil only; while it runs, the enclosing scroll view
/// does not scroll.
struct PencilDrag: UIGestureRecognizerRepresentable {
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
