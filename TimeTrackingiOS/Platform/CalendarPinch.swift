// CalendarPinch: the iPad Calendar's pinch by axis, which SwiftUI does not
// provide (spec_calendar.md §1.2, §1.3; spec_ios.md §10.2).

import SwiftUI
import UIKit

/// A pinch whose axis follows the fingers' spread (vertical zoom or the
/// number of days).
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
