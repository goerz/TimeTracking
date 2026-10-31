// AutomationTargets: the browsers and terminals the tracker reads through
// Apple Events, which the Tracker pane's "Ask for Access" asks for
// (spec_activity_tracking.md §3.1, §3.3, §7.4).

/// The apps whose Automation permission the tracker needs.
public enum AutomationTargets {
    /// The bundle identifiers of the scriptable browsers (3.3) and terminals
    /// (3.1), in the order the Tracker pane asks for them.
    public static let bundleIDs = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "company.thebrowser.Browser",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi",
        "com.googlecode.iterm2",
        "com.apple.Terminal",
    ]
}
