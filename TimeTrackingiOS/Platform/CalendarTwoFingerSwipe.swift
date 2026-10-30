// CalendarTwoFingerSwipe: the iPad Calendar's two-finger sideways swipe,
// which SwiftUI does not provide (spec_planner_calendar.md §1.2;
// spec_ios.md §10.2).

import SwiftUI
import UIKit

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
