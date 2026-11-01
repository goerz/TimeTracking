// TimeStore+ContextColors: the synced context color assignments of the
// Activity view and the Calendar's blocks (spec_activity.md §1.3).

import Foundation

extension TimeStore {
    /// Gives every context of `contexts` without a color the next one
    /// (`ContextPalette.assigning`), stores the setting when it changed,
    /// and returns all assignments. A failed write still returns them, so
    /// the colors show until the next try.
    public func assignContextColors(_ contexts: [String]) throws -> [String: Int] {
        let current = try value(.activityContextColors)
        let assigned = ContextPalette.assigning(contexts, to: current)
        if assigned != current {
            try? set(.activityContextColors, assigned)
        }
        return assigned
    }
}
