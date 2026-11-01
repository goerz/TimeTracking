// Midnight chains: task and project changes along a chain
// (spec_timer.md §4.3, spec_data_and_sync.md §1.5).

import Foundation
import GRDB

extension StoreTransaction {
    /// Changes task and project of every live piece of the chain of `id`
    /// (`nil` leaves a field as it is; `.some(nil)` clears the project).
    /// Returns the pieces by start.
    @discardableResult
    public func updateChain(of id: EntryID, task: String?, projectID: ProjectID??) throws -> [TimeEntry] {
        let entry = try liveEntry(id)
        var pieces: [TimeEntry] = []
        for piece in try chainEntries(root: entry.rootID) {
            try pieces.append(contentsOf: update(piece.id, EntryChange(projectID: projectID, task: task)))
        }
        return pieces.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    /// The live pieces of the chain of `id`, by start.
    public func chain(of id: EntryID) throws -> [TimeEntry] {
        guard let entry = try entry(id, includeDeleted: true) else {
            throw StoreError.unknownID
        }
        return try chainEntries(root: entry.rootID)
    }
}

extension TimeStore {
    /// `StoreTransaction.updateChain(of:task:projectID:)` as one write.
    @discardableResult
    public func updateChain(of id: EntryID, task: String? = nil, projectID: ProjectID?? = nil) throws -> [TimeEntry] {
        try write { try $0.updateChain(of: id, task: task, projectID: projectID) }
    }

    /// The live pieces of the chain of `id`, by start.
    public func chain(of id: EntryID) throws -> [TimeEntry] {
        try read { database in
            guard let entry = try StoreQueries.entry(id, includeDeleted: true, in: database) else {
                throw StoreError.unknownID
            }
            return try StoreQueries.chainEntries(root: entry.rootID, in: database)
        }
    }
}
