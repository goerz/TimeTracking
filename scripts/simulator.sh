#!/bin/bash
# The simulators by name, for the Makefile and scripts/demo.sh (architecture.md §2.6).
#
#   scripts/simulator.sh udid <name>       prints the UDID of the available simulator <name>
#   scripts/simulator.sh show <name>...    shows each simulator in Device Hub
#
# Everything addresses "TimeTracking iPhone" and "TimeTracking iPad" by name and
# resolves the UDID here, at run time, so no UDID is ever committed. The tools
# themselves need the UDID: an xcodebuild destination with `name=` implies
# `OS=latest` (the newest iOS of the selected Xcode) and misses a device on an
# older runtime, and simctl documents only UDIDs. See docs/xcode27.md.
set -eu

developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"

# `simctl list devices available` prints "    <name> (<UDID>) (<state>)" under
# one "-- <runtime> --" heading per runtime, oldest first; with the same name
# on several runtimes, the device on the newest one wins.
udid() {
    local found
    found=$(xcrun simctl list devices available | awk -v name="$1" '
        BEGIN { prefix = "    " name " (" }
        index($0, prefix) == 1 {
            rest = substr($0, length(prefix) + 1)
            if (rest ~ /^[0-9A-F-]+\) \(/) { sub(/\).*/, "", rest); found = rest }
        }
        END { print found }')
    if [ -z "$found" ]; then
        echo "no available simulator named \"$1\" (make sim-create creates it)" >&2
        return 1
    fi
    echo "$found"
}

# Xcode 27 has no Simulator.app: Device Hub shows a device for the URL
# devices://device/open?id=<UDID>. Older Xcodes still have Simulator.app.
show() {
    local hub="$developer_dir/../Applications/DeviceHub.app" name id
    if [ -d "$hub" ]; then
        for name in "$@"; do
            id=$(udid "$name")
            open -a "$hub" "devices://device/open?id=$id"
        done
    elif ! open -a Simulator 2> /dev/null; then
        echo "Neither Device Hub nor Simulator.app found; the simulators run without a window (make sim-screenshots captures them)."
    fi
}

case "${1-}" in
udid)
    [ "$#" = 2 ] || { echo "usage: $0 udid <name>" >&2; exit 64; }
    udid "$2"
    ;;
show)
    shift
    show "$@"
    ;;
*)
    echo "usage: $0 udid <name> | show <name>..." >&2
    exit 64
    ;;
esac
