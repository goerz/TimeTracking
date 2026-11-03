// SampleOrigin: where a sample of the user's timeline was observed
// (spec_activity_tracking.md §2.4).

import Foundation

/// The device a sample was observed on, and whether it was reconstructed
/// from the Mac's app usage history rather than observed live.
nonisolated struct SampleOrigin: Hashable, Sendable {
    var device: String
    var isReconstructed = false
}
