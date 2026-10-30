// TimeEntryEntity: a time entry as an intent result (spec_automation.md §5).

public import AppIntents
public import Foundation

/// A time entry, identified by its UUID; found by identifier only.
public struct TimeEntryEntity: AppEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Time Entry"
    public static let defaultQuery = TimeEntryEntityQuery()

    public let id: UUID
    @Property(title: "Start") public var start: Date
    @Property(title: "End") public var end: Date?
    /// Seconds, a running entry's up to the query time.
    @Property(title: "Duration") public var duration: Int
    @Property(title: "Running") public var running: Bool
    @Property(title: "Task") public var task: String
    @Property(title: "Project") public var project: String?

    public init(_ listing: EntryListing, now: Date) {
        self.id = listing.entry.id.uuid
        self.start = listing.entry.start
        self.end = listing.entry.end
        self.duration = listing.entry.seconds(at: now)
        self.running = listing.entry.isRunning
        self.task = listing.entry.task
        self.project = listing.project?.name
    }

    public var entryID: EntryID {
        EntryID(id)
    }

    /// The task or "No task", with the project and start as subtitle.
    public var displayRepresentation: DisplayRepresentation {
        let title = task.isEmpty ? "No task" : task
        let time = start.formatted(date: .abbreviated, time: .shortened)
        let subtitle = project.map { "\($0), \(time)" } ?? time
        return DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }
}

/// Resolves entries by identifier.
public struct TimeEntryEntityQuery: EntityQuery {
    @Dependency private var environment: IntentEnvironment

    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [TimeEntryEntity] {
        let service = try await environment.automation()
        let store = service.store
        let entries = try await service.run {
            var found: [TimeEntry] = []
            for id in identifiers {
                if let entry = try await store.entry(EntryID(id)) {
                    found.append(entry)
                }
            }
            return found
        }
        return try await service.listings(entries).map { TimeEntryEntity($0, now: service.now) }
    }
}
