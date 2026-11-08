# Activity

The Activity section shows what the tracker recorded over a date range: how much of each day was active, at which hours, in which apps, and on which workspaces, the project folders and sites the work belongs to. It is a view of the [neutral record](tracked-and-recorded.md), so it changes nothing, assigns no projects, and creates no entries. Press ⌘5 on the Mac, or use the Activity tab on the iPad. It needs the [tracker](../howto/tracker.md) to be on; otherwise it invites you to set it up.

```{figure} /images/mac-activity.png
:alt: The Activity section with a total at the top, a row of app chips, a heatmap of active hours, a stacked bar chart per day, and lists of apps and workspaces.

The header, chips, heatmap, and panels for one week of recorded activity.
```

The date range is the one from [Reports](reports.md): change it in either place and both follow. The header gives the total active time, the number of days with activity, and the average per day. With several devices it also gives each device's share, and a popup narrows every panel to one device.

## Chips

Below the header, one chip per app, ranked by time. Clicking chips filters every panel to those apps. A browser, for example, gives you just its sites. "All" turns the filter off. Each app keeps an automatically assigned color here, and only here: in the Calendar, activity cards are a neutral gray so they don't compete with your area colors.

## Panels

The heatmap shows active minutes by hour: one row per day for up to a week, per week for up to 98 days, and per month beyond that. Darker cells mean more activity. The columns start at your [start of day](start-of-day.md). Hover over a cell for its top items.

The bar chart stacks each day's active time by app in those same colors. Clicking a cell or a bar opens the Calendar at that day and hour with the matching blocks highlighted, and ⌘5 brings you back exactly where you were.

The Apps panel ranks apps by time, and "Where the time went" ranks workspaces, each shown by the last part of its name, such as "MyApp". A workspace has a chevron that opens its items: the files, sessions, and pages that made up its time.

"In the background" lists work that ran without your attention, such as builds and coding agents, marked as not counting toward active time. "Away" adds up the gaps during the day by cause, such as idle, asleep, or locked, leaving out the time before your first and after your last activity of the day.

## The health line

A line at the bottom shows whether the tracker is running and names any source that is limited or off, with a shortcut to Tracker Settings. If a number looks low, look here first: a red dot means the tracker wasn't running.

## On the iPad

The tab shows the same panels from the synced log, without the exclusion shortcut. Its footer reports on the Mac's tracker instead, such as "Mac tracker: checked 2 min ago".

To hide an app or site from now on, right-click it and choose "Exclude from Tracking…"; see [Keep something out of the activity record](../howto/exclude.md). The [Activity spec](../reference/activity.md) has every figure's definition.
