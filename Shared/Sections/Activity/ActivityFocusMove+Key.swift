// ActivityFocusMove+Key: the arrow keys as focus moves (activity.md §2).

import SwiftUI
import TimeTrackingCore

extension ActivityFocusMove {
    /// The keys of a focused heatmap or chart: the arrows, Space, and Return.
    static let panelKeys: Set<KeyEquivalent> = [.leftArrow, .rightArrow, .upArrow, .downArrow, .space, .return]

    init?(_ key: KeyEquivalent) {
        switch key {
        case .leftArrow: self = .left
        case .rightArrow: self = .right
        case .upArrow: self = .above
        case .downArrow: self = .below
        default: return nil
        }
    }
}
