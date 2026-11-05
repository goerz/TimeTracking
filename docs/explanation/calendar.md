# The Calendar

The Calendar shows days side by side on one time axis, so that what you did, what you tracked, and what you planned line up at a glance. It is where past time gets drawn, moved, and repaired. Press ⌘2 on the Mac, or use the Calendar tab on the iPad; the iPhone has no calendar view.

```{figure} /images/mac-calendar.png
:alt: The Calendar with several days. Each day has a column of gray activity cards, a column of colored entry cards, and a column of plans, with a colored line marking the current time on today's column.

Activity, Tracked, and Calendar columns for each day, with the now-line on today.
```

## Three columns per day

The Tracked column in the middle holds your entries, each a card in its area's color with the task, project, client, and duration. It is always shown. The Activity column on the left holds the [tracker's record](tracked-and-recorded.md) as gray cards, and the Calendar column on the right holds time blocks and events from the calendars you chose. Each of those two can be hidden with the glyphs in the day header, with ⌥⌘A and ⌥⌘K, or in the View menu.

The header above each day shows every column's total, so you can compare recorded, tracked, and planned time at a glance. Above the columns, a summary strip adds up the days in view, with a bar stacked by project.

## Moving through time

The strip of days has no beginning or end. Scroll sideways with a trackpad swipe, or hold ⇧ with a mouse wheel, and days load as you go. The arrows in the toolbar and the ← and → keys snap one day at a time. ⌘T returns to today, and a click on a day's date slides it to the left edge. ⌥-click shows that one day alone, as wide as the window.

Two things control the scale. ⌘+ and ⌘− zoom the hours, and ⌘0 resets them. The slider at the right of the summary strip, or ⌥⌘[ and ⌥⌘], makes days narrower or wider, so the window's width decides how many days fit. A day column runs from [Midnight](midnight.md) to Midnight.

## Working with entries

Drag vertically in empty space in the Tracked column and a provisional card appears, with a popover for the task and project. Times snap to five minutes by default, or to the minute with ⌥ held. Press Return to keep the entry and Escape to throw it away.

Drag a card to move it, also onto another day, and drag its top or bottom edge to resize it. Every move is one undo step. A click selects a card, and double-click or Return opens the [editor](timer.md#the-editor). The context menu offers Continue, Edit…, Split Here, Duplicate to Next Day, and Delete.

No part of an entry can lie after the now-line, so drags stop there. If a drawing or a move would overlap another entry, a small popover asks what you meant, and the default is to trim:

- Trim shortens the changed entry so it ends where the neighbor begins.
- Overlap keeps both as they are, and the cards then sit side by side with a ⚠ badge.
- Cancel puts everything back.

Overlaps of a minute or less are trimmed without asking.

## Activity cards

Each card names the workspace that dominated that stretch, such as "paper (tmux)", and the main subject inside it. Parts already covered by an entry are dimmed, so what remains bright is time you have not accounted for. A click opens the details: how long, on which device, and the main items in order. A phone glyph marks time on an iPhone or iPad.

Hover over a card and click "+", drag it into the Tracked column, or press Space on a selected card, and you get a provisional entry over the longest stretch no entry covers yet. Gaps longer than 15 minutes show their length, and thin strips at the edge of the column mark background work that went on while you were away.

If you turned on [sleep and workouts](../howto/health.md), they appear as thin lines in this column, dark blue and dark green.

## Time blocks and events

A time block is a plan such as "write the intro, 9 to 11". It is an ordinary event in an iCloud calendar, by default one named "Time Blocks", so it shows on every device and in every calendar app. Blocks can be drawn in the future, moved, and resized like entries, and they may link to a project, which gives them its color.

Events from your other calendars appear as pale cards and are read-only. Both kinds can become entries: hover and click "+", or drag the card into the Tracked column. The source stays as it was, because the plan and the record stay separate.

[Plan the day with time blocks](../howto/time-blocks.md) covers the details, including how scripts can create blocks with any calendar tool. All keys and rules are in the [Calendar spec](../reference/calendar.md).
