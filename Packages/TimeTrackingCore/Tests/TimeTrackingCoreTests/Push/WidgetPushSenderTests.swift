// When and to whom the Mac sends widget pushes (spec_data_and_sync.md §4.3, §9 item 35).

import CryptoKit
import Foundation
import Testing
import TimeTrackingCore

/// A Mac whose sync loop feeds a `WidgetPushSender`, another Mac, and the
/// iOS devices as `Device` records.
private struct PushRig {
    let net: Network
    let http = RecordingHTTP()
    let sender: WidgetPushSender

    init(hasKey: Bool = true) async throws {
        let net = try await Network(["Mac", "Other"])
        self.net = net
        let mac = net.peers[0]
        let credentials = hasKey
            ? APNsCredentials(keyID: "ABC123DEFG", teamID: "T", privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation)
            : nil
        let client = APNsClient(credentials: StaticAPNsCredentials(credentials), topic: "X.push-type.widgets", clock: net.clock, http: http)
        let sender = WidgetPushSender(store: mac.store, client: client, clock: net.clock)
        self.sender = sender
        await mac.sync.onLiveState { event in await sender.handle(event) }
        try await mac.store.registerDevice(name: "Mac", platform: .mac)
        let now = net.clock.now
        let devices: [Device] = [
            ("iPhone", DevicePlatform.iphone, "aa11"), ("iPad", .ipad, "bb22"), ("Old iPhone", .iphone, nil), ("Other Mac", .mac, "cc33"),
        ].map { name, platform, token in
            Device(id: DeviceID(), name: name, platform: platform, lastSeenAt: now, widgetPushToken: token, createdAt: now, modifiedAt: now)
        }
        let records = devices.map { device in
            SyncRecord(ref: SyncRecordRef(.device, device.id.rawValue), fields: [
                "name": .string(device.name), "platform": .string(device.platform.rawValue), "lastSeenAt": .date(now),
                "createdAt": .date(now), "modifiedAt": .date(now),
            ].merging(device.widgetPushToken.map { ["widgetPushToken": SyncValue.string($0)] } ?? [:]) { first, _ in first })
        }
        _ = try await net.server.transport(for: "seed").send(saving: records, deleting: [])
        try await net.converge()
    }

    var tokens: [String] {
        http.requests.compactMap { $0.url?.lastPathComponent }
    }
}

struct WidgetPushSenderTests {
    @Test("DATA-35 a confirmed save pushes to each iPhone and iPad token; fetched running changes push, activity elsewhere not")
    func sendingRules() async throws {
        let rig = try await PushRig()
        let (mac, other) = (rig.net.peers[0], rig.net.peers[1])
        let baseline = rig.http.requests.count

        _ = try await mac.store.start(projectID: nil, task: "Paper", at: rig.net.clock.now)
        try await mac.sync.sync()
        #expect(Array(rig.tokens.dropFirst(baseline)).sorted() == ["aa11", "bb22"])
        #expect(await rig.sender.status == .idle(lastSentAt: rig.net.clock.now))

        // Another device's start reaches the Mac with a changed running part.
        rig.net.clock.advance(by: 10)
        _ = try await other.store.start(projectID: nil, task: "Review", at: rig.net.clock.now)
        try await other.sync.sync()
        let beforeFetch = rig.http.requests.count
        try await mac.sync.sync()
        #expect(Array(rig.tokens.dropFirst(beforeFetch)).sorted() == ["aa11", "bb22"])

        // Another Mac's activity alone sends nothing.
        rig.net.clock.advance(by: 120)
        try await other.store.setLiveActivity(LiveStateTests.activity("Other Mac", at: rig.net.clock.now), for: DeviceID())
        try await other.sync.sync()
        let beforeActivity = rig.http.requests.count
        try await mac.sync.sync()
        #expect(rig.http.requests.count == beforeActivity)
    }

    @Test("DATA-35 activity-only pushes reach a token at most once per 60 seconds, the later one at the window's end")
    func activityWindow() async throws {
        let rig = try await PushRig()
        let mac = rig.net.peers[0]
        let own = mac.test.deviceID
        _ = try await mac.store.start(projectID: nil, task: "Paper", at: rig.net.clock.now)
        try await mac.sync.sync()
        let afterStart = rig.http.requests.count

        rig.net.clock.advance(by: 20)
        try await mac.store.setLiveActivity(LiveStateTests.activity("Mac", at: rig.net.clock.now), for: own)
        try await mac.sync.sync()
        #expect(rig.http.requests.count == afterStart)
        #expect(await rig.sender.nextDue == rig.net.clock.now + 40)

        rig.net.clock.advance(by: 20)
        try await mac.store.setLiveActivity(LiveStateTests.activity("Mac again", at: rig.net.clock.now), for: own)
        try await mac.sync.sync()
        await rig.sender.sendDue()
        #expect(rig.http.requests.count == afterStart)

        rig.net.clock.advance(by: 20)
        await rig.sender.sendDue()
        #expect(Array(rig.tokens.dropFirst(afterStart)).sorted() == ["aa11", "bb22"])
        #expect(await rig.sender.nextDue == nil)

        // A running change is not held back by the window.
        rig.net.clock.advance(by: 5)
        _ = try await mac.store.stop(at: rig.net.clock.now)
        try await mac.sync.sync()
        #expect(rig.http.requests.count == afterStart + 4)
    }

    @Test("DATA-35 without the APNs key the status is noKey and nothing is sent")
    func noKey() async throws {
        let rig = try await PushRig(hasKey: false)
        let mac = rig.net.peers[0]
        _ = try await mac.store.start(projectID: nil, task: "Paper", at: rig.net.clock.now)
        try await mac.sync.sync()
        #expect(rig.http.requests.isEmpty)
        #expect(await rig.sender.status == .noKey)
    }
}
