# Activity

The Activity section shows what the tracker recorded over a date range: how much of each day was active, at which hours, in which apps, sessions, and browsers, and where inside them the time went. It is a view of the [neutral record](tracked-and-recorded.md), so it changes nothing, assigns no projects, and creates no entries. Press ⌘5 on the Mac, or use the Activity tab on the iPad. It needs the [tracker](../howto/tracker.md) to be on; otherwise it invites you to set it up.

```{figure} /images/mac-activity.png
:alt: The Activity section with a total at the top, a row of app chips, a heatmap of active hours, a stacked bar chart per day, and lists of apps and subjects.

The header, chips, heatmap, and panels for one week of recorded activity.
```

The date range is the one from [Reports](reports.md): change it in either place and both follow. The header gives the total active time, the number of days with activity, and the average per day. With several devices it also gives each device's share, and a popup narrows every panel to one device.

## Chips

Below the header, one chip per app or terminal session, ranked by time. Clicking chips filters every panel to those contexts. A browser, for example, gives you just its sites. "All" turns the filter off. Each app keeps an automatically assigned color here, and only here: in the Calendar, activity cards are a neutral gray so they don't compete with your area colors.

## Panels

The heatmap shows active minutes by hour: one row per day for up to a week, per week for up to 98 days, and per month beyond that. Darker cells mean more activity. The columns start at your [Midnight](midnight.md) hour. Hover over a cell for its top items.

The bar chart stacks each day's active time by app in those same colors. Clicking a cell or a bar opens the Calendar at that day and hour with the matching blocks highlighted, and ⌘5 brings you back exactly where you were.

The Apps panel ranks contexts by time, and "Where the time went" ranks subjects such as sites, sessions, and folders. On the Mac that recorded them, a subject has a chevron that opens its details: the pages visited or files modified. Elsewhere those stay private to that Mac, and the panel says so.

"In the background" lists work that ran without your attention, such as builds and coding agents, marked as not counting toward active time. "Away" adds up the gaps during the day by cause, such as idle, asleep, or locked, leaving out the time before your first and after your last activity of the day.

## The health line

A line at the bottom shows whether the tracker is running and names any source that is limited or off, with a shortcut to Tracker Settings. If a number looks low, look here first: a red dot means the tracker wasn't running.

## On the iPad

The tab shows the same panels from the synced log, without the drill-down into subjects, the cause of away time, or the exclusion shortcut. Its footer reports on the Mac's tracker instead, such as "Mac tracker: checked 2 min ago".

To hide an app or site from now on, right-click it and choose "Exclude from Tracking…"; see [Keep something out of the activity record](../howto/exclude.md). The [Activity spec](../reference/activity.md) has every figure's definition.
