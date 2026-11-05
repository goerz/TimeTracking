// AutomationService: the operations behind the tool, the App Intents, and
// the URL scheme (spec_automation.md §1, §3, §5, §6).

public import Foundation

/// The library operations every scripting surface calls. Each surface only
/// parses its input and formats the result; refusals are
/// `AutomationError`s with the tool's messages.
public struct AutomationService: Sendable {
    public let store: TimeStore
    /// The zone dates are read and printed in (the system zone).
    public let timeZone: TimeZone

    public init(store: TimeStore, timeZone: TimeZone = .current) {
        self.store = store
        self.timeZone = timeZone
    }

    public var calendar: TrackingCalendar {
        store.displayCalendar(timeZone: timeZone)
    }

    public var now: Date {
        store.clock.now
    }

    public var today: TrackingDay {
        calendar.day(containing: now)
    }

    // MARK: Status

    /// The running entry, today's total including it, and the outbox size.
    public func status() async throws(AutomationError) -> AutomationStatus {
        let now = now
        let today = today
        let store = store
        let total = try await totalSeconds(on: today)
        return try await run {
            let running = try await store.runningEntry()
            let listing = try await store.listings(for: running.map { [$0] } ?? []).first
            return try await AutomationStatus(
                running: listing,
                today: today,
                todaySeconds: total,
                pendingChanges: store.outboxCount(),
                asOf: now
            )
        }
    }

    /// The tracked seconds of `day`: every entry's part on it, the running
    /// one up to now.
    public func totalSeconds(on day: TrackingDay) async throws(AutomationError) -> Int {
        let store = store
        let now = now
        let interval = calendar.interval(of: day)
        return try await run {
            try await store.entries(in: interval, includeDeleted: false)
                .reduce(0) { $0 + Self.seconds(of: $1, within: interval, at: now) }
        }
    }

    // MARK: Start, stop, continue

    /// Starts an entry, stopping the running one; never infers a project.
    public func start(
        task: String,
        projectID: ProjectID?,
        at: Date? = nil,
        force: Bool = false
    ) async throws(AutomationError) -> StartResult {
        let store = store
        let outcome = try await run {
            try await store.transaction { try $0.checkedStart(projectID: projectID, task: task, at: at, force: force) }
        }
        return try await result(outcome)
    }

    /// Stops the running entry; refuses when nothing runs.
    public func stop(at: Date? = nil) async throws(AutomationError) -> EntryListing {
        let store = store
        let stopped = try await run { try await store.transaction { try $0.checkedStop(at: at) } }
        return try await listing(stopped)
    }

    /// Stops the running entry only while it belongs to the chain of
    /// `id`; `nil` when another entry or none runs.
    public func stop(chainOf id: EntryID) async throws(AutomationError) -> EntryListing? {
        let store = store
        let now = store.clock.now
        let stopped = try await run { try await store.transaction { try $0.stop(chainOf: id, at: now) } }
        guard let stopped else {
            return nil
        }
        return try await listing(stopped)
    }

    /// What `continue` repeats: the given entry, the most recent entry of a
    /// project or with a task, or the most recent entry other than the
    /// running one.
    public enum ContinueSource: Hashable, Sendable {
        case latest
        case entry(EntryID)
        case project(ProjectID)
        case task(String)
    }

    /// Starts a new entry with the task and project of `source`, stopping
    /// a running entry first. Refuses continuing the running entry itself.
    public func `continue`(_ source: ContinueSource) async throws(AutomationError) -> StartResult {
        let store = store
        let template = try await run { () async throws -> TimeEntry? in
            switch source {
            case let .entry(id):
                return try await store.entry(id)
            case .latest:
                return try await store.recentEntries(before: nil, limit: 20).first { !$0.isRunning }
            case let .project(projectID):
                return try await store.entries(matching: ReportQuery.allTime(projects: [projectID])).last
            case let .task(text):
                let folded = text.folded
                return try await store.entries(matching: ReportQuery.allTime()).last { $0.task.folded.contains(folded) }
            }
        }
        guard let template else {
            if case .entry = source {
                throw .notFound("No such entry.")
            }
            throw .notFound("No entry to continue.")
        }
        guard !template.isRunning else {
            throw .refused("That entry is running already.")
        }
        let projectID = template.projectID
        let task = template.task
        let outcome = try await run {
            try await store.transaction { try $0.checkedStart(projectID: projectID, task: task, at: nil, force: true) }
        }
        return try await result(outcome)
    }

    // MARK: Entries

    /// The entries whose start lies in `range` (all time when `nil`) and
    /// that pass `filter`, ascending unless `descending`.
    public func entries(
        in range: DayRange?,
        filter: EntryFilter = EntryFilter(),
        runningOnly: Bool = false,
        limit: Int? = nil,
        descending: Bool = false
    ) async throws(AutomationError) -> EntriesResult {
        let store = store
        let now = now
        let calendar = calendar
        let listings = try await run { () async throws -> [EntryListing] in
            var entries: [TimeEntry] = []
            if runningOnly {
                if let running = try await store.runningEntry() {
                    let instant = DateInterval(start: running.start, duration: 0)
                    entries = try await store.entries(matching: ReportQuery.allTime(filter: filter, around: instant))
                        .filter { $0.id == running.id }
                }
            } else {
                let interval = range.map { $0.interval(in: calendar) }
                entries = try await store.entries(matching: ReportQuery.allTime(filter: filter, around: interval))
                    .filter { entry in interval.map { entry.start >= $0.start && entry.start < $0.end } ?? true }
                    .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
            }
            var listings = try await store.listings(for: entries)
            if descending {
                listings.reverse()
            }
            if let limit {
                listings = Array(listings.prefix(max(0, limit)))
            }
            return listings
        }
        return EntriesResult(range: range, listings: listings, now: now, calendar: calendar)
    }

    /// Creates a stopped entry; returns every midnight piece.
    public func createEntry(_ draft: EntryDraft, force: Bool = false) async throws(AutomationError) -> [EntryListing] {
        let store = store
        let pieces = try await run { try await store.transaction { try $0.checkedCreate(draft, force: force) } }
        return try await listings(pieces)
    }

    /// Changes one entry; returns every piece.
    public func editEntry(_ id: EntryID, _ change: EntryChange, force: Bool = false) async throws(AutomationError) -> [EntryListing] {
        let store = store
        let pieces = try await run { try await store.transaction { try $0.checkedUpdate(id, change, force: force) } }
        return try await listings(pieces)
    }

    /// Deletes one entry.
    public func deleteEntry(_ id: EntryID) async throws(AutomationError) {
        let store = store
        try await run { try await store.delete([id]) }
    }

    /// The listing of one entry.
    public func listing(_ entry: TimeEntry) async throws(AutomationError) -> EntryListing {
        try await listings([entry])[0]
    }

    public func listings(_ entries: [TimeEntry]) async throws(AutomationError) -> [EntryListing] {
        let store = store
        return try await run { try await store.listings(for: entries) }
    }

    // MARK: Helpers

    private func result(_ outcome: StartOutcome) async throws(AutomationError) -> StartResult {
        let entries = [outcome.entry] + (outcome.stopped.map { [$0] } ?? [])
        let listings = try await listings(entries)
        return StartResult(entry: listings[0], stopped: listings.count > 1 ? listings[1] : nil)
    }

    /// Seconds of `entry` inside `interval`, a running entry up to `now`.
    static func seconds(of entry: TimeEntry, within interval: DateInterval, at now: Date) -> Int {
        let start = max(entry.start, interval.start)
        let end = min(entry.end ?? now, interval.end)
        return max(0, Int(end.timeIntervalSince(start).rounded(.down)))
    }

    /// Runs store calls, turning their errors into automation errors.
    func run<R>(_ body: () async throws -> R) async throws(AutomationError) -> R {
        try await AutomationError.catching(body)
    }
}
