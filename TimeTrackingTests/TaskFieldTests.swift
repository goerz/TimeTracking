// Autocompletion, the `@` trigger, the picker, and quick creation
// (spec_timer.md §2.2, §2.3; spec_projects.md §3, §5).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

@MainActor
struct TaskFieldTests {
    @Test("TM-8 three characters show at most 8 suggestions, the chip's project first; accepting sets task and project")
    func suggestions() async throws {
        let test = try await TestApp()
        let projects = try await test.projects(["Noise Model", "Other"])
        for index in 0 ..< 9 {
            let start = String(format: "07:%02d", index * 2)
            let end = String(format: "07:%02d", index * 2 + 1)
            try await test.entry("Clarify item \(index)", projects[1], from: start, to: end)
        }
        try await test.entry("Clarify noise model", projects[0], from: "06:00", to: "06:30")
        let field = test.app.miniTimer.taskField
        await field.userEdited("cla", chipProject: projects[0].id)
        #expect(field.suggestions.count == 8)
        #expect(field.suggestions.first?.task == "Clarify noise model")
        #expect(field.labels[projects[0].id]?.name == "Noise Model")
        #expect(field.isShowingSuggestions)
        // ↓ then Return accepts the second one.
        field.move(by: 1)
        let accepted = try #require(field.acceptSuggestion())
        await test.app.timer.accept(accepted)
        #expect(test.app.timer.taskText == "Clarify item 8")
        #expect(test.app.timer.draftProjectID == projects[1].id)
        #expect(!field.isShowingSuggestions)
    }

    @Test("TM-9 @noi opens the picker searching noi; Return assigns and removes @noi; Escape leaves it; a@b opens nothing")
    func atTrigger() async throws {
        let test = try await TestApp()
        let projects = try await test.projects(["Noise Model", "Website"])
        let field = test.app.miniTimer.taskField
        #expect(TaskFieldModel.trigger(in: "a@b") == nil)
        await field.userEdited("a@b", chipProject: nil)
        #expect(field.picker == nil)

        test.app.timer.taskText = "Clarify @noi"
        await field.userEdited("Clarify @noi", chipProject: nil)
        let picker = try #require(field.picker)
        #expect(picker.search == "noi")
        #expect(picker.taskMatching)
        #expect(picker.highlight == .project(projects[0].id))
        // Return in the field: the highlight is assigned and "@noi" removed.
        await test.app.taskFieldReturn(in: test.app.miniTimer).value
        #expect(field.picker == nil)
        #expect(test.app.timer.taskText == "Clarify")
        #expect(test.app.timer.draftProjectID == projects[0].id)
        // A click in the list does the same.
        test.app.timer.taskText = "Fix @web"
        await field.userEdited("Fix @web", chipProject: nil)
        await test.app.taskFieldPicked(.project(projects[1].id), in: test.app.miniTimer).value
        #expect(field.picker == nil)
        #expect(test.app.timer.taskText == "Fix")
        #expect(test.app.timer.draftProjectID == projects[1].id)

        // Escape closes the picker and leaves the text.
        await field.userEdited("@noi", chipProject: nil)
        #expect(field.picker != nil)
        #expect(field.escape(text: "@noi"))
        #expect(field.picker == nil)
        await field.userEdited("@noi ", chipProject: nil)
        #expect(field.picker == nil)
        // Deleting the @ and typing it again opens it again.
        await field.userEdited("noi", chipProject: nil)
        await field.userEdited("@", chipProject: nil)
        #expect(field.picker != nil)
    }

    @Test("TM-10 the picker search noise lists the project of Clarify noise model tracked within 90 days")
    func taskMatching() async throws {
        let test = try await TestApp()
        let projects = try await test.projects(["Paper", "Website"])
        try await test.entry("Clarify noise model", projects[0], from: "2024-02-20T09:00", to: "2024-02-20T10:00")
        test.app.openChipPicker(in: test.app.miniTimer)
        let picker = try #require(test.app.miniTimer.pickerModel)
        picker.search = "noise"
        await picker.reload()
        #expect(picker.content.groups.flatMap(\.rows).map(\.project.name) == ["Paper"])
        #expect(picker.placeholder == "Search projects and tasks")
    }

    @Test("TM-11 PP-17 Create Project from the picker opens the dialog named after the search; Create assigns the running entry or draft")
    func quickCreation() async throws {
        let test = try await TestApp()
        _ = try await test.projects(["Website"])
        // The draft.
        test.app.openChipPicker(in: test.app.miniTimer)
        let picker = try #require(test.app.miniTimer.pickerModel)
        picker.search = " noise "
        await picker.reload()
        #expect(picker.content.createName == "noise")
        try await test.app.choose(#require(picker.createFromSearch()), in: test.app.miniTimer)
        let dialog = try #require(test.app.miniTimer.dialogModel)
        #expect(dialog.name == "noise")
        await dialog.load()
        #expect(dialog.areaID != nil)
        let project = try #require(await dialog.submit())
        await test.app.dialogFinished(project, in: test.app.miniTimer)
        #expect(test.app.timer.draftProjectID == project.id)
        #expect(test.app.miniTimer.dialogModel == nil)
        // The running entry.
        await test.app.timer.start()
        await test.app.choose(.create("Second"), in: test.app.miniTimer)
        let next = try #require(test.app.miniTimer.dialogModel)
        await next.load()
        let created = try #require(await next.submit())
        await test.app.dialogFinished(created, in: test.app.miniTimer)
        #expect(try await test.store.runningEntry()?.projectID == created.id)
    }

    @Test("PP-16 the dialog rejects a name differing only in case or diacritics within the client")
    func dialogValidation() async throws {
        let test = try await TestApp()
        let projects = try await test.projects(["Résumé"], client: "Consulting")
        let dialog = ProjectDialogModel(store: test.store, mode: .create, name: "resume")
        await dialog.load(preferredArea: projects[0].areaID)
        #expect(dialog.nameError == "A project with this name already exists for Consulting")
        #expect(!dialog.canSubmit)
        dialog.name = "Resume 2"
        await dialog.validate()
        #expect(dialog.canSubmit)
    }

    @Test("A chip label keeps the names of a deleted project and area that an entry still references")
    func labelOfDeletedProject() async throws {
        let test = try await TestApp()
        let project = try await test.projects(["Noise Model"])[0]
        let entry = try await test.entry("Clarify noise model", project, from: "06:00", to: "06:30")
        try await test.store.delete([entry.id])
        try await test.store.deleteProject(project.id)
        try await test.store.deleteArea(project.areaID)
        let label = await ProjectLabel.load(project.id, from: test.store)
        #expect(label == ProjectLabel(name: "Noise Model", client: "University", area: "Research", color: label.color))
        #expect(await ProjectLabel.loadLive(project.id, from: test.store) == .noProject)
        #expect(await ProjectLabel.load(nil, from: test.store) == .noProject)
    }
}
