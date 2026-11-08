# The iPhone app

The iPhone gets the Timer in pocket form. The other views need the width of a bigger screen, so the phone concentrates on starting, stopping, and looking up what is running.

```{figure} /images/iphone-timer.png
:alt: The iPhone app's Timer screen, with a card for the running entry at the top and the list of recent entries below.
:width: 300px
:align: center

One screen: the running entry above the recent list.
```

## The Timer screen

A card at the top holds the task field, the project chip, and a row with the Pomodoro button, the elapsed time, Discard, and Start or Stop. It works like the [Mac's bar](timer.md#the-running-entry-bar), including `@` for the project picker and suggestions under the field. Tapping the elapsed time opens the running entry's edit sheet.

Below the card, a line shows what your Mac is doing if its tracker runs, such as "MacBook · WezTerm · MyApp", followed by the same day-grouped list as on the Mac. Tap a row to edit it, tap ▶ or swipe fully to the right to continue it, and swipe left to delete it. Long-press for the full menu. Pull down to reveal the search field.

## What is different on iOS

The iPhone creates entries only by starting them, like the Mac's Timer. Past intervals are drawn in the Calendar on the Mac or iPad.

There is no idle detection, because iOS can't tell. Instead, a notification asks "Still tracking…?" when an entry has run for a set number of hours, four by default, with Keep Running and Stop as actions. That setting is on for the iPhone and off for the iPad, so two devices don't remind you at once.

The Pomodoro belongs to the device: one started here is invisible on the Mac, and the reverse. It survives the app being closed, and its phase ends arrive as notifications.

Every change is stored on the device first, so all of this works offline, and a small pill shows while changes wait to go out. The app needs an iCloud account: without one, it shows a screen asking for it and nothing else.

## Beyond the app

The iPhone is also where most quick interactions happen outside the app. [Widgets](widgets.md) start and stop entries from the Home Screen and Lock Screen, Control Center and the Action button can toggle the timer, and [Siri understands phrases](../howto/shortcuts.md) such as "Start tracking Household in TimeTracking".

Only the iPhone can [import sleep and workouts](../howto/health.md) from Apple Health, and it can [collect activity](../howto/ios-activity.md) for the Mac's tracker to merge in. The [iOS spec](../reference/ios.md) has the details.
