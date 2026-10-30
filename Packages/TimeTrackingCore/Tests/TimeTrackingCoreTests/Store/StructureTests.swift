// Clients, areas, projects (spec_data_and_sync.md §1.1 to §1.3, §9 items 1 to 4, 6 to 8, 10, 11).

import Foundation
import Testing
import TimeTrackingCore

struct StructureTests {
    @Test("DATA-1 creating a client creates its general area; renaming the client renames it")
    func clientHasGeneralArea() async throws {
        let test = try await TestStore()
        let (client, area) = try await test.store.createClient(name: "  University ")
        #expect(client.name == "University")
        #expect(area.isGeneral)
        #expect(area.name == "University")
        #expect(area.sortOrder == 0)
        #expect(try await test.store.areas(of: client.id, includeRetired: true).count == 1)
        try await test.store.updateClient(client.id, name: "College")
        let areas = try await test.store.areas(of: client.id, includeRetired: true)
        #expect(areas.map(\.name) == ["College"])
    }

    @Test("DATA-2 renaming, retiring, reordering, or deleting a general area fails; its color can change")
    func generalAreaIsFixed() async throws {
        let store = try await TestStore().store
        let (_, general) = try await store.createClient(name: "Home")
        for change in [AreaChange(name: "Other"), AreaChange(retired: true), AreaChange(sortOrder: 3)] {
            await #expect(throws: StoreError.generalArea) {
                try await store.updateArea(general.id, change)
            }
        }
        await #expect(throws: StoreError.generalArea) {
            try await store.deleteArea(general.id)
        }
        try await store.updateArea(general.id, AreaChange(color: "#112233"))
        #expect(try await store.areas(of: general.clientID, includeRetired: true).first?.color == "#112233")
    }

    @Test("DATA-3 duplicate folded names fail for clients, areas, projects, and moves; another client is fine")
    func duplicateNames() async throws {
        let store = try await TestStore().store
        let (client, _) = try await store.createClient(name: "Émile")
        await #expect(throws: StoreError.duplicateName) {
            try await store.createClient(name: "emile")
        }
        let area = try await store.createArea(AreaDraft(clientID: client.id, name: "Research"))
        await #expect(throws: StoreError.duplicateName) {
            try await store.createArea(AreaDraft(clientID: client.id, name: "RESEARCH"))
        }
        await #expect(throws: StoreError.duplicateName) {
            try await store.createArea(AreaDraft(clientID: client.id, name: "Emile"))
        }
        let teaching = try await store.createArea(AreaDraft(clientID: client.id, name: "Teaching"))
        _ = try await store.createProject(ProjectDraft(areaID: area.id, name: "Noise paper"))
        await #expect(throws: StoreError.duplicateName) {
            try await store.createProject(ProjectDraft(areaID: teaching.id, name: "noise PAPER"))
        }
        let (other, otherGeneral) = try await store.createClient(name: "Other")
        let elsewhere = try await store.createProject(ProjectDraft(areaID: otherGeneral.id, name: "Noise Paper"))
        #expect(elsewhere.name == "Noise Paper")
        await #expect(throws: StoreError.duplicateName) {
            try await store.updateProject(elsewhere.id, ProjectChange(areaID: teaching.id))
        }
        #expect(other.name == "Other")
    }

    @Test("DATA-4 deleting a client fails while it has another area or a live project, else tombstones it with its general area")
    func deleteClient() async throws {
        let store = try await TestStore().store
        let (client, general) = try await store.createClient(name: "Client")
        let area = try await store.createArea(AreaDraft(clientID: client.id, name: "Area"))
        await #expect(throws: StoreError.referenced) {
            try await store.deleteClient(client.id)
        }
        try await store.deleteArea(area.id)
        let project = try await store.createProject(ProjectDraft(areaID: general.id, name: "P"))
        await #expect(throws: StoreError.referenced) {
            try await store.deleteClient(client.id)
        }
        try await store.deleteProject(project.id)
        try await store.deleteClient(client.id)
        #expect(try await store.clients(includeRetired: true).isEmpty)
        #expect(try await store.areas(of: client.id, includeRetired: true).isEmpty)
        let data = try await store.exportDocument(includeDeleted: true)
        let document = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let areas = try #require(document?["areas"] as? [[String: Any]])
        #expect(areas.filter { $0["deletedAt"] != nil }.count == 2)
    }

    @Test("DATA-6 projectArchived, areaRetired, activeProjects; restoring a project un-retires its area")
    func archivedAndRetired() async throws {
        let test = try await TestStore()
        let store = test.store
        let made = try await test.structure(projects: ["P"])
        let area = made.area
        let project = made.projects[0]
        await #expect(throws: StoreError.activeProjects) {
            try await store.updateArea(area.id, AreaChange(retired: true))
        }
        try await store.archive(project.id)
        await #expect(throws: StoreError.projectArchived) {
            try await store.start(projectID: project.id, task: "x", at: test.clock.now)
        }
        try await store.updateArea(area.id, AreaChange(retired: true))
        await #expect(throws: StoreError.areaRetired) {
            try await store.createProject(ProjectDraft(areaID: area.id, name: "New"))
        }
        try await store.restoreProject(project.id)
        let restored = try await store.areas(of: area.clientID, includeRetired: true).first { $0.id == area.id }
        #expect(restored?.isRetired == false)
        #expect(try await store.project(project.id)?.isArchived == false)
    }

    @Test("DATA-7 archiving keeps entries, hides the project from the tree and autocompletion, and retires an idle client")
    func archiving() async throws {
        let test = try await TestStore()
        let store = test.store
        let made = try await test.structure(projects: ["P"])
        let projects = made.projects
        let client = made.client
        let project = projects[0]
        _ = try await store.create(EntryDraft(
            projectID: project.id,
            task: "Write intro",
            start: test.date("2024-03-14T08:00"),
            end: test.date("2024-03-14T09:00")
        ))
        #expect(try await store.distinctTasks(projectID: project.id, prefix: "wr", limit: 5).map(\.task) == ["Write intro"])
        try await store.archive(project.id)
        #expect(try await store.entries(on: TrackingDay(year: 2024, month: 3, day: 14)).count == 1)
        #expect(try await store.distinctTasks(projectID: project.id, prefix: "wr", limit: 5).isEmpty)
        let tree = try await store.projectTree(includeArchived: false)
        #expect(!tree.flatMap(\.areas).flatMap(\.projects).contains { $0.id == project.id })
        #expect(try await store.projectTree(includeArchived: true).flatMap(\.areas).flatMap(\.projects).contains { $0.id == project.id })
        #expect(try await store.clients(includeRetired: false).isEmpty)
        #expect(try await store.clients(includeRetired: true).first { $0.id == client.id }?.isRetired == true)
    }

    @Test("DATA-8 clients are alphabetical by folded name: alpha, Beta, Émile, zeta")
    func clientOrder() async throws {
        let store = try await TestStore().store
        for name in ["zeta", "Émile", "Beta", "alpha"] {
            _ = try await store.createClient(name: name)
        }
        #expect(try await store.clients(includeRetired: true).map(\.name) == ["alpha", "Beta", "Émile", "zeta"])
    }

    @Test("DATA-10 colors are stored uppercase; malformed colors fail with invalidColor")
    func colors() async throws {
        let store = try await TestStore().store
        let (client, _) = try await store.createClient(name: "C")
        let area = try await store.createArea(AreaDraft(clientID: client.id, name: "A", color: "#2e8bc0"))
        #expect(area.color == "#2E8BC0")
        for bad in ["2E8BC0", "#2E8BC", "blue"] {
            await #expect(throws: StoreError.invalidColor) {
                try await store.createArea(AreaDraft(clientID: client.id, name: "B", color: bad))
            }
        }
    }

    @Test("DATA-11 the default color is the midpoint of the largest hue gap at S 0.65, B 0.80")
    func defaultColor() throws {
        func color(hue: Double) -> AreaColor {
            AreaColor(hue: hue, saturation: 0.65, brightness: 0.80)
        }
        #expect(AreaColor.defaultHue(existing: []) == 210)
        #expect(AreaColor.defaultHue(existing: [color(hue: 0), color(hue: 120)]) == 240)
        #expect(AreaColor.defaultHue(existing: [0, 90, 180, 270].map(color)) == 45)
        let gray = try AreaColor("#808080")
        let pale = AreaColor(hue: 90, saturation: 0.05, brightness: 0.9)
        #expect(AreaColor.defaultHue(existing: [color(hue: 0), color(hue: 120), gray, pale]) == 240)
        let hsb = AreaColor.defaultColor(existing: []).hsb
        #expect(abs(hsb.hue - 210) < 1)
        #expect(abs(hsb.saturation - 0.65) < 0.01)
        #expect(abs(hsb.brightness - 0.80) < 0.01)
    }

    @Test func colorDerivations() throws {
        #expect(try AreaColor("#FFFF00").textColor == .black)
        #expect(try AreaColor("#1A237E").textColor == .white)
        let base = try AreaColor("#2E8BC0")
        #expect(base.lightnessStep(0) == base)
        #expect(base.lightnessStep(6) == base)
        #expect(base.lightnessStep(1).relativeLuminance > base.relativeLuminance)
        #expect(base.lightnessStep(2).relativeLuminance < base.relativeLuminance)
        #expect(AreaColor.isRepeatedStep(6))
    }
}
