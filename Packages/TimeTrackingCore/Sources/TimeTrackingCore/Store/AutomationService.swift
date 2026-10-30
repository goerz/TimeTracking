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
        TrackingCalendar(timeZone: timeZone)
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
        return try await run {
            let running = try await store.runningEntry()
            let entries = try await store.entries(in: calendar.interval(of: today), includeDeleted: false)
            let total = entries.reduce(0) { $0 + Self.seconds(of: $1, within: calendar.interval(of: today), at: now) }
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
            var listings: [EntryListing]
            if runningOnly {
                let running = try await store.runningEntry().map { [$0] } ?? []
                listings = try await store.listings(for: running).filter { filter.matches($0) }
            } else {
                let interval = range.map { $0.interval(in: calendar) }
                let entries = try await store.entries(matching: ReportQuery.allTime(filter: filter, around: interval))
                    .filter { entry in interval.map { entry.start >= $0.start && entry.start < $0.end } ?? true }
                    .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
                listings = try await store.listings(for: entries)
            }
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
        do {
            return try await body()
        } catch {
            throw AutomationError(wrapping: error)
        }
    }
}

/// The result of `status`.
public struct AutomationStatus: Hashable, Sendable {
    public var running: EntryListing?
    public var today: TrackingDay
    /// Today's total including the running entry's part of today.
    public var todaySeconds: Int
    public var pendingChanges: Int
    public var asOf: Date
}

/// The result of `start` and `continue`.
public struct StartResult: Hashable, Sendable {
    public var entry: EntryListing
    /// The entry that was running and is now stopped.
    public var stopped: EntryListing?
}

/// Entries of a range with their day subtotals.
public struct EntriesResult: Hashable, Sendable {
    /// The range; `nil` for all time or `--running`.
    public var range: DayRange?
    public var listings: [EntryListing]
    public var now: Date
    /// Seconds of all listed entries, the running one up to `now`.
    public var totalSeconds: Int
    /// Per day of the listed entries' starts, in listing order.
    public var days: [(day: TrackingDay, seconds: Int)]

    public init(range: DayRange?, listings: [EntryListing], now: Date, calendar: TrackingCalendar) {
        self.range = range
        self.listings = listings
        self.now = now
        self.totalSeconds = listings.reduce(0) { $0 + $1.entry.seconds(at: now) }
        var days: [(day: TrackingDay, seconds: Int)] = []
        for listing in listings {
            let day = calendar.day(containing: listing.entry.start)
            if days.last?.day == day {
                days[days.count - 1].seconds += listing.entry.seconds(at: now)
            } else {
                days.append((day, listing.entry.seconds(at: now)))
            }
        }
        self.days = days
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.range == rhs.range && lhs.listings == rhs.listings && lhs.now == rhs.now
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(range)
        hasher.combine(listings)
    }
}

extension EntryFilter {
    /// Whether `listing` passes the filter.
    public func matches(_ listing: EntryListing) -> Bool {
        if let clients, !(listing.client.map { clients.contains($0.id) } ?? false) {
            return false
        }
        if let areas, !(listing.area.map { areas.contains($0.id) } ?? false) {
            return false
        }
        if let projects, !(listing.project.map { projects.contains($0.id) } ?? false) {
            return false
        }
        if listing.project == nil, !includeNoProject {
            return false
        }
        if noProjectOnly, listing.project != nil {
            return false
        }
        if let text = taskContains?.folded, !text.isEmpty, !listing.entry.task.folded.contains(text) {
            return false
        }
        return true
    }
}

extension ReportQuery {
    /// A query over every day an entry can have, for `entries(matching:)`.
    static func allTime(
        // swiftlint:disable:next discouraged_optional_collection
        projects: Set<ProjectID>? = nil,
        filter: EntryFilter = EntryFilter(),
        around interval: DateInterval? = nil
    ) -> Self {
        var filter = filter
        if let projects {
            filter.projects = projects
        }
        let calendar = TrackingCalendar(timeZone: .gmt)
        let days = interval.map { interval in
            calendar.day(containing: interval.start).adding(days: -2) ... calendar.day(containing: interval.end).adding(days: 2)
        } ?? TrackingDay(year: 1970, month: 1, day: 1) ... TrackingDay(year: 9999, month: 12, day: 31)
        return Self(days: days, groupBy: [], granularity: .total, filter: filter)
    }
}
