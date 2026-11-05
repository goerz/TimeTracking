// CalendarPinch: the iPad Calendar's pinch by axis, which SwiftUI does not
// provide (calendar.md §1.2, §1.3; ios.md §10.2).

import Foundation
import SwiftUI
import UIKit

/// A pinch whose axis follows the fingers' spread (the hours' zoom or the
/// day width); it zooms only once the spread has clearly changed, and not
/// while a sideways swipe owns the touch (`CalendarTouchArbiter`).
struct CalendarPinch: UIGestureRecognizerRepresentable {
    /// The scale since the pinch began and whether the fingers spread horizontally.
    var onPinch: (_ scale: Double, _ horizontal: Bool) -> Void
    var onEnd: () -> Void

    /// How far the fingers' spread must change (as a scale's logarithm,
    /// about 12%) before the pinch zooms, so a two-finger sideways swipe
    /// does not zoom by accident.
    static let threshold = 0.12

    final class Coordinator {
        var horizontal = false
        /// The scale at which the pinch passed the threshold; `nil` before.
        var engagedAt: Double?
    }

    func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context _: Context) -> UIPinchGestureRecognizer {
        UIPinchGestureRecognizer()
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPinchGestureRecognizer, context: Context) {
        let coordinator = context.coordinator
        let scale = Double(recognizer.scale)
        switch recognizer.state {
        case .began:
            coordinator.engagedAt = nil
            if recognizer.numberOfTouches >= 2 {
                let first = recognizer.location(ofTouch: 0, in: recognizer.view)
                let second = recognizer.location(ofTouch: 1, in: recognizer.view)
                coordinator.horizontal = abs(first.x - second.x) > abs(first.y - second.y)
            }
            pinch(scale, coordinator)
        case .changed:
            pinch(scale, coordinator)
        case .ended, .cancelled, .failed:
            if coordinator.engagedAt != nil {
                onEnd()
            }
            coordinator.engagedAt = nil
            CalendarTouchArbiter.pinching = false
        default:
            break
        }
    }

    /// Zooms from the scale at which the threshold was passed, unless a
    /// sideways swipe owns the touch.
    private func pinch(_ scale: Double, _ coordinator: Coordinator) {
        if coordinator.engagedAt == nil {
            guard !CalendarTouchArbiter.swiping, abs(log(scale)) > Self.threshold else {
                return
            }
            coordinator.engagedAt = scale
            CalendarTouchArbiter.pinching = true
        }
        onPinch(scale / (coordinator.engagedAt ?? scale), coordinator.horizontal)
    }
}
