// TrackerReport: the tracker's status as `timetracking tracker` prints it
// (automation.md §3.13; activity_tracking.md §3.5, §4.1, §4.4).

public import Foundation

/// Liveness by the rule of activity_tracking.md §4.4, presence, version,
/// the sources' health, whether this Mac records, and the newest date file.
public struct TrackerReport: Sendable {
    public enum Liveness: String, Sendable, Hashable {
        case running
        /// Running, but the last tick is 90 seconds old or older.
        case delayed
        /// The last tick is 2 minutes old or older, or there is no `current.json`.
        case notRunning
    }

    /// The parsed `current.json`; `nil` without one.
    public var state: TrackerState?
    /// This Mac's hardware UUID.
    public var thisMac: String?
    /// The id in `blocks/owner`; `nil` without the file.
    public var owner: String?
    /// Whether `blocks/owner` could be read (not a placeholder, not unreadable).
    public var ownerReadable: Bool
    /// The latest date with a date file, and when that file changed.
    public var newestDateFile: (day: TrackingDay, modified: Date?)?
    public var now: Date
    public var timeZone: TimeZone

    public init(
        state: TrackerState?,
        thisMac: String?,
        owner: String?,
        ownerReadable: Bool,
        newestDateFile: (day: TrackingDay, modified: Date?)?,
        now: Date,
        timeZone: TimeZone
    ) {
        self.state = state
        self.thisMac = thisMac
        self.owner = owner
        self.ownerReadable = ownerReadable
        self.newestDateFile = newestDateFile
        self.now = now
        self.timeZone = timeZone
    }

    public var liveness: Liveness {
        guard let state, state.isRunning(at: now) else {
            return .notRunning
        }
        return state.isDelayed(at: now) ? .delayed : .running
    }

    /// Which Mac writes the date files, by `blocks/owner`.
    public enum Recorder: Sendable, Hashable {
        case thisMac
        case otherMac
        /// No readable owner file: the first agent to write claims it.
        case unclaimed
    }

    public var recorder: Recorder {
        guard ownerReadable, let owner else {
            return .unclaimed
        }
        return owner.lowercased() == thisMac?.lowercased() ? .thisMac : .otherMac
    }

    private func timestamp(_ date: Date) -> JSONValue {
        .string(ReportCSVWriter.timestamp(date, in: timeZone))
    }

    /// `{"status", "lastTick", "version", "presence", "foreground", "sources",
    /// "recording", "newestDateFile", "asOf"}`.
    public var json: JSONValue {
        .object([
            "status": .string(liveness.rawValue),
            "lastTick": state.map { timestamp($0.health.lastTick) } ?? .null,
            "version": .optional(state?.health.version),
            "presence": state.map { state in
                .object([
                    "state": .string(state.presence.state.rawValue),
                    "since": timestamp(state.presence.since),
                    "lastInput": state.presence.lastInput.map(timestamp) ?? .null,
                ])
            } ?? .null,
            "foreground": state?.foreground.map(ActivityListing.item) ?? .null,
            "sources": .array((state?.health.sources ?? []).map { source in
                .object([
                    "id": .string(source.id),
                    "name": .string(source.name),
                    "status": .string(source.status.rawValue),
                    "reason": .optional(source.reason.isEmpty ? nil : source.reason),
                ])
            }),
            "recording": .object([
                "thisMac": .optional(thisMac),
                "owner": .optional(owner),
                "thisMacRecords": recorder == .unclaimed ? .null : .bool(recorder == .thisMac),
            ]),
            "newestDateFile": newestDateFile.map { file in
                .object(["date": .string(file.day.description), "modified": file.modified.map(timestamp) ?? .null])
            } ?? .null,
            "asOf": timestamp(now),
        ])
    }
}
