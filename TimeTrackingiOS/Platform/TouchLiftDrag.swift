// TouchLiftDrag: the iPad Calendar's long press, then drag, by finger
// (spec_calendar.md §2.3, §2.4; spec_ios.md §10.2). A UIKit long press
// takes the touch only once the press is held, so a quick drag still
// scrolls; SwiftUI's long press sequenced before a drag took every touch,
// and the Calendar did not scroll by finger.

import SwiftUI
import UIKit

/// A long press that lifts an item or starts drawing, then follows the
/// finger; while it runs, the enclosing scroll view does not scroll.
struct TouchLiftDrag: UIGestureRecognizerRepresentable {
    /// A long press without a drag (the item's menu); `nil` ends it as a
    /// drag that did not move.
    var onLongPress: (() -> Void)?
    var onChanged: (CalendarDrag) -> Void
    var onEnded: (CalendarDrag) -> Void

    final class Coordinator {
        var start: CGPoint?
        weak var scrollPan: UIGestureRecognizer?
    }

    func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context _: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = CalendarTouch.liftSeconds
        recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)] // swiftlint:disable:this legacy_objc_type
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let location = context.converter.localLocation
        let coordinator = context.coordinator
        switch recognizer.state {
        case .began:
            coordinator.start = location
            coordinator.scrollPan = EnclosingScrollPan.of(recognizer.view)
            coordinator.scrollPan?.isEnabled = false
        case .changed:
            if let start = coordinator.start {
                onChanged(CalendarDrag(start: start, location: location))
            }
        case .ended:
            if let start = coordinator.start {
                let drag = CalendarDrag(start: start, location: location)
                if hypot(drag.translation.width, drag.translation.height) >= 4 {
                    onEnded(drag)
                } else if let onLongPress {
                    onLongPress()
                } else {
                    onEnded(drag)
                }
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
}
