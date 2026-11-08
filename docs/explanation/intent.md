# Why TimeTracking exists

Most time trackers record only what you remember to tell them. That breaks in a familiar way: you forget to start the timer, the afternoon goes by, and at the end of the day you reconstruct it from memory. The reverse approach, automatic tracking, knows which apps were open but not what the work was for.

TimeTracking keeps both records and refuses to merge them. You state your work as time entries, which are the only thing that counts as tracked time. A background tracker separately notes where your attention went. When the two disagree, you see that side by side in the Calendar and decide what happened, usually with one drag from the activity record into your entries.

The app is built around a few decisions that follow from this.

Starting must take no thought. The Timer, the Mini Timer, the menu bar, a global keyboard shortcut, a Home Screen widget, Siri, and the command line all start and stop the same entry. Typing a task and pressing Return is enough; a project can follow later, and so can a correction.

The running entry is one thing across all your devices. Start it on the Mac, and your iPhone's widget shows it within seconds. Stop it on the iPhone, and the menu bar on the Mac stops counting. At most one entry runs at a time, anywhere, so you never have to wonder which device holds the truth.

Repairing the past is a normal activity. The Calendar lets you draw, move, resize, split, and duplicate entries, so a forgotten stop or a missed meeting costs seconds. Overlaps are allowed once you confirm them, because what actually happened is sometimes messy.

Plans belong next to the record. A time block is an event in an ordinary iCloud calendar, so a plan reaches every device and calendar app without any special sync. The app shows it beside your entries and draws no conclusions: there is no score and no "done" state, because a plan you didn't follow isn't a failure to be reported.

Your data is yours. Everything lives in the private iCloud database of your own account, and there is no server, account, or web service in between. The JSON export and the command-line tool give you all of it, and scripts may read the database directly. The tracker's samples stay on the Mac that recorded them, and [you decide what it records at all](privacy.md).

The app targets one person. There are no teams, invoices, or approvals. "Client" means who the work is for, which may just as well be your household as a paying customer.

It is also deliberately limited to current Apple platforms, macOS 27 and iOS 27. It looks and behaves like an app Apple might have made, with system controls, a menu command for every action, and a keyboard shortcut for every frequent one.
