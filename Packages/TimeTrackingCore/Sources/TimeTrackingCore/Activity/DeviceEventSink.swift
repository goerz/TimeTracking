// DeviceEventSink: where the iOS app and its extensions put device events
// (spec_data_and_sync.md §6).

/// Collects device events on iOS. Extensions append; only the app flushes.
public protocol DeviceEventSink: Sendable {
    /// Stages `event` for the next flush.
    func append(_ event: DeviceEvent) throws
    /// Uploads the staged events and forgets them once uploaded.
    func flush() async throws
}
