#!/bin/bash
# `make mac-debug` (architecture.md §2.5): quits every running copy of
# the app's bundle identifier, from any checkout, and opens the given build,
# so the app that runs is the one just built.
#
# Usage: relaunch_mac_app.sh <app path> <bundle id> [launch arguments...]
set -eu
app=$1
bundle_id=$2
shift 2

# running [terminate]: the number of running copies; with "terminate", each
# is asked to quit first (as Quit in its menu would).
running() {
    osascript -l JavaScript -e "ObjC.import('AppKit');
        const apps = \$.NSRunningApplication.runningApplicationsWithBundleIdentifier('$bundle_id');
        if ('${1:-}' === 'terminate') { for (let i = 0; i < apps.count; i++) { apps.objectAtIndex(i).terminate; } }
        apps.count" 2>/dev/null || echo 0
}

if [ "$(running terminate)" != 0 ]; then
    for _ in $(seq 100); do
        [ "$(running)" = 0 ] && break
        sleep 0.1
    done
    if [ "$(running)" != 0 ]; then
        echo "$bundle_id did not quit within 10 seconds (an open sheet or alert?); quit it and retry" >&2
        exit 1
    fi
fi
# `open` starts the app without this environment, so a fixed clock goes along.
if [ -n "${TIMETRACKING_NOW:-}" ]; then
    open --env "TIMETRACKING_NOW=$TIMETRACKING_NOW" "$app" --args "$@"
else
    open "$app" --args "$@"
fi
