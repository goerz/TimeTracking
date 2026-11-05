# TimeTracking

A personal time tracker for the Mac, iPhone, and iPad. It records time entries (client, area, project, task), keeps the running entry in sync across devices within seconds, plans the day next to the calendar, reports on tracked time, and keeps a separate record of where attention went on each device.

The apps are built from source and development-signed; there is no App Store or TestFlight distribution.

## Requirements

- macOS 27 and Xcode 27 at `/Applications/Xcode.app`
- A paid Apple Developer Program membership, signed in to Xcode
- iOS 27 simulator runtime for the simulator targets

## Getting started

```sh
cp local.mk.example local.mk   # set TEAM, BUNDLE_ID, APP_NAME
make install                   # build, check, and install into /Applications
timetracking --version         # the tool, linked into $(PREFIX)/bin
```

`make help` lists all targets: `make sim` runs the iOS app on the simulators, `make iphone` installs it on a device named in `local.mk`, `make test` runs the test suite, and `make check` runs lint, the behavior check, and the personal-data check.

## Documentation

The specifications in `docs/reference/` describe the product: start with `docs/reference/components.md`. `CLAUDE.md` summarizes the project conventions.
