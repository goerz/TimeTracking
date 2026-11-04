// CalendarTouchArbiter: which of the iPad Calendar's two-finger gestures
// owns the current touch, the sideways swipe or the pinch
// (spec_calendar.md §1.2, §1.3; spec_ios.md §10.2).

/// Two fingers swiping sideways always change their spread a little, so
/// the first of the two gestures to start in earnest owns the touch and the
/// other gives way until the fingers lift.
@MainActor
enum CalendarTouchArbiter {
    /// The sideways swipe has started.
    static var swiping = false
    /// The pinch has passed its threshold and zooms.
    static var pinching = false
}
