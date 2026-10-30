#!/bin/sh
# `make lint`: SwiftFormat --lint and SwiftLint lint --strict from the package
# checkouts, without building the project (spec_architecture.md §4.3, ARCH-15).
#
#   scripts/lint.sh [<derived data folder>]
#
# LINT_PATHS overrides the checked folders (see scripts/lint_paths.sh).
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
derived="${1:-$root/build.noindex}"
case "$derived" in /*) ;; *) derived="$root/$derived" ;; esac
packages="$derived/SourcePackages"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [ ! -d "$packages/checkouts/SwiftFormat" ] || [ ! -d "$packages/artifacts" ]; then
    echo "Resolving packages into $packages..." >&2
    xcodebuild -quiet -resolvePackageDependencies -project "$root/TimeTracking.xcodeproj" -scheme TimeTracking \
        -derivedDataPath "$derived" -skipPackagePluginValidation -skipMacroValidation >&2 || exit 1
fi
swiftformat=$("$root/scripts/lint_tools.sh" swiftformat "$packages") || exit 1
swiftlint=$("$root/scripts/lint_tools.sh" swiftlint "$packages") || exit 1
. "$root/scripts/lint_paths.sh"

cd "$root" || exit 1
status=0
# shellcheck disable=SC2086
"$swiftformat" --lint --quiet --config .swiftformat $LINT_PATHS || status=1
# shellcheck disable=SC2086
"$swiftlint" lint --strict --quiet --config .swiftlint.yml $LINT_PATHS || status=1
[ "$status" = 0 ] && echo "lint: clean"
exit "$status"
