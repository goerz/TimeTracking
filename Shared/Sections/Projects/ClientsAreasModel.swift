// ClientsAreasModel: the client and area rows of the projects table, their
// sheets, and their actions (projects.md §2.5, §4). Counts and
// the rules for which action applies come from the library's
// `ClientAreaOutline`.

import Foundation
import Observation
import os
import TimeTrackingCore

/// A selected client or area row.
enum ClientsAreasSelection: Hashable {
    case client(ClientID)
    case area(AreaID)
}

/// The clients and areas, their sheets, and their confirmations.
@Observable
final class ClientsAreasModel {
    @ObservationIgnored let store: TimeStore
    @ObservationIgnored let clock: any Clock
    @ObservationIgnored weak var projects: ProjectsModel?
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private(set) var pendingUndo: Task<Void, Never>?

    private(set) var outline: [ClientOutline] = []
    /// A client or area row selected alone in the projects table; selecting
    /// it clears the selected projects.
    var selection: ClientsAreasSelection? {
        didSet {
            if selection != nil, projects?.selection.isEmpty == false {
                projects?.selection = []
            }
        }
    }

    var clientForm: ClientFormModel?
    var areaForm: AreaFormModel?
    var confirmation: ClientsAreasConfirmation?
    private(set) var lastError: String?

    init(store: TimeStore, clock: any Clock) {
        self.store = store
        self.clock = clock
    }

    func reload() async {
        do {
            outline = try await ClientAreaOutline.build(
                clients: store.clients(includeRetired: true),
                areas: store.areas(of: nil, includeRetired: true),
                projects: store.projects(filter: ProjectFilter(state: .all))
            )
        } catch {
            report(error)
        }
    }

    func client(_ id: ClientID) -> ClientOutline? {
        outline.first { $0.id == id }
    }

    func area(_ id: AreaID) -> (ClientOutline, AreaOutline)? {
        for client in outline {
            if let area = client.areas.first(where: { $0.id == id }) {
                return (client, area)
            }
        }
        return nil
    }

    /// The client of the selection (⇧⌥⌘N adds an area to it).
    var selectedClient: ClientID? {
        switch selection {
        case let .client(id): id
        case let .area(id): area(id)?.0.id
        case nil: nil
        }
    }

    // MARK: Sheets

    /// New Client….
    func newClient() async {
        clientForm = await ClientFormModel.create(store: store)
    }

    /// Rename… on a client.
    func renameClient(_ id: ClientID) {
        guard let client = client(id)?.client else {
            return
        }
        let form = ClientFormModel(store: store, mode: .rename(client))
        form.undoManager = undoManager
        clientForm = form
    }

    /// New Area… (⇧⌥⌘N); the Client popup starts on the given client or
    /// the selected one.
    func newArea(in client: ClientID? = nil) async {
        areaForm = await AreaFormModel.create(store: store, client: client ?? selectedClient)
    }

    /// Edit… (double-click, ↩) on an area.
    func editArea(_ id: AreaID) {
        guard let (client, area) = area(id) else {
            return
        }
        let form = AreaFormModel.edit(store: store, area: area.area, client: client.client)
        form.undoManager = undoManager
        areaForm = form
    }

    /// Double-click or ↩ on the selection.
    func editSelection() {
        switch selection {
        case let .client(id): renameClient(id)
        case let .area(id): editArea(id)
        case nil: break
        }
    }

    /// A sheet closed; a created client or area is selected.
    func sheetFinished(created: ClientsAreasSelection? = nil) async {
        clientForm = nil
        areaForm = nil
        await projects?.reload()
        if let created {
            selection = created
        }
    }

    // MARK: Area actions

    /// Move Up (⌥⌘↑) or Move Down (⌥⌘↓); undoable.
    func move(_ id: AreaID, by step: Int) async {
        guard let (client, _) = area(id) else {
            return
        }
        await apply(ClientAreaOutline.move(client, area: id, by: step), in: client, name: step < 0 ? "Move Up" : "Move Down")
    }

    private func apply(_ changes: [(AreaID, Int)], in client: ClientOutline, name: String) async {
        guard !changes.isEmpty else {
            return
        }
        let old = client.areas.filter { !$0.area.isGeneral }.map { ($0.id, $0.area.sortOrder) }
        await perform(name: name) { store in
            for (area, order) in changes {
                try await store.updateArea(area, AreaChange(sortOrder: order))
            }
        } undo: { store in
            for (area, order) in old {
                try await store.updateArea(area, AreaChange(sortOrder: order))
            }
        }
    }

    /// Retire (only without active projects) or Reactivate; undoable.
    func setRetired(_ id: AreaID, _ retired: Bool) async {
        await perform(name: retired ? "Retire" : "Reactivate") { store in
            try await store.updateArea(id, AreaChange(retired: retired))
        } undo: { store in
            try await store.updateArea(id, AreaChange(retired: !retired))
        }
    }

    /// Delete… on an area: confirmed.
    func requestDelete(_ id: AreaID) {
        guard let (_, area) = area(id), area.canDelete else {
            return
        }
        confirmation = ClientsAreasConfirmation(title: "Delete “\(area.area.name)”?", confirmTitle: "Delete", action: .deleteArea(id))
    }

    /// Remove… on a client: confirmed.
    func requestRemove(_ id: ClientID) {
        guard let client = client(id), client.canRemove else {
            return
        }
        confirmation = ClientsAreasConfirmation(title: "Remove “\(client.client.name)”?", confirmTitle: "Remove", action: .removeClient(id))
    }

    func confirm() async {
        guard let confirmation else {
            return
        }
        self.confirmation = nil
        switch confirmation.action {
        case let .deleteArea(id):
            await perform(name: nil) { store in try await store.deleteArea(id) }
        case let .removeClient(id):
            await perform(name: nil) { store in try await store.deleteClient(id) }
        }
        selection = nil
    }

    // MARK: Helpers

    private func perform(
        name: String?,
        _ write: (TimeStore) async throws -> Void,
        undo: (@Sendable (TimeStore) async throws -> Void)? = nil
    ) async {
        do {
            try await write(store)
            if let name, let undo, let undoManager {
                undoManager.registerUndo(withTarget: self) { model in
                    model.pendingUndo = Task { @MainActor in
                        try? await undo(model.store)
                        await model.reload()
                        await model.projects?.reload()
                    }
                }
                undoManager.setActionName(name)
            }
        } catch {
            report(error)
        }
        if let projects {
            await projects.reload()
        } else {
            await reload()
        }
    }

    private func report(_ error: any Error) {
        lastError = UserMessage.text(for: error)
        Logging.logger(category: "Sections").error("Clients & Areas command failed: \(String(describing: error), privacy: .public)")
    }

    /// Waits for a pending undo (tests).
    func waitForUndo() async {
        await pendingUndo?.value
    }
}

/// Delete or Remove, as an alert.
struct ClientsAreasConfirmation: Identifiable, Equatable {
    enum Action: Equatable {
        case deleteArea(AreaID)
        case removeClient(ClientID)
    }

    var title: String
    var confirmTitle: String
    var action: Action

    var id: String {
        title
    }

    var message: String {
        "This cannot be undone."
    }
}
