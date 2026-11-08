# The start of day

If you often work past midnight, a calendar day is the wrong unit. A session from 23:00 to 01:00 is one evening to you, but two days to a clock. The setting "Start of day" moves the hour at which the app's days begin.

Throughout this documentation, "midnight" always means 00:00 on the clock.

```{figure} /images/mac-settings-general.png
:alt: The General pane of the Mac app's settings window, with the "Start of day" setting among its options.
:width: 460px
:align: center

"Start of day" is in the General pane on the Mac and in Settings on the iPhone and iPad.
```

The setting takes a whole hour from 00:00 to 23:00, with 00:00 as the default. People set it to the middle of their night. With the start of day at 04:00, the app's "Tuesday" runs from Tuesday 04:00 to Wednesday 04:00, and at 02:00 on Wednesday night it is still Tuesday: the Timer's "Today" stays open, the Calendar's day column runs past the end of the date, and the day total keeps counting.

A day that starts at noon or later takes the name of the date it ends on. With the start of day at 22:00, "Tuesday" runs from Monday 22:00 to Tuesday 22:00.

## What it changes

The start of day changes how the app shows and adds up your time. The Timer list, the Calendar, Reports, Activity, the Projects totals, the widgets, and the command-line tool's day ranges all follow it. The Calendar's first hour label moves to that hour, and the heatmap in Activity starts there too.

It changes no stored data. Entries are stored whole, with their real start and end, and they are cut into pieces only for display. So you can change the setting at any time, see every view rearrange at once, and change it back with nothing lost. The setting syncs, so all your devices agree on what "today" is.

## Entries across the day change

An entry that crosses the start of a day, or real midnight with the default setting, is one entry. It can span any number of dates, even a timer you forgot over a long weekend.

Where it crosses, the app draws a piece on each day. The Timer list shows one row per day with that day's part, the Calendar shows one card per day, and Reports count each part on its day. Daily sums stay plain sums, and they add up to the weekly total.

You always edit the whole entry. Clicking either row opens the same stored entry with its real start and stop. Dragging either card in the Calendar moves all of it. The running timer also counts from the entry's real start, so it never resets at the day change.

## What stays on the clock

Some things deliberately ignore the setting, because they are about the real clock. The activity tracker files each block under the real date it starts on, even when it runs past midnight, and the app then places each block on the day it started. Reminders use the hours you set, as clock times. The menu bar's "Started 23:10 yesterday" compares plain dates, because it tells you when the entry started by the clock. The all-day strip in the Calendar shows the events of the date the column is named after.

The [reference](../reference/data_and_sync.md#8-days-weeks-and-time-zones) has the exact rules, including daylight-saving days and travel. To change the setting, see [Move the start of the day](../howto/midnight.md).
