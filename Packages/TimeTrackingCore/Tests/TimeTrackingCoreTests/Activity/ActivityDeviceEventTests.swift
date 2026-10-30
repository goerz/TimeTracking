// Tests for DeviceEvent and DeviceEventStagingFile (spec_data_and_sync.md §6,
// spec_activity_tracking.md §6.2, spec_ios.md §9.1, §9.6).

import CloudKit
import Foundation
import Synchronization
import Testing
import TimeTrackingCore

/// Collects the batches an uploader receives.
final class UploadRecorder: Sendable {
    private let batches = Mutex<[[DeviceEvent]]>([])
    private let failure = Mutex<ActivityError?>(nil)

    init(failing: Bool = false) {
        if failing {
            failure.withLock { $0 = .fileSystem("offline") }
        }
    }

    var received: [[DeviceEvent]] {
        batches.withLock { $0 }
    }

    func setFailing(_ failing: Bool) {
        failure.withLock { $0 = failing ? .fileSystem("offline") : nil }
    }

    func upload(_ events: [DeviceEvent]) throws {
        if let error = failure.withLock({ $0 }) {
            throw error
        }
        batches.withLock { $0.append(events) }
    }
}

struct ActivityDeviceEventTests {
    private static func event(_ milliseconds: Int64, label: String = "Mail") -> DeviceEvent {
        DeviceEvent(
            deviceID: "phone-1",
            time: Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000),
            source: .ladder,
            label: label,
            kind: "minute",
            payload: #"{"n":3}"#
        )
    }

    private static func numbered(_ event: DeviceEvent, _ sequence: Int) -> DeviceEvent {
        var result = event
        result.sequence = sequence
        return result
    }

    @Test func theRecordNameIsDeviceMillisecondsAndSequence() {
        #expect(Self.numbered(Self.event(1_730_000_000_123), 2).recordName == "phone-1-1730000000123-2")
    }

    @Test func eachAppendGetsTheNextSequence() async throws {
        try await withTemporaryFolder { temporary in
            let recorder = UploadRecorder()
            let staging = DeviceEventStagingFile(folder: temporary.url) { try recorder.upload($0) }
            let events = [Self.event(1000), Self.event(1000), Self.event(2500)]
            for event in events {
                try staging.append(event)
            }
            let expected = events.enumerated().map { Self.numbered($0.element, $0.offset + 1) }
            #expect(try staging.readAll() == expected)
            #expect(Set(expected.map(\.recordName)).count == 3)
            try await staging.flush()
            #expect(recorder.received == [expected])
            #expect(try staging.readAll().isEmpty)
            #expect(try Data(contentsOf: staging.fileURL).isEmpty)
            #expect(try staging.lastFlushedSequence() == 3)
            try await staging.flush()
            #expect(recorder.received.count == 1)
            // Numbering continues after a flush, so record names never repeat.
            try staging.append(Self.event(3000))
            #expect(try staging.readAll().map(\.sequence) == [4])
        }
    }

    @Test func theOffsetAndDeviceNameRoundTrip() throws {
        var event = Self.event(1000)
        event.utcOffset = -14_400
        event.deviceName = "iPhone"
        let decoded = try JSONDecoder().decode(DeviceEvent.self, from: JSONEncoder().encode(event))
        #expect(decoded == event)
        #expect(decoded.payloadInt("n") == 3)
        let record = CloudKitDeviceEvents.record(event)
        #expect(record.recordID.zoneID.zoneName == "ActivityEvents")
        #expect(record.recordID.recordName == event.recordName)
        #expect(CloudKitDeviceEvents.event(record) == event)
    }

    @Test("IOS-27 lastFlushedSeq advances only after the upload is acknowledged")
    func aFailedUploadKeepsTheEvents() async throws {
        try await withTemporaryFolder { temporary in
            let recorder = UploadRecorder(failing: true)
            let staging = DeviceEventStagingFile(folder: temporary.url) { try recorder.upload($0) }
            try staging.append(Self.event(1000))
            await #expect(throws: ActivityError.fileSystem("offline")) {
                try await staging.flush()
            }
            #expect(try staging.lastFlushedSequence() == 0)
            #expect(try staging.readAll() == [Self.numbered(Self.event(1000), 1)])
            recorder.setFailing(false)
            try await staging.flush()
            #expect(try staging.lastFlushedSequence() == 1)
            #expect(recorder.received == [[Self.numbered(Self.event(1000), 1)]])
        }
    }

    @Test("IOS-27 a flush interrupted after the acknowledgement does not upload again")
    func anAcknowledgedBatchIsNotResent() async throws {
        try await withTemporaryFolder { temporary in
            let staging = DeviceEventStagingFile(folder: temporary.url) { _ in }
            try staging.append(Self.event(1000))
            try staging.append(Self.event(2000))
            let lines = try Data(contentsOf: staging.fileURL)
            try await staging.flush()
            // A crash between the acknowledgement and the truncation leaves the lines.
            try lines.write(to: staging.fileURL)
            try staging.append(Self.event(3000))
            let recorder = UploadRecorder()
            let resumed = DeviceEventStagingFile(folder: temporary.url) { try recorder.upload($0) }
            try await resumed.flush()
            #expect(recorder.received.map { $0.map(\.sequence) } == [[3]])
            #expect(try Data(contentsOf: staging.fileURL).isEmpty)
        }
    }

    @Test("IOS-27 concurrent appends from two processes never interleave lines")
    func concurrentAppendsStayWholeLines() async throws {
        try await withTemporaryFolder { temporary in
            let folder = temporary.url
            // Each writer opens the file itself, as the app and an extension do;
            // flock serializes separate open file descriptions like separate processes.
            let long = String(repeating: "x", count: 5000)
            try await withThrowingTaskGroup(of: Void.self) { group in
                for writer in 0 ..< 2 {
                    group.addTask {
                        let staging = DeviceEventStagingFile(folder: folder)
                        for index in 0 ..< 100 {
                            try staging.append(Self.event(Int64(index), label: "\(writer)-\(long)"))
                        }
                    }
                }
                try await group.waitForAll()
            }
            let staging = DeviceEventStagingFile(folder: folder)
            let text = try String(contentsOf: staging.fileURL, encoding: .utf8)
            let lines = text.split(separator: "\n")
            #expect(lines.count == 200)
            let decoded = try lines.map { try JSONDecoder().decode(DeviceEvent.self, from: Data($0.utf8)) }
            #expect(decoded.map(\.sequence) == Array(1 ... 200))
            #expect(decoded.filter { $0.label.hasPrefix("0-") }.count == 100)
        }
    }

    @Test func eventsAppendedDuringTheUploadSurviveTheTruncation() async throws {
        try await withTemporaryFolder { temporary in
            let folder = temporary.url
            let staging = DeviceEventStagingFile(folder: folder) { _ in
                try DeviceEventStagingFile(folder: folder).append(Self.event(9000))
            }
            try staging.append(Self.event(1000))
            try ActivityFixture.append("not json\n", to: staging.fileURL)
            try await staging.flush()
            #expect(try staging.readAll() == [Self.numbered(Self.event(9000), 2)])
        }
    }

    @Test func anExtensionCannotFlush() async throws {
        try await withTemporaryFolder { temporary in
            let staging = DeviceEventStagingFile(folder: temporary.url)
            try staging.append(Self.event(1000))
            await #expect(throws: ActivityError.self) {
                try await staging.flush()
            }
            #expect(try staging.readAll().count == 1)
        }
    }

    @Test func theInMemoryServerFeedsTheSourceOnce() async throws {
        let server = InMemoryDeviceEventServer()
        try await server.upload([Self.numbered(Self.event(1000), 1), Self.numbered(Self.event(2000), 2)])
        let source = server.source
        let (first, token) = try await source.events(since: nil)
        #expect(first.map(\.sequence) == [1, 2])
        try await server.upload([Self.numbered(Self.event(2000), 2), Self.numbered(Self.event(3000), 3)])
        let (second, next) = try await source.events(since: token)
        #expect(second.map(\.sequence) == [2, 3])
        #expect(try await source.events(since: next).0.isEmpty)
        try await source.purge(before: Date(timeIntervalSince1970: 2.5))
        #expect(await server.all.map(\.sequence) == [3])
    }
}
