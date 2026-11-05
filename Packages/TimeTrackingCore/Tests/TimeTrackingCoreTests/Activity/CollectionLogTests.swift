// Tests for the collectors' shared log: the Focus filter, the automation
// intent, the Safari extension's reduction, the app's own lines, and the
// flush rules (ios.md §9.1, §9.3 to §9.7; activity_tracking.md §7.2).

import Foundation
import Testing
import TimeTrackingCore

struct CollectionLogTests {
    /// An enabled log over a staging file in a temporary folder.
    private struct Harness {
        let folder: TemporaryFolder
        let clock = ManualClock.fixture(in: ActivityFixture.newYork)
        let state: CollectionSharedState
        let staging: DeviceEventStagingFile
        let log: CollectionLog

        init(enabled: Bool = true) throws {
            self.folder = try TemporaryFolder()
            self.state = try CollectionSharedState(defaults: #require(UserDefaults(suiteName: "CollectionLogTests.\(UUID().uuidString)")))
            state.isEnabled = enabled
            self.staging = DeviceEventStagingFile(folder: folder.url)
            self.log = CollectionLog(state: state, sink: staging, deviceID: "phone", clock: clock, timeZone: ActivityFixture.newYork)
        }

        var lines: [String] {
            get throws {
                try staging.readAll().map { "\($0.source.rawValue) \($0.kind) \($0.label)" }
            }
        }
    }

    private static let rules: ExclusionRules = {
        var privacy = TrackerPrivacySettings()
        privacy.excludeDomains = ["bank.example"]
        privacy.privateDomains = ["mail.example"]
        return ExclusionRules(privacy: privacy, homeDirectory: "/Users/alex")
    }()

    @Test("IOS-29 a configured Focus appends on and off lines with its label without the app")
    func theFocusFilterLogsOnAndOff() throws {
        let harness = try Harness()
        // What the App Intents extension does: performed with the label at
        // the start, with the default parameters at the end.
        #expect(try harness.log.focusFilterPerformed(label: "Work", collect: true) == ["on"])
        harness.clock.advance(by: 3600)
        #expect(try harness.log.focusFilterPerformed(label: nil, collect: true) == ["off"])
        #expect(try harness.lines == ["focus on Work", "focus off Work"])
        let events = try harness.staging.readAll()
        #expect(events[1].time.timeIntervalSince(events[0].time) == 3600)
        #expect(events[0].payload == nil)
        #expect(harness.state.focusLabel == nil)
        #expect(harness.state.lastFocusEventAt == harness.clock.now)
    }

    @Test func switchingFocusEndsTheFirst() throws {
        let harness = try Harness()
        try harness.log.focusFilterPerformed(label: "Work", collect: true)
        try harness.log.focusFilterPerformed(label: "Work", collect: true)
        try harness.log.focusFilterPerformed(label: "Sleep", collect: false)
        try harness.log.focusFilterPerformed(label: "", collect: true)
        #expect(try harness.lines == ["focus on Work", "focus off Work", "focus on Sleep", "focus off Sleep"])
        #expect(try harness.staging.readAll()[2].payloadBool("collect", default: true) == false)
    }

    @Test func aSuspendingFocusSilencesSafariAndAutomations() throws {
        let harness = try Harness()
        try harness.log.focusFilterPerformed(label: "Sleep", collect: false)
        #expect(try !harness.log.logIntent(label: "Mail", kind: .appOpened))
        #expect(try !harness.log.logWeb(url: "https://example.com/a", at: nil, exclusions: .empty))
        #expect(try harness.log.logApp(foreground: true))
        try harness.log.focusFilterPerformed(label: nil, collect: true)
        #expect(try harness.log.logIntent(label: "Mail", kind: .appOpened))
        #expect(try harness.lines == ["focus on Sleep", "app foreground TimeTracking", "focus off Sleep", "intent appOpened Mail"])
    }

    @Test func nothingIsLoggedWithCollectionOff() throws {
        let harness = try Harness(enabled: false)
        #expect(try !harness.log.logIntent(label: "Home", kind: .arrived))
        #expect(try !harness.log.logApp(foreground: true))
        #expect(try harness.log.focusFilterPerformed(label: "Work", collect: true).isEmpty)
        #expect(try harness.lines.isEmpty)
        // The Focus state still follows, so the off of a later run is right.
        #expect(harness.state.focusLabel == "Work")
    }

    @Test func automationsLogTheirKind() throws {
        let harness = try Harness()
        for kind in ActivityEventKind.allCases {
            try harness.log.logIntent(label: "Label", kind: kind)
        }
        #expect(try harness.staging.readAll().map(\.kind) == [
            "appOpened", "appClosed", "arrived", "left", "chargerConnected", "chargerDisconnected", "custom",
        ])
    }

    @Test("IOS-30 the Safari handler drops exclude_domains, reduces private_domains, strips queries and fragments")
    func theWebReducerAppliesTheExclusions() {
        let rules = Self.rules
        #expect(WebEventReducer.label(for: "https://www.bank.example/account?id=7", exclusions: rules) == nil)
        #expect(WebEventReducer.label(for: "https://login.bank.example/", exclusions: rules) == nil)
        #expect(WebEventReducer.label(for: "https://mail.example/inbox/42#reply", exclusions: rules) == "mail.example")
        #expect(WebEventReducer.label(for: "https://github.com/owner/repo/pull/12?diff=split#top", exclusions: rules)
            == "github.com/owner/repo/pull/12")
        #expect(WebEventReducer.label(for: "https://www.example.com/", exclusions: rules) == "example.com")
        #expect(WebEventReducer.label(for: "http://localhost:8888/tree?token=secret", exclusions: rules) == "localhost:8888/tree")
        #expect(WebEventReducer.label(for: "about:blank", exclusions: rules) == nil)
        #expect(WebEventReducer.label(for: "file:///Users/alex/notes.txt", exclusions: rules) == nil)
    }

    @Test("TRK-8 the iOS web extension entry point writes no excluded domain")
    func theWebExtensionEntryPointKeepsNoExcludedDomain() throws {
        let harness = try Harness()
        let message: [String: Any] = ["url": "https://bank.example/login?user=alex", "time": 1_710_424_800_000.0]
        let parsed = try #require(WebEventReducer.message(message))
        #expect(try !harness.log.logWeb(url: parsed.url, at: parsed.time, exclusions: Self.rules))
        try harness.log.logWeb(url: "https://mail.example/inbox/42?q=x", at: nil, exclusions: Self.rules)
        let text = try String(contentsOf: harness.staging.fileURL, encoding: .utf8)
        #expect(!text.contains("bank.example"))
        #expect(!text.contains("inbox"))
        #expect(!text.contains("q=x"))
        #expect(try harness.lines == ["webext tab mail.example"])
        #expect(harness.state.lastWebEventAt != nil)
    }

    @Test func aWebMessageCarriesItsTime() throws {
        let harness = try Harness()
        let parsed = try #require(WebEventReducer.message(["url": "https://example.com/a", "time": 1_710_424_800_000.0]))
        try harness.log.logWeb(url: parsed.url, at: parsed.time, exclusions: .empty)
        #expect(try harness.staging.readAll().first?.time == Date(timeIntervalSince1970: 1_710_424_800))
        #expect(WebEventReducer.message(["time": 1.0]) == nil)
    }

    @Test("IOS-31 a flush is due only when the last one is more than 5 minutes old")
    func theFlushRule() {
        let now = ManualClock.fixtureNow()
        #expect(CollectionFlush.isDue(lastFlushAt: nil, now: now))
        #expect(!CollectionFlush.isDue(lastFlushAt: now.addingTimeInterval(-300), now: now))
        #expect(!CollectionFlush.isDue(lastFlushAt: now.addingTimeInterval(-60), now: now))
        #expect(CollectionFlush.isDue(lastFlushAt: now.addingTimeInterval(-301), now: now))
        #expect(CollectionFlush.isDue(lastFlushAt: now.addingTimeInterval(60), now: now))
    }

    @Test func theFlushStampsTheDeviceName() {
        let event = DeviceEvent(deviceID: "phone", time: .now, source: .app, label: "TimeTracking", kind: "foreground")
        #expect(CollectionFlush.stamped([event], deviceName: " iPhone ").first?.deviceName == "iPhone")
        #expect(CollectionFlush.stamped([event], deviceName: "").first?.deviceName == nil)
    }

    @Test func theSettingsCopyFollowsTheSharedFile() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let folders = folder.folders
        #expect(try !CollectionFlush.refreshSettingsCopy(from: folders.shared, to: folders.local))
        try ActivityFixture.write("[privacy]\nexclude_domains = [\"bank.example\"]\n", to: folders.settingsURL, modified: .now)
        #expect(try CollectionFlush.refreshSettingsCopy(from: folders.shared, to: folders.local))
        #expect(try !CollectionFlush.refreshSettingsCopy(from: folders.shared, to: folders.local))
        #expect(CollectionLog.exclusions(folder: folders.local).excludesDomain("www.bank.example"))
        #expect(!CollectionLog.exclusions(folder: folders.shared.appending(path: "missing")).excludesDomain("bank.example"))
    }

    @Test func theSetsAlwaysStartWithEverything() throws {
        let state = try CollectionSharedState(defaults: #require(UserDefaults(suiteName: "CollectionLogTests.\(UUID().uuidString)")))
        #expect(state.ladderSets == [.everything])
        state.ladderSets = [LadderSet(id: "mail", label: "Mail")]
        #expect(state.ladderSets.map(\.id) == ["everything", "mail"])
    }
}
