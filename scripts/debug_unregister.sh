#!/bin/sh
# `make mac-debug-unregister` (architecture.md §2.5): quits the Debug app
# and agent, runs the Debug agent's --unregister, resets its TCC grants, and
# unregisters the Debug agent bundles from LaunchServices.
#
#   scripts/debug_unregister.sh <Debug app id> <agent> <legacy agent> [<bundle>...]
#
# The --unregister runs from the first of <agent> and <legacy agent> that is
# built. Every given bundle that exists is unregistered from LaunchServices.
# LAUNCHCTL overrides launchctl (scripts/test_make.sh).
set -eu
# shellcheck source=scripts/common.sh
. "$(dirname "$0")/common.sh"

app_id="$1"
agent="$2"
legacy_agent="$3"
shift 3
launchctl="${LAUNCHCTL:-launchctl}"

for candidate in "$agent" "$legacy_agent"; do
    if [ -x "$candidate/Contents/MacOS/TimeTrackingAgent" ]; then
        "$candidate/Contents/MacOS/TimeTrackingAgent" --unregister || true
        break
    fi
done
quit_app "$app_id"
"$launchctl" bootout "gui/$(id -u)/$app_id.agent" >/dev/null 2>&1 || true
for service in Accessibility AppleEvents SystemPolicyAllFiles; do
    tccutil reset "$service" "$app_id.agent" >/dev/null 2>&1 || true
done
for bundle in "$agent" "$legacy_agent" "$@"; do
    [ ! -d "$bundle" ] || "$lsregister" -u "$bundle" 2>/dev/null || true
done
echo "The Debug agent is unregistered."
