// Array.stableSorted: the stable sort behind the tool's project orders and
// the intents' project lists (spec_automation.md §3.8, §5).

import Foundation

extension Array {
    /// Sorted by `areInIncreasingOrder`, equal elements keeping their order.
    func stableSorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> [Element] {
        enumerated().sorted { lhs, rhs in
            areInIncreasingOrder(lhs.element, rhs.element)
                || (!areInIncreasingOrder(rhs.element, lhs.element) && lhs.offset < rhs.offset)
        }.map(\.element)
    }
}
