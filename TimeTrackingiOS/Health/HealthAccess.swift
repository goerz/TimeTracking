// HealthAccess: Apple Health as the iPhone's import uses it, so tests can
// replace HealthKit (ios.md §7 item 6).

import Foundation
import TimeTrackingCore

/// Reading and the authorization request; `nil` on the iPad and where
/// HealthKit is unavailable.
protocol HealthAccess: Sendable {
    var source: any HealthSampleReading { get }
    /// Asks for read access to `kinds` where not asked yet; shows the
    /// system sheet, so only while the app is in the foreground.
    func authorize(_ kinds: Set<HealthPeriod.Kind>) async
}
