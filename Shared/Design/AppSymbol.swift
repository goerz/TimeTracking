// AppSymbol: the app's own symbols in the asset catalog (spec_design.md §5).

/// Symbols the app draws itself, as symbol assets in `AppResources`; every
/// other glyph is an SF Symbol.
enum AppSymbol {
    /// The Pomodoro and its focus phase: an apple, which SF Symbols lacks.
    static let pomodoro = "pomodoro"
    /// The Pomodoro break, an SF Symbol named here beside its focus glyph.
    static let pomodoroBreak = "cup.and.saucer"

    /// The glyph of a Pomodoro phase: the apple for focus, the cup for break.
    static func phase(isFocus: Bool) -> String {
        isFocus ? pomodoro : pomodoroBreak
    }

    static func isCustom(_ name: String) -> Bool {
        name == pomodoro
    }
}
