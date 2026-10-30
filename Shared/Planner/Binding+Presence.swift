// Binding+Presence: an optional's presence as a Bool binding for alerts,
// sheets, and popovers of the Planner.

import SwiftUI

extension Binding where Value == Bool {
    /// True while `value` is set; setting false clears it.
    static func isPresent(_ value: Binding<(some Any)?>) -> Self {
        Self {
            value.wrappedValue != nil
        } set: { shown in
            if !shown {
                value.wrappedValue = nil
            }
        }
    }
}
