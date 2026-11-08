// TimeStore+AppColors: the synced app color assignments of the Activity
// section (activity.md §1.3).

import Foundation

extension TimeStore {
    /// Gives every app of `apps` without a color the next one
    /// (`AppPalette.assigning`), stores the setting when it changed, and
    /// returns all assignments. A failed write still returns them, so the
    /// colors show until the next try.
    public func assignAppColors(_ apps: [String]) throws -> [String: Int] {
        let current = try value(.activityAppColors)
        let assigned = AppPalette.assigning(apps, to: current)
        if assigned != current {
            try? set(.activityAppColors, assigned)
        }
        return assigned
    }
}
