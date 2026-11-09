// ActivityBlockSummary: what hovering a block shows, computed from the one
// block on read (activity_tracking.md §2.8; calendar.md §3.2).

public import Foundation

/// A block's summary: the header, foreground items grouped by workspace,
/// background items, and the footer.
///
/// `.summary` keeps the hover's limits (`summary_lines` item lines,
/// workspaces under `summary_min_share` folded, three background items);
/// `.everything` is the popover's list of every item.
public struct ActivityBlockSummary: Sendable, Hashable {
    public enum Extent: Sendable, Hashable {
        case summary
        case everything
    }

    /// One item line: its label, the device when it is not the block's
    /// main device, and its seconds.
    public struct Line: Sendable, Hashable {
        public var label: String
        /// Set when the item ran on another device than the block's main one.
        public var otherDevice: String?
        public var seconds: Int
    }

    /// The items of one workspace.
    public struct Group: Sendable, Hashable {
        /// The workspace as stored, a full path or name.
        public var workspace: String
        /// Its last component, as shown.
        public var name: String
        /// What stands beside the name: the full path when it differs, or
        /// "Screen Time set"; empty otherwise.
        public var subtitle: String
        public var seconds: Int
        /// The share of the block's active time, 0 to 1.
        public var share: Double
        public var lines: [Line]
    }

    /// One background item: its label, its workspace's name, and its seconds.
    public struct BackgroundLine: Sendable, Hashable {
        public var label: String
        public var workspaceName: String
        public var seconds: Int
    }

    public var start: Date
    public var end: Date
    public var activeSeconds: Int
    public var endReason: ActivityEndReason?
    public var isOpen: Bool
    /// The devices that contributed, the most time first; the first is the main one.
    public var devices: [String]
    public var groups: [Group]
    /// The item lines left out by the limits.
    public var moreCount: Int
    public var background: [BackgroundLine]
    public var reconstructedSeconds: Int

    /// The background items a hover lists at most.
    public static let backgroundLimit = 3

    public init(block: ActivityBlock, settings: TrackerSettings, extent: Extent = .summary) {
        self.start = block.start
        self.end = block.end
        self.activeSeconds = block.activeSeconds
        self.endReason = block.endReason
        self.isOpen = block.isOpen
        self.reconstructedSeconds = block.reconstructedSeconds
        let devices = block.devices.map(\.name)
        self.devices = devices
        let mainDevice = devices.first
        let active = max(block.activeSeconds, 1)

        var groups = Self.makeGroups(of: block.foreground, mainDevice: mainDevice, active: active)
        var shown = 0
        var hidden = 0
        if extent == .summary {
            groups = groups.compactMap { group in
                guard group.share >= settings.blocks.summaryMinShare, shown < settings.blocks.summaryLines else {
                    hidden += group.lines.count
                    return nil
                }
                var kept = group
                kept.lines = Array(group.lines.prefix(settings.blocks.summaryLines - shown))
                shown += kept.lines.count
                hidden += group.lines.count - kept.lines.count
                return kept
            }
        }
        self.groups = groups
        self.moreCount = hidden

        let background = Self.merged(block.background.map { item in
            BackgroundLine(
                label: Self.backgroundLabel(item.item, jobCommands: settings.terminal.jobCommands),
                workspaceName: item.item.workspaceName,
                seconds: item.seconds
            )
        })
        .enumerated()
        .sorted { $0.element.seconds == $1.element.seconds ? $0.offset < $1.offset : $0.element.seconds > $1.element.seconds }
        .map(\.element)
        self.background = extent == .summary ? Array(background.prefix(Self.backgroundLimit)) : background
    }

    /// The groups of the foreground items, the largest first; within a
    /// group the lines keep the block's order, which is the order of their
    /// time, and lines that read the same are one.
    private static func makeGroups(of items: [ActivityBlockItem], mainDevice: String?, active: Int) -> [Group] {
        var order: [String] = []
        var byWorkspace: [String: [ActivityBlockItem]] = [:]
        for item in items {
            let workspace = item.item.workspace.isEmpty ? item.item.appName : item.item.workspace
            if byWorkspace[workspace] == nil {
                order.append(workspace)
            }
            byWorkspace[workspace, default: []].append(item)
        }
        let groups = order.map { workspace -> Group in
            let members = byWorkspace[workspace] ?? []
            let seconds = members.reduce(0) { $0 + $1.seconds }
            let name = ActivityItem.workspaceName(workspace)
            let isScreenTime = members.allSatisfy(\.item.isScreenTime)
            return Group(
                workspace: workspace,
                name: name,
                subtitle: isScreenTime ? "Screen Time set" : (workspace == name ? "" : workspace),
                seconds: seconds,
                share: Double(seconds) / Double(active),
                lines: merged(members.map { member in
                    Line(
                        label: member.item.label,
                        otherDevice: member.device == mainDevice ? nil : member.device,
                        seconds: member.seconds
                    )
                })
            )
        }
        return groups.enumerated()
            .sorted { $0.element.seconds == $1.element.seconds ? $0.offset < $1.offset : $0.element.seconds > $1.element.seconds }
            .map(\.element)
    }

    /// Lines that read the same as one line with their seconds added, where
    /// the first of them was: Items that differ only in what the label
    /// leaves out, such as a viewer's page in its window title.
    private static func merged<L: MergeableLine>(_ lines: [L]) -> [L] {
        var result: [L] = []
        var index: [L.Key: Int] = [:]
        for line in lines {
            if let position = index[line.key] {
                result[position].seconds += line.seconds
            } else {
                index[line.key] = result.count
                result.append(line)
            }
        }
        return result
    }

    /// A background item's label: its app and its command for a job of
    /// `job_commands`, else its session ("tmux · make test", "Claude Code · refactor-parser").
    public static func backgroundLabel(_ item: ActivityItem, jobCommands: [String]) -> String {
        let program = item.command.split(separator: " ").first.map { String($0.split(separator: "/").last ?? $0) } ?? ""
        let detail = jobCommands.contains(program) ? item.command : item.session
        return detail.isEmpty ? item.appName : "\(item.appName) · \(detail)"
    }
}

/// A summary line that merges with another that reads the same.
private protocol MergeableLine {
    associatedtype Key: Hashable

    var key: Key { get }
    var seconds: Int { get set }
}

extension ActivityBlockSummary.Line: MergeableLine {
    fileprivate var key: [String?] {
        [label, otherDevice]
    }
}

extension ActivityBlockSummary.BackgroundLine: MergeableLine {
    fileprivate var key: [String] {
        [label, workspaceName]
    }
}
