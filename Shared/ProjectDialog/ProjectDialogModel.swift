// ProjectDialogModel: the shared project dialog for creating and editing
// projects (spec_planner_projects.md §3).

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

    @ObservationIgnored let store: TimeStore
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
            lastError = error.localizedDescription
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

    /// "New Client…": the client persists even if the dialog is canceled.
    func createClient(name: String) async {
        do {
            let (client, general) = try await store.createClient(name: name, generalAreaColor: nil)
            clients = try await store.clients(includeRetired: true)
            await select(client: client.id, area: general.id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// "New Area…" in the selected client.
    func createArea(name: String, color: String?) async {
        guard let clientID else {
            return
        }
        do {
            let area = try await store.createArea(AreaDraft(clientID: clientID, name: name, color: color))
            await select(client: clientID, area: area.id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Create or Save. Returns the project.
    func submit() async -> Project? {
        await validate()
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
                try await store.updateProject(project.id, ProjectChange(name: name.trimmed, areaID: areaID))
                if isArchived != project.isArchived {
                    if isArchived {
                        try await store.archive(project.id)
                    } else {
                        try await store.restoreProject(project.id)
                    }
                }
                return try await store.project(project.id)
            }
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
}
