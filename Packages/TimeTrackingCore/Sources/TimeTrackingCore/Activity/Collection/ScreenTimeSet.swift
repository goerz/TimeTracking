// ScreenTimeSet: a user-labeled set of apps, categories, or domains whose daily
// use the DeviceActivity Screen Time measures (ios.md §9.2).

public import Foundation

/// One app set of Screen Time. Only `label` reaches the log; `selection`
/// is the opaque, archived `FamilyActivitySelection` the app's picker made.
public struct ScreenTimeSet: Sendable, Hashable, Codable, Identifiable {
    /// The id of the automatic set that measures all activity.
    public static let everythingID = "everything"
    /// The label of that set (fixed; the Mac merge recognizes it).
    public static let everythingLabel = "Everything"
    /// Labels the Activity collection screen suggests for new sets.
    public static let suggestedLabels = ["Mail", "Messages", "Social", "Browsing", "Reading", "Work apps"]

    /// `everything`, or a UUID string for a named set.
    public var id: String
    public var label: String
    /// The archived selection; `nil` for "Everything" (`includesAllActivity`).
    public var selection: Data?

    public init(id: String = UUID().uuidString.lowercased(), label: String, selection: Data? = nil) {
        self.id = id
        self.label = label
        self.selection = selection
    }

    /// The automatic "Everything" set, which cannot be deleted.
    public static let everything = Self(id: everythingID, label: everythingLabel)

    public var isEverything: Bool {
        id == Self.everythingID
    }
}
