// ActivityBlockItem: an Item of a block with its device and seconds
// (activity_tracking.md §2.2, §4.2).

/// An Item with the name of the device it ran on and the seconds it earned.
public struct ActivityBlockItem: Sendable, Hashable {
    /// The device's name, or `remote` for synced Safari history of no known device.
    public var device: String
    public var seconds: Int
    public var item: ActivityItem

    public init(device: String, seconds: Int, item: ActivityItem) {
        self.device = device
        self.seconds = seconds
        self.item = item
    }

    /// The device name of synced Safari history no device could be found for (§6.1).
    public static let remoteDevice = "remote"

    /// Equal Items on one device as one BlockItem with their seconds
    /// added, in the order of their first appearance (§2.2).
    public static func merged(_ items: [Self]) -> [Self] {
        var result: [Self] = []
        var index: [Key: Int] = [:]
        for item in items where item.seconds > 0 {
            let key = Key(device: item.device, item: item.item)
            if let position = index[key] {
                result[position].seconds += item.seconds
            } else {
                index[key] = result.count
                result.append(item)
            }
        }
        return result
    }

    private struct Key: Hashable {
        var device: String
        var item: ActivityItem
    }
}
