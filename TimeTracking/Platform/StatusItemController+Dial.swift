// StatusItemController+Dial: the status item's dial icon, drawn from the app
// icon's ring and knob (menubar.md §1.1, design.md §9).

import AppKit
import TimeTrackingCore

extension StatusItemController {
    /// The dial's geometry in points on its 16 pt square.
    private enum Dial {
        static let size: CGFloat = 16
        static let radius: CGFloat = 5.4
        static let width: CGFloat = 2.3
        static let knob: CGFloat = 1.75
        /// The clear gap around the knob.
        static let gap: CGFloat = 0.9
        /// The track's opacity; the arc and knob are opaque.
        static let track: CGFloat = 0.3
    }

    /// A template image: the ring's track, the arc from 12 o'clock to
    /// `fraction` of a turn, and the knob at its end; the track alone for
    /// `nil`. The badge adds the tracker warning's exclamation mark.
    static func dialImage(_ fraction: Double?, badge: Bool) -> NSImage {
        let size = NSSize(width: badge ? Dial.size + 2 : Dial.size, height: Dial.size)
        let image = NSImage(size: size, flipped: false) { _ in
            drawDial(fraction, center: NSPoint(x: Dial.size / 2, y: Dial.size / 2))
            if badge {
                drawBadge(in: NSRect(x: size.width - 9, y: 0, width: 9, height: 9))
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawDial(_ fraction: Double?, center: NSPoint) {
        let ring = NSBezierPath()
        ring.appendArc(withCenter: center, radius: Dial.radius, startAngle: 0, endAngle: 360)
        ring.lineWidth = Dial.width
        NSColor.black.withAlphaComponent(Dial.track).setStroke()
        ring.stroke()
        guard let fraction else {
            return
        }
        let turn = min(max(fraction, 0), 1)
        // Clockwise from 12 o'clock; AppKit's angles run counterclockwise from 3 o'clock.
        let end = 90 - 360 * turn
        if turn > 0 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: Dial.radius, startAngle: 90, endAngle: end, clockwise: true)
            arc.lineWidth = Dial.width
            NSColor.black.setStroke()
            arc.stroke()
        }
        let radians = end * .pi / 180
        let knob = NSPoint(x: center.x + Dial.radius * cos(radians), y: center.y + Dial.radius * sin(radians))
        clearCircle(at: knob, radius: Dial.knob + Dial.gap)
        NSColor.black.setFill()
        circle(at: knob, radius: Dial.knob).fill()
    }

    private static func drawBadge(in rect: NSRect) {
        clearCircle(at: NSPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2 + 1)
        NSImage(systemSymbolName: SymbolName.warningBadge, accessibilityDescription: nil)?.draw(in: rect)
    }

    private static func clearCircle(at point: NSPoint, radius: CGFloat) {
        guard let context = NSGraphicsContext.current else {
            return
        }
        let previous = context.compositingOperation
        context.compositingOperation = .clear
        circle(at: point, radius: radius).fill()
        context.compositingOperation = previous
    }

    private static func circle(at point: NSPoint, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius))
    }
}
