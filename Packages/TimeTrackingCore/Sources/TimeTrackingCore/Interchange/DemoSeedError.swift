// DemoSeedError: why `make demo` refused a store (spec_architecture.md §2.5).

import Foundation

/// Why `DemoSeed.seed` refused to replace a store.
public enum DemoSeedError: Error, Equatable, Sendable, LocalizedError {
    /// The store is not in a Debug or simulator container.
    case notDevelopmentStore(String)

    public var errorDescription: String? {
        switch self {
        case let .notDevelopmentStore(path):
            "Refusing to replace \(path): not in a Debug or simulator container"
        }
    }
}
