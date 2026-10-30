# Sourced by install.sh, unregister_builds.sh, and debug_unregister.sh: what
# the scripts that register, unregister, or quit the Mac apps share.
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# quit_app <bundle id>: asks the app to quit if it is running.
quit_app() {
    osascript -e "if application id \"$1\" is running then tell application id \"$1\" to quit" \
        >/dev/null 2>&1 || true
}
