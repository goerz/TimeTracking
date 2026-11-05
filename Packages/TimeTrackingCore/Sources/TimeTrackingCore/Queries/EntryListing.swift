// EntryListing: an entry with the names display and CSV resolve it to
// (data_and_sync.md §7.3, automation.md §8.2). Client and area come
// from the project's current area.

import Foundation
import GRDB

/// An entry with its project, area, and client (each `nil` when absent or
/// not received yet).
public struct EntryListing: Identifiable, Hashable, Sendable {
    public var entry: TimeEntry
    public var project: Project?
    public var area: Area?
    public var client: Client?
    /// The stored entry when `entry` is only its piece of one day
    /// (`TrackingCalendar.pieces(of:at:)`).
    public var whole: TimeEntry?
    /// This row presents the stored entry's editor; of an entry's rows in
    /// one list only the earliest does (`anchoringEditors()`).
    var anchorsEditor = true

    public init(entry: TimeEntry, project: Project?, area: Area?, client: Client?, whole: TimeEntry? = nil) {
        self.entry = entry
        self.project = project
        self.area = area
        self.client = client
        self.whole = whole
    }

    public var id: EntryID {
        entry.id
    }

    /// Tells a stored entry's pieces apart in one list.
    public var rowID: String {
        "\(entry.id) \(entry.day)"
    }

    /// What an editor opens: the stored entry, on the row that anchors it
    /// only, so the entry's other rows don't present a second editor.
    public var editable: TimeEntry? {
        anchorsEditor ? whole ?? entry : nil
    }

    /// The listing's pieces in `calendar`.
    func pieces(in calendar: TrackingCalendar, at now: Date) -> [Self] {
        let pieces = calendar.pieces(of: entry, at: now)
        return pieces.map { piece in
            var listing = self
            listing.entry = piece
            listing.whole = pieces.count > 1 ? entry : nil
            return listing
        }
    }
}

extension [EntryListing] {
    /// The rows of one list, in start order: each entry's first row anchors
    /// its editor, also when the list holds only its later pieces.
    func anchoringEditors() -> Self {
        var seen: Set<EntryID> = []
        return map { listing in
            var listing = listing
            listing.anchorsEditor = seen.insert(listing.id).inserted
            return listing
        }
    }
}

extension TimeStore {
    /// Resolves the project, area, and client of each entry, tombstones
    /// included, so history keeps its names.
    public func listings(for entries: [TimeEntry]) throws -> [EntryListing] {
        try read { database in
            let projects = try Dictionary(
                Row.fetchAll(database, sql: "SELECT * FROM project").map(Project.init(row:)).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let areas = try Dictionary(
                Row.fetchAll(database, sql: "SELECT * FROM area").map(Area.init(row:)).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let clients = try Dictionary(
                Row.fetchAll(database, sql: "SELECT * FROM client").map(Client.init(row:)).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            return entries.map { entry in
                let project = entry.projectID.flatMap { projects[$0] }
                let area = project.flatMap { areas[$0.areaID] }
                return EntryListing(entry: entry, project: project, area: area, client: area.flatMap { clients[$0.clientID] })
            }
        }
    }
}
