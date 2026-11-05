#!/bin/sh
# Verifies Release products after `make build-mac` / `make build-ios`
# (architecture.md §1.4, §2.2, §2.3, ARCH-4, ARCH-5, ARCH-24). Exits
# non-zero on any violation and lists them all.
#
#   scripts/check_products.sh mac <APP_NAME>.app <BUNDLE_ID> <TEAM>
#   scripts/check_products.sh ios <APP_NAME>.app <BUNDLE_ID> <TEAM>
#
# The expected entitlements are the files Config/<target>.entitlements with
# the identifiers of the Release identity substituted. Entitlements the
# provisioning profile adds by itself (application identifier, team
# identifier, and on iOS the development get-task-allow) are ignored.
set -u

platform="$1"
app="$2"
bundle_id="$3"
team="$4"
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/check_products.XXXXXX")
trap 'rm -rf "$work"' EXIT
failures=0

fail() {
    echo "check_products: $*" >&2
    failures=$((failures + 1))
}

case "$platform" in
mac) group="$team.$bundle_id" ;;
ios) group="group.$bundle_id" ;;
*) echo "usage: $0 mac|ios <app> <BUNDLE_ID> <TEAM>" >&2; exit 64 ;;
esac
container="iCloud.$bundle_id"

# Prints the top-level keys of a plist, one per line, sorted.
keys() {
    /usr/libexec/PlistBuddy -c Print "$1" 2>/dev/null | sed -n 's/^    \([^ ][^=]*\) = .*/\1/p' | sort
}

# check_entitlements <binary or bundle> <target name>
check_entitlements() {
    product="$1"
    target="$2"
    actual="$work/$target.actual.plist"
    expected="$work/$target.expected.plist"
    if ! codesign -d --entitlements - --xml "$product" > "$actual" 2>/dev/null || [ ! -s "$actual" ]; then
        printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict/></plist>\n' > "$actual"
    fi
    sed -e "s/\$(TT_APP_GROUP)/$group/g" -e "s/\$(TT_CLOUDKIT_CONTAINER)/$container/g" \
        "$root/Config/$target.entitlements" > "$expected"
    # plutil key paths split at dots, so entitlement keys go through PlistBuddy.
    for key in com.apple.application-identifier application-identifier com.apple.developer.team-identifier; do
        /usr/libexec/PlistBuddy -c "Delete :$key" "$actual" >/dev/null 2>&1 || true
    done
    if [ "$platform" = mac ]; then
        for key in $(keys "$actual" | grep -E '^(com\.apple\.security\.)?get-task-allow$|^com\.apple\.security\.cs\.'); do
            fail "$target carries $key"
        done
    else
        /usr/libexec/PlistBuddy -c "Delete :get-task-allow" "$actual" >/dev/null 2>&1 || true
    fi
    plutil -convert xml1 "$actual"
    plutil -convert xml1 "$expected"
    if ! cmp -s "$actual" "$expected"; then
        fail "$target entitlements differ from Config/$target.entitlements:"
        diff "$expected" "$actual" | sed 's/^/    /' >&2
    fi
}

# check_signature <binary or bundle> <target name>
check_signature() {
    product="$1"
    target="$2"
    if ! codesign --verify --strict "$product" 2>/dev/null; then
        fail "$target: signature does not verify"
        return
    fi
    info=$(codesign -dv "$product" 2>&1)
    case "$info" in
    *"TeamIdentifier=$team"*) ;;
    *) fail "$target is not signed by team $team" ;;
    esac
    if [ "$platform" = mac ]; then
        case "$info" in
        *"(runtime)"*) ;;
        *) fail "$target lacks the hardened runtime" ;;
        esac
    fi
}

# bundle_id_of <bundle>
bundle_id_of() {
    plutil -extract CFBundleIdentifier raw "$1/$2" 2>/dev/null
}

# check_release_names <bundle> <Info.plist path in the bundle> <target name>:
# Debug bundles carry "Debug" in their file and display names (§2.2,
# ARCH-24), Release bundles never do.
check_release_names() {
    case "$(basename "$1")" in
    *Debug*) fail "$3 bundle file name $(basename "$1") contains Debug" ;;
    esac
    for key in CFBundleName CFBundleDisplayName; do
        case "$(plutil -extract "$key" raw "$1/$2" 2>/dev/null)" in
        *Debug*) fail "$3 $key contains Debug" ;;
        esac
    done
}

[ -d "$app" ] || { echo "check_products: no product at $app" >&2; exit 1; }

if [ "$platform" = mac ]; then
    agent="$app/Contents/Library/LoginItems/TimeTrackingAgent.app"
    cli="$app/Contents/Helpers/timetracking"
    event="$app/Contents/Helpers/tracker-event"
    plist="$app/Contents/Library/LaunchAgents/$bundle_id.agent.plist"
    program="Contents/Library/LoginItems/TimeTrackingAgent.app/Contents/MacOS/TimeTrackingAgent"

    [ -d "$agent" ] || fail "missing $agent"
    [ -x "$cli" ] || fail "missing $cli"
    [ -x "$event" ] || fail "missing $event"
    [ ! -e "$app/Contents/Frameworks" ] || fail "$app/Contents/Frameworks exists (the package must link statically)"
    [ "$(bundle_id_of "$app" Contents/Info.plist)" = "$bundle_id" ] || fail "app bundle identifier is not $bundle_id"
    [ "$(bundle_id_of "$agent" Contents/Info.plist)" = "$bundle_id.agent" ] || fail "agent bundle identifier is not $bundle_id.agent"
    check_release_names "$app" Contents/Info.plist TimeTracking
    check_release_names "$agent" Contents/Info.plist TimeTrackingAgent

    if [ -f "$plist" ]; then
        [ "$(plutil -extract Label raw "$plist" 2>/dev/null)" = "$bundle_id.agent" ] || fail "launchd Label is not $bundle_id.agent"
        [ "$(plutil -extract BundleProgram raw "$plist" 2>/dev/null)" = "$program" ] || fail "launchd BundleProgram is not $program"
        [ -x "$app/$program" ] || fail "launchd BundleProgram $program is not an executable in the app"
        [ "$(plutil -extract AssociatedBundleIdentifiers.0 raw "$plist" 2>/dev/null)" = "$bundle_id" ] \
            || fail "launchd AssociatedBundleIdentifiers does not name $bundle_id"
        [ "$(plutil -extract KeepAlive raw "$plist" 2>/dev/null)" = true ] || fail "launchd KeepAlive is not true"
        [ "$(plutil -extract ProcessType raw "$plist" 2>/dev/null)" = Background ] || fail "launchd ProcessType is not Background"
        /usr/libexec/PlistBuddy -c "Print :MachServices:$bundle_id.agent" "$plist" >/dev/null 2>&1 \
            || fail "launchd MachServices lacks $bundle_id.agent"
    else
        fail "missing launchd plist $plist"
    fi
    [ "$(ls "$app/Contents/Library/LaunchAgents" 2>/dev/null | wc -l | tr -d ' ')" = 1 ] \
        || fail "Contents/Library/LaunchAgents must hold exactly one plist"

    for pair in "$app:TimeTracking" "$agent:TimeTrackingAgent" "$cli:TimeTrackingCLI" "$event:TrackerEvent"; do
        product="${pair%:*}"
        target="${pair##*:}"
        [ -e "$product" ] || continue
        check_signature "$product" "$target"
        check_entitlements "$product" "$target"
    done
else
    [ "$(bundle_id_of "$app" Info.plist)" = "$bundle_id" ] || fail "iOS app bundle identifier is not $bundle_id"
    check_release_names "$app" Info.plist TimeTrackingiOS
    [ ! -e "$app/Frameworks/TimeTrackingCore.framework" ] || fail "TimeTrackingCore is embedded as a framework"
    check_signature "$app" TimeTrackingiOS
    check_entitlements "$app" TimeTrackingiOS
    for pair in PlugIns/TimeTrackingWidgets.appex:TimeTrackingWidgets:widgets \
        Extensions/TimeTrackingIntents.appex:TimeTrackingIntents:intents \
        PlugIns/TimeTrackingMonitor.appex:TimeTrackingMonitor:monitor \
        PlugIns/TimeTrackingWebExtension.appex:TimeTrackingWebExtension:web-extension; do
        path="$app/${pair%%:*}"
        rest="${pair#*:}"
        target="${rest%%:*}"
        suffix="${rest#*:}"
        if [ ! -d "$path" ]; then
            fail "missing $path"
            continue
        fi
        [ "$(bundle_id_of "$path" Info.plist)" = "$bundle_id.$suffix" ] || fail "$target bundle identifier is not $bundle_id.$suffix"
        check_signature "$path" "$target"
        check_entitlements "$path" "$target"
    done
fi

if find "$app" -name Info.plist -exec plutil -extract CFBundleIdentifier raw {} \; 2>/dev/null | grep -q '\.debug'; then
    fail "a Release bundle identifier contains .debug"
fi

if [ "$failures" -gt 0 ]; then
    echo "check_products: $failures violation(s) in $app" >&2
    exit 1
fi
echo "check_products: $app passed"
