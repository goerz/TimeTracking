// SampleSelection: a selection of stored Samples for `replace`
// (activity_tracking.md §4.1).

public import Foundation

/// A selection of stored Samples: a time range, optionally one device and some sources.
public struct SampleSelection: Sendable, Hashable {
    public var range: DateInterval
    public var deviceID: String?
    // `nil` means every source, which an empty set cannot express.
    // swiftlint:disable:next discouraged_optional_collection
    public var sources: Set<SampleSource>?

    // swiftlint:disable:next discouraged_optional_collection
    public init(range: DateInterval, deviceID: String? = nil, sources: Set<SampleSource>? = nil) {
        self.range = range
        self.deviceID = deviceID
        self.sources = sources
    }

    func contains(_ sample: Sample) -> Bool {
        sample.time >= range.start && sample.time < range.end
            && (deviceID.map { $0 == sample.deviceID } ?? true)
            && (sources.map { $0.contains(sample.source) } ?? true)
    }
}
