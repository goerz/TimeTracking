// SteppingClock: a ManualClock that moves forward each time it is read,
// standing in for work that takes time (architecture.md §3.3: tests never
// sleep).

import Foundation
import Synchronization
import TimeTrackingCore

/// Reads `base`, after moving it `step` seconds forward; with `step` 0 it is `base`.
final class SteppingClock: TimeTrackingCore.Clock {
    let base: ManualClock
    private let seconds = Mutex<TimeInterval>(0)

    init(base: ManualClock) {
        self.base = base
    }

    /// How far each read moves the clock.
    var step: TimeInterval {
        get { seconds.withLock { $0 } }
        set { seconds.withLock { $0 = newValue } }
    }

    var now: Date {
        base.advance(by: step)
        return base.now
    }
}
