// ProjectTable: filtering, grouping, sorting, and the status line of the
// Projects section (spec_planner_projects.md §2).

public import Foundation

/// Group by.
public enum ProjectGrouping: String, Codable, Sendable, CaseIterable {
    case ungrouped = "none"
    case client
    case area

    public var title: String {
        switch self {
        case .ungrouped: "None"
        case .client: "Client"
        case .area: "Area"
        }
    }
}

/// Sort by (State is not sortable).
public enum ProjectSortKey: String, Codable, Sendable, CaseIterable {
    case name
    case client
    case area
    case created
    case lastTracked = "last_tracked"
    case totalTracked = "total_tracked"

    public var title: String {
        switch self {
        case .name: "Name"
        case .client: "Client"
        case .area: "Area"
        case .created: "Created"
        case .lastTracked: "Last tracked"
        case .totalTracked: "Total tracked"
        }
    }
}

/// The Filters popover's "Last tracked".
public enum LastTrackedFilter: String, Codable, Sendable, CaseIterable {
    case anyTime = "any_time"
    case last30Days = "last_30_days"
    case last90Days = "last_90_days"
    case notLast90Days = "not_last_90_days"
    case notLastYear = "not_last_year"
    case never

    public var title: String {
        switch self {
        case .anyTime: "Any time"
        case .last30Days: "In the last 30 days"
        case .last90Days: "In the last 90 days"
        case .notLast90Days: "Not in the last 90 days"
        case .notLastYear: "Not in the last year"
        case .never: "Never"
        }
    }

    /// Whether a project last tracked at `last` passes at `now`.
    public func matches(_ last: Date?, now: Date) -> Bool {
        let day = 86_400.0
        switch self {
        case .anyTime:
            return true
        case .last30Days:
            return last.map { $0 >= now.addingTimeInterval(-30 * day) } ?? false
        case .last90Days:
            return last.map { $0 >= now.addingTimeInterval(-90 * day) } ?? false
        case .notLast90Days:
            return last.map { $0 < now.addingTimeInterval(-90 * day) } ?? false
        case .notLastYear:
            return last.map { $0 < now.addingTimeInterval(-365 * day) } ?? false
        case .never:
            return last == nil
        }
    }
}

extension ProjectFilter.State: Codable {
    public var title: String {
        switch self {
        case .active: "Active"
        case .archived: "Archived"
        case .all: "All"
        }
    }
}

/// The stored view state of the projects table (the search is not stored).
public struct ProjectTableOptions: Hashable, Codable, Sendable {
    public var state: ProjectFilter.State = .active
    public var clients: Set<ClientID> = []
    public var areas: Set<AreaID> = []
    public var lastTracked: LastTrackedFilter = .anyTime
    public var grouping: ProjectGrouping = .client
    public var sort: ProjectSortKey = .name
    public var ascending = true

    public init() {}

    /// The Filters badge: checked clients and areas, plus a Last tracked choice.
    public var filterCount: Int {
        clients.count + areas.count + (lastTracked == .anyTime ? 0 : 1)
    }

    /// Checking a client clears its areas' checks.
    public mutating func toggle(client: ClientID, areasOfClient: [AreaID]) {
        if clients.contains(client) {
            clients.remove(client)
        } else {
            clients.insert(client)
            areas.subtract(areasOfClient)
        }
    }

    /// Checking an area clears its client's check.
    public mutating func toggle(area: Area) {
        if areas.contains(area.id) {
            areas.remove(area.id)
        } else {
            areas.insert(area.id)
            clients.remove(area.clientID)
        }
    }

    /// "Clear" in the popover.
    public mutating func clearFilters() {
        clients = []
        areas = []
        lastTracked = .anyTime
    }

    /// A header click: the same key reverses, another sorts ascending.
    public mutating func sort(by key: ProjectSortKey) {
        if sort == key {
            ascending.toggle()
        } else {
            sort = key
            ascending = true
        }
    }
}

/// One row of the table.
public struct ProjectTableRow: Hashable, Sendable, Identifiable {
    public var row: ProjectRow
    /// Another live project of the client has this name (⚠).
    public var isDuplicate: Bool
    /// The area is missing: "–" for Client, "(deleted area)" for Area.
    public var isOrphan: Bool

    public var id: ProjectID {
        row.id
    }

    public var clientText: String {
        isOrphan ? "–" : row.client?.name ?? "–"
    }

    /// The area's name; a general area shows the client's name (secondary).
    public var areaText: String {
        isOrphan ? "(deleted area)" : row.area?.name ?? ""
    }

    public var areaIsGeneral: Bool {
        row.area?.isGeneral ?? false
    }

    /// "Another project of Consulting has this name".
    public var duplicateTooltip: String? {
        isDuplicate ? "Another project of \(row.client?.name ?? "this client") has this name" : nil
    }
}

/// A group header with its rows.
public struct ProjectTableGroup: Hashable, Sendable, Identifiable {
    /// The collapse key: `client:<id>`, `area:<id>`, `orphans`, or `all`.
    public var id: String
    /// "Consulting · 3 projects", "Consulting · Research · 2 projects".
    public var title: String
    public var clientID: ClientID?
    public var areaID: AreaID?
    /// The swatch of an area group.
    public var color: String?
    public var totalSeconds: Int
    public var rows: [ProjectTableRow]

    public var count: Int {
        rows.count
    }
}

/// The table after filtering, grouping, and sorting.
public struct ProjectTable: Hashable, Sendable {
    public var groups: [ProjectTableGroup]
    /// Over all projects, regardless of filters.
    public var activeCount: Int
    public var archivedCount: Int

    public var shownCount: Int {
        groups.reduce(0) { $0 + $1.count }
    }

    public var rows: [ProjectTableRow] {
        groups.flatMap(\.rows)
    }

    /// "9 projects shown (9 active, 25 archived)".
    public var statusText: String {
        "\(shownCount) \(shownCount == 1 ? "project" : "projects") shown (\(activeCount) active, \(archivedCount) archived)"
    }

    /// "No projects yet" (no project at all) or "No projects match".
    public var emptyText: String? {
        guard shownCount == 0 else {
            return nil
        }
        return activeCount + archivedCount == 0 ? "No projects yet" : "No projects match"
    }

    public init(groups: [ProjectTableGroup], activeCount: Int, archivedCount: Int) {
        self.groups = groups
        self.activeCount = activeCount
        self.archivedCount = archivedCount
    }

    /// Builds the table from all live projects (any state) and all areas
    /// and clients (retired included).
    public init(rows all: [ProjectRow], areas: [Area], options: ProjectTableOptions, search: String, now: Date) {
        let order = Dictionary(areas.map { ($0.id, $0.sortOrder) }, uniquingKeysWith: { first, _ in first })
        let names = Dictionary(grouping: all.filter { $0.area != nil }) { "\($0.client?.id.rawValue ?? "")/\($0.project.name.folded)" }
        let visible = all.filter { row in
            Self.passes(row, options: options, search: search, now: now)
        }
        .map { row in
            ProjectTableRow(
                row: row,
                isDuplicate: (names["\(row.client?.id.rawValue ?? "")/\(row.project.name.folded)"]?.count ?? 0) > 1,
                isOrphan: row.area == nil
            )
        }
        let sorted = visible.sorted { Self.precedes($0, $1, options: options, areaOrder: order) }
        self.init(
            groups: Self.groups(sorted, grouping: options.grouping, areaOrder: order),
            activeCount: all.count { !$0.project.isArchived },
            archivedCount: all.count(where: \.project.isArchived)
        )
    }

    static func passes(_ row: ProjectRow, options: ProjectTableOptions, search: String, now: Date) -> Bool {
        switch options.state {
        case .active where row.project.isArchived, .archived where !row.project.isArchived:
            return false
        default:
            break
        }
        if !options.clients.isEmpty || !options.areas.isEmpty {
            let byClient = row.client.map { options.clients.contains($0.id) } ?? false
            guard byClient || options.areas.contains(row.project.areaID) else {
                return false
            }
        }
        guard options.lastTracked.matches(row.lastUsed, now: now) else {
            return false
        }
        return ProjectPickerContent.matches(search, project: row.project.name, area: row.area?.name ?? "", client: row.client?.name ?? "")
    }

    /// The sort of §2.2; orphans after everything else; the name breaks ties.
    static func precedes(_ lhs: ProjectTableRow, _ rhs: ProjectTableRow, options: ProjectTableOptions, areaOrder: [AreaID: Int]) -> Bool {
        if lhs.isOrphan != rhs.isOrphan {
            return rhs.isOrphan
        }
        if options.sort == .lastTracked, (lhs.row.lastUsed == nil) != (rhs.row.lastUsed == nil) {
            return rhs.row.lastUsed == nil
        }
        let order = compare(lhs.row, rhs.row, key: options.sort, areaOrder: areaOrder)
        if order != .orderedSame {
            return (order == .orderedAscending) == options.ascending
        }
        return (lhs.row.project.name.folded, lhs.id) < (rhs.row.project.name.folded, rhs.id)
    }

    /// The order of two rows by `key` alone.
    private static func compare(
        _ left: ProjectRow,
        _ right: ProjectRow,
        key: ProjectSortKey,
        areaOrder: [AreaID: Int]
    ) -> ComparisonResult {
        func ordered<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
            lhs == rhs ? .orderedSame : lhs < rhs ? .orderedAscending : .orderedDescending
        }
        func areaKey(_ row: ProjectRow) -> String {
            "\(row.client?.name.folded ?? "")\u{1F}\(String(format: "%06d", areaOrder[row.project.areaID] ?? 0))"
        }
        switch key {
        case .name:
            return ordered(left.project.name.folded, right.project.name.folded)
        case .client:
            return ordered(left.client?.name.folded ?? "", right.client?.name.folded ?? "")
        case .area:
            return ordered(areaKey(left), areaKey(right))
        case .created:
            return ordered(left.project.createdAt, right.project.createdAt)
        case .totalTracked:
            return ordered(left.totalSeconds, right.totalSeconds)
        case .lastTracked:
            return ordered(left.lastUsed ?? .distantFuture, right.lastUsed ?? .distantFuture)
        }
    }

    static func groups(_ rows: [ProjectTableRow], grouping: ProjectGrouping, areaOrder: [AreaID: Int]) -> [ProjectTableGroup] {
        guard grouping != .ungrouped else {
            let all = ProjectTableGroup(id: "all", title: "", totalSeconds: rows.reduce(0) { $0 + $1.row.totalSeconds }, rows: rows)
            return rows.isEmpty ? [] : [all]
        }
        var keys: [String] = []
        var members: [String: [ProjectTableRow]] = [:]
        for row in rows {
            let key = groupKey(row, grouping: grouping)
            if members[key] == nil {
                keys.append(key)
            }
            members[key, default: []].append(row)
        }
        let groups = keys.compactMap { key -> ProjectTableGroup? in
            guard let rows = members[key], let first = rows.first else {
                return nil
            }
            return group(key: key, rows: rows, first: first, grouping: grouping)
        }
        return groups.sorted { lhs, rhs in
            let left = groupSortKey(lhs, areaOrder: areaOrder)
            let right = groupSortKey(rhs, areaOrder: areaOrder)
            return left < right
        }
    }

    private static func groupKey(_ row: ProjectTableRow, grouping: ProjectGrouping) -> String {
        if row.isOrphan {
            return "orphans"
        }
        return grouping == .client ? "client:\(row.row.client?.id.rawValue ?? "")" : "area:\(row.row.project.areaID.rawValue)"
    }

    private static func group(
        key: String,
        rows: [ProjectTableRow],
        first: ProjectTableRow,
        grouping: ProjectGrouping
    ) -> ProjectTableGroup {
        let count = "\(rows.count) \(rows.count == 1 ? "project" : "projects")"
        let total = rows.reduce(0) { $0 + $1.row.totalSeconds }
        if first.isOrphan {
            return ProjectTableGroup(id: key, title: "(deleted area) · \(count)", totalSeconds: total, rows: rows)
        }
        let client = first.row.client?.name ?? ""
        if grouping == .client {
            return ProjectTableGroup(
                id: key,
                title: "\(client) · \(count)",
                clientID: first.row.client?.id,
                totalSeconds: total,
                rows: rows
            )
        }
        let area = first.row.area
        let title = area?.isGeneral ?? true ? "\(client) · \(count)" : "\(client) · \(area?.name ?? "") · \(count)"
        return ProjectTableGroup(
            id: key,
            title: title,
            clientID: first.row.client?.id,
            areaID: area?.id,
            color: area?.color,
            totalSeconds: total,
            rows: rows
        )
    }

    private static func groupSortKey(_ group: ProjectTableGroup, areaOrder: [AreaID: Int]) -> String {
        guard let first = group.rows.first, !first.isOrphan else {
            return "\u{10FFFF}"
        }
        let client = first.row.client?.name.folded ?? ""
        let order = group.areaID.flatMap { areaOrder[$0] } ?? 0
        return "\(client)\u{1F}\(first.row.client?.id.rawValue ?? "")\u{1F}\(String(format: "%06d", order))"
    }

    /// "Today", "Yesterday", the weekday within the last 7 days, "Oct 27"
    /// within the current year, "2024" otherwise; "Never" for `nil`.
    public static func dateText(_ date: Date?, now: Date, calendar: TrackingCalendar) -> String {
        guard let date else {
            return "Never"
        }
        let day = calendar.day(containing: date)
        let today = calendar.day(containing: now)
        let distance = day.distance(to: today)
        switch distance {
        case 0:
            return "Today"
        case 1:
            return "Yesterday"
        case 2 ..< 7:
            return DayText.weekdayNames[day.isoWeekday - 1]
        default:
            return day.year == today.year ? "\(DayText.shortMonth(day)) \(day.day)" : String(day.year)
        }
    }
}
