# TimeTracking

[![Source code on GitHub](https://img.shields.io/badge/goerz-TimeTracking-blue.svg?logo=github)](https://github.com/goerz/TimeTracking)
[![Documentation build](https://github.com/goerz/TimeTracking/actions/workflows/docs.yml/badge.svg?branch=master)](https://github.com/goerz/TimeTracking/actions/workflows/docs.yml)
[![Library tests](https://github.com/goerz/TimeTracking/actions/workflows/test.yml/badge.svg?branch=master)](https://github.com/goerz/TimeTracking/actions/workflows/test.yml)
[![GPL v3 License](https://img.shields.io/badge/License-GPLv3-green.svg)](https://github.com/goerz/TimeTracking/blob/master/LICENSE)

TimeTracking is a personal time tracker for the Mac, iPhone, and iPad. You say what you are working on and press start; the app records a time entry, shows it on every device within seconds, and later tells you where the week went. Next to that record of what you said you did, an optional background tracker keeps a separate record of where your attention actually was, so filling the gaps at the end of the day takes a drag instead of a guess.

```{figure} /images/mac-desktop.png
:alt: A Mac desktop with the Calendar open, the Mini Timer beside it, and the status menu open under the running time in the menu bar. The Calendar shows days side by side, each with a column of recorded activity, a column of colored time entries, and a column of plans.

The Calendar on the Mac, with the Mini Timer beside it and the status menu open under the running time.
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
