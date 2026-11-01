// SymbolName: the one symbol per concept of the design language, for every
// target: both apps, the widgets, and the intents (spec_design.md §5).

/// Symbol names by concept. Views name a concept here instead of writing an
/// SF Symbol's name, so a concept has one symbol everywhere. `pomodoro` is
/// the app's own symbol (an asset); every other name is an SF Symbol.
public enum SymbolName {
    // MARK: Entries and the Timer

    public static let start = "play.fill"
    public static let stop = "stop.fill"
    public static let startCircle = "play.circle.fill"
    public static let stopCircle = "stop.circle.fill"
    /// Discard the running entry; also the clear button of a filter chip.
    public static let discard = "xmark"
    public static let add = "plus"
    public static let addCircle = "plus.circle.fill"
    public static let edit = "pencil"
    public static let delete = "trash"
    public static let more = "ellipsis"
    public static let moreCircle = "ellipsis.circle.fill"
    public static let copy = "doc.on.doc"
    /// Restore, undo, continue the last entry (App Shortcuts).
    public static let restore = "arrow.counterclockwise"
    /// Float on top: `pin`, and `pinned` while on.
    public static let pin = "pin"
    public static let pinned = "pin.fill"
    /// A running entry in a list.
    public static let running = "record.circle"
    /// The start time of an entry.
    public static let startTime = "clock"
    /// The Timer tab and the menu bar's Show Mini Timer.
    public static let timer = "stopwatch"
    /// The menu bar's Open (the main window).
    public static let mainWindow = "macwindow"

    // MARK: Pomodoro

    /// The Pomodoro and its focus: the app's apple (an asset, not an SF Symbol).
    public static let pomodoro = "pomodoro"
    public static let pomodoroBreak = "cup.and.saucer"
    /// The glyph of a Pomodoro phase: the apple for focus, the cup for break.
    public static func phase(isFocus: Bool) -> String {
        isFocus ? pomodoro : pomodoroBreak
    }

    /// The Pomodoro where only SF Symbols are allowed (App Shortcuts).
    public static let pomodoroSystem = "timer"

    // MARK: Sections and panes

    public static let projects = "folder"
    public static let calendar = "calendar"
    public static let reports = "chart.bar"
    /// Activity, and the tracker that records it.
    public static let activity = "waveform.path.ecg"
    public static let clients = "person.crop.square"
    public static let settings = "gearshape"
    public static let idle = "moon.zzz"
    public static let reminders = "bell"
    public static let shortcuts = "keyboard"
    public static let suggestions = "sparkles"

    // MARK: Navigation, lists, and toolbars

    public static let previous = "chevron.left"
    public static let next = "chevron.right"
    /// The Calendar's Go to Today: a calendar page
    /// showing today's day of the month (`1.calendar` to `31.calendar`).
    public static func today(_ day: TrackingDay) -> String {
        "\(day.day).calendar"
    }

    /// The Calendar's Go to Date… (its date picker): the page of `today`
    /// with an ellipsis.
    public static let goToDate = "ellipsis.calendar"
    /// A collapsed row (`next`) opens to `expanded`.
    public static let expanded = "chevron.down"
    public static let ascending = "chevron.up"
    public static let descending = "chevron.down"
    /// The indicator of a pop-up chip.
    public static let popUp = "chevron.up.chevron.down"
    public static let search = "magnifyingglass"
    public static let filter = "line.3.horizontal.decrease"
    public static let filterActive = "line.3.horizontal.decrease.circle.fill"
    public static let sort = "arrow.up.arrow.down"
    public static let zoomIn = "plus.magnifyingglass"
    public static let zoomOut = "minus.magnifyingglass"
    public static let calendarColumns = "rectangle.split.3x1"
    public static let share = "square.and.arrow.up"
    public static let info = "info.circle"
    /// A total (App Shortcuts' today's total).
    public static let total = "sum"

    // MARK: Status

    public static let warning = "exclamationmark.triangle"
    public static let warningFill = "exclamationmark.triangle.fill"
    /// The menu bar item's badge while the tracker is not running.
    public static let warningBadge = "exclamationmark.circle.fill"
    public static let done = "checkmark.circle.fill"
    public static let checkmark = "checkmark"
    /// A filter tree's check boxes: checked, partly checked, unchecked.
    public static let checkboxOn = "checkmark.square.fill"
    public static let checkboxMixed = "minus.square.fill"
    public static let checkboxOff = "square"
    public static let notChecked = "circle.dashed"
    /// A step not done yet, beside `done`.
    public static let notDone = "circle"
    public static let statusDot = "circle.fill"
    public static let iCloudOff = "icloud.slash"
    public static let iCloudDownload = "icloud.and.arrow.down"

    // MARK: Devices

    public static let mac = "desktopcomputer"
    public static let iPhone = "iphone"
    public static let iPad = "ipad"
    /// Activity from other devices (synced Safari history).
    public static let otherDevices = "cloud"

    /// Whether `name` is the app's own symbol, an asset rather than an SF Symbol.
    public static func isCustom(_ name: String) -> Bool {
        name == pomodoro
    }
}
