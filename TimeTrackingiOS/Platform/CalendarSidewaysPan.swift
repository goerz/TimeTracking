// CalendarSidewaysPan: the iPad Calendar's sideways swipe through time, with
// one finger or two, which SwiftUI's vertical scroll view does not provide
// (spec_calendar.md §1.2; spec_ios.md §10.2).

import SwiftUI
import UIKit

/// A sideways swipe over the days: they follow the fingers, then coast on
/// with the swipe's speed. It fails as soon as a touch moves mostly up or
/// down (the hours scroll) or is held still long enough to lift an item
/// (`TouchLiftDrag`), or once a pinch zooms (`CalendarTouchArbiter`); while
/// it runs, the hours do not scroll and a pinch does not zoom.
struct CalendarSidewaysPan: UIGestureRecognizerRepresentable {
    /// The sideways movement since the last call, in points.
    var onChanged: (_ delta: CGFloat) -> Void
    /// The sideways speed when the fingers lift, in points per second.
    var onEnded: (_ velocity: CGFloat) -> Void

    /// Lets the hours' scroll view pan alongside, and lets the swipe begin
    /// only when it moves mostly sideways.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var last: CGFloat = 0
        weak var scrollPan: UIGestureRecognizer?

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else {
                return true
            }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool {
            true
        }
    }

    func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> SidewaysPanRecognizer {
        let recognizer = SidewaysPanRecognizer()
        recognizer.delegate = context.coordinator
        recognizer.maximumNumberOfTouches = 2
        recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)] // swiftlint:disable:this legacy_objc_type
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: SidewaysPanRecognizer, context: Context) {
        let coordinator = context.coordinator
        let translation = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began:
            CalendarTouchArbiter.swiping = true
            coordinator.last = 0
            coordinator.scrollPan = EnclosingScrollPan.of(recognizer.view)
            coordinator.scrollPan?.isEnabled = false
            onChanged(translation)
            coordinator.last = translation
        case .changed:
            onChanged(translation - coordinator.last)
            coordinator.last = translation
        case .ended:
            onEnded(recognizer.velocity(in: recognizer.view).x)
            finish(coordinator)
        case .cancelled, .failed:
            finish(coordinator)
        default:
            break
        }
    }

    private func finish(_ coordinator: Coordinator) {
        CalendarTouchArbiter.swiping = false
        coordinator.last = 0
        coordinator.scrollPan?.isEnabled = true
        coordinator.scrollPan = nil
    }
}

/// A pan that only a mostly sideways, prompt movement starts.
final class SidewaysPanRecognizer: UIPanGestureRecognizer {
    private var touchDown: TimeInterval?
    private var startPoint: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if touchDown == nil {
            touchDown = event.timestamp
            startPoint = location(in: view)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        // Decided before the pan sees the move: a quick swipe moves far
        // enough in one event for the pan to begin at once.
        if state == .possible, let startPoint {
            let point = location(in: view)
            let delta = CGSize(width: point.x - startPoint.x, height: point.y - startPoint.y)
            if CalendarTouchArbiter.pinching {
                // The pinch owns the touch.
                state = .failed
                return
            }
            if let touchDown, event.timestamp - touchDown > CalendarTouch.liftSeconds {
                // Held still first: a lift, not a swipe.
                state = .failed
                return
            }
            if hypot(delta.width, delta.height) > 4, abs(delta.height) >= abs(delta.width) {
                // Up or down: the hours scroll.
                state = .failed
                return
            }
        }
        super.touchesMoved(touches, with: event)
    }

    override func reset() {
        super.reset()
        touchDown = nil
        startPoint = nil
    }
}
