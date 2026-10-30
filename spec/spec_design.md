# Spec: Design Language

The visual rules every surface follows: the Mac Timer window, menu bar item, Planner, and settings; the iPhone and iPad app; widgets and controls. A component spec describes what a surface contains and how it behaves; this spec decides how it looks. Where a component spec gives a size, symbol, or style that conflicts with this one, this one wins and the component spec is corrected.

The app looks like it was made by Apple for the current OS: system text styles, SF Symbols, standard controls, system materials, and the platform's toolbar. Custom drawing is reserved for data (calendar cards, charts, heatmaps) and for the start and stop buttons.

## 1. Typography

Only the system's semantic text styles, so Dynamic Type works on iOS and sizes match the platform on the Mac. No `.font(.system(size:))` outside widgets' fixed layouts and the print layout. Bold comes from the style (`.headline`) or `.weight(.semibold)`; never `.bold()` on running text.

| Role | Style | Notes |
|---|---|---|
| Window and screen titles | System (`navigationTitle`, window title) | Never a `Text` title inside the content. |
| Task field, running timer | `.title3` | The timer uses `.monospacedDigit()` and `.weight(.medium)`; it sits on the field's baseline. iPhone and iPad Timer card: `.title2` for both. |
| Metric (summary tiles, "8h 30m active") | `.title2.weight(.semibold)`, monospaced digits | One metric size everywhere. |
| Group and card headers (day headers, card titles) | `.headline` | The trailing total of a day header uses the same style with monospaced digits. |
| Row title (task) | `.body` | |
| Row metadata (project · client, times) | `.subheadline` | Project in the primary color, " · client" in `.secondary`. |
| Row duration | `.body`, monospaced digits | Trailing, in the primary color. |
| Labels beside controls, table column headers | System default for the control | |
| Captions, axis labels, legends, footnotes | `.caption` | `.secondary`. |
| Calendar card text | `.caption` (title `.caption.weight(.semibold)`) | Data-dense surfaces only. |

Every duration that changes while visible, and every column of durations, uses monospaced digits.

## 2. Duration formats

| Context | Format | Example |
|---|---|---|
| Running timer, Timer list rows and day totals | `h:mm:ss` | `0:25:00` |
| Pomodoro countdown | `m:ss`, `+m:ss` in overtime | `24:59` |
| Calendar cards and day headers, Activity, Reports summaries and charts | `XhYYm` (`25m` below one hour) | `4h 07m` |
| Reports tables | `XhYYm` | `6h 24m` |

## 3. Layout and spacing

A 4 pt grid. The `Design` tokens in `Shared/Design/Design.swift` hold the values; views use them instead of literals.

| Token | Value | Use |
|---|---|---|
| `Design.Spacing.tight` | 4 pt | Icon to label, dot to text |
| `Design.Spacing.small` | 8 pt | Between related controls, row internal spacing |
| `Design.Spacing.medium` | 12 pt | Between groups in a bar or card |
| `Design.Spacing.large` | 16 pt | Content insets on iOS, card padding |
| `Design.Spacing.window` | 20 pt | Content insets in Mac windows |
| `Design.Radius.card` | 12 pt | Cards (Reports, Activity, iOS Timer card) |
| `Design.Radius.small` | 6 pt | Calendar cards, swatches, tags |

Cards use `.background(.background.secondary, in: .rect(cornerRadius: Design.Radius.card))` on the Mac and the inset-grouped `List`/`Form` look on iOS. No borders and no shadows on cards; separation comes from the fill.

Hit targets: at least 44 × 44 pt on iOS; on the Mac, standard control sizes (`.regular`, `.small` only in dense rows).

## 4. Toolbars

Window-level controls live in the platform toolbar, never in a custom row inside the content.

- Mac Planner: one unified toolbar. The window title is the section name; the date range is the `navigationSubtitle`. Leading (`.navigation`): the period arrows (`chevron.left`, `chevron.right`) as a `ControlGroup`, then Today. Trailing (`.primaryAction`), in this order: view options (segmented pickers, column toggles, zoom), the section's create action (`plus`, Fill Day), then share, export, and print. Sections keep their items in the same positions, so switching sections never moves a shared control.
- Icon-only toolbar items are `Label(title, systemImage:)` with `.help(title)`; the title shows in "Icon and Text" mode and in the overflow menu. Text-only toolbar buttons are allowed for a single word that has no clear symbol (Today).
- Mutually exclusive options: `Picker` with `.pickerStyle(.segmented)` (or `.menu` when there are more than four). On/off options: `Toggle` with `.toggleStyle(.button)` and a symbol. No custom filled or tinted toolbar buttons; the system draws the toolbar's glass.
- iPad: the same items in the navigation bar, in the same order, with system overflow. iPhone: at most two trailing items; everything else in an `ellipsis.circle` menu.

## 5. Symbols

SF Symbols only, monochrome, default weight, in the text style of the adjacent text. Inline metadata glyphs use `.secondary` and `.imageScale(.small)`. One symbol per concept, everywhere:

| Concept | Symbol |
|---|---|
| Projects (sidebar, tab) | `folder` |
| Calendar | `calendar` |
| Reports | `chart.bar` |
| Activity | `waveform.path.ecg` |
| Timer (tab) | `stopwatch` |
| Start, continue | `play.fill` |
| Stop | `stop.fill` |
| Discard the running entry | `xmark` (in the secondary circle button) |
| Pomodoro | `timer` |
| Pomodoro break | `cup.and.saucer` |
| Pin (float on top) | `pin`, `pin.fill` when on |
| New (entry, project, client) | `plus` |
| Edit | `pencil` |
| Delete | `trash` |
| Filter | `line.3.horizontal.decrease` |
| Share, export | `square.and.arrow.up` |
| Print | `printer` |
| Settings | `gearshape` |
| More | `ellipsis.circle` |
| Suggestions, Fill Day | `sparkles` |
| Mac activity (device) | `desktopcomputer` |
| iPhone, iPad activity | `iphone`, `ipad` |
| Tracked time | `stopwatch` |
| Time blocks, calendar events | `calendar` |
| Client | `person.crop.square` |
| Area | `circle.hexagongrid` |
| Warning | `exclamationmark.triangle` |
| Sync problem | `icloud.slash` |

A sidebar shows its symbols in the accent color (the system sidebar style); no multicolor symbols.

## 6. Color

- The accent color is the asset catalog's `AccentColor`, shared by both apps and the widgets; it comes from the app icon (§9). Views use `Color.accentColor` or `.tint`, never a literal.
- Start and continue: `Color.startTint` (system green); stop: `Color.stopTint` (system red). Both are defined once in `Shared/Design/Design.swift` (the widgets keep a copy).
- Area colors (user-chosen RGB) are data: they fill calendar cards, chart segments, and the 8 pt area dot. Text on an area color picks black or white by contrast.
- Everything else uses semantic colors (`.primary`, `.secondary`, `.tertiary`, `.background`, `.separator`) and works in light and dark appearance and with Increase Contrast.

## 7. Components

| Component | Look |
|---|---|
| Start, stop, continue buttons | `CircleButtonStyle`: a filled circle with a white glyph at 40% of the diameter. Timer bar: 32 pt on the Mac, 44 pt on iOS. List rows: 24 pt on the Mac (shown on hover and selection), 32 pt on iOS. No halo. |
| Discard button | The same circle at the same size in `.quaternary` fill with a `.secondary` `xmark` glyph. |
| Pomodoro button | A circular button the size of the start button: `timer` glyph in `.secondary` while off; while on, it widens to a capsule of the same height holding a small progress ring in the accent color (break: `.secondary`) and the remaining time in `.subheadline.monospacedDigit()`; a pending confirmation fills the circle with the accent color and shows `play.fill`. Click: off → Start Pomodoro; pending → the confirmation; otherwise the menu. The menu holds every action of `spec_timer_window.md` §5. |
| Project chip | `.bordered` capsule button, `.small` control size on the Mac: area dot, project, " · client" in `.secondary`, `chevron.up.chevron.down` in `.secondary`. "No project" with a hollow dot. |
| Area dot | 8 pt circle in the area color; hollow (1 pt `.secondary` stroke) for no project. |
| Lists | `List` (`.inset` on the Mac, `.insetGrouped` on iOS) with section headers in `.headline`; row padding `Design.Spacing.small` vertically. |
| Empty states | `ContentUnavailableView` with the section's symbol. |
| Forms and settings | `Form` with `.formStyle(.grouped)`; labels in sentence case; help text as the section footer. |
| Dialogs and sheets | Title via `navigationTitle`; Cancel leading and the confirming action trailing (`.confirmationAction`). |

## 8. Mac windows

- Timer window: hidden title bar; the title-bar row holds only the traffic lights and, at the far right, the pin button. The running-entry bar starts below it (`spec_timer_window.md` §2).
- Planner: `NavigationSplitView` with a sidebar of fixed sections; the toolbar of §4.
- Settings: `TabView` panes with a symbol per tab, each pane a grouped `Form` with a fixed width of 520 pt.
- Menu bar item: the system menu style; a running entry shows as a disabled header (task in `.headline`, project · client, "Started 09:35 · 0:25 elapsed").

## 9. App icon and identity

One icon for the Mac and iOS apps, made in Icon Composer (`.icon`, layered for the system's light, dark, and tinted appearances). Its dominant hue is the app's accent color. The widgets and the menu bar use SF Symbols, not the icon.

## 10. Verification

Every surface is checked in screenshots in light and dark appearance, on the Mac at the default and minimum window sizes, on the iPhone at the default and the largest non-accessibility Dynamic Type size, and on the iPad in landscape and in a narrow split view.

## 11. Decisions

- System text styles over a custom type scale: sizes follow the platform and Dynamic Type for free.
- System green and red for start and stop: they adapt to dark mode and Increase Contrast; the accent color is free to carry the brand.
- The Pomodoro countdown lives on its button, and the timer label always shows the elapsed time, so the running entry's duration is never hidden.
