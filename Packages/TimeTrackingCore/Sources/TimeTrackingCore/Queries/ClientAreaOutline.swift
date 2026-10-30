// ClientAreaOutline: the Clients & Areas view's rows, counts, and the rules
// for which actions apply (spec_planner_projects.md §4).

import Foundation

/// An area row with its project counts.
public struct AreaOutline: Hashable, Sendable, Identifiable {
    public var area: Area
    public var activeCount: Int
    public var archivedCount: Int
    /// Position among the client's areas (the general area is 0).
    public var index: Int
    public var isLast: Bool

    public var id: AreaID {
        area.id
    }

    /// "1 active · 2 archived" (a zero archived count is omitted).
    public var countsText: String {
        ClientAreaOutline.counts(active: activeCount, archived: archivedCount)
    }

    /// "general", "retired", or nothing.
    public var tag: String? {
        area.isGeneral ? "general" : area.isRetired ? "retired" : nil
    }

    public var canRename: Bool {
        !area.isGeneral
    }

    /// Retire: only without active projects; never the general area.
    public var canRetire: Bool {
        !area.isGeneral && !area.isRetired && activeCount == 0
    }

    public var canUnretire: Bool {
        area.isRetired
    }

    /// Delete: only without projects in any state; never the general area.
    public var canDelete: Bool {
        !area.isGeneral && activeCount + archivedCount == 0
    }

    /// "Has N projects".
    public var deleteTooltip: String? {
        guard !area.isGeneral, !canDelete else {
            return nil
        }
        let count = activeCount + archivedCount
        return "Has \(count) \(count == 1 ? "project" : "projects")"
    }

    /// The general area stays first.
    public var canMoveUp: Bool {
        !area.isGeneral && index > 1
    }

    public var canMoveDown: Bool {
        !area.isGeneral && !isLast
    }
}

/// A client row with its areas.
public struct ClientOutline: Hashable, Sendable, Identifiable {
    public var client: Client
    public var areas: [AreaOutline]

    public var id: ClientID {
        client.id
    }

    public var activeCount: Int {
        areas.reduce(0) { $0 + $1.activeCount }
    }

    public var archivedCount: Int {
        areas.reduce(0) { $0 + $1.archivedCount }
    }

    /// "3 areas · 3 active · 4 archived".
    public var countsText: String {
        "\(areas.count) \(areas.count == 1 ? "area" : "areas") · " + ClientAreaOutline.counts(active: activeCount, archived: archivedCount)
    }

    /// Remove: only without areas besides the general one and without projects.
    public var canRemove: Bool {
        areas.allSatisfy(\.area.isGeneral) && activeCount + archivedCount == 0
    }

    /// "Has N areas and M projects".
    public var removeTooltip: String? {
        guard !canRemove else {
            return nil
        }
        let others = areas.count { !$0.area.isGeneral }
        let projects = activeCount + archivedCount
        return "Has \(others) \(others == 1 ? "area" : "areas") and \(projects) \(projects == 1 ? "project" : "projects")"
    }
}

/// The outline of clients alphabetically, each with its areas in order.
public enum ClientAreaOutline {
    public static func build(clients: [Client], areas: [Area], projects: [ProjectRow]) -> [ClientOutline] {
        var active: [AreaID: Int] = [:]
        var archived: [AreaID: Int] = [:]
        for row in projects {
            if row.project.isArchived {
                archived[row.project.areaID, default: 0] += 1
            } else {
                active[row.project.areaID, default: 0] += 1
            }
        }
        let byClient = Dictionary(grouping: areas, by: \.clientID)
        return clients
            .sorted { ($0.name.folded, $0.id) < ($1.name.folded, $1.id) }
            .map { client in
                let ordered = (byClient[client.id] ?? []).sorted { lhs, rhs in
                    (lhs.isGeneral ? 0 : 1, lhs.sortOrder, lhs.name.folded) < (rhs.isGeneral ? 0 : 1, rhs.sortOrder, rhs.name.folded)
                }
                return ClientOutline(client: client, areas: ordered.enumerated().map { index, area in
                    AreaOutline(
                        area: area,
                        activeCount: active[area.id] ?? 0,
                        archivedCount: archived[area.id] ?? 0,
                        index: index,
                        isLast: index == ordered.count - 1
                    )
                })
            }
    }

    /// The new `sortOrder` of each non-general area of `client` after moving
    /// `area` to position `target` among them (0-based), as changes for the
    /// areas whose order differs. The general area stays first.
    public static func reorder(_ client: ClientOutline, moving area: AreaID, to target: Int) -> [(AreaID, Int)] {
        var others = client.areas.filter { !$0.area.isGeneral }
        guard let from = others.firstIndex(where: { $0.id == area }) else {
            return []
        }
        let moved = others.remove(at: from)
        others.insert(moved, at: min(max(target, 0), others.count))
        return others.enumerated().compactMap { index, outline in
            outline.area.sortOrder == index + 1 ? nil : (outline.id, index + 1)
        }
    }

    /// Move Up (`-1`) or Move Down (`1`).
    public static func move(_ client: ClientOutline, area: AreaID, by step: Int) -> [(AreaID, Int)] {
        let others = client.areas.filter { !$0.area.isGeneral }
        guard let from = others.firstIndex(where: { $0.id == area }) else {
            return []
        }
        return reorder(client, moving: area, to: from + step)
    }

    static func counts(active: Int, archived: Int) -> String {
        archived == 0 ? "\(active) active" : "\(active) active · \(archived) archived"
    }
}
