// What a failed change shows: UserMessage's sentences, never the library's
// error text (design.md §11).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

@MainActor
struct UserMessageTests {
    private struct Unexpected: Error {}

    @Test func sentences() {
        #expect(UserMessage.text(for: StoreError.unknownID) == "This was deleted, perhaps on another device.")
        #expect(UserMessage.text(for: StoreError.duplicateName) == "That name is already used.")
        #expect(UserMessage.text(for: Unexpected()) == UserMessage.couldNotSave)
    }

    @Test func editorShowsTheSentence() async throws {
        let test = try await TestApp()
        var ghost = try await test.entry("Notes", from: "09:10", to: "09:35")
        ghost.id = EntryID()
        let model = EntryEditorModel(store: test.store, clock: test.clock, entry: ghost)
        model.undoManager = test.undo
        await model.delete()
        #expect(model.message == "This was deleted, perhaps on another device.")
    }

    @Test func clientSheetShowsTheSentence() async throws {
        let test = try await TestApp()
        var (ghost, _) = try await test.store.createClient(name: "Consulting")
        ghost.id = ClientID()
        let form = ClientFormModel(store: test.store, mode: .rename(ghost))
        form.name = "Advisory"
        #expect(await form.submit() == nil)
        #expect(form.lastError == "This was deleted, perhaps on another device.")
    }
}
