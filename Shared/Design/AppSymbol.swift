// AppSymbol: the app's own symbols in the asset catalog (spec_design.md §5).

/// Symbols the app draws itself, as symbol assets in `AppResources`; every
/// other glyph is an SF Symbol.
enum AppSymbol {
    /// The Pomodoro and its focus phase: an apple, which SF Symbols lacks.
    static let pomodoro = "pomodoro"

    static func isCustom(_ name: String) -> Bool {
        name == pomodoro
    }
}
