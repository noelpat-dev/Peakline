#!/bin/zsh

set -eu

readonly SCRIPT_DIR="${0:A:h}"
readonly LABEL="com.noel.peakline-auto-refresh"
readonly SOURCE_PLIST="$SCRIPT_DIR/$LABEL.plist"
readonly CATALOG_DIR="$SCRIPT_DIR/apps.d"
readonly DESTINATION_PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
readonly TEMP_PLIST="$DESTINATION_PLIST.tmp.$$"
readonly DOMAIN="gui/$(/usr/bin/id -u)"

if ! /usr/bin/plutil -lint "$SOURCE_PLIST" >/dev/null; then
    print -u2 "Malformed LaunchAgent plist: $SOURCE_PLIST"
    exit 64
fi

typeset -a app_plists
app_plists=("$CATALOG_DIR"/*.plist(N))
if (( ${#app_plists} == 0 )); then
    print -u2 "No app catalog entries found in $CATALOG_DIR."
    exit 64
fi

for app_plist in "${app_plists[@]}"; do
    [[ -f "$app_plist" ]] || continue
    if ! /usr/bin/plutil -lint "$app_plist" >/dev/null; then
        print -u2 "Malformed app catalog entry: $app_plist"
        exit 64
    fi
    app_key="${app_plist:t:r}"
    if ! "$SCRIPT_DIR/peakline_auto_refresh.zsh" --app "$app_key" --dry-run >/dev/null; then
        print -u2 "Invalid app catalog entry: $app_plist"
        exit 64
    fi
done

/bin/mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/PeaklineAutoRefresh"
/bin/chmod 755 "$SCRIPT_DIR/peakline_auto_refresh.zsh"
trap '/bin/rm -f "$TEMP_PLIST"' EXIT
/bin/cp "$SOURCE_PLIST" "$TEMP_PLIST"
/bin/chmod 644 "$TEMP_PLIST"
/bin/mv -f "$TEMP_PLIST" "$DESTINATION_PLIST"

/bin/launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
/bin/launchctl bootstrap "$DOMAIN" "$DESTINATION_PLIST"
/bin/launchctl enable "$DOMAIN/$LABEL"

print "Auto Refresh is installed and enabled for all catalog apps."
print "It checks every 15 minutes at minutes 2, 17, 32, and 47 and performs work only inside the one-day expiry window."
print "Status includes the UTC time, outcome, and message from the last attempt, even before a successful installation is recorded."
print "Status: $SCRIPT_DIR/peakline_auto_refresh.zsh --all --status"
