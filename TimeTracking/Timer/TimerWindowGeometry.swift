// TimerWindowGeometry: full and compact mode by window height
// (spec_timer_window.md §1.1, §1.3).

import CoreGraphics

/// The quantities of §1.1 and the frame rules. Frames are in AppKit screen
/// coordinates (origin bottom-left), so "keeping the top-left corner" keeps
/// `maxY`.
enum TimerWindowGeometry {
    static let barHeight: CGFloat = 88
    static let threshold: CGFloat = 200
    static let minimumFullHeight: CGFloat = 300
    static let minimumWidth: CGFloat = 360
    static let defaultFullSize = CGSize(width: 440, height: 560)
    static let defaultCompactSize = CGSize(width: 440, height: 88)
    /// A restored frame needs this much on some screen.
    static let minimumVisible = CGSize(width: 100, height: 44)

    /// Whether a window of `height` is in compact mode.
    static func isCompact(height: CGFloat) -> Bool {
        height < threshold
    }

    /// The frame a drag ending at `frame` snaps to: below the threshold the
    /// bar height, between the threshold and the minimum full height that
    /// minimum; the width as dragged and the top-left corner fixed.
    static func snapped(_ frame: CGRect) -> CGRect {
        let height: CGFloat = if frame.height < threshold {
            barHeight
        } else {
            max(frame.height, minimumFullHeight)
        }
        return resized(frame, to: CGSize(width: max(frame.width, minimumWidth), height: height))
    }

    /// `frame` with `size`, keeping the top-left corner.
    static func resized(_ frame: CGRect, to size: CGSize) -> CGRect {
        CGRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
    }

    /// ⇧⌘M: the other mode's remembered size (or default) at the current
    /// top-left corner.
    static func toggled(_ frame: CGRect, fullFrame: CGRect?, compactFrame: CGRect?) -> CGRect {
        let size = if isCompact(height: frame.height) {
            fullFrame?.size ?? defaultFullSize
        } else {
            compactFrame?.size ?? defaultCompactSize
        }
        return resized(frame, to: size)
    }

    /// The frame to restore at launch: `stored` unless less than 100 × 44 pt
    /// of it lies on any screen, else centered on the main screen.
    static func restored(_ stored: CGRect?, screens: [CGRect], mainScreen: CGRect) -> CGRect {
        let fallback = stored?.size ?? defaultFullSize
        if let stored, screens.contains(where: { screen in
            let visible = screen.intersection(stored)
            return !visible.isNull && visible.width >= minimumVisible.width && visible.height >= minimumVisible.height
        }) {
            return stored
        }
        return CGRect(
            x: mainScreen.midX - fallback.width / 2,
            y: mainScreen.midY - fallback.height / 2,
            width: fallback.width,
            height: fallback.height
        )
    }
}
