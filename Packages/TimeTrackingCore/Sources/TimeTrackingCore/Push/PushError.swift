// PushError: failures of the APNs client (spec_architecture.md §2.4).

import Foundation

public enum PushError: Error, Hashable, Sendable, LocalizedError {
    /// No Keychain item: `make apns-key` has not run.
    case noKey
    case invalidKey(String)
    /// A Keychain status other than success or not found.
    case keychain(Int)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .noKey: "No push key is installed."
        case let .invalidKey(message): message
        case let .keychain(status): "The push key couldn't be read from the Keychain (error \(status))."
        case let .network(message): message
        }
    }
}
