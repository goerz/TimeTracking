// Tests for DeviceEvent and DeviceEventStagingFile (spec_data_and_sync.md §6,
// spec_activity_tracking.md §6.2).

import Foundation
import Synchronization
import Testing
import TimeTrackingCore

/// Collects the batches an uploader receives.
private final class UploadRecorder: Sendable {
    private let batches = Mutex<[[DeviceEvent]]>([])
    let failing: Bool

    init(failing: Bool = false) {
        self.failing = failing
    }

    var received: [[DeviceEvent]] {
        batches.withLock { $0 }
    }

    func upload(_ events: [DeviceEvent]) throws {
        if failing {
            throw ActivityError.fileSystem("offline")
        }
        batches.withLock { $0.append(events) }
    }
}

struct ActivityDeviceEventTests {
    private static func event(_ milliseconds: Int64, sequence: Int = 0) -> DeviceEvent {
        DeviceEvent(
            deviceID: "phone-1",
            time: Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000),
            source: .ladder,
            label: "Mail",
            kind: "threshold",
            payload: #"{"minutes":3}"#,
            sequence: sequence
        )
    }

    @Test func theRecordNameIsDeviceMillisecondsAndSequence() {
        #expect(Self.event(1_730_000_000_123, sequence: 2).recordName == "phone-1-1730000000123-2")
    }

    @Test func eventsRoundTripThroughTheStagingFile() async throws {
        try await withTemporaryFolder { temporary in
            let recorder = UploadRecorder()
            let staging = DeviceEventStagingFile(folder: temporary.url) { try recorder.upload($0) }
            let events = [Self.event(1000), Self.event(1000, sequence: 1), Self.event(2500)]
            for event in events {
                try staging.append(event)
            }
            #expect(try staging.readAll() == events)
            try await staging.flush()
            #expect(recorder.received == [events])
            #expect(try staging.readAll().isEmpty)
            #expect(try Data(contentsOf: staging.fileURL).isEmpty)
            try await staging.flush()
            #expect(recorder.received.count == 1)
        }
    }

    @Test func aFailedUploadKeepsTheEvents() async throws {
        try await withTemporaryFolder { temporary in
            let recorder = UploadRecorder(failing: true)
            let staging = DeviceEventStagingFile(folder: temporary.url) { try recorder.upload($0) }
            try staging.append(Self.event(1000))
            await #expect(throws: ActivityError.fileSystem("offline")) {
                try await staging.flush()
            }
            #expect(try staging.readAll() == [Self.event(1000)])
        }
    }

    @Test func eventsAppendedDuringTheUploadSurviveTheTruncation() async throws {
        try await withTemporaryFolder { temporary in
            let folder = temporary.url
            let late = Self.event(9000)
            let staging = DeviceEventStagingFile(folder: folder) { _ in
                try DeviceEventStagingFile(folder: folder) { _ in }.append(late)
            }
            try staging.append(Self.event(1000))
            try ActivityFixture.append("not json\n", to: staging.fileURL)
            try await staging.flush()
            #expect(try staging.readAll() == [late])
        }
    }
}
