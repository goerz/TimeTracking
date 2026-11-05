// Name folding: case- and diacritic-insensitive comparison (data_and_sync.md §1).

import Foundation

extension String {
    /// The string without leading and trailing white space.
    public var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The trimmed string, folded for case and diacritics: the key of name
    /// uniqueness, alphabetical order, and task autocompletion.
    public var folded: String {
        trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
