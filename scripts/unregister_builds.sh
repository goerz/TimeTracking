#!/bin/sh
# Unregisters from LaunchServices every copy of the apps whose bundle
# identifier starts with BUNDLE_ID, except the installed one
# (architecture.md §2.5, build-mac). Build products in build.noindex/
# and Xcode's DerivedData otherwise compete with the installed app for URL
# schemes, login items, and "Open With".
#
#   scripts/unregister_builds.sh <BUNDLE_ID> <installed app path>
set -eu
# shellcheck source=scripts/common.sh
. "$(dirname "$0")/common.sh"

bundle_id="$1"
installed="$2"

"$lsregister" -dump 2>/dev/null | awk -v id="$bundle_id" '
    /^-+$/ { if (path != "" && match_id) print path; path = ""; match_id = 0; next }
    /^path:/ { sub(/^path: +/, ""); sub(/ \(0x[0-9a-f]+\)$/, ""); path = $0; next }
    /^identifier:/ { sub(/^identifier: +/, ""); if ($0 == id || index($0, id ".") == 1) match_id = 1; next }
    END { if (path != "" && match_id) print path }
' | sort -u | while IFS= read -r path; do
    case "$path" in
    "$installed" | "$installed"/*) continue ;;
    esac
    "$lsregister" -u "$path" 2>/dev/null || true
    echo "Unregistered $path"
done
