// BlockSummaryText: the words of a block's summary, for the hover and the
// popover (activity_tracking.md §2.8; calendar.md §3.2).

import Foundation
import TimeTrackingCore

/// The lines of a block summary as text.
enum BlockSummaryText {
    /// "09:52 – 11:05 · 1h 13m".
    static func range(_ summary: ActivityBlockSummary, zone: TimeZone) -> String {
        let duration = ActivityText.duration(Int(summary.end.timeIntervalSince(summary.start)))
        return "\(CalendarText.range(summary.start, summary.end, zone: zone)) · \(duration)"
    }

    /// "Active 1h 06m · went idle · MacBook, iPhone"; `remote` reads "Other devices (Safari)".
    static func detail(_ summary: ActivityBlockSummary) -> String {
        var parts = ["Active \(ActivityText.duration(summary.activeSeconds))"]
        if let reason = summary.endReason, !summary.isOpen {
            parts.append(reason.phrase)
        }
        parts.append(summary.devices.map(ActivityDeviceName.display).joined(separator: ", "))
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "4m rebuilt from app usage history", or `nil` without.
    static func footer(_ summary: ActivityBlockSummary) -> String? {
        summary.reconstructedSeconds > 0 ? "\(ActivityText.duration(summary.reconstructedSeconds)) rebuilt from app usage history" : nil
    }

    /// The summary as one text, for the hover.
    static func text(_ summary: ActivityBlockSummary, zone: TimeZone = .current) -> String {
        var lines = [range(summary, zone: zone), detail(summary)]
        for group in summary.groups {
            let subtitle = group.subtitle.isEmpty ? "" : " (\(group.subtitle))"
            lines.append("\(group.name)\(subtitle) \(ActivityText.duration(group.seconds)) · \(Int((group.share * 100).rounded()))%")
            for line in group.lines {
                let device = line.otherDevice.map { "\(ActivityDeviceName.display($0)) " } ?? ""
                lines.append("    \(device)\(line.label) \(ActivityText.duration(line.seconds))")
            }
        }
        if summary.moreCount > 0 {
            lines.append("+\(summary.moreCount) more")
        }
        if !summary.background.isEmpty {
            lines.append("Background")
            lines += summary.background.map { "    \($0.label) \($0.workspaceName) \(ActivityText.duration($0.seconds))" }
        }
        if let footer = footer(summary) {
            lines.append(footer)
        }
        return lines.joined(separator: "\n")
    }
}
