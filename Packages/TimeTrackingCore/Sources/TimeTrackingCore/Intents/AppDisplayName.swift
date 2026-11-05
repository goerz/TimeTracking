// AppDisplayName: the app's name as the Home Screen shows it, for texts
// that name the app (ios.md §3.1, §6.1). The name is personal (from
// local.mk), so no text hard-codes it.

import Foundation

/// The display name of the running bundle; the app and its extensions all
/// carry the app's name (with " Debug" in Debug).
public enum AppDisplayName {
    /// The running bundle's `CFBundleDisplayName`, or `nil` without one
    /// (package tests, previews).
    public static let current: String? = name(infoDictionary: Bundle.main.infoDictionary ?? [:])

    /// The name, or "the app" without one.
    public static var orGeneric: String {
        current ?? "the app"
    }

    /// `CFBundleDisplayName`, or `nil` when it is missing or empty.
    public static func name(infoDictionary: [String: Any]) -> String? {
        guard let value = infoDictionary["CFBundleDisplayName"] as? String, !value.isEmpty else {
            return nil
        }
        return value
    }
}
