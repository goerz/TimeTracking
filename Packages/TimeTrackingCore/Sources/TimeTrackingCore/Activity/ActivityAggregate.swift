// ActivityAggregate: one bucket of an activity aggregate (spec_data_and_sync.md §6).

/// The seconds of one bucket of `ActivityReading.aggregate(in:by:device:)`.
public struct ActivityAggregate: Sendable, Hashable {
    /// The bucket an aggregate row stands for.
    public enum Bucket: Sendable, Hashable, Comparable {
        /// A context, subject, or group key.
        case value(String)
        /// A local hour of the day, 0 to 23.
        case hour(Int)
        /// A local date, `YYYY-MM-DD`.
        case day(String)
    }

    public var bucket: Bucket
    /// Seconds in the bucket.
    public var seconds: Int
    /// The number of blocks contributing to the bucket.
    public var blockCount: Int

    public init(bucket: Bucket, seconds: Int, blockCount: Int) {
        self.bucket = bucket
        self.seconds = seconds
        self.blockCount = blockCount
    }
}
