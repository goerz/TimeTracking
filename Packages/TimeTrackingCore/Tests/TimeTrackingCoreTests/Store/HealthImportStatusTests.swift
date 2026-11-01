// Tests of the import status the Calendar settings show
// (spec_calendar.md §6 and PC-25, spec_data_and_sync.md §1.9).

import Foundation
import Testing
import TimeTrackingCore

struct HealthImportStatusTests {
    @Test("PC-25 the Apple Health status line: never imported, waiting for a kind, a kind without periods, imported; the status syncs")
    func summary() async throws {
        let net = try await Network()
        let (phone, mac) = (net.peers[0], net.peers[1])
        let test = phone.test
        let now = test.clock.now
        #expect(HealthImportStatus.summary(nil, shown: [], found: []) == nil)
        #expect(HealthImportStatus.summary(nil, shown: [.sleep], found: []) == .never)
        // The phone read sleep only; workouts were turned on since.
        let status = HealthImportStatus(device: "Phone", date: now, kinds: [.sleep])
        try await phone.store.set(.calendarHealthImport, status)
        try await phone.store.replaceHealthPeriods(
            .sleep,
            from: test.date("2024-03-10T00:00"),
            with: [DateInterval(start: test.date("2024-03-13T23:00"), end: test.date("2024-03-14T06:30"))]
        )
        try await net.converge()
        let synced = try await mac.store.value(.calendarHealthImport)
        #expect(synced == status)
        let found = try await mac.store.healthKinds()
        #expect(found == [.sleep])
        #expect(HealthImportStatus.summary(synced, shown: [.sleep, .workout], found: found) == .waiting(device: "Phone", kinds: [.workout]))
        #expect(HealthImportStatus.summary(synced, shown: [.sleep], found: found) == .imported(device: "Phone", date: status.date))
        // Both read, but no workouts in Health (or access denied).
        let both = HealthImportStatus(device: "Phone", date: now, kinds: [.workout, .sleep])
        #expect(both.kinds == [.sleep, .workout])
        #expect(
            HealthImportStatus.summary(both, shown: [.sleep, .workout], found: found)
                == .empty(device: "Phone", date: both.date, kinds: [.workout])
        )
        // A rewrite within the hour is skipped unless the kinds differ.
        #expect(both.replaces(nil))
        #expect(both.replaces(status))
        #expect(!HealthImportStatus(device: "Phone", date: now + 600, kinds: [.sleep]).replaces(status))
        #expect(HealthImportStatus(device: "Phone", date: now + 3600, kinds: [.sleep]).replaces(status))
        #expect(HealthImportStatus(device: "Other", date: now, kinds: [.sleep]).replaces(status))
    }
}
