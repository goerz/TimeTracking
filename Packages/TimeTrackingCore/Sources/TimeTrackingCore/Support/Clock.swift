// Clock: the source of the current instant (spec_architecture.md §3.3).

public import Foundation

/// The source of "now".
///
/// Code that needs the current time reads it from a `Clock` it was given
/// rather than calling `Date()`, so tests can fix and advance time with
/// `ManualClock` instead of sleeping.
///
/// This protocol shadows the standard library's `Clock` inside modules that
/// import `TimeTrackingCore`; write `Swift.Clock` for the latter.
public protocol Clock: Sendable {
    /// The current instant.
    var now: Date { get }
}
