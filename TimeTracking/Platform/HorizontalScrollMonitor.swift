// HorizontalScrollMonitor: sideways trackpad and mouse scrolling over the
// Calendar, which SwiftUI's vertical scroll view ignores
// (calendar.md §1.2).

import AppKit
import SwiftUI

/// Reports the sideways part of scroll events over the view it backs, in
/// points (positive: the content moves left, toward later days), and
/// whether it is a trackpad's momentum. A
/// trackpad gesture counts only when it starts mostly sideways, and then
/// with its momentum; an up-and-down one stays the scroll view's. The
/// events still reach the scroll view, which keeps to the gesture's main
/// axis, so a sideways gesture never scrolls the hours.
struct HorizontalScrollMonitor: NSViewRepresentable {
    var onScroll: (_ points: CGFloat, _ momentum: Bool) -> Void

    func makeNSView(context _: Context) -> MonitorView {
        let view = MonitorView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: MonitorView, context _: Context) {
        view.onScroll = onScroll
    }

    static func dismantleNSView(_ view: MonitorView, coordinator _: ()) {
        view.stop()
    }

    /// One scroll event's values the view needs.
    struct Scroll {
        var windowNumber: Int
        var location: NSPoint
        var deltaX: CGFloat
        var deltaY: CGFloat
        var precise: Bool
        var phase: NSEvent.Phase
        var momentumPhase: NSEvent.Phase
    }

    /// A trackpad gesture's axis, decided by its first movement.
    enum GestureAxis {
        case undecided
        case sideways
        case vertical
    }

    final class MonitorView: NSView {
        var onScroll: (_ points: CGFloat, _ momentum: Bool) -> Void = { _, _ in }
        private var monitor: Any?
        /// The current trackpad gesture's axis.
        private var axis = GestureAxis.undecided

        /// Points per line for a mouse wheel without precise deltas.
        private static let lineHeight: CGFloat = 24

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                stop()
            } else {
                start()
            }
        }

        /// Clicks go to the views in front.
        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }

        func start() {
            guard monitor == nil else {
                return
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                let scroll = Scroll(
                    windowNumber: event.windowNumber,
                    location: event.locationInWindow,
                    deltaX: event.scrollingDeltaX,
                    deltaY: event.scrollingDeltaY,
                    precise: event.hasPreciseScrollingDeltas,
                    phase: event.phase,
                    momentumPhase: event.momentumPhase
                )
                MainActor.assumeIsolated { self?.handle(scroll) }
                return event
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        private func handle(_ scroll: Scroll) {
            guard let window, scroll.windowNumber == window.windowNumber else {
                return
            }
            let inside = bounds.contains(convert(scroll.location, from: nil))
            // A mouse wheel (or ⇧ with one): every event on its own.
            if scroll.phase.isEmpty, scroll.momentumPhase.isEmpty {
                if inside, abs(scroll.deltaX) > abs(scroll.deltaY) {
                    onScroll(-scroll.deltaX * (scroll.precise ? 1 : Self.lineHeight), false)
                }
                return
            }
            if scroll.phase.contains(.began) || scroll.phase.contains(.mayBegin) {
                axis = .undecided
            }
            if axis == .undecided, scroll.momentumPhase.isEmpty, scroll.deltaX != 0 || scroll.deltaY != 0 {
                axis = inside && abs(scroll.deltaX) > abs(scroll.deltaY) ? .sideways : .vertical
            }
            if axis == .sideways {
                onScroll(-scroll.deltaX, !scroll.momentumPhase.isEmpty)
            }
            if scroll.momentumPhase.contains(.ended) || scroll.momentumPhase.contains(.cancelled) {
                axis = .undecided
            }
        }
    }
}
