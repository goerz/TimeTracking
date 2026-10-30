// ClientFormModel: the client sheet's model: name rule, default color, and
// undoable rename (spec_planner_projects.md §4.2, §4.4).

import Foundation
import Observation
import TimeTrackingCore

/// The client sheet: Name and, for a new client, Color (the general area's).
@Observable
final class ClientFormModel {
    enum Mode: Equatable {
        case create
        case rename(Client)
    }

    @ObservationIgnored let store: TimeStore
    @ObservationIgnored weak var undoManager: UndoManager?
    let mode: Mode
    var name: String
    /// `#RRGGBB`, prefilled with the default rule (create only).
    var color: String
    private(set) var nameError: String?
    private(set) var lastError: String?

    init(store: TimeStore, mode: Mode, color: String = "#4D94CC") {
        self.store = store
        self.mode = mode
        self.color = color
        if case let .rename(client) = mode {
            self.name = client.name
        } else {
            self.name = ""
        }
    }

    /// A new client with the default color of §4.4 prefilled.
    static func create(store: TimeStore) async -> ClientFormModel {
        await ClientFormModel(store: store, mode: .create, color: AreaFormModel.defaultColor(store: store))
    }

    var title: String {
        mode == .create ? "New Client" : "Rename Client"
    }

    var confirmTitle: String {
        mode == .create ? "Create" : "Rename"
    }

    var showsColor: Bool {
        mode == .create
    }

    var canSubmit: Bool {
        !name.trimmed.isEmpty && nameError == nil
    }

    /// Unique among clients, case- and diacritic-insensitively.
    func validate() async {
        let excluded: ClientID? = if case let .rename(client) = mode {
            client.id
        } else {
            nil
        }
        let clients = await (try? store.clients(includeRetired: true)) ?? []
        let taken = clients.contains { $0.id != excluded && $0.name.folded == name.folded }
        nameError = taken && !name.trimmed.isEmpty ? "A client with this name already exists" : nil
    }

    /// Create or Rename; returns the client and its general area.
    func submit() async -> (Client, Area?)? {
        await validate()
        guard canSubmit else {
            return nil
        }
        do {
            switch mode {
            case .create:
                let (client, area) = try await store.createClient(name: name.trimmed, generalAreaColor: color)
                return (client, area)
            case let .rename(client):
                let newName = name.trimmed
                try await store.updateClient(client.id, name: newName)
                undoManager?.registerUndo(withTarget: store) { store in
                    Task { try? await store.updateClient(client.id, name: client.name) }
                }
                undoManager?.setActionName("Rename Client")
                var renamed = client
                renamed.name = newName
                return (renamed, nil)
            }
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
}

extension ClientFormModel: Identifiable {
    var id: ObjectIdentifier {
        ObjectIdentifier(self)
    }
}
