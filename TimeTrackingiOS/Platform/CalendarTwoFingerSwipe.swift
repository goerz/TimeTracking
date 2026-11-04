// CalendarTwoFingerSwipe: the iPad Calendar's two-finger sideways swipe,
// which SwiftUI does not provide (spec_calendar.md §1.2;
// spec_ios.md §10.2).

import SwiftUI
import UIKit

/// Two fingers swiping sideways: the days follow the fingers.
struct CalendarTwoFingerSwipe: UIGestureRecognizerRepresentable {
    /// The sideways movement since the last call, in points.
    var onChanged: (_ delta: CGFloat) -> Void

    final class Coordinator {
        var last: CGFloat = 0
        var sideways = false
    }

    func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context _: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.minimumNumberOfTouches = 2
        recognizer.maximumNumberOfTouches = 2
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view)
        let coordinator = context.coordinator
        switch recognizer.state {
        case .began, .changed:
            if recognizer.state == .began {
                coordinator.last = 0
                coordinator.sideways = abs(translation.x) > abs(translation.y)
            }
            if coordinator.sideways {
                onChanged(translation.x - coordinator.last)
                coordinator.last = translation.x
            }
        default:
            coordinator.last = 0
        }
    }
}
