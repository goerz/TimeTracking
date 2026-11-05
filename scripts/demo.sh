#!/bin/bash
# The seeding and launching part of `make demo` (architecture.md §2.5, ARCH-23).
#
#   scripts/demo.sh <fixture> <Debug Mac app> <Debug support folder> <Debug app id> <simulator app> [<simulator>...]
#
# Quits the Debug Mac app of this build, replaces the Debug store and the
# block log in its Activity folder with Fixtures/Store/<fixture>.json moved
# to today (the package's DemoStore tool, which refuses any store outside a
# Debug or simulator container), and opens the app. Then, on each named
# simulator (scripts/simulator.sh resolves the name): boots it, installs the
# app, replaces the app's own store the same way (no block log), launches it,
# and shows it in Device Hub. The simulators do not wait for
# CloudKit; records that exist only in the Debug CloudKit zone still sync
# back once the apps are online.
set -eu

[ "$#" -ge 5 ] || { echo "usage: $0 <fixture> <mac app> <support folder> <app id> <simulator app> [<simulator>...]" >&2; exit 64; }
fixture="$1" mac_app="$2" support="$3" app_id="$4" sim_app="$5"
shift 5
root=$(cd "$(dirname "$0")/.." && pwd)

seed() {
    swift run --quiet --package-path "$root/Packages/TimeTrackingCore" DemoStore "$fixture" "$@"
}

# Quits the Debug app started from this build (not other copies) and waits.
quit_debug_app() {
    local executable pid
    executable="$(cd "$mac_app" && pwd)/Contents/MacOS/"
    for pid in $(pgrep -f "^$executable" || true); do
        osascript -l JavaScript -e "ObjC.import('AppKit'); \$.NSRunningApplication.runningApplicationWithProcessIdentifier($pid).terminate" \
            >/dev/null 2>&1 || kill "$pid" 2>/dev/null || true
    done
    for _ in $(seq 50); do
        pgrep -f "^$executable" >/dev/null || return 0
        sleep 0.1
    done
    pkill -f "^$executable" || true
}

swift build --quiet --package-path "$root/Packages/TimeTrackingCore" --product DemoStore

quit_debug_app
holders=$(lsof -t "$support/store.sqlite" "$support/store.sqlite-wal" 2>/dev/null | sort -u | tr '\n' ' ' || true)
if [ -n "$holders" ]; then
    echo "The Debug store is open in process $holders; quit it first." >&2
    exit 1
fi
seed "$support/store.sqlite" "$support/Activity"
open "$mac_app"

for name in "$@"; do
    udid=$("$root/scripts/simulator.sh" udid "$name")
    xcrun simctl bootstatus "$udid" -b >/dev/null
    xcrun simctl install "$udid" "$sim_app"
    xcrun simctl terminate "$udid" "$app_id" 2>/dev/null || true
    group=$(xcrun simctl get_app_container "$udid" "$app_id" "group.$app_id")
    seed "$group/Library/Application Support/TimeTracking/store.sqlite"
    xcrun simctl launch "$udid" "$app_id" >/dev/null
done
[ "$#" = 0 ] || "$root/scripts/simulator.sh" show "$@"
