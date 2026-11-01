// ProjectDialogModel: the shared project dialog for creating and editing
// projects (spec_projects.md §3).

import Foundation
import Observation
import TimeTrackingCore

/// Name, client, and area of a new or edited project, with validation.
@Observable
final class ProjectDialogModel {
    enum Mode: Equatable {
        case create
        case edit(Project)
    }

    /// The area of the last project created this session (a default).
    static var lastCreatedArea: AreaID?

    /// A question before Save: moving a project with entries to another
    /// client (§3.3), or restoring into a retired area (§2.5).
    struct Confirmation: Equatable {
        var title: String
        var message: String
        var confirmTitle: String
    }

    @ObservationIgnored let store: TimeStore
    @ObservationIgnored weak var undoManager: UndoManager?
    /// The running undo of an edit (tests wait for it).
    @ObservationIgnored private(set) var pendingUndo: Task<Void, Never>?
    let mode: Mode

    var name: String
    private(set) var clients: [Client] = []
    private(set) var areas: [Area] = []
    private(set) var clientID: ClientID?
    var areaID: AreaID?
    var isArchived = false
    /// "A project with this name already exists for Consulting".
    private(set) var nameError: String?
    private(set) var lastError: String?
    /// Asked before Save; `submit(confirmed: true)` proceeds.
    var confirmation: Confirmation?

    init(store: TimeStore, mode: Mode, name: String = "") {
        self.store = store
        self.mode = mode
        if case let .edit(project) = mode {
            self.name = project.name
            self.areaID = project.areaID
            self.isArchived = project.isArchived
        } else {
            self.name = name.trimmed
        }
    }

    var title: String {
        mode == .create ? "New Project" : "Edit Project"
    }

    var confirmTitle: String {
        mode == .create ? "Create" : "Save"
    }

    /// Create or Save is enabled only for a valid name, client, and area.
    var canSubmit: Bool {
        !name.trimmed.isEmpty && nameError == nil && clientID != nil && areaID != nil
    }

    /// Loads clients and areas and applies the defaults of §3.2:
    /// `preferredArea`, else the last project created this session, else
    /// the first client alphabetically and its general area.
    func load(preferredArea: AreaID? = nil) async {
        do {
            clients = try await store.clients(includeRetired: true)
            let allAreas = try await store.areas(of: nil, includeRetired: true)
            let start = areaID ?? preferredArea ?? Self.lastCreatedArea
            if let area = allAreas.first(where: { $0.id == start }) {
                await select(client: area.clientID, area: area.id)
            } else if let client = clients.first {
                await select(client: client.id, area: nil)
            }
        } catch {
            lastError = UserMessage.logged(error, category: "Sections")
        }
    }

    /// The Client popup; the area resets to the client's general area.
    func select(client: ClientID, area: AreaID? = nil) async {
        clientID = client
        let current = areaID
        let list = await (try? store.areas(of: client, includeRetired: true)) ?? []
        areas = list.filter { !$0.isRetired || $0.id == current }
        areaID = area ?? areas.first(where: \.isGeneral)?.id ?? areas.first?.id
        await validate()
    }

    /// Checks the name against the client's projects (any state).
    func validate() async {
        guard let clientID, !name.trimmed.isEmpty else {
            nameError = nil
            return
        }
        let excluding: ProjectID? = if case let .edit(project) = mode {
            project.id
        } else {
            nil
        }
        let taken = await (try? store.projectNameIsTaken(name, client: clientID, excluding: excluding)) ?? false
        let clientName = clients.first { $0.id == clientID }?.name ?? ""
        nameError = taken ? "A project with this name already exists for \(clientName)" : nil
    }

    /// "New Client…" created a client (it persists if the dialog is
    /// canceled): select it and its general area.
    func clientCreated(_ client: Client, general: Area?) async {
        clients = await (try? store.clients(includeRetired: true)) ?? clients
        await select(client: client.id, area: general?.id)
    }

    /// "New Area…" created an area in the selected client.
    func areaCreated(_ area: Area) async {
        await select(client: area.clientID, area: area.id)
    }

    /// The selected client's name.
    var clientName: String {
        clients.first { $0.id == clientID }?.name ?? ""
    }

    /// Create or Save. Returns the project, or `nil` while a confirmation
    /// is pending or on failure.
    func submit(confirmed: Bool = false) async -> Project? {
        await validate()
        lastError = nil
        guard canSubmit, let areaID else {
            return nil
        }
        do {
            switch mode {
            case .create:
                let project = try await store.createProject(ProjectDraft(areaID: areaID, name: name.trimmed))
                Self.lastCreatedArea = areaID
                return project
            case let .edit(project):
                if !confirmed, let question = try await confirmationNeeded(for: project, areaID: areaID) {
                    confirmation = question
                    return nil
                }
                confirmation = nil
                try await save(project, areaID: areaID)
                return try await store.project(project.id)
            }
        } catch {
            lastError = UserMessage.logged(error, category: "Sections")
            return nil
        }
    }

    /// The question §3.3 or §2.5 asks before this edit, if any.
    private func confirmationNeeded(for project: Project, areaID: AreaID) async throws -> Confirmation? {
        let areas = try await store.areas(of: nil, includeRetired: true)
        let oldArea = areas.first { $0.id == project.areaID }
        let newArea = areas.first { $0.id == areaID }
        if let newArea, oldArea?.clientID != newArea.clientID {
            let rows = try await store.projects(filter: ProjectFilter(state: .all))
            let count = rows.first { $0.id == project.id }?.entryCount ?? 0
            if count > 0 {
                let client = clients.first { $0.id == newArea.clientID }?.name ?? ""
                let place = newArea.isGeneral ? client : "\(client) · \(newArea.name)"
                return Confirmation(
                    title: "Move “\(name.trimmed)” and its \(count) \(count == 1 ? "entry" : "entries") to \(place)?",
                    message: "Reports for past dates will show them there.",
                    confirmTitle: "Move"
                )
            }
        }
        if project.isArchived, !isArchived, let newArea, newArea.isRetired {
            return Confirmation(
                title: "Restore “\(name.trimmed)” and reactivate “\(newArea.name)”?",
                message: "The area “\(newArea.name)” is retired. Restoring the project makes it active again.",
                confirmTitle: "Restore"
            )
        }
        return nil
    }

    /// Writes the edit and registers its inverse for ⌘Z.
    private func save(_ project: Project, areaID: AreaID) async throws {
        try await store.updateProject(project.id, ProjectChange(name: name.trimmed, areaID: areaID))
        if isArchived != project.isArchived {
            if isArchived {
                try await store.archive(project.id)
            } else {
                try await store.restoreProject(project.id)
            }
        }
        undoManager?.registerUndo(withTarget: self) { model in
            let store = model.store
            model.pendingUndo = Task {
                try? await store.updateProject(project.id, ProjectChange(name: project.name, areaID: project.areaID))
                if project.isArchived {
                    try? await store.archive(project.id)
                } else {
                    try? await store.restoreProject(project.id)
                }
            }
        }
        undoManager?.setActionName("Edit Project")
    }
}

extension ProjectDialogModel: Identifiable {
    var id: ObjectIdentifier {
        ObjectIdentifier(self)
    }
}
