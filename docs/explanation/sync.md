# How your devices stay in step

The app has no server of its own. Each device keeps a complete local copy of your data, and iCloud carries the changes between them, inside the private database of your own account.

Because the copy is local, everything works offline. Start, stop, or edit an entry on a plane and the change applies at once; it goes out when the device is back online. On the iPhone and iPad a small pill under the Timer card shows while changes are waiting.

## The running entry

Ordinary sync is fast enough for reports, but not for the question "what is running right now?". That answer travels separately, in a small live record that every device reads and writes. When you start an entry on the Mac, the Mac app also sends a push straight to the widgets on your iPhone and iPad. With the Mac awake and online, a stop on any device reaches a Home Screen widget in about five seconds, even while the iOS app is suspended.

These pushes need a key from your Apple Developer account, installed once with `make apns-key`, and they need a running Mac app. Without either, widgets still catch up, only more slowly: through iCloud's own notifications, background refreshes, and the next time you open the app. See [Add widgets and controls](../howto/widgets.md).

## When two devices disagree

At most one entry can run across all your devices. If two devices start entries while offline, both changes eventually meet. The later start wins, and the earlier entry stops at that moment, so no time is counted twice.

Other conflicts resolve per record, with the latest change winning. If a change this way touches an entry your iPhone or iPad created, a banner says "Another device changed an entry" and the entry's sheet explains what happened, for example that it stopped because an entry started on another device.

Two projects with the same name, created offline on two devices, both stay and get a warning sign in the Projects table. Merge or rename one to resolve it.

Deleted things don't vanish from the sync at once. Each deletion leaves a marker for 180 days, so a device that comes back after months still learns about it instead of bringing the record back.

## What syncs and what doesn't

Your clients, areas, projects, and entries sync, and so do settings that describe you rather than a device: the start of day, the Pomodoro durations, pinned projects, and the Calendar's settings. Settings that belong to one device stay there, such as the idle threshold, keyboard shortcuts, the menu bar display, and window positions.

Time blocks travel through your iCloud calendar like any event, and activity through files in iCloud Drive. A running Pomodoro stays on its device on purpose: it is a rhythm you follow at one screen, so one started on the Mac is invisible on the phone.

The [sync reference](../reference/data_and_sync.md#3-synchronization) describes the mechanism.
