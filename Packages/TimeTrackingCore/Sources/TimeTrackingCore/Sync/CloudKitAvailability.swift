// CloudKitAvailability: whether this process may use its CloudKit container
// (data_and_sync.md §3.1 item 5).

import Foundation
#if os(macOS)
    import Security
#endif

/// Checks the iCloud entitlement before CloudKit is touched: creating a
/// `CKContainer` without it stops the process, and ad-hoc signed builds
/// carry no entitlements. Without the entitlement the app keeps working
/// locally.
public enum CloudKitAvailability {
    /// Whether the process is entitled to `containerIdentifier`.
    public static func check(containerIdentifier: String) -> Bool {
        #if os(macOS)
            guard let task = SecTaskCreateFromSelf(nil),
                  let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil),
                  let containers = value as? [String]
            else {
                return false
            }
            return containers.contains(containerIdentifier)
        #else
            // iOS builds are always signed with their entitlements.
            return true
        #endif
    }
}
