// AppGroupDefaults: the App Group's `UserDefaults` suite, held by the
// device settings and the shared-state wrappers (spec_architecture.md §1.5,
// spec_data_and_sync.md §1.6).

import Foundation

/// A `UserDefaults` suite that can cross concurrency domains.
struct AppGroupDefaults: @unchecked Sendable {
    /// UserDefaults is thread-safe; the macOS 27 SDK does not mark it `Sendable`.
    let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The App Group suite of `identity`, or the standard defaults.
    init(identity: AppIdentity?) {
        self.defaults = identity.flatMap { UserDefaults(suiteName: $0.appGroup) } ?? .standard
    }
}
