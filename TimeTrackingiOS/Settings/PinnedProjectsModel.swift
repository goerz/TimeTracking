// PinnedProjectsModel: the ordered pinned list of Settings > Widgets over the
// synced `pinnedProjectIDs` (spec_ios.md §2.9, §3.4).

import Foundation
import Observation
import TimeTrackingCore

/// Adds from the picker, reorders, and removes pinned projects.
@Observable
final class PinnedProjectsModel {
    @ObservationIgnored let store: TimeStore

    private(set) var rows: [ProjectRow] = []

    init(store: TimeStore) {
        self.store = store
    }

    func load() async {
        let ids = await (try? store.value(.pinnedProjectIDs)) ?? []
        let all = await (try? store.projects(filter: ProjectFilter(state: .all))) ?? []
        rows = ids.compactMap { id in all.first { $0.project.id == id } }
    }

    func add(_ id: ProjectID) async {
        var ids = rows.map(\.project.id)
        guard !ids.contains(id) else {
            return
        }
        ids.append(id)
        await save(ids)
    }

    /// The list's drag: `source` rows go before the row at `destination`.
    func move(from source: IndexSet, to destination: Int) async {
        let ids = rows.map(\.project.id)
        let moving = source.sorted().map { ids[$0] }
        var kept = ids.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let shift = source.count { $0 < destination }
        kept.insert(contentsOf: moving, at: min(max(destination - shift, 0), kept.count))
        await save(kept)
    }

    func remove(at offsets: IndexSet) async {
        let ids = rows.map(\.project.id).enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        await save(ids)
    }

    private func save(_ ids: [ProjectID]) async {
        try? await store.set(.pinnedProjectIDs, ids)
        await load()
    }
}
