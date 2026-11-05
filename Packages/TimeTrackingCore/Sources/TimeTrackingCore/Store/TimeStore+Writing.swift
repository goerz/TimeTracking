// The async write API of TimeStore (data_and_sync.md §7.1).

public import Foundation
import GRDB

extension TimeStore: TimeStoreWriting {
    @discardableResult
    public func start(projectID: ProjectID?, task: String, at: Date) throws -> TimeEntry {
        try write { try $0.start(projectID: projectID, task: task, at: at) }
    }

    @discardableResult
    public func stop(at: Date) throws -> TimeEntry? {
        try write { try $0.stop(at: at) }
    }

    @discardableResult
    public func `continue`(_ id: EntryID, at: Date) throws -> TimeEntry {
        try write { try $0.continue(id, at: at) }
    }

    @discardableResult
    public func create(_ draft: EntryDraft) throws -> TimeEntry {
        try write { try $0.create(draft) }
    }

    @discardableResult
    public func update(_ id: EntryID, _ change: EntryChange) throws -> TimeEntry {
        try write { try $0.update(id, change) }
    }

    @discardableResult
    public func move(_ id: EntryID, by offset: TimeInterval) throws -> TimeEntry {
        try write { try $0.move(id, by: offset) }
    }

    @discardableResult
    public func split(_ id: EntryID, at: Date) throws -> (TimeEntry, TimeEntry) {
        try write { try $0.split(id, at: at) }
    }

    public func delete(_ ids: [EntryID]) throws {
        try write { try $0.delete(ids) }
    }

    public func restore(_ ids: [EntryID]) throws {
        try write { try $0.restore(ids) }
    }

    @discardableResult
    public func createClient(name: String, generalAreaColor: String? = nil) throws -> (Client, Area) {
        try write { try $0.createClient(name: name, generalAreaColor: generalAreaColor) }
    }

    public func updateClient(_ id: ClientID, name: String) throws {
        try write { try $0.updateClient(id, name: name) }
    }

    public func deleteClient(_ id: ClientID) throws {
        try write { try $0.deleteClient(id) }
    }

    @discardableResult
    public func createArea(_ draft: AreaDraft) throws -> Area {
        try write { try $0.createArea(draft) }
    }

    public func updateArea(_ id: AreaID, _ change: AreaChange) throws {
        try write { try $0.updateArea(id, change) }
    }

    public func deleteArea(_ id: AreaID) throws {
        try write { try $0.deleteArea(id) }
    }

    @discardableResult
    public func createProject(_ draft: ProjectDraft) throws -> Project {
        try write { try $0.createProject(draft) }
    }

    public func updateProject(_ id: ProjectID, _ change: ProjectChange) throws {
        try write { try $0.updateProject(id, change) }
    }

    public func archive(_ id: ProjectID) throws {
        try write { try $0.archive(id) }
    }

    public func restoreProject(_ id: ProjectID) throws {
        try write { try $0.restoreProject(id) }
    }

    public func merge(project: ProjectID, into target: ProjectID) throws {
        try write { try $0.merge(project: project, into: target) }
    }

    public func deleteProject(_ id: ProjectID) throws {
        try write { try $0.deleteProject(id) }
    }

    public func set<T>(_ key: SyncedSettingKey<T>, _ value: T) throws {
        try write { try $0.set(key, value) }
    }

    /// The value of a synced setting, or its default.
    public func value<T>(_ key: SyncedSettingKey<T>) throws -> T {
        try read { try StoreQueries.settingValue(key, in: $0) }
    }

    /// The calendar of the days the app shows in `timeZone`, by the synced
    /// `midnightHour`. Reads the store on the caller's thread, so synchronous
    /// code gets it too; never call it inside a transaction.
    public nonisolated func displayCalendar(timeZone: TimeZone = .current) -> TrackingCalendar {
        let hour = try? reader.read { try StoreQueries.settingValue(.midnightHour, in: $0) }
        return TrackingCalendar(timeZone: timeZone, midnightHour: hour ?? 0)
    }

    /// Creates or refreshes this device's record (at most hourly).
    @discardableResult
    public func registerDevice(name: String, platform: DevicePlatform) throws -> Device {
        try write { try $0.registerDevice(name: name, platform: platform) }
    }

    public func setWidgetPushToken(_ token: String?) throws {
        try write { try $0.setWidgetPushToken(token) }
    }

    /// Daily maintenance: hard-deletes tombstones older than 180 days.
    @discardableResult
    public func purgeExpiredTombstones() throws -> Int {
        try write { try $0.purgeExpiredTombstones() }
    }

    @preconcurrency
    public func transaction<R: Sendable>(_ body: @Sendable (StoreTransaction) throws -> R) throws -> R {
        try write(body)
    }
}
