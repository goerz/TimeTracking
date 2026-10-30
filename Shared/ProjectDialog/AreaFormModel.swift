// AreaFormModel: the area sheet's model: name rules, default color, and
// undoable rename and recolor (spec_planner_projects.md §4.3, §4.4).

import Foundation
import Observation
import TimeTrackingCore

/// The area sheet: Name and Color; the general area's name is fixed.
@Observable
final class AreaFormModel {
    enum Mode: Equatable {
        case create(ClientID)
        case edit(Area)
    }

    @ObservationIgnored let store: TimeStore
    @ObservationIgnored weak var undoManager: UndoManager?
    let mode: Mode
    /// The client's name (an area may not take it).
    let clientName: String
    var name: String
    var color: String
    private(set) var nameError: String?
    private(set) var lastError: String?

    init(store: TimeStore, mode: Mode, clientName: String, color: String = "#4D94CC") {
        self.store = store
        self.mode = mode
        self.clientName = clientName
        if case let .edit(area) = mode {
            self.name = area.name
            self.color = area.color
        } else {
            self.name = ""
            self.color = color
        }
    }

    /// A new area of `client` with the default color prefilled.
    static func create(store: TimeStore, client: ClientID) async -> AreaFormModel {
        let name = await (try? store.clients(includeRetired: true).first { $0.id == client }?.name) ?? ""
        return await AreaFormModel(store: store, mode: .create(client), clientName: name, color: defaultColor(store: store))
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
        !name.trimmed.isEmpty && nameError == nil
    }

    private var clientID: ClientID {
        switch mode {
        case let .create(client): client
        case let .edit(area): area.clientID
        }
    }

    /// Unique within the client and not the client's name.
    func validate() async {
        guard nameEditable, !name.trimmed.isEmpty else {
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
            nameError = "An area cannot have the client's name"
        } else if siblings.contains(where: { $0.id != excluded && $0.name.folded == name.folded }) {
            nameError = "An area with this name already exists for \(clientName)"
        } else {
            nameError = nil
        }
    }

    /// Create or Save; returns the area. Rename and recolor are undoable.
    func submit() async -> Area? {
        await validate()
        guard canSubmit else {
            return nil
        }
        do {
            switch mode {
            case let .create(client):
                return try await store.createArea(AreaDraft(clientID: client, name: name.trimmed, color: color))
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
            lastError = error.localizedDescription
            return nil
        }
    }
}

extension AreaFormModel: Identifiable {
    var id: ObjectIdentifier {
        ObjectIdentifier(self)
    }
}
