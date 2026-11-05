# TimeTracking

TimeTracking is a personal time tracker for the Mac, iPhone, and iPad. You say what you are working on and press start; the app records a time entry, shows it on every device within seconds, and later tells you where the week went. Next to that record of what you said you did, an optional background tracker keeps a separate record of where your attention actually was, so filling the gaps at the end of the day takes a drag instead of a guess.

```{figure} /images/mac-calendar.png
:alt: The Calendar section of the Mac app, showing several days side by side, each with a column of recorded activity, a column of colored time entries, and a column of plans.

The Calendar on the Mac: recorded activity, tracked entries, and plans on one time axis.
```

All data stays in your own iCloud account. There is no server, no web app, and no team feature. The apps are built from source and installed with a Makefile, so using TimeTracking takes Xcode and an Apple Developer Program membership.

::::{grid} 1 1 2 2
:gutter: 3

:::{grid-item-card} Tutorials
:link: tutorials/index
:link-type: doc

Install the app and track your first day, step by step.
:::

:::{grid-item-card} How-to guides
:link: howto/index
:link-type: doc

Short recipes for a goal you already have: correct an entry, plan a day, export a report, script the app.
:::

:::{grid-item-card} Explanation
:link: explanation/index
:link-type: doc

Why the app exists, how its ideas fit together, and a tour of every view.
:::

:::{grid-item-card} Reference
:link: reference/index
:link-type: doc

The specifications: the exact behavior of every component, which the code is tested against.
:::
::::

```{toctree}
:hidden:

tutorials/index
howto/index
explanation/index
reference/index
```
