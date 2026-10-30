// Siri's Start Timer App Shortcut: inference and project names
// (spec_ios.md §6.2, §6.3).

import Foundation
import Testing
import TimeTrackingCore

struct SiriTests {
    @Test("IOS-20 the Siri shortcut's answer \"Bugfixes\" infers the project; the same intent from a Shortcuts action assigns none")
    func inference() async throws {
        let fixture = try await AutomationTestStore(running: false)
        let siri = try await IntentActions.start(task: "Bugfixes", project: nil, inferProject: true, service: fixture.service)
        #expect(siri.value.project == "Noise paper")
        #expect(siri.dialog == "Started Bugfixes on Noise paper.")
        let action = try await IntentActions.start(task: "Bugfixes", project: nil, inferProject: false, service: fixture.service)
        #expect(action.value.project == nil)
        #expect(StartTimerIntent().inferProject == false)
        #expect(StartTimerIntent(inferProject: true).inferProject)
    }

    @Test("IOS-21 a project name resolves to its project; a name matching two asks which one by subtitle; none fails")
    func names() async throws {
        let fixture = try await AutomationTestStore(running: false)
        let rows = try await fixture.service.projects(state: .all)
        let noise = try ProjectEntityQuery.resolve("Noise paper", in: rows)
        #expect(noise.map(\.project.id) == [fixture.noisePaper.id])
        let started = try await IntentActions.start(task: nil, project: noise[0].project.id, inferProject: true, service: fixture.service)
        #expect(started.value.project == "Noise paper")

        let admins = try ProjectEntityQuery.resolve("Admin", in: rows).map(ProjectEntity.init)
        #expect(admins.count == 2)
        #expect(Set(admins.map(\.client)) == ["University", "Side business"])
        #expect(admins.contains { "\($0.client) · \($0.area)" == "University · Teaching" })
        #expect(throws: AutomationError.notFound("I couldn't find a project called Gardening.")) {
            try ProjectEntityQuery.resolve("Gardening", in: rows)
        }
    }
}
