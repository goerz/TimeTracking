// EnclosingScrollPan: pauses the scroll view around a Calendar drag on the
// iPad while the drag runs (calendar.md §2.3, §2.4; ios.md §10.2).

import UIKit

/// The pan of the nearest scroll view enclosing a view.
enum EnclosingScrollPan {
    static func of(_ view: UIView?) -> UIGestureRecognizer? {
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
