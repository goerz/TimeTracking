#!/bin/sh
# `make install` and `make uninstall` (spec_architecture.md §2.5, ARCH-20).
#
#   scripts/install.sh install   <built app> <BUNDLE_ID> <APP_NAME> <PREFIX> [<ALIAS>]
#   scripts/install.sh uninstall <BUNDLE_ID> <APP_NAME> <PREFIX> [<ALIAS>]
#
# Install replaces every app in /Applications with BUNDLE_ID by a copy of
# the built app, registers it with LaunchServices, links `timetracking` and
# `tracker-event` into PREFIX/bin (plus ALIAS for `timetracking`), and writes
# shell completions from the installed tool. Uninstall removes the app, and
# only those links and completion files that install wrote; containers, the
# Keychain item, and iCloud data stay.
set -eu

lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
marker="# Written by TimeTracking's make install; removed by make uninstall."

quit_app_and_agent() {
    bundle_id="$1"
    osascript -e "if application id \"$bundle_id\" is running then tell application id \"$bundle_id\" to quit" \
        >/dev/null 2>&1 || true
    launchctl kill TERM "gui/$(id -u)/$bundle_id.agent" >/dev/null 2>&1 || true
}

# Prints the apps in /Applications whose bundle identifier is BUNDLE_ID.
installed_apps() {
    for candidate in /Applications/*.app; do
        [ -d "$candidate" ] || continue
        id=$(plutil -extract CFBundleIdentifier raw "$candidate/Contents/Info.plist" 2>/dev/null || true)
        [ "$id" = "$1" ] && echo "$candidate"
    done
    return 0
}

completion_paths() {
    # <name> -> "<shell> <path>" lines for every installed shell
    name="$1"
    prefix="$2"
    if command -v zsh >/dev/null 2>&1; then echo "zsh $prefix/share/zsh/site-functions/_$name"; fi
    if command -v bash >/dev/null 2>&1; then echo "bash $prefix/share/bash-completion/completions/$name"; fi
    if command -v fish >/dev/null 2>&1; then echo "fish $prefix/share/fish/vendor_completions.d/$name.fish"; fi
    return 0
}

# write_completion <shell> <path> <tool> <command name>
write_completion() {
    shell="$1"
    path="$2"
    tool="$3"
    name="$4"
    mkdir -p "$(dirname "$path")"
    tmp="$path.tmp"
    if [ "$name" = timetracking ]; then
        script=$("$tool" --generate-completion-script "$shell")
        case "$shell" in
        zsh) printf '%s\n' "$script" | sed "1a\\
$marker
" > "$tmp" ;;
        *) printf '%s\n%s\n' "$marker" "$script" > "$tmp" ;;
        esac
    else
        # The alias reuses the completion of `timetracking`.
        case "$shell" in
        zsh) printf '#compdef %s\n%s\n_timetracking "$@"\n' "$name" "$marker" > "$tmp" ;;
        bash) printf '%s\n_comp_load timetracking 2>/dev/null || . "%s"\ncomplete -F _timetracking %s\n' \
            "$marker" "$(dirname "$path")/timetracking" "$name" > "$tmp" ;;
        fish) printf '%s\ncomplete -c %s -w timetracking\n' "$marker" "$name" > "$tmp" ;;
        esac
    fi
    mv "$tmp" "$path"
}

link() {
    target="$1"
    path="$2"
    mkdir -p "$(dirname "$path")"
    if [ -e "$path" ] && [ ! -L "$path" ]; then
        echo "install: $path exists and is not a link; leaving it" >&2
        return 0
    fi
    ln -sfn "$target" "$path"
}

unlink_if_ours() {
    path="$1"
    [ -L "$path" ] || return 0
    case "$(readlink "$path")" in
    */Contents/Helpers/timetracking | */Contents/Helpers/tracker-event) rm -f "$path" ;;
    esac
}

remove_if_ours() {
    path="$1"
    [ -f "$path" ] || return 0
    if grep -qxF "$marker" "$path"; then rm -f "$path"; fi
}

command="$1"
shift
case "$command" in
install)
    built="$1"
    bundle_id="$2"
    app_name="$3"
    prefix="$4"
    alias="${5:-}"
    destination="/Applications/$app_name.app"
    [ -d "$built" ] || { echo "install: no built app at $built" >&2; exit 1; }
    quit_app_and_agent "$bundle_id"
    installed_apps "$bundle_id" | while IFS= read -r old; do
        rm -rf "$old"
        echo "Removed $old"
    done
    ditto "$built" "$destination"
    "$lsregister" -f "$destination"
    echo "Installed $destination"
    tool="$destination/Contents/Helpers/timetracking"
    link "$tool" "$prefix/bin/timetracking"
    link "$destination/Contents/Helpers/tracker-event" "$prefix/bin/tracker-event"
    [ -z "$alias" ] || link "$tool" "$prefix/bin/$alias"
    for name in timetracking $alias; do
        completion_paths "$name" "$prefix" | while read -r shell path; do
            write_completion "$shell" "$path" "$tool" "$name"
        done
    done
    echo "Linked timetracking and tracker-event into $prefix/bin"
    ;;
uninstall)
    bundle_id="$1"
    app_name="$2"
    prefix="$3"
    alias="${4:-}"
    agent="/Applications/$app_name.app/Contents/Library/LoginItems/TimeTrackingAgent.app/Contents/MacOS/TimeTrackingAgent"
    [ ! -x "$agent" ] || "$agent" --unregister || true
    quit_app_and_agent "$bundle_id"
    installed_apps "$bundle_id" | while IFS= read -r old; do
        "$lsregister" -u "$old" 2>/dev/null || true
        rm -rf "$old"
        echo "Removed $old"
    done
    for name in timetracking tracker-event $alias; do
        unlink_if_ours "$prefix/bin/$name"
    done
    for name in timetracking $alias; do
        for path in "$prefix/share/zsh/site-functions/_$name" "$prefix/share/bash-completion/completions/$name" \
            "$prefix/share/fish/vendor_completions.d/$name.fish"; do
            remove_if_ours "$path"
        done
    done
    echo "Removed the links and completions under $prefix"
    ;;
*)
    echo "usage: $0 install|uninstall ..." >&2
    exit 64
    ;;
esac
