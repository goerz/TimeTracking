// RebuildContext: what a pass of the rebuild loop needs besides the store
// (activity_tracking.md §2.7, §4.3).

/// What the rebuild needs besides the store: the block settings, the write
/// rules, this Mac's id and name, and the redaction of what leaves the Mac.
public struct RebuildContext: Sendable {
    public var settings: TrackerBlockSettings
    public var rules: SampleRules
    public var macDeviceID: String
    public var macName: String
    public var redactor: Redactor

    public init(settings: TrackerBlockSettings, rules: SampleRules, macDeviceID: String, macName: String, redactor: Redactor) {
        self.settings = settings
        self.rules = rules
        self.macDeviceID = macDeviceID
        self.macName = macName
        self.redactor = redactor
    }
}
