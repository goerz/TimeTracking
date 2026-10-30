#!/bin/bash
# Tests of the Makefile, the scripts, and the hooks (spec_architecture.md §3.1, §8).
#
#   scripts/test_make.sh [--build] [--products] [--sim] [--install] [--all]
#
# Without options it runs the fast tests (about a minute): Local.xcconfig
# writing, the TEAM guard, identifiers, help, check-behaviors, apns-key
# against a temporary keychain, clean and distclean, lint, and the
# pre-commit hook. Most run `make` in a sandbox copy of the repository with
# a synthetic local.mk, so nothing personal or built is touched.
#   --build     a compiler warning fails the build (ARCH-15; ~30 s); swift test
#               in a copy without local.mk and without network (ARCH-1; ~3 min)
#   --products  checks of the Release products (ARCH-4, ARCH-5; needs make build-mac build-ios)
#               and the Debug products' names (ARCH-24; also needs make mac-debug build-sim)
#   --sim       recreates the two simulators (ARCH-18; ~1 min)
#   --install   make install / uninstall into a temporary PREFIX (ARCH-20; needs TEAM; reinstalls)
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/test_make.XXXXXX")
probes="$root/TimeTrackingCLI/ZZWarningProbe.swift $root/Packages/TimeTrackingCore/Sources/TimeTrackingCore/Support/ZZWarningProbe.swift"
# shellcheck disable=SC2086
trap 'rm -rf "$scratch"; rm -f $probes' EXIT

run_build=0 run_products=0 run_sim=0 run_install=0
for arg in "$@"; do
    case "$arg" in
    --build) run_build=1 ;;
    --products) run_products=1 ;;
    --sim) run_sim=1 ;;
    --install) run_install=1 ;;
    --all) run_build=1 run_products=1 run_sim=1 run_install=1 ;;
    *) echo "usage: $0 [--build] [--products] [--sim] [--install] [--all]" >&2; exit 64 ;;
    esac
done

passed=0
failed=0
failures=()

# behavior "<ID> <description>" <function>: runs one test.
behavior() {
    local name="$1" function="$2" log="$scratch/log.$((passed + failed))" status
    # Not inside `if`: set -e is ignored in a condition, also in subshells.
    ( set -e; "$function" ) > "$log" 2>&1
    status=$?
    if [ "$status" = 0 ]; then
        passed=$((passed + 1))
        echo "✔ $name"
    else
        failed=$((failed + 1))
        failures+=("$name")
        echo "✘ $name"
        sed 's/^/    /' "$log"
    fi
}

not() {
    ! "$@"
}

check() {
    # check <description> <command...>: fails the test with the description.
    local description="$1"
    shift
    if ! "$@"; then
        echo "failed: $description"
        return 1
    fi
}

# A copy of the repository's build machinery with a synthetic local.mk.
sandbox() {
    local dir
    dir=$(mktemp -d "$scratch/sandbox.XXXXXX")
    cp "$root/Makefile" "$root/.gitignore" "$dir/"
    mkdir -p "$dir/Config" "$dir/spec"
    cp "$root"/Config/*.entitlements "$root"/Config/*.plist "$root/Config/Project.xcconfig" "$dir/Config/"
    cp -R "$root/scripts" "$root/.githooks" "$dir/"
    rm "$dir/scripts/test_make.sh"
    cat > "$dir/local.mk" <<EOF
TEAM = ${1-TESTTEAM01}
BUNDLE_ID = com.example.test
APP_NAME = Test
EOF
    git -C "$dir" init -q
    git -C "$dir" config user.name Test
    git -C "$dir" config user.email test@example.com
    echo "$dir"
}

fake_tool() {
    # fake_tool <name> <exit status>: a command that records its call.
    local bin="$scratch/bin"
    mkdir -p "$bin"
    printf '#!/bin/sh\necho "$0 $*" >> "%s/calls"\nexit %s\n' "$scratch" "$2" > "$bin/$1"
    chmod +x "$bin/$1"
    echo "$bin/$1"
}

# --- ARCH-2

test_secrets() {
    local sb before after
    sb=$(sandbox)
    make -C "$sb" --no-print-directory secrets
    check "Local.xcconfig has TT_BUNDLE_ID" grep -qx 'TT_BUNDLE_ID = com.example.test' "$sb/Config/Local.xcconfig"
    check "Local.xcconfig has TT_APP_NAME" grep -qx 'TT_APP_NAME = Test' "$sb/Config/Local.xcconfig"
    check "Local.xcconfig has DEVELOPMENT_TEAM" grep -qx 'DEVELOPMENT_TEAM = TESTTEAM01' "$sb/Config/Local.xcconfig"
    before=$(stat -f %Fm "$sb/Config/Local.xcconfig")
    make -C "$sb" --no-print-directory secrets
    after=$(stat -f %Fm "$sb/Config/Local.xcconfig")
    check "a second run leaves the modification time unchanged" [ "$before" = "$after" ]
    sed -i '' 's/^APP_NAME = Test$/APP_NAME = Other/' "$sb/local.mk"
    make -C "$sb" --no-print-directory secrets
    check "a change rewrites the file" grep -qx 'TT_APP_NAME = Other' "$sb/Config/Local.xcconfig"
    check "make secrets sets the hooks path" [ "$(git -C "$sb" config core.hooksPath)" = .githooks ]
}

# --- ARCH-3

test_team_guard() {
    local sb fake target output
    sb=$(sandbox "")
    fake=$(fake_tool xcodebuild 0)
    for target in build-mac build-ios sim demo install "device D=x"; do
        rm -f "$scratch/calls"
        # shellcheck disable=SC2086
        if output=$(make -C "$sb" --no-print-directory XCODEBUILD="$fake" $target 2>&1); then
            echo "make $target succeeded without TEAM"
            return 1
        fi
        check "make $target says set TEAM in local.mk" grep -q 'set TEAM in local.mk' <<< "$output"
        check "make $target did not call xcodebuild" [ ! -e "$scratch/calls" ]
    done
}

# --- ARCH-6, ARCH-7

# build_settings <configuration> <overrides...>: "target<TAB>setting = value" lines.
build_settings() {
    local configuration="$1"
    shift
    xcodebuild -showBuildSettings -alltargets -project "$root/TimeTracking.xcodeproj" -configuration "$configuration" \
        TT_BUNDLE_ID=com.example.test DEVELOPMENT_TEAM=TESTTEAM01 "$@" 2>/dev/null \
        | awk '/^Build settings for action build and target / { target = $NF; sub(/:$/, "", target); next }
               /^    [A-Z_]+ = / { sub(/^    /, ""); print target "\t" $0 }'
}

# settings <configuration> [<APP_NAME>]: the file of build_settings with
# TT_APP_NAME (default Test); each query runs once per suite run.
settings() {
    local file="$scratch/settings.$1.${2:-Test}"
    [ -s "$file" ] || build_settings "$1" TT_APP_NAME="${2:-Test}" > "$file"
    echo "$file"
}

setting() {
    # setting <file> <target> <name>
    awk -F '\t' -v t="$2" -v n="$3 = " '$1 == t && index($2, n) == 1 { print substr($2, length(n) + 1); exit }' "$1"
}

test_debug_identifiers() {
    local debug release
    debug=$(settings Debug)
    release=$(settings Release)
    check "Debug app id" [ "$(setting "$debug" TimeTracking PRODUCT_BUNDLE_IDENTIFIER)" = com.example.test.debug ]
    check "Debug iOS app id" [ "$(setting "$debug" TimeTrackingiOS PRODUCT_BUNDLE_IDENTIFIER)" = com.example.test.debug ]
    check "Debug agent id" [ "$(setting "$debug" TimeTrackingAgent PRODUCT_BUNDLE_IDENTIFIER)" = com.example.test.debug.agent ]
    check "Debug iOS App Group" [ "$(setting "$debug" TimeTrackingiOS TT_APP_GROUP)" = group.com.example.test.debug ]
    check "Debug Mac App Group" [ "$(setting "$debug" TimeTracking TT_APP_GROUP)" = TESTTEAM01.com.example.test.debug ]
    check "Debug CloudKit container" [ "$(setting "$debug" TimeTracking TT_CLOUDKIT_CONTAINER)" = iCloud.com.example.test.debug ]
    check "Debug URL scheme" [ "$(setting "$debug" TimeTracking TT_URL_SCHEME)" = timetracking-debug ]
    check "Release app id" [ "$(setting "$release" TimeTracking PRODUCT_BUNDLE_IDENTIFIER)" = com.example.test ]
    check "Release URL scheme" [ "$(setting "$release" TimeTracking TT_URL_SCHEME)" = timetracking ]
    if grep -E $'\t(PRODUCT_BUNDLE_IDENTIFIER|TT_APP_ID|TT_APP_GROUP|TT_CLOUDKIT_CONTAINER|TT_URL_SCHEME) = .*debug' "$release"; then
        echo "a Release identifier contains debug"
        return 1
    fi
}

test_app_name() {
    local base renamed target name
    base=$(settings Debug)
    renamed=$(settings Debug Renamed)
    check "the Debug Mac bundle is Renamed Debug.app" [ "$(setting "$renamed" TimeTracking FULL_PRODUCT_NAME)" = "Renamed Debug.app" ]
    check "the iOS bundle is Renamed.app" [ "$(setting "$renamed" TimeTrackingiOS FULL_PRODUCT_NAME)" = Renamed.app ]
    for target in TimeTracking TimeTrackingiOS; do
        check "$target display name" [ "$(setting "$renamed" $target TT_DISPLAY_NAME)" = "Renamed Debug" ]
        for name in PRODUCT_MODULE_NAME EXECUTABLE_NAME PRODUCT_BUNDLE_IDENTIFIER; do
            check "$target $name unchanged" [ "$(setting "$renamed" $target $name)" = "$(setting "$base" $target $name)" ]
        done
        check "$target Info.plist uses the display name" grep -q '\$(TT_DISPLAY_NAME)' "$root/Config/$target-Info.plist"
    done
    check "module name" [ "$(setting "$renamed" TimeTracking PRODUCT_MODULE_NAME)" = TimeTracking ]
    check "executable name" [ "$(setting "$renamed" TimeTrackingiOS EXECUTABLE_NAME)" = TimeTrackingiOS ]
    for target in TimeTrackingAgent TimeTrackingCLI TrackerEvent TimeTrackingWidgets; do
        check "$target product name unchanged" \
            [ "$(setting "$renamed" $target FULL_PRODUCT_NAME)" = "$(setting "$base" $target FULL_PRODUCT_NAME)" ]
    done
}

# --- ARCH-24

display_name_is_setting() {
    grep -A1 CFBundleDisplayName "$1" | grep -qE '\$\((TT_DISPLAY_NAME|TT_AGENT_NAME)\)'
}

# Debug Mac bundles carry " Debug" in their file names, all Debug bundles in
# their display names; no Release name contains Debug.
test_debug_names() {
    local debug release target plist
    debug=$(settings Debug)
    release=$(settings Release)
    check "Debug Mac app file name" [ "$(setting "$debug" TimeTracking FULL_PRODUCT_NAME)" = "Test Debug.app" ]
    check "Debug agent file name" [ "$(setting "$debug" TimeTrackingAgent FULL_PRODUCT_NAME)" = "TimeTrackingAgent Debug.app" ]
    check "Debug agent name" [ "$(setting "$debug" TimeTrackingAgent TT_AGENT_NAME)" = "TimeTrackingAgent Debug" ]
    check "Release Mac app file name" [ "$(setting "$release" TimeTracking FULL_PRODUCT_NAME)" = Test.app ]
    check "Release agent file name" [ "$(setting "$release" TimeTrackingAgent FULL_PRODUCT_NAME)" = TimeTrackingAgent.app ]
    for target in TimeTracking TimeTrackingAgent; do
        check "$target Debug executable unchanged" \
            [ "$(setting "$debug" $target EXECUTABLE_NAME)" = "$(setting "$release" $target EXECUTABLE_NAME)" ]
    done
    for target in TimeTracking TimeTrackingiOS TimeTrackingWidgets TimeTrackingIntents TimeTrackingMonitor TimeTrackingWebExtension; do
        check "$target Debug display name" [ "$(setting "$debug" $target TT_DISPLAY_NAME)" = "Test Debug" ]
    done
    check "the agent's Info.plist names come from TT_AGENT_NAME" \
        [ "$(grep -c '<string>$(TT_AGENT_NAME)</string>' "$root/Config/TimeTrackingAgent-Info.plist")" = 2 ]
    for plist in "$root"/Config/*-Info.plist; do
        if grep -q CFBundleDisplayName "$plist"; then
            check "$(basename "$plist") display name is a Debug-aware setting" display_name_is_setting "$plist"
        fi
    done
    if grep -E $'\t(FULL_PRODUCT_NAME|TT_DISPLAY_NAME|TT_AGENT_NAME|TT_MAC_APP_NAME) = .*Debug' "$release"; then
        echo "a Release name contains Debug"
        return 1
    fi
}

# --- ARCH-9, ARCH-10

# A temporary keychain; `security create-keychain` leaves the search list alone.
keychain=""
make_keychain() {
    keychain="$scratch/test.keychain-db"
    security create-keychain -p test "$keychain"
    security unlock-keychain -p test "$keychain"
}

drop_keychain() {
    [ -z "$keychain" ] || security delete-keychain "$keychain" 2>/dev/null
    keychain=""
}

item_count() {
    security dump-keychain "$keychain" 2>/dev/null | grep -c '"svce"<blob>="com.example.test.apns"' || true
}

test_apns_key() {
    local sb dir secret
    sb=$(sandbox)
    dir="$scratch/keys"
    mkdir -p "$dir"
    openssl ecparam -name prime256v1 -genkey -noout 2>/dev/null | openssl pkcs8 -topk8 -nocrypt -out "$dir/AuthKey_ABC123DEFG.p8"
    make_keychain
    make -C "$sb" --no-print-directory apns-key P8="$dir/AuthKey_ABC123DEFG.p8" KEYCHAIN="$keychain" > "$scratch/apns.out" 2>&1
    check "the output never shows the key" not grep -q 'PRIVATE KEY' "$scratch/apns.out"
    check "one item" [ "$(item_count)" = 1 ]
    security find-generic-password -s com.example.test.apns -a ABC123DEFG -w "$keychain" > "$dir/secret.json"
    check "keyID" [ "$(plutil -extract keyID raw -o - "$dir/secret.json")" = ABC123DEFG ]
    check "teamID" [ "$(plutil -extract teamID raw -o - "$dir/secret.json")" = TESTTEAM01 ]
    secret=$(plutil -extract p8 raw -o - "$dir/secret.json")
    check "p8 equals the file" [ "$secret" = "$(cat "$dir/AuthKey_ABC123DEFG.p8")" ]
    make -C "$sb" --no-print-directory apns-key P8="$dir/AuthKey_ABC123DEFG.p8" KEYCHAIN="$keychain" > /dev/null 2>&1
    check "a second run leaves exactly one item" [ "$(item_count)" = 1 ]
    drop_keychain
}

test_apns_key_rejects() {
    local sb dir before after
    sb=$(sandbox)
    dir="$scratch/badkeys"
    mkdir -p "$dir"
    openssl ecparam -name secp384r1 -genkey -noout 2>/dev/null | openssl pkcs8 -topk8 -nocrypt -out "$dir/AuthKey_P384P384P3.p8"
    openssl genrsa 2048 2>/dev/null | openssl pkcs8 -topk8 -nocrypt -out "$dir/AuthKey_RSARSARSA1.p8"
    make_keychain
    before=$(security dump-keychain "$keychain" 2>/dev/null)
    for p8 in "$dir/AuthKey_MISSING000.p8" "$dir/AuthKey_P384P384P3.p8" "$dir/AuthKey_RSARSARSA1.p8"; do
        if make -C "$sb" --no-print-directory apns-key P8="$p8" KEYCHAIN="$keychain" > /dev/null 2>&1; then
            echo "apns-key accepted $p8"
            drop_keychain
            return 1
        fi
    done
    after=$(security dump-keychain "$keychain" 2>/dev/null)
    drop_keychain
    check "the keychain is unchanged" [ "$before" = "$after" ]
}

# --- ARCH-12

write_spec() {
    # write_spec <sandbox> <items...>
    local sb="$1"
    shift
    {
        printf '# Spec: Timer\n\n## 9. Testable behaviors\n\n'
        for n in "$@"; do printf -- '- TW-%s. Behavior %s.\n' "$n" "$n"; done
        printf '\n## 10. Decisions\n\n1. Not a behavior.\n'
    } > "$sb/spec/spec_timer_window.md"
}

write_tests() {
    local sb="$1"
    shift
    mkdir -p "$sb/FakeTests"
    {
        printf 'import Testing\n\nstruct FakeTests {\n'
        for n in "$@"; do printf '    @Test("TW-%s behavior %s") func t%s() {}\n' "$n" "$n" "$n"; done
        printf '}\n'
    } > "$sb/FakeTests/FakeTests.swift"
}

test_check_behaviors() {
    local sb output
    sb=$(sandbox)
    write_spec "$sb" 1 2 3
    write_tests "$sb" 1 2 3
    check "complete lists pass" make -C "$sb" --no-print-directory check-behaviors
    write_spec "$sb" 1 2 3 999
    if output=$(make -C "$sb" --no-print-directory check-behaviors 2>&1); then
        echo "passed with TW-999 untested"
        return 1
    fi
    check "TW-999 is listed" grep -q 'TW-999' <<< "$output"
    check "the gap is reported" grep -q 'not continuous' <<< "$output"
    write_spec "$sb" 1 2 3
    write_tests "$sb" 1 2 3 7
    if output=$(make -C "$sb" --no-print-directory check-behaviors 2>&1); then
        echo "passed with an unknown test identifier"
        return 1
    fi
    check "TW-7 is reported as defined by no spec" grep -q 'TW-7 is defined by no spec' <<< "$output"
    write_spec "$sb" 1 3 4
    write_tests "$sb" 1 3 4
    if output=$(make -C "$sb" --no-print-directory check-behaviors 2>&1); then
        echo "passed with a non-continuous list"
        return 1
    fi
    check "the non-continuous list is reported" grep -q 'expected TW-2, found TW-3' <<< "$output"
    # XCTest method names and shell tests count too.
    write_spec "$sb" 1 2
    printf 'final class X: XCTestCase {\n    func testTW1_TW2_both() {}\n}\n' > "$sb/FakeTests/FakeTests.swift"
    check "XCTest names count" make -C "$sb" --no-print-directory check-behaviors
}

# --- ARCH-13

test_help() {
    local output group target expected
    output=$(make -C "$root" --no-print-directory help)
    expected="Build:all build build-mac build-ios build-sim
Develop:sim sim-create stop mac-debug demo mac-debug-unregister logs sim-logs screenshots
Use:install mac uninstall apns-key device iphone ipad devices console
Test:unit-test agent-test ui-test test test-sync
Check:lint check-behaviors check-private check hooks
Project:secrets xcode skills clean distclean help"
    while IFS=: read -r group targets; do
        for target in $targets; do
            # The target must appear between its heading and the next heading.
            if ! awk -v g="$group" -v t="$target" '
                /^[A-Z]/ { in_group = ($0 == g); next }
                in_group && /^  / { line = $0; sub(/^  /, "", line); split(line, parts, /  +/)
                                    k = split(parts[1], names, " "); for (i = 1; i <= k; i++) if (names[i] == t) found = 1 }
                END { exit !found }' <<< "$output"; then
                echo "make help does not list $target under $group"
                return 1
            fi
        done
    done <<< "$expected"
}

# --- ARCH-14

test_clean() {
    local sb fake_true fake_false output
    sb=$(sandbox)
    mkdir -p "$sb/build.noindex/Build/Products/Release/Test.app" "$sb/build.noindex/Build/Intermediates.noindex/x" \
        "$sb/build.noindex/Logs/Build" "$sb/build.noindex/SourcePackages/checkouts"
    make -C "$sb" --no-print-directory clean > /dev/null
    check "clean keeps the products" [ -d "$sb/build.noindex/Build/Products/Release/Test.app" ]
    check "clean removes intermediates" [ ! -e "$sb/build.noindex/Build/Intermediates.noindex" ]
    check "clean removes logs" [ ! -e "$sb/build.noindex/Logs" ]
    fake_true=$(fake_tool launchctl-registered 0)
    fake_false=$(fake_tool launchctl-unregistered 113)
    if output=$(make -C "$sb" --no-print-directory distclean LAUNCHCTL="$fake_true" 2>&1); then
        echo "distclean ran while the Debug agent is registered"
        return 1
    fi
    check "distclean names the way out" grep -q 'make mac-debug-unregister' <<< "$output"
    check "distclean asked launchctl about the Debug agent" grep -q 'print gui/[0-9]*/com.example.test.debug.agent' "$scratch/calls"
    check "a refused distclean keeps build.noindex" [ -d "$sb/build.noindex" ]
    make -C "$sb" --no-print-directory distclean LAUNCHCTL="$fake_false" > /dev/null
    check "distclean removes build.noindex" [ ! -e "$sb/build.noindex" ]
    check "distclean keeps local.mk" [ -f "$sb/local.mk" ]
}

# --- ARCH-15

test_lint_fails() {
    local dir case fake_bin
    dir="$scratch/lint"
    mkdir -p "$dir/swiftlint" "$dir/format" "$dir/available" "$dir/clean"
    printf '// Lint probe.\n\nlet value: Any = 1\nlet number = value as! Int\n' > "$dir/swiftlint/Probe.swift"
    printf '// Lint probe.\n\nfunc probe() -> Int {\n  1\n}\n' > "$dir/format/Probe.swift"
    printf '// Lint probe.\n\nfunc probe() -> Bool {\n    if #available(macOS 27, *) {\n        return true\n    }\n    return false\n}\n' \
        > "$dir/available/Probe.swift"
    printf '// Lint probe.\n\nfunc probe() -> Int {\n    1\n}\n' > "$dir/clean/Probe.swift"
    # A fake xcodebuild first in PATH proves that lint builds nothing.
    fake_bin="$scratch/lintbin"
    mkdir -p "$fake_bin"
    printf '#!/bin/sh\ncase "$*" in *-resolvePackageDependencies*) exec %s "$@" ;; esac\necho "xcodebuild $*" >> "%s/lint-calls"\nexit 1\n' \
        "$DEVELOPER_DIR/usr/bin/xcodebuild" "$scratch" > "$fake_bin/xcodebuild"
    chmod +x "$fake_bin/xcodebuild"
    check "a clean file passes" env PATH="$fake_bin:$PATH" LINT_PATHS="$dir/clean" make -C "$root" --no-print-directory lint
    for case in swiftlint format available; do
        if env PATH="$fake_bin:$PATH" LINT_PATHS="$dir/$case" make -C "$root" --no-print-directory lint > "$scratch/lint.out" 2>&1; then
            echo "lint passed the $case probe"
            return 1
        fi
    done
    check "the #available probe is reported by the custom rule" \
        sh -c "env PATH='$fake_bin:$PATH' LINT_PATHS='$dir/available' make -C '$root' --no-print-directory lint 2>&1 | grep -q no_availability_checks"
    check "lint did not build" [ ! -e "$scratch/lint-calls" ]
}

test_warning_fails_build() {
    local probe="$root/TimeTrackingCLI/ZZWarningProbe.swift" package_probe
    package_probe="$root/Packages/TimeTrackingCore/Sources/TimeTrackingCore/Support/ZZWarningProbe.swift"
    printf 'func warningProbe() {\n    let unused = 1\n}\n' > "$probe"
    printf 'func warningProbe() {\n    let unused = 1\n}\n' > "$package_probe"
    local status=0
    xcodebuild -quiet -project "$root/TimeTracking.xcodeproj" -derivedDataPath "$root/build.noindex" -scheme TimeTrackingCLI \
        -configuration Debug -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation \
        CODE_SIGNING_ALLOWED=NO build > "$scratch/warn.out" 2>&1 && status=1
    swift build --package-path "$root/Packages/TimeTrackingCore" > "$scratch/warn-package.out" 2>&1 && status=2
    rm -f "$probe" "$package_probe"
    check "the app build fails on a warning" [ "$status" != 1 ]
    check "the package build fails on a warning" [ "$status" != 2 ]
    check "the failure is the warning" grep -q "never used" "$scratch/warn.out"
}

# --- ARCH-1

test_package_without_local_mk() {
    local copy="$scratch/checkout"
    mkdir -p "$copy"
    # The tracked and unignored files: no local.mk, no Local.xcconfig, no build products.
    (cd "$root" && git ls-files -z --cached --others --exclude-standard) |
        (cd "$root" && rsync -a --from0 --files-from=- ./ "$copy/")
    check "the copy has no local.mk" [ ! -e "$copy/local.mk" ]
    check "the copy has no Local.xcconfig" [ ! -e "$copy/Config/Local.xcconfig" ]
    check "the copy has the package" [ -f "$copy/Packages/TimeTrackingCore/Package.swift" ]
    # No network: IP traffic is denied, so the pinned packages come from the
    # checkout's resolved package clones (GRDB's submodule cannot be fetched
    # offline); nothing is built yet in the copy. SwiftPM's manifest sandbox
    # cannot nest inside this one, hence --disable-sandbox. swift test never
    # signs, and the copy lies outside ~/Documents, so no permission prompt
    # can block it.
    local build="$root/Packages/TimeTrackingCore/.build"
    check "the checkout has resolved its packages" [ -d "$build/checkouts" ]
    mkdir -p "$copy/Packages/TimeTrackingCore/.build"
    for item in checkouts repositories workspace-state.json; do
        [ ! -e "$build/$item" ] || ditto "$build/$item" "$copy/Packages/TimeTrackingCore/.build/$item"
    done
    sandbox-exec -p '(version 1) (allow default) (deny network-outbound (remote ip)) (deny network-inbound (local ip))' \
        swift test --package-path "$copy/Packages/TimeTrackingCore" --disable-automatic-resolution --disable-sandbox > "$scratch/package-test.out" 2>&1 ||
        { tail -30 "$scratch/package-test.out"; return 1; }
    check "the package tests ran" grep -Eq "Test run with [0-9]+ tests" "$scratch/package-test.out"
}

# --- ARCH-22

test_pre_commit() {
    local sb
    sb=$(sandbox)
    make -C "$sb" --no-print-directory hooks
    printf 'Nothing personal here.\n' > "$sb/clean.txt"
    git -C "$sb" add clean.txt
    check "a clean commit passes" git -C "$sb" commit -q -m "Add a clean file"
    printf 'let team = "TESTTEAM01"\n' > "$sb/leak.swift"
    git -C "$sb" add leak.swift
    if git -C "$sb" commit -q -m "Add the team id" > "$scratch/commit.out" 2>&1; then
        echo "the commit with the TEAM value went through"
        return 1
    fi
    check "the hook names the file" grep -q 'leak.swift:1: personal value' "$scratch/commit.out"
    check "the hook does not print the value" not grep -q 'TESTTEAM01' "$scratch/commit.out"
    git -C "$sb" reset -q leak.swift
    printf 'Private word: Frobnicator\n' > "$sb/word.txt"
    printf 'frobnicator\n' > "$sb/.private-strings"
    git -C "$sb" add word.txt
    if git -C "$sb" commit -q -m "Add a private word" > /dev/null 2>&1; then
        echo "a .private-strings word went through"
        return 1
    fi
    git -C "$sb" reset -q word.txt
    if git -C "$sb" commit -q --allow-empty -m "Mention TESTTEAM01" > /dev/null 2>&1; then
        echo "the commit-msg hook let the TEAM value through"
        return 1
    fi
}

# --- ARCH-4, ARCH-5 (--products)

local_value() {
    sed -n "s/^$1 *= *//p" "$root/local.mk"
}

# product_app <products folder>: the APP_NAME bundle in build.noindex/Build/Products/<folder>.
product_app() {
    local name
    name=$(local_value APP_NAME)
    echo "$root/build.noindex/Build/Products/$1/${name:-TimeTracking}.app"
}

test_mac_products() {
    local app copy entitlements bundle_id team
    app=$(product_app Release)
    bundle_id=$(local_value BUNDLE_ID)
    team=$(local_value TEAM)
    check "a Release Mac build exists (run make build-mac)" [ -d "$app" ]
    check "the Release Mac products pass" "$root/scripts/check_products.sh" mac "$app" "$bundle_id" "$team"
    copy="$scratch/Copy.app"
    ditto "$app" "$copy"
    rm "$copy/Contents/Helpers/tracker-event"
    check "a missing tool fails" not "$root/scripts/check_products.sh" mac "$copy" "$bundle_id" "$team"
    rm -rf "$copy"
    ditto "$app" "$copy"
    entitlements="$scratch/get-task-allow.plist"
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>com.apple.security.get-task-allow</key><true/></dict></plist>\n' \
        > "$entitlements"
    codesign -f -s - -o runtime --entitlements "$entitlements" "$copy/Contents/Helpers/timetracking" 2> /dev/null
    check "get-task-allow fails" sh -c "'$root/scripts/check_products.sh' mac '$copy' '$bundle_id' '$team' 2>&1 | grep -q 'TimeTrackingCLI carries com.apple.security.get-task-allow'"
    rm -rf "$copy"
    ditto "$app" "$copy"
    mkdir "$copy/Contents/Frameworks"
    check "Contents/Frameworks fails" not "$root/scripts/check_products.sh" mac "$copy" "$bundle_id" "$team"
}

test_ios_products() {
    local app
    app=$(product_app Release-iphoneos)
    check "a Release iOS build exists (run make build-ios)" [ -d "$app" ]
    check "the Release iOS products pass" "$root/scripts/check_products.sh" ios "$app" "$(local_value BUNDLE_ID)" "$(local_value TEAM)"
}

# plist_value <plist> <key>
plist_value() {
    plutil -extract "$2" raw "$1" 2>/dev/null
}

# The built Debug and Release bundles' file and display names (ARCH-24).
test_product_names() {
    local name debug_app agent release_app sim_app ios_app plist program extension
    name=$(local_value APP_NAME)
    name=${name:-TimeTracking}
    debug_app=$(product_app Debug)
    debug_app="${debug_app%.app} Debug.app"
    agent="$debug_app/Contents/Library/LoginItems/TimeTrackingAgent Debug.app"
    check "a Debug Mac build exists (run make mac-debug)" [ -d "$debug_app" ]
    check "the Debug app's bundle name" [ "$(plist_value "$debug_app/Contents/Info.plist" CFBundleName)" = "$name Debug" ]
    check "the Debug app's display name" [ "$(plist_value "$debug_app/Contents/Info.plist" CFBundleDisplayName)" = "$name Debug" ]
    check "the Debug app's executable" [ -x "$debug_app/Contents/MacOS/TimeTracking" ]
    check "the Debug agent is TimeTrackingAgent Debug.app" [ -d "$agent" ]
    check "the Debug agent's bundle name" [ "$(plist_value "$agent/Contents/Info.plist" CFBundleName)" = "TimeTrackingAgent Debug" ]
    check "the Debug agent's display name" [ "$(plist_value "$agent/Contents/Info.plist" CFBundleDisplayName)" = "TimeTrackingAgent Debug" ]
    check "the Debug agent's executable" [ -x "$agent/Contents/MacOS/TimeTrackingAgent" ]
    plist=$(ls "$debug_app"/Contents/Library/LaunchAgents/*.plist)
    program=$(plist_value "$plist" BundleProgram)
    check "the Debug launchd plist names the Debug agent" \
        [ "$program" = "Contents/Library/LoginItems/TimeTrackingAgent Debug.app/Contents/MacOS/TimeTrackingAgent" ]
    check "the Debug BundleProgram is an executable" [ -x "$debug_app/$program" ]
    release_app=$(product_app Release)
    check "a Release Mac build exists (run make build-mac)" [ -d "$release_app" ]
    check "the Release agent is TimeTrackingAgent.app" [ -d "$release_app/Contents/Library/LoginItems/TimeTrackingAgent.app" ]
    check "the Release Mac bundles' names lack Debug" not sh -c "find '$release_app' -name Info.plist \
        -exec plutil -extract CFBundleName raw {} \; -exec plutil -extract CFBundleDisplayName raw {} \; 2>/dev/null | grep Debug"
    check "no Release Mac bundle file name contains Debug" [ -z "$(find "$release_app" -name '*Debug*')" ]
    sim_app=$(product_app Debug-iphonesimulator)
    check "a simulator build exists (run make build-sim)" [ -d "$sim_app" ]
    check "the simulator app's display name" [ "$(plist_value "$sim_app/Info.plist" CFBundleDisplayName)" = "$name Debug" ]
    for extension in "$sim_app"/PlugIns/*.appex "$sim_app"/Extensions/*.appex; do
        [ -d "$extension" ] || continue
        check "$(basename "$extension") Debug display name" \
            [ "$(plist_value "$extension/Info.plist" CFBundleDisplayName)" = "$name Debug" ]
    done
    ios_app=$(product_app Release-iphoneos)
    check "a Release iOS build exists (run make build-ios)" [ -d "$ios_app" ]
    check "the Release iOS bundles' display names lack Debug" not sh -c "find '$ios_app' -name Info.plist \
        -exec plutil -extract CFBundleDisplayName raw {} \; 2>/dev/null | grep Debug"
}

# --- ARCH-18 (--sim)

sim_udid() {
    xcrun simctl list devices | grep -F "    $1 (" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
}

test_sim_create() {
    local name before after output
    for name in "TimeTracking iPhone" "TimeTracking iPad"; do
        while [ -n "$(sim_udid "$name")" ]; do xcrun simctl delete "$(sim_udid "$name" | head -n 1)"; done
    done
    make -C "$root" --no-print-directory sim-create
    for name in "TimeTracking iPhone" "TimeTracking iPad"; do
        check "$name exists once" [ "$(sim_udid "$name" | wc -l | tr -d ' ')" = 1 ]
    done
    before=$(sim_udid "TimeTracking iPhone")
    output=$(make -C "$root" --no-print-directory sim-create)
    after=$(sim_udid "TimeTracking iPhone")
    check "a second run does nothing" [ -z "$output" ]
    check "the simulator is the same" [ "$before" = "$after" ]
    xcodebuild -quiet -project "$root/TimeTracking.xcodeproj" -derivedDataPath "$root/build.noindex" -scheme TimeTrackingiOS \
        -destination 'platform=iOS Simulator,name=TimeTracking iPhone' -only-testing:TimeTrackingiOSTests \
        -skipPackagePluginValidation -skipMacroValidation -allowProvisioningUpdates test
}

# --- ARCH-23

test_demo() {
    local sb fake output line
    sb=$(sandbox)
    fake=$(fake_tool xcodebuild 0)
    rm -f "$scratch/calls"
    if output=$(make -C "$sb" --no-print-directory XCODEBUILD="$fake" demo FIXTURE=nonexistent 2>&1); then
        echo "make demo succeeded with an unknown fixture"
        return 1
    fi
    check "an unknown fixture is named" grep -q 'no store fixture nonexistent' <<< "$output"
    check "an unknown fixture stops before xcodebuild" [ ! -e "$scratch/calls" ]
    mkdir -p "$sb/Fixtures/Store"
    printf '{}\n' > "$sb/Fixtures/Store/running.json"
    output=$(make -C "$sb" --no-print-directory -n demo FIXTURE=running HOME=/home/test)
    line=$(grep '^scripts/demo.sh ' <<< "$output")
    check "the Mac app is built before seeding" grep -q 'build -scheme TimeTracking -configuration Debug' <<< "$output"
    check "the simulator app is built before seeding" grep -q 'build -scheme TimeTrackingiOS -configuration Debug' <<< "$output"
    check "the fixture is passed" grep -q '^scripts/demo.sh "running" ' <<< "$line"
    check "the seeded store is the Debug container's" \
        grep -qF '"/home/test/Library/Group Containers/TESTTEAM01.com.example.test.debug/Library/Application Support/TimeTracking"' <<< "$line"
    check "the Release container is never named" not grep -qF 'TESTTEAM01.com.example.test/' <<< "$output"
    check "the simulators get the Debug app id" grep -qF '"com.example.test.debug" "build.noindex/Build/Products/Debug-iphonesimulator/Test.app" "TimeTracking iPhone" "TimeTracking iPad"' <<< "$line"
}

# --- ARCH-20 (--install)

test_install() {
    local prefix="$scratch/prefix" app_name tool version expected
    app_name=$(local_value APP_NAME)
    mkdir -p "$prefix/bin" "$prefix/share/zsh/site-functions"
    printf 'other\n' > "$prefix/bin/other"
    printf '#compdef other\n' > "$prefix/share/zsh/site-functions/_other"
    make -C "$root" --no-print-directory install PREFIX="$prefix" ALIAS=ttx
    tool="$prefix/bin/timetracking"
    check "timetracking is linked" [ -L "$tool" ]
    check "tracker-event is linked" [ -L "$prefix/bin/tracker-event" ]
    check "the alias is linked" [ -L "$prefix/bin/ttx" ]
    version=$("$tool" --version)
    expected="$(plutil -extract CFBundleShortVersionString raw "/Applications/${app_name:-TimeTracking}.app/Contents/Info.plist") ($(plutil -extract CFBundleVersion raw "/Applications/${app_name:-TimeTracking}.app/Contents/Info.plist"))"
    check "--version prints the installed app's version" [ "$version" = "$expected" ]
    check "zsh completion" [ -f "$prefix/share/zsh/site-functions/_timetracking" ]
    check "bash completion" [ -f "$prefix/share/bash-completion/completions/timetracking" ]
    check "zsh completion for the alias" [ -f "$prefix/share/zsh/site-functions/_ttx" ]
    make_keychain
    security add-generic-password -s "$(local_value BUNDLE_ID).apns" -a TESTKEY000 -w '{}' "$keychain"
    make -C "$root" --no-print-directory uninstall PREFIX="$prefix" ALIAS=ttx
    check "the Keychain item stays" security find-generic-password -s "$(local_value BUNDLE_ID).apns" "$keychain" > /dev/null
    drop_keychain
    check "the timetracking link is gone" [ ! -L "$tool" ]
    check "the tracker-event link is gone" [ ! -L "$prefix/bin/tracker-event" ]
    check "the alias link is gone" [ ! -L "$prefix/bin/ttx" ]
    check "the zsh completion is gone" [ ! -e "$prefix/share/zsh/site-functions/_timetracking" ]
    check "the bash completion is gone" [ ! -e "$prefix/share/bash-completion/completions/timetracking" ]
    check "other links stay" [ -f "$prefix/bin/other" ]
    check "other completions stay" [ -f "$prefix/share/zsh/site-functions/_other" ]
    check "the app is gone" [ ! -e "/Applications/${app_name:-TimeTracking}.app" ]
    # Leave the machine as it was: installed with the user's PREFIX.
    make -C "$root" --no-print-directory install > /dev/null
}

behavior "ARCH-2 make secrets writes Local.xcconfig and leaves it untouched without changes" test_secrets
behavior "ARCH-3 without TEAM the app-building targets stop before xcodebuild" test_team_guard
behavior "ARCH-6 the Debug identifiers carry .debug and no Release identifier does" test_debug_identifiers
behavior "ARCH-7 APP_NAME renames the app bundles and display names only" test_app_name
behavior "ARCH-9 make apns-key stores one Keychain item with the key" test_apns_key
behavior "ARCH-10 make apns-key rejects a missing or non-P-256 key and leaves the keychain unchanged" test_apns_key_rejects
behavior "ARCH-12 make check-behaviors reports untested, unknown, and non-continuous identifiers" test_check_behaviors
behavior "ARCH-13 make help lists every target under its group" test_help
behavior "ARCH-14 make clean keeps the products; make distclean removes build.noindex unless the Debug agent is registered" test_clean
behavior "ARCH-15 make lint fails on a SwiftLint finding, a formatting difference, or #available, without building" test_lint_fails
behavior "ARCH-22 the pre-commit hook refuses a staged TEAM value" test_pre_commit
behavior "ARCH-23 make demo seeds only the Debug container after building both Debug apps; an unknown fixture stops first" test_demo
behavior "ARCH-24 Debug Mac bundle file names and all Debug display names contain Debug; Release names do not" test_debug_names
[ "$run_build" = 0 ] || behavior "ARCH-15 a compiler warning fails the build" test_warning_fails_build
[ "$run_build" = 0 ] || behavior "ARCH-1 swift test passes in a copy of the checkout without local.mk, signing, or network" test_package_without_local_mk
[ "$run_products" = 0 ] || behavior "ARCH-4 the Release Mac app holds the agent, launchd plist, and tools, and no Frameworks" test_mac_products
[ "$run_products" = 0 ] || behavior "ARCH-5 the Release iOS bundles have the entitlements of the table" test_ios_products
[ "$run_products" = 0 ] || behavior "ARCH-24 the built Debug bundles carry Debug in their file and display names, the Release ones nowhere" test_product_names
[ "$run_sim" = 0 ] || behavior "ARCH-18 make sim-create creates the simulators once; tests pass on fresh ones" test_sim_create
[ "$run_install" = 0 ] || behavior "ARCH-20 make install links a tool that prints the app's version; uninstall removes only its files" test_install

echo
echo "test_make: $passed passed, $failed failed"
[ "$failed" = 0 ] || { printf '  %s\n' "${failures[@]}"; exit 1; }
