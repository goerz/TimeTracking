// Tests that the App Group's `UserDefaults` layout stays readable: the keys,
// value types, and encodings that installed apps already hold
// (data_and_sync.md §1.6, ios.md §3.1, §9).

import Foundation
import Testing
import TimeTrackingCore

struct AppGroupDefaultsTests {
    private static func suite() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "AppGroupDefaultsTests." + UUID().uuidString))
    }

    private static let instant = Date(timeIntervalSince1970: 1_710_410_400)

    @Test("Device settings read and write JSON data under the key's name and the device id as text")
    func deviceSettings() throws {
        let defaults = try Self.suite()
        let id = DeviceID()
        defaults.set(Data("false".utf8), forKey: "pomodoro.sounds")
        defaults.set(Data("15".utf8), forKey: "idle.thresholdMinutes")
        defaults.set(id.rawValue, forKey: "deviceID")

        let settings = DeviceSettings(defaults: defaults)
        #expect(settings[.pomodoroSounds] == false)
        #expect(settings[.idleThresholdMinutes] == 15)
        #expect(settings.deviceID == id)

        settings[.idleThresholdMinutes] = 20
        #expect(defaults.data(forKey: "idle.thresholdMinutes") == Data("20".utf8))
    }

    @Test("Collection state reads and writes Booleans, text, dates, numbers, and JSON data under collection.* keys")
    func collectionState() throws {
        let defaults = try Self.suite()
        let named = LadderSet(id: "set-1", label: "Work")
        let ladder = LadderSetState(day: "2024-03-14", generation: 2, window: [1, 2, 4], countedStep: 2, countedAt: Self.instant)
        defaults.set(true, forKey: "collection.enabled")
        defaults.set("Work", forKey: "collection.focus.label")
        defaults.set(true, forKey: "collection.focus.suspends")
        defaults.set(Self.instant, forKey: "collection.lastWebEventAt")
        defaults.set(Self.instant + 1, forKey: "collection.lastFocusEventAt")
        defaults.set(Self.instant + 2, forKey: "collection.lastIntentEventAt")
        try defaults.set(JSONEncoder().encode([LadderSet.everything, named]), forKey: "collection.ladder.sets")
        defaults.set(240, forKey: "collection.ladder.eventCap")
        try defaults.set(JSONEncoder().encode(ladder), forKey: "collection.ladder.state.set-1")

        let state = CollectionSharedState(defaults: defaults)
        #expect(state.isEnabled)
        #expect(state.focusLabel == "Work")
        #expect(state.focusSuspendsCollection)
        #expect(state.lastWebEventAt == Self.instant)
        #expect(state.lastFocusEventAt == Self.instant + 1)
        #expect(state.lastIntentEventAt == Self.instant + 2)
        #expect(state.ladderSets == [.everything, named])
        #expect(state.eventCap == 240)
        #expect(state.ladderState(for: "set-1") == ladder)

        state.isEnabled = false
        state.eventCap = 120
        state.setLadderState(nil, for: "set-1")
        #expect(defaults.object(forKey: "collection.enabled") as? Bool == false)
        #expect(defaults.object(forKey: "collection.ladder.eventCap") as? Int == 120)
        #expect(defaults.object(forKey: "collection.ladder.state.set-1") == nil)
    }

    @Test("Widget state reads and writes the LiveState fields, times, push token, and setup flag under their keys")
    func widgetState() throws {
        let defaults = try Self.suite()
        let entry = EntryID()
        defaults.set(
            #"{"entryID":"\#(entry.rawValue)","projectID":null,"task":"Review","chainStart":"2024-03-14T10:00:00Z"}"#,
            forKey: "widget.liveState.running"
        )
        defaults.set(Self.instant, forKey: "widget.liveState.changedAt")
        defaults.set("{}", forKey: "widget.liveState.activity")
        defaults.set(true, forKey: "widget.liveState.present")
        defaults.set(Self.instant + 1, forKey: "widget.lastFetchAt")
        defaults.set(Self.instant + 2, forKey: "widget.lastAppWriteAt")
        defaults.set("00ff", forKey: "widget.pushToken")
        defaults.set(true, forKey: "widget.pushToken.present")
        defaults.set(true, forKey: "setupComplete")
        defaults.set(Self.instant + 3, forKey: "collection.lastFlushAt")

        let state = WidgetSharedState(defaults: defaults)
        let live = try #require(state.liveState)
        #expect(live.running?.entryID == entry)
        #expect(live.running?.task == "Review")
        #expect(live.running?.start == Self.instant)
        #expect(live.changedAt == Self.instant)
        #expect(live.activity.isEmpty)
        #expect(state.lastFetchAt == Self.instant + 1)
        #expect(state.lastAppWriteAt == Self.instant + 2)
        #expect(state.pushToken == .some("00ff"))
        #expect(state.setupComplete)
        #expect(state.lastFlushAt == Self.instant + 3)

        state.recordPushToken(Data([0xAB, 0x01]), widgetCount: 1)
        state.liveState = nil
        #expect(defaults.string(forKey: "widget.pushToken") == "ab01")
        #expect(defaults.object(forKey: "widget.pushToken.present") as? Bool == true)
        for key in ["widget.liveState.running", "widget.liveState.changedAt", "widget.liveState.activity", "widget.liveState.present"] {
            #expect(defaults.object(forKey: key) == nil)
        }
    }
}
