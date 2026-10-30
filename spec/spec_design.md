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
| Reports breakdown, entry list, and bar tooltips | `XhYYmZZs` (to the second, [spec_planner_reports.md](spec_planner_reports.md) §5.2, §6) | `6h 24m 23s` |
| Projects table totals | `XhYYm`, unbounded hours | `432h 21m` |

## 3. Layout and spacing

A 4 pt grid. The `Design` tokens in `Shared/Design/Design.swift` hold the values; views use them instead of literals.

| Token | Value | Use |
|---|---|---|
| `Design.Spacing.tight` | 4 pt | Icon to label, dot to text |
| `Design.Spacing.small` | 8 pt | Between related controls, row internal spacing |
| `Design.Spacing.medium` | 12 pt | Between groups in a bar or card |
| `Design.Spacing.large` | 16 pt | Content insets on iOS, card padding |
| `Design.Spacing.window` | 20 pt | Content insets in Mac windows |
| `Design.Spacing.content` | `window` on the Mac, `large` on iOS | Content insets of views shared by both apps (the Planner sections) |
| `Design.Radius.card` | 12 pt | Cards (Reports, Activity, iOS Timer card) |
| `Design.Radius.small` | 6 pt | Calendar cards, swatches, tags, list row highlights |
| `Design.CircleDiameter.bar` | 32 pt Mac, 44 pt iOS | Start, stop, discard, and Pomodoro buttons of the Timer bar and card |
| `Design.CircleDiameter.row` | 24 pt Mac, 32 pt iOS | Continue buttons in list rows |

Cards use `.background(.background.secondary, in: .rect(cornerRadius: Design.Radius.card))` on the Mac and the inset-grouped `List`/`Form` look on iOS. No borders and no shadows on cards; separation comes from the fill.

Hit targets: at least 44 × 44 pt on iOS; on the Mac, standard control sizes (`.regular`, `.small` only in dense rows).

## 4. Toolbars

Window-level controls live in the platform toolbar, never in a custom row inside the content.

- Mac Planner: one unified toolbar. The window title is the section name; in Calendar, Reports, and Activity the shown range is the `navigationSubtitle` ("This week · W44"). Leading (`.navigation`, before the title), in these three sections: the period arrows (`chevron.left`, `chevron.right`) as one `ToolbarItemGroup` (a `ControlGroup` does not stay in `.navigation`), then Today, a `Menu` whose primary action goes to today and whose menu holds the section's date choices (Reports and Activity: the presets and "Choose Dates…"; Calendar: "Go to Date…"), which open the date popover anchored to it. Projects has no leading items. Trailing (`.primaryAction`), in this order: view options (Filters first, then segmented pickers, menus, zoom, the options popover), the section's create action (`plus`, Fill Day), then print and export. The arrows and Today never move when the section changes, and Filters is the first trailing item wherever it exists.
- Overflow: the period items, Filters, and create actions carry `.visibilityPriority(.high)`, zoom and options `.low`, so a narrow window keeps navigation and moves view options into the system overflow (`chevron.right.2`) first.
- Icon-only toolbar items are `Label(title, systemImage:)` with `.help(title)`; the title shows in "Icon and Text" mode and in the overflow menu. Text-only toolbar buttons are allowed for a single word that has no clear symbol (Today).
- Mutually exclusive options: `Picker` with `.pickerStyle(.segmented)` (or `.menu` when there are more than four). Several on/off options of one kind (the Calendar's columns): `Toggle`s inside one toolbar `Menu`, shown as check marks. A single on/off option: `Toggle` with `.toggleStyle(.button)` and a symbol. No custom filled or tinted toolbar buttons; the system draws the toolbar's glass.
- State that would need a badge shows in the symbol and the title instead: Filters uses `line.3.horizontal.decrease.circle.fill` and the title "Filters (2)" while a filter is active. Active filters that can be removed one by one sit in a filter bar at the top of the content, not in the toolbar.
- Status rows at the bottom of a section (the projects count, the tracker health line) are `.subheadline` in `.secondary` with `Design.Spacing.content` side insets; their buttons are `.borderless`.
- iPad: the same items in the navigation bar, in the same order, with the title inline and system overflow. iPhone: at most two trailing items; everything else in an `ellipsis.circle` menu.

## 5. Symbols

SF Symbols, monochrome, default weight, in the text style of the adjacent text. The one exception is the Pomodoro's apple: SF Symbols has no fruit apple (`apple.logo` is Apple's logo, reserved for Apple's products), so `pomodoro` is a custom symbol (`AppSymbol.pomodoro`) in `AppResources/Assets.xcassets`, with a copy in `TimeTrackingWidgets/Assets.xcassets`. It is an outline apple with a stem and a solid leaf, drawn to the template's Regular-M cap height with the stroke of `timer`, so it scales, tints, and aligns like an SF Symbol; `Image(symbol:)` and `NSImage.symbol(_:)` resolve either kind. App Shortcuts, which accept only SF Symbols, keep `timer`. Inline metadata glyphs use `.secondary` and `.imageScale(.small)`. One symbol per concept, everywhere:

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
| Pomodoro, focus phase | `pomodoro` (the app's apple) |
| Pomodoro break | `cup.and.saucer` |
| Pin (float on top) | `pin`, `pin.fill` when on |
| New (entry, project, client) | `plus` |
| Edit | `pencil` |
| Delete | `trash` |
| Filter | `line.3.horizontal.decrease`; `line.3.horizontal.decrease.circle.fill` while a filter is active |
| Previous, next period or day | `chevron.left`, `chevron.right` |
| Zoom out, zoom in | `minus.magnifyingglass`, `plus.magnifyingglass` |
| Calendar columns (menu) | `rectangle.split.3x1` |
| Sort and group (menu) | `arrow.up.arrow.down` |
| Clients & Areas | `person.crop.square` (the Client symbol) |
| Share, export | `square.and.arrow.up` |
| Print | `printer` |
| Settings | `gearshape` |
| More | `ellipsis.circle` |
| Suggestions, Fill Day | `sparkles` |
| Mac activity (device) | `desktopcomputer` |
| iPhone, iPad activity | `iphone`, `ipad` |
| Tracked time | `stopwatch` |
| Start time, last stop (menu bar header) | `clock` |
| Time blocks, calendar events | `calendar` |
| Client | `person.crop.square` |
| Area | `circle.hexagongrid` |
| Warning | `exclamationmark.triangle` |
| Sync problem | `icloud.slash` |

A sidebar shows its symbols in the accent color (the system sidebar style); no multicolor symbols.

## 6. Color

- The accent color is the asset catalog's `AccentColor`, shared by both apps and the widgets; it comes from the app icon (§9). Views use `Color.accentColor` or `.tint`, never a literal.
- Start and continue: `Color.startTint` (system green); stop: `Color.stopTint` (system red). Both are defined once in `Shared/Design/Design.swift` (the widgets keep a copy).
- Today and now (the Calendar's highlighted date, today's tint, the now-line and its time bubble) use the accent color.
- Area colors (user-chosen RGB) are data: they fill calendar cards, chart segments, and the 8 pt area dot. Text on an area color picks black or white by contrast.
- Everything else uses semantic colors (`.primary`, `.secondary`, `.tertiary`, `.background`, `.separator`) and works in light and dark appearance and with Increase Contrast.

## 7. Components

| Component | Look |
|---|---|
| Start, stop, continue buttons | `CircleButtonStyle`: a filled circle with a white glyph at 40% of the diameter. Timer bar: 32 pt on the Mac, 44 pt on iOS. List rows: 24 pt on the Mac (shown on hover and selection), 32 pt on iOS. No halo. |
| Discard button | A borderless `xmark` glyph in `.secondary` (medium weight, 40% of the circle's diameter), its hit area the circle's size (32 pt Mac, 44 pt iOS): a rare, destructive action does not get the weight of Stop. |
| Pomodoro button | A circular button the size of the start button with a light fill (`.quaternary` on the Mac, `.fill.tertiary` on iOS): the apple (`pomodoro`) in `.secondary` while off. While on, it widens once to a capsule of the same height and a fixed width that fits `+88:88` (`8:88:88` when a phase lasts an hour or more), holding a small progress ring in the accent color (break: `.secondary`) and the remaining time in `.subheadline.monospacedDigit()`. A pending confirmation keeps that capsule, tinted with the accent color (18% fill, accent glyph and text): the next phase's glyph (`cup.and.saucer` for Start Break, `pomodoro` for Start Focus) and its name ("Break", "Focus") in `.subheadline.weight(.semibold)`; tooltip and accessibility label "Start Break (⌘↩)". Neighbors therefore move only when the Pomodoro turns on or off. Click: off → Start Pomodoro; pending → the confirmation; otherwise the menu. The menu holds every action of `spec_timer_window.md` §5. |
| Project chip | `.bordered` capsule button, `.small` control size on the Mac; on iOS a capsule with the Pomodoro button's light fill: area dot, project, " · client" in `.secondary`, `chevron.up.chevron.down` in `.secondary`. "No project" with a hollow dot. |
| Area dot | 8 pt circle in the area color; hollow (1 pt `.secondary` stroke) for no project. |
| Lists | `List` (`.inset` on the Mac, `.insetGrouped` on iOS) with section headers in `.headline`; row padding `Design.Spacing.small` vertically. |
| Empty states | `ContentUnavailableView` with the section's symbol. |
| Forms and settings | `Form` with `.formStyle(.grouped)`; labels in sentence case; help text as the section footer. |
| Dialogs and sheets | iOS: title via `navigationTitle`; Cancel leading and the confirming action trailing (`.confirmationAction`). Mac sheets (no navigation bar): the title as centered `.headline` text at the top, the grouped form, and Cancel then the confirming action (`.borderedProminent`) at the bottom trailing edge. Shared dialogs use `DialogScaffold`. |

## 8. Mac windows

- Timer window: hidden title bar; the title-bar row holds only the traffic lights and, at the far right, the pin button. The running-entry bar starts below it (`spec_timer_window.md` §2).
- Planner: `NavigationSplitView` with a sidebar of fixed sections; the toolbar of §4.
- Settings: `TabView` panes with a symbol per tab, each pane a grouped `Form` with a fixed width of 520 pt whose window takes the pane's height (scrolling off, height fixed to the content); only a pane longer than the screen allows (Tracker) has a fixed height and scrolls. Numbers are a trailing value with a stepper after it; a dependent setting is disabled, not indented.
- Menu bar item: the elapsed time as text, and during a Pomodoro a trailing segment with the phase glyph and the countdown (the rule of §11). The menu is the system menu style; a running entry shows as a header view (task in `.headline`; area dot, project, " · client" in `.secondary`; `clock`, "Started 09:35 · 0:25 elapsed" in `.secondary`), never as grayed-out disabled items (`spec_menubar.md` §2.1).
- Menus: items set the symbols of §5 as images and leave `preferredImageVisibility` automatic; macOS 27 hides menu item images by default, so no menu relies on them.

## 9. App icon and identity

One icon, `AppResources/AppIcon.icon` (Icon Composer), for the Mac app, the tracker agent (it appears in Login Items and System Settings), and the iOS app. The `AppResources` folder belongs to those three targets; `ASSETCATALOG_COMPILER_APPICON_NAME` is set for them in `Project.xcconfig`. The widgets and the menu bar use SF Symbols, not the icon.

The icon is a ring of five flat arcs on a near-black navy squircle: time filling up with project colors, a white knob at the open end as the running entry. The geometry is exact on the 1024 pt grid:

| Element | Value |
|---|---|
| Background | Vertical gradient `#141E40` to `#0A1028` (dark appearance `#10141D` to `#07090E`) |
| Ring | Center (512, 512), centerline radius 300, width 96 (radii 252 to 348) |
| Track | Full ring, white at 7% opacity |
| Arcs | Butt caps, 4° gaps; boundaries at 0, 72, 128, 196, 248, 300° clockwise from 12 o'clock; `#4FA8FF`, `#5EE0B5`, `#FFD15C`, `#FF9F59`, `#F2706A` |
| Knob | White circle, diameter 128, on the centerline at 298° |

Layers are flat: no glass, specular highlight, shadow, or translucency. The system derives the tinted and clear appearances.

The accent color is `#2F7FE0` (dark appearance `#6FB2FF`), the blue of the first arc deepened for contrast on white. It lives in `AppResources/Assets.xcassets` (`AccentColor`, set as `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`), with a copy in `TimeTrackingWidgets/Assets.xcassets`.

## 10. Verification

Every surface is checked in screenshots in light and dark appearance, on the Mac at the default and minimum window sizes, on the iPhone at the default and the largest non-accessibility Dynamic Type size, and on the iPad in landscape and in a narrow split view.

## 11. Decisions

- System text styles over a custom type scale: sizes follow the platform and Dynamic Type for free.
- System green and red for start and stop: they adapt to dark mode and Increase Contrast; the accent color is free to carry the brand.
- Reports tables and tooltips keep seconds: rows must add up to the footer and to the CSV export exactly, and the running row visibly counts up (PR-13, PR-17). Every other summary rounds to the minute.
- The Pomodoro countdown lives on its button, and the timer label always shows the elapsed time, so the running entry's duration is never hidden.
