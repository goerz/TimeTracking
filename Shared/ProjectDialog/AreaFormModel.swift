// AreaFormModel: the area sheet's model: name rules, default color, and
// undoable rename and recolor (projects.md §4.3, §4.4).

import Foundation
import Observation
import TimeTrackingCore

/// The area sheet: Name, Client, and Color. A new area's client is chosen
/// in the Client popup (fixed when the project dialog asks for the area);
/// an existing area's client and the general area's name are fixed.
@Observable
final class AreaFormModel {
    enum Mode: Equatable {
        case create
        case edit(Area)
    }

    @ObservationIgnored let store: TimeStore
    @ObservationIgnored weak var undoManager: UndoManager?
    let mode: Mode
    /// The clients of the Client popup, alphabetically.
    let clients: [Client]
    /// The area's client; `nil` until one is chosen.
    var clientID: ClientID?
    /// The Client popup cannot change.
    let clientFixed: Bool
    var name: String
    var color: String
    private(set) var nameError: String?
    private(set) var lastError: String?

    init(store: TimeStore, mode: Mode, clients: [Client], client: ClientID?, clientFixed: Bool, color: String = "#4D94CC") {
        self.store = store
        self.mode = mode
        self.clients = clients.sorted { ($0.name.folded, $0.id) < ($1.name.folded, $1.id) }
        if case let .edit(area) = mode {
            self.clientID = area.clientID
            self.clientFixed = true
            self.name = area.name
            self.color = area.color
        } else {
            self.clientID = client
            self.clientFixed = clientFixed
            self.name = ""
            self.color = color
        }
    }

    /// A new area, in `client` if given (`fixed`: only there), with the
    /// default color prefilled.
    static func create(store: TimeStore, client: ClientID?, fixed: Bool = false) async -> AreaFormModel {
        let clients = await (try? store.clients(includeRetired: true)) ?? []
        return await AreaFormModel(
            store: store,
            mode: .create,
            clients: clients,
            client: client,
            clientFixed: fixed && client != nil,
            color: defaultColor(store: store)
        )
    }

    /// An existing area of `client`.
    static func edit(store: TimeStore, area: Area, client: Client) -> AreaFormModel {
        AreaFormModel(store: store, mode: .edit(area), clients: [client], client: area.clientID, clientFixed: true)
    }

    /// The chosen client's name (an area may not take it).
    var clientName: String {
        clients.first { $0.id == clientID }?.name ?? ""
    }

    /// `AreaColor.defaultColor(existing:)` over every live area.
    static func defaultColor(store: TimeStore) async -> String {
        let areas = await (try? store.areas(of: nil, includeRetired: true)) ?? []
        return AreaColor.defaultColor(existing: areas.compactMap(\.areaColor)).hex
    }

    var title: String {
        if case .create = mode {
            return "New Area"
        }
        return "Edit Area"
    }

    var confirmTitle: String {
        if case .create = mode {
            return "Create"
        }
        return "Save"
    }

    /// The general area's name cannot change.
    var nameEditable: Bool {
        if case let .edit(area) = mode {
            return !area.isGeneral
        }
        return true
    }

    /// "Named after the client" under the disabled field.
    var nameNote: String? {
        nameEditable ? nil : "Named after the client"
    }

    var canSubmit: Bool {
        clientID != nil && !name.trimmed.isEmpty && nameError == nil
    }

    /// Unique within the client and not the client's name.
    func validate() async {
        guard nameEditable, !name.trimmed.isEmpty, let clientID else {
            nameError = nil
            return
        }
        let excluded: AreaID? = if case let .edit(area) = mode {
            area.id
        } else {
            nil
        }
        let siblings = await (try? store.areas(of: clientID, includeRetired: true)) ?? []
        if name.folded == clientName.folded {
            nameError = "This name is used by the client's general area"
        } else if siblings.contains(where: { $0.id != excluded && $0.name.folded == name.folded }) {
            nameError = "An area with this name already exists for \(clientName)"
        } else {
            nameError = nil
        }
    }

    /// Create or Save; returns the area. Rename and recolor are undoable.
    func submit() async -> Area? {
        await validate()
        lastError = nil
        guard canSubmit else {
            return nil
        }
        do {
            switch mode {
            case .create:
                guard let clientID else {
                    return nil
                }
                return try await store.createArea(AreaDraft(clientID: clientID, name: name.trimmed, color: color))
            case let .edit(area):
                let newName = nameEditable && name.trimmed != area.name ? name.trimmed : nil
                let newColor = color.uppercased() != area.color ? color : nil
                guard newName != nil || newColor != nil else {
                    return area
                }
                try await store.updateArea(area.id, AreaChange(name: newName, color: newColor))
                undoManager?.registerUndo(withTarget: store) { store in
                    Task {
                        try? await store.updateArea(
                            area.id,
                            AreaChange(name: newName == nil ? nil : area.name, color: newColor == nil ? nil : area.color)
                        )
                    }
                }
                undoManager?.setActionName(newColor == nil ? "Rename Area" : "Recolor Area")
                return try await store.areas(of: area.clientID, includeRetired: true).first { $0.id == area.id }
            }
        } catch {
            lastError = UserMessage.logged(error, category: "Sections")
            return nil
        }
    }
}

extension AreaFormModel: Identifiable {
    var id: ObjectIdentifier {
        ObjectIdentifier(self)
    }
}
