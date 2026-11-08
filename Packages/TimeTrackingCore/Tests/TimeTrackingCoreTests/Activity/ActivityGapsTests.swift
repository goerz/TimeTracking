// Tests of the Calendar's gaps between blocks of any device
// (calendar.md §3.1).

import Foundation
import Testing
import TimeTrackingCore

struct ActivityGapsTests {
    private static let day = "2026-10-27"

    private static func block(_ start: String, _ end: String, device: String = "MacBook") throws -> ActivityBlock {
        try ActivityFixture.block(day, start, end, [(ActivityFixture.app("Mail"), 60)], device: device)
    }

    private static func interval(_ start: String, _ end: String) throws -> DateInterval {
        try DateInterval(
            start: ActivityFixture.instant("\(day)T\(start):00-04:00"),
            end: ActivityFixture.instant("\(day)T\(end):00-04:00")
        )
    }

    @Test("a block of another device splits a gap, and an overlapping block closes it")
    func gapsAcrossDevices() throws {
        let blocks = try [
            Self.block("09:00", "10:00"),
            Self.block("10:30", "10:35", device: "iphone"),
            Self.block("11:00", "12:00"),
            Self.block("11:30", "12:30", device: "iphone"),
            Self.block("12:40", "13:00"),
            Self.block("14:00", "15:00"),
        ]
        let gaps = ActivityBlock.gaps(between: blocks.shuffled(), longerThan: 900)
        #expect(try gaps == [
            Self.interval("10:00", "10:30"),
            Self.interval("10:35", "11:00"),
            Self.interval("13:00", "14:00"),
        ])
    }

    @Test("a block inside an earlier, longer block leaves no gap")
    func containedBlock() throws {
        let blocks = try [Self.block("09:00", "12:00"), Self.block("09:30", "09:40", device: "ipad"), Self.block("12:10", "13:00")]
        #expect(ActivityBlock.gaps(between: blocks, longerThan: 900).isEmpty)
        #expect(ActivityBlock.gaps(between: [], longerThan: 900).isEmpty)
    }
}
