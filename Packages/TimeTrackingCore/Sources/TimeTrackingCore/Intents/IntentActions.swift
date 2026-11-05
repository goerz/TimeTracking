// IntentActions: what the App Intents do, on an AutomationService, with
// their dialogs (spec_automation.md §5, spec_ios.md §6.3). The intents'
// `perform()` only resolves parameters and calls these.

public import Foundation

/// The operations behind the intents; the result value and dialog text.
public enum IntentActions {
    /// An intent's result: its value and the dialog Siri speaks.
    public struct Outcome<Value: Sendable>: Sendable {
        public var value: Value
        public var dialog: String
    }

    /// Starts an entry, stopping the running one. With `inferProject` (the
    /// Siri App Shortcut only), a non-empty task, and no project, the
    /// project is the one of the most recent entry with that task
    /// (trimmed, case- and diacritic-insensitive) whose project is active.
    public static func start(
        task: String?,
        project: ProjectID?,
        inferProject: Bool,
        service: AutomationService
    ) async throws(AutomationError) -> Outcome<TimeEntryEntity> {
        let task = task?.trimmed ?? ""
        var projectID = project
        if inferProject, projectID == nil, !task.isEmpty {
            projectID = try await inferredProject(task: task, service: service)
        }
        let result = try await service.start(task: task, projectID: projectID)
        return Outcome(value: TimeEntryEntity(result.entry, now: service.now), dialog: IntentText.started(result.entry))
    }

    /// Stops the running entry; nothing running is a `nil` result with
    /// "Nothing is running.", not an error.
    public static func stop(service: AutomationService) async throws(AutomationError) -> Outcome<TimeEntryEntity?> {
        let status = try await service.status()
        guard status.running != nil else {
            return Outcome(value: nil, dialog: "Nothing is running.")
        }
        let stopped = try await service.stop()
        let seconds = try await service.store.automationChainSeconds(of: stopped.entry, now: service.now)
        return Outcome(
            value: TimeEntryEntity(stopped, now: service.now),
            dialog: "Stopped \(IntentText.subject(stopped)) after \(IntentText.duration(seconds))."
        )
    }

    /// Continues the most recent entry other than the running one, or the
    /// project's most recent entry.
    public static func `continue`(
        project: ProjectID?,
        service: AutomationService
    ) async throws(AutomationError) -> Outcome<TimeEntryEntity> {
        let result = try await service.continue(project.map { .project($0) } ?? .latest)
        return Outcome(value: TimeEntryEntity(result.entry, now: service.now), dialog: IntentText.started(result.entry))
    }

    /// The running entry, if any.
    public static func current(service: AutomationService) async throws(AutomationError) -> Outcome<TimeEntryEntity?> {
        let status = try await service.status()
        guard let running = status.running else {
            return Outcome(value: nil, dialog: "Nothing is running.")
        }
        return Outcome(
            value: TimeEntryEntity(running, now: service.now),
            dialog: "\(IntentText.subject(running)) is running for \(IntentText.duration(running.entry.seconds(at: service.now)))."
        )
    }

    /// The total of `date`'s day (today when `nil`) including the running entry.
    public static func total(on date: Date?, service: AutomationService) async throws(AutomationError) -> Outcome<Int> {
        let calendar = service.calendar
        let day = date.map { calendar.day(containing: $0) } ?? service.today
        let seconds = try await service.totalSeconds(on: day)
        let suffix = day == service.today ? "today" : "on \(IntentText.spokenDay(day, today: service.today))"
        return Outcome(value: seconds, dialog: "\(IntentText.duration(seconds)) \(suffix)")
    }

    /// Entries whose start lies in the half-open day range of `from` and `to`.
    public static func entries(
        from: Date,
        to: Date,
        project: ProjectID?,
        client: ClientID?,
        service: AutomationService
    ) async throws(AutomationError) -> Outcome<[TimeEntryEntity]> {
        let calendar = service.calendar
        var range = DayRange(from: calendar.day(containing: from), to: calendar.day(containing: to))
        if range.to <= range.from {
            range.to = range.from.adding(days: 1)
        }
        var filter = EntryFilter()
        if let project {
            filter.projects = [project]
        }
        if let client {
            filter.clients = [client]
        }
        let result = try await service.entries(in: range, filter: filter)
        let entities = result.listings.map { TimeEntryEntity($0, now: service.now) }
        return Outcome(value: entities, dialog: entities.count == 1 ? "1 entry" : "\(entities.count) entries")
    }

    /// Creates an active project in `area`; fails as `project create`.
    public static func createProject(
        name: String,
        area: AreaID,
        service: AutomationService
    ) async throws(AutomationError) -> Outcome<ProjectEntity> {
        let store = service.store
        let project = try await service.run { try await store.createProject(ProjectDraft(areaID: area, name: name)) }
        let row = try await service.row(project.id)
        return Outcome(value: ProjectEntity(row), dialog: "Created \(row.project.name).")
    }

    /// The project of the most recent entry whose task equals `task` and
    /// whose project is active.
    static func inferredProject(task: String, service: AutomationService) async throws(AutomationError) -> ProjectID? {
        let store = service.store
        let folded = task.folded
        let entries = try await service.run {
            try await store.entries(matching: ReportQuery.allTime(filter: EntryFilter(includeArchived: false)))
        }
        return entries.last { $0.task.folded == folded && $0.projectID != nil }?.projectID
    }
}

/// The dialog texts of the intents.
public enum IntentText {
    /// "Started Clarify noise model on Noise paper."
    public static func started(_ listing: EntryListing) -> String {
        "Started \(subject(listing))."
    }

    /// "Clarify noise model on Noise paper", the task or project alone, or "a timer".
    public static func subject(_ listing: EntryListing) -> String {
        let task = listing.entry.task
        switch (task.isEmpty, listing.project?.name) {
        case let (false, name?): return "\(task) on \(name)"
        case (false, nil): return task
        case let (true, name?): return name
        case (true, nil): return "a timer"
        }
    }

    /// "4 hours 2 minutes", "1 hour", "25 minutes".
    public static func duration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = seconds / 60 % 60
        let hourText = hours == 1 ? "1 hour" : "\(hours) hours"
        let minuteText = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        if hours == 0 {
            return minuteText
        }
        return minutes == 0 ? hourText : "\(hourText) \(minuteText)"
    }

    /// "Thursday, March 14", with ", 2023" when `day` is not in `today`'s year.
    public static func spokenDay(_ day: TrackingDay, today: TrackingDay) -> String {
        let text = DayText.longWeekdayDate(day)
        return day.year == today.year ? text : "\(text), \(day.year)"
    }
}

extension TimeStore {
    /// The seconds of the chain `entry` ends.
    func automationChainSeconds(of entry: TimeEntry, now: Date) throws(AutomationError) -> Int {
        let start = try AutomationError.catching { try chainStart(of: entry.id) }
        return max(0, Int((entry.end ?? now).timeIntervalSince(start).rounded(.down)))
    }
}
