// TimeStoreWriting: every write of the store (spec_data_and_sync.md §7.1).

public import Foundation

/// The write API. Every write validates, writes, runs the invariant pass,
/// queues outbox rows, commits, and posts the change notification.
public protocol TimeStoreWriting: Sendable {
    /// Starts an entry at `at`, stopping the running one there.
    func start(projectID: ProjectID?, task: String, at: Date) async throws -> TimeEntry
    /// Stops the running entry; `nil` when nothing runs.
    func stop(at: Date) async throws -> TimeEntry?
    /// Starts a new entry with the project and task of `id`.
    func `continue`(_ id: EntryID, at: Date) async throws -> TimeEntry
    /// Creates an entry; returns its midnight-split pieces, the given id first.
    func create(_ draft: EntryDraft) async throws -> [TimeEntry]
    /// Changes project, task, start, or end; returns the pieces, the given id first.
    func update(_ id: EntryID, _ change: EntryChange) async throws -> [TimeEntry]
    func move(_ id: EntryID, by offset: TimeInterval) async throws -> [TimeEntry]
    /// A user split at `at`; the second part gets a random id.
    func split(_ id: EntryID, at: Date) async throws -> (TimeEntry, TimeEntry)
    func delete(_ ids: [EntryID]) async throws
    func restore(_ ids: [EntryID]) async throws
    func createClient(name: String, generalAreaColor: String?) async throws -> (Client, Area)
    func updateClient(_ id: ClientID, name: String) async throws
    func deleteClient(_ id: ClientID) async throws
    func createArea(_ draft: AreaDraft) async throws -> Area
    func updateArea(_ id: AreaID, _ change: AreaChange) async throws
    func deleteArea(_ id: AreaID) async throws
    func createProject(_ draft: ProjectDraft) async throws -> Project
    func updateProject(_ id: ProjectID, _ change: ProjectChange) async throws
    func archive(_ id: ProjectID) async throws
    func restoreProject(_ id: ProjectID) async throws
    func merge(project: ProjectID, into target: ProjectID) async throws
    func deleteProject(_ id: ProjectID) async throws
    func set<T>(_ key: SyncedSettingKey<T>, _ value: T) async throws
    func setWidgetPushToken(_ token: String?) async throws
    func importDocument(_ data: Data, options: ImportOptions) async throws -> ImportReport
    /// Runs `body` as one transaction with one invariant pass.
    func transaction<R: Sendable>(_ body: @Sendable (StoreTransaction) throws -> R) async throws -> R
}
