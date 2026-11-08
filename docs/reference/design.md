# Design Language

The visual rules of every surface: the Mac main window, Mini Timer, menu bar item, and settings; the iPhone and iPad app; widgets and controls. A component spec says what a surface contains and how it behaves; this spec says how it looks and wins where the two differ on a size, symbol, or style.

The app looks like it was made by Apple for the current OS: system text styles, SF Symbols, standard controls, system materials, and the platform's toolbar. Custom drawing is reserved for data (calendar cards, charts, heatmaps) and for the start and stop buttons.

## 1. Typography

Only the system's semantic text styles, so sizes follow the platform and Dynamic Type works on iOS. No `.font(.system(size:))` outside widgets' fixed layouts and the glyphs of circle buttons, which scale with the circle. Bold comes from the style (`.headline`) or `.weight(.semibold)`, never `.bold()` on running text.

| Role | Style | Notes |
|---|---|---|
| Window and screen titles | System (`navigationTitle`, window title) | Never a `Text` title inside the content |
| Task field, running timer | `.title3` | The timer is `.weight(.medium)` on the field's baseline; iPhone and iPad Timer card: `.title2` for both |
| Metric (summary tiles, "8h 30m active") | `.title2.weight(.semibold)` | One metric size everywhere |
| Group and card headers | `.headline` | Also a day header's trailing total |
| Row title (task), row duration | `.body` | The duration trails in the primary color |
| Row metadata (project · client, times) | `.subheadline` | Project in the primary color, " · client" in `.secondary` |
| Captions, axis labels, legends, footnotes | `.caption` | `.secondary` |
| Calendar card text | `.caption` (title `.caption.weight(.semibold)`) | Data-dense surfaces only |

Every duration that changes while visible, and every column of durations, uses monospaced digits.

## 2. Duration formats

| Context | Format | Example |
|---|---|---|
| Running timer, Timer list rows and day totals | `h:mm:ss` | `0:25:00` |
| Pomodoro countdown | `m:ss`, `+m:ss` in overtime | `24:59` |
| Calendar cards and day headers, Activity, Reports summaries and charts | `XhYYm` (`25m` below one hour) | `4h 07m` |
| Reports breakdown, entry list, and bar tooltips | `XhYYmZZs` | `6h 24m 23s` |
| Projects table totals | `XhYYm`, unbounded hours | `432h 21m` |

Reports tables and tooltips keep seconds because rows must add up to the footer and to the CSV export exactly, and the running row visibly counts up ([reports.md](reports.md) §5.2, §6).

Wherever a Pomodoro shows, the elapsed time stays the primary text and the countdown is secondary: on the Pomodoro button in the Timer, or a segment behind the phase glyph in the menu bar and widgets. The running entry's duration is never hidden.

## 3. Layout and spacing

A 4 pt grid. The `Design` tokens in `Shared/Design/Design.swift` hold every spacing, padding, corner radius, and circle diameter, and views use them instead of literals. Content insets are 20 pt in Mac windows and 16 pt on iOS; card radius is 12 pt, and calendar cards, swatches, and row highlights take 6 pt. Literals remain only for optical adjustments of 1 to 3 pt and for offsets that line text up with another element. Popovers and sheets have `large` insets and `medium` spacing between groups; popups such as completion lists and chart tooltips take the card radius.

Cards use `.cardBackground()` on the Mac (the secondary background in the card radius) and the inset-grouped `List` or `Form` look on iOS. They have no borders and no shadows; separation comes from the fill.

Hit targets are at least 44 × 44 pt on iOS; on the Mac, standard control sizes (`.regular`, `.small` only in dense rows).

## 4. Toolbars

Window-level controls live in the platform toolbar, never in a custom row inside the content.

- Mac sections have one unified toolbar of the same structure, so the arrows never move when the section changes. The window title is the section name and the `navigationSubtitle` the shown range ("This week · W44").
- Leading (`.navigation`): the period arrows as one `ToolbarItemGroup` (a `ControlGroup` does not stay in `.navigation`), then the section's date menu, a text `Menu` titled by what is shown that anchors the date popover. In Reports, Projects, and Activity it is the range menu ("This month", "Week 43") with the presets and "Choose Dates…"; in the Calendar it reads "Today" while today is shown, else the shown days ("Oct 19 – 23"), with Go to Today and Go to Date…. No section has a separate Today button, because icon buttons next to the arrows merge into their capsule; Go to Today is also View › Go to Today (⌘T). A text label never names something other than what is shown.
- Trailing (`.primaryAction`), in this order: Filters wherever it exists, the section's view options, then the search field. The Calendar, Reports, and Projects have only Filters and the search field.
- Actions on a card's or table's content sit with it, not in the toolbar: Export in the Reports card's header, New below the Projects table, the Calendar's day width, column toggles, and zoom in and over its columns.
- The period items and Filters carry `.visibilityPriority(.high)`, so a narrow window keeps navigation and moves view options into the system overflow first.
- Icon-only items are `Label(title, systemImage:)` with `.help(title)`. A menu whose title shows the current choice is text.
- Mutually exclusive options: a segmented `Picker` (`.menu` above four options). Several on/off options of one kind: `Toggle`s in one toolbar `Menu`. A single on/off option: `Toggle` with `.toggleStyle(.button)` and a symbol. No custom filled or tinted toolbar buttons; the system draws the toolbar's glass.
- State that would need a badge shows in the symbol and the title: Filters uses its filled symbol and the title "Filters (2)" while a filter is active. Filters that can be removed one by one sit in a filter bar at the top of the content.
- Status rows at the bottom of a section (the projects count, the tracker health line) are `.subheadline` in `.secondary` with `content` side insets; their buttons are `.borderless`.
- iPad: the same items in the navigation bar, in the same order, with the title inline and system overflow. iPhone: at most two trailing items, the rest in a menu.

## 5. Symbols

SF Symbols, monochrome, default weight, in the text style of the adjacent text; inline metadata glyphs use `.secondary` and `.imageScale(.small)`. A sidebar shows its symbols in the accent color; there are no multicolor symbols.

There is one symbol per concept, everywhere: `SymbolName` in the library (`Support/SymbolName.swift`) names each concept, and views use its constants. The only literals are the App Shortcuts' `systemImageName`s, which must be compile-time literals; a comment there names their constants.

The one exception to SF Symbols is the Pomodoro's apple: SF Symbols has no fruit apple (`apple.logo` is reserved for Apple's products), so `pomodoro` is a custom symbol in `AppResources/Assets.xcassets`, with a copy in `TimeTrackingWidgets/Assets.xcassets`. It is an outline apple with a stem and a solid leaf, drawn to the template's Regular-M cap height with the stroke of `timer`, so it scales, tints, and aligns like an SF Symbol. App Shortcuts accept only SF Symbols and keep `timer`.

## 6. Color

- The accent color is the asset catalog's `AccentColor`, shared by both apps and the widgets (§9). Views use `Color.accentColor` or `.tint`, never a literal. Today and now (the Calendar's highlighted date, today's tint, the now-line and its time bubble) use it.
- Start and continue are system green (`Color.startTint`), stop system red (`Color.stopTint`): they adapt to dark mode and Increase Contrast and leave the accent color to the brand.
- Saturdays and Sundays in the Calendar have `Color.weekendTint` (the primary color at 3.5%) behind their header and columns; today's accent tint wins.
- Errors use `Color.errorText` (system red). `ErrorLine` shows the message under a control with the warning symbol, in `.caption` on the Mac and `.footnote` on iOS; a dialog's inline field error is plain text in the same color.
- Area colors (user-chosen RGB) are data: they fill calendar cards, chart segments, and the area dot. A malformed value shows gray. Text on an area color picks black or white by contrast.
- The tracker's block cards in the Calendar use `Color.activityBlock` (the secondary label color) for every app, the left border only on hover; app colors appear only in the Activity section ([activity.md](activity.md) §1.3). Sleep and workout lines are dark blue and dark green.
- Everything else uses semantic colors and works in light and dark appearance and with Increase Contrast.

## 7. Components

| Component | Look |
|---|---|
| Start, stop, continue buttons | `CircleButtonStyle`: a filled circle with a white glyph at 40% of the diameter, no halo. Timer bar: 32 pt on the Mac, 44 pt on iOS. List rows: 24 pt on the Mac (shown on hover and selection), 32 pt on iOS. |
| Discard button | A borderless `xmark` glyph in `.secondary` with the circle's hit area: a rare, destructive action does not get the weight of Stop. |
| Pomodoro button | A circle the size of the start button with a light fill (`.quaternary` on the Mac, `.fill.tertiary` on iOS), the apple in `.primary` while off (a `.secondary` glyph on the light fill reads as disabled). While on, it widens once to a capsule of the same height and a fixed width that fits `+88:88` (`8:88:88` when a phase lasts an hour or more), holding a small progress ring in the accent color (break: `.secondary`) and the remaining time in `.subheadline.monospacedDigit()`. A pending confirmation keeps that capsule, tinted with the accent color at 18%: the next phase's glyph and its name ("Break", "Focus") in `.subheadline.weight(.semibold)`, tooltip and accessibility label "Start Break (⌘↩)". Neighbors therefore move only when the Pomodoro turns on or off. Click: off, Start Pomodoro; pending, the confirmation; otherwise the menu, which holds every action of [timer.md](timer.md) §5. |
| Project chip | `.bordered` capsule button, `.small` on the Mac; on iOS a capsule with the Pomodoro button's light fill: area dot, project, " · client" in `.secondary`, the pop-up chevron in `.secondary`. "No project" has a hollow dot. |
| Area dot | 8 pt circle in the area color; hollow (1 pt `.secondary` stroke) for no project. |
| Lists | `List` (`.inset` on the Mac, `.insetGrouped` on iOS) with section headers in `.headline`; row padding `small` vertically. |
| Empty states | `ContentUnavailableView` with the section's symbol. |
| Forms and settings | `Form` with `.formStyle(.grouped)`; labels in sentence case; help text as the section footer. |
| Dialogs and sheets | iOS: title via `navigationTitle`, Cancel leading, the confirming action trailing. Mac sheets: centered `.headline` title, the grouped form, and Cancel then the confirming action (`.borderedProminent`) at the bottom trailing edge. Shared dialogs use `DialogScaffold`. |

### 7.1 Stable layout

Nothing moves or resizes on its own once it is on screen; only the viewer's action or a real change of state does.

- A live value redraws only its own text, inside a `TimelineView`. It never changes a view's identity (no `.id(date)`), and the tick never wraps a control the viewer may be editing or focusing: a new identity each second resets focus and makes SwiftUI rebuild the main menu, which drops the window items AppKit adds to an open Window menu.
- A ticking number has monospaced digits and keeps its width: the Pomodoro capsule fits the longest countdown, and the menu bar countdown is led by figure spaces to the width of the phase's length.
- An open menu is never rebuilt; its rows are compared by value, and changing text updates in place.
- Controls that come and go with state (discard while running, the Pomodoro capsule) change only when that state changes, never on a tick.

## 8. Mac windows

- Mini Timer: hidden title bar whose row holds only the traffic lights and, at the far right, the pin button; the running-entry bar starts below it ([timer.md](timer.md) §2).
- Main window: the iPad's adaptable `TabView` (`.sidebarAdaptable`), shown on the Mac as a sidebar of the Timer and the four sections; each section owns the toolbar of §4.
- Settings: `TabView` panes with a symbol per tab, each a grouped `Form`. The window is 520 pt wide and as tall as the current pane up to 720 pt, beyond which the form scrolls, and can't be resized. A list that can grow without bound is a short scrolling list inside its section. Numbers are a trailing value with a stepper after it; a dependent setting is disabled, not indented.
- Menu bar item: the dial icon, the elapsed time as text, and during a Pomodoro the segment of §2. A running entry shows in the menu as a header view, never as grayed-out disabled items ([menubar.md](menubar.md) §2.1).
- Menus: items set the symbols of §5 as images and leave `preferredImageVisibility` automatic; macOS 27 hides menu item images by default, so no menu relies on them.

## 9. App icon and identity

One icon, `AppResources/AppIcon.icon` (Icon Composer), for the Mac app, the tracker agent (it appears in Login Items and System Settings), and the iOS app. The widgets use SF Symbols. The menu bar item's dial is the icon reduced to one template color: a single ring with the knob, which moves as a minute hand or with the Pomodoro's progress.

The icon is a ring of five flat arcs on a near-black navy squircle: time filling up with project colors, with a white knob at the open end as the running entry. Layers are flat, with no glass, specular highlight, shadow, or translucency; the system derives the tinted and clear appearances.

The accent color is `#2F7FE0` (dark appearance `#6FB2FF`), the blue of the first arc deepened for contrast on white. It lives in `AppResources/Assets.xcassets`, with a copy in `TimeTrackingWidgets/Assets.xcassets`.

## 10. Verification

The design holds in light and dark appearance, on the Mac at the default and minimum window sizes, on the iPhone at the default and the largest non-accessibility Dynamic Type size, and on the iPad in landscape and in a narrow split view.

## 11. Words

User-visible text names what the user sees and gets, never how the code works. Text a user reads never contains a case name, a raw value, a setting key, a file the user did not open, or an error's `errorDescription` from the library, which is written for logs; `UserMessage` turns store errors into sentences, and the log keeps the details.

| Internal term | On screen |
|---|---|
| Pomodoro phase | focus, break ("when a focus or break ends") |
| tick, sample | how recent or how soon: "updated 12 s ago", "within 30 seconds" |
| agent (the tracker process) | tracker ("Tracker version") |
| health record, source | what the tracker records ("Window titles", "Browser history") |
| source status `active`, `fallback`, `off` | On, Limited, Off |
| Knowledge store | app usage history |
| activity block | activity ("Delete This Activity…"); counted, "periods of activity" |
| time block | time block (only these are "blocks") |
| Item, `app` | app |
| workspace (a full path or name) | its last component ("MyApp") |
| Sample | not shown; "recorded activity" where it must be named |
| store, database, record | your entries, your data |
| outbox, pending changes | waiting to sync |
| app set (iOS Screen Time set) | app group |
| activity log (the files) | Activity (the section) wherever the user's view is meant; "activity logs" only for the files, in the Tracker pane |
| event, labeled event (iOS collection) | what was recorded ("when a Focus turns on") |
| fetch, upload, flush | check, send |
