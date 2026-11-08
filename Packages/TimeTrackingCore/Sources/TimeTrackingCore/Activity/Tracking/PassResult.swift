// PassResult: what one pass of the rebuild loop did (activity_tracking.md §2.7).

/// What one pass did.
public enum PassResult: Sendable, Hashable {
    /// The date was formed; `current` says what becomes of the block of `current.json`.
    case formed(day: TrackingDay, written: BlockLogFolder.WriteResult, current: CurrentBlockUpdate)
    /// The date file couldn't be written; the date stays marked, and the
    /// agent waits before the next pass.
    case failed(day: TrackingDay, reason: String)
    /// The date is frozen; its file stays as it is.
    case frozen(TrackingDay)
    /// The date before is unsettled: nothing formed, the date before runs again first.
    case waiting(TrackingDay)
}
