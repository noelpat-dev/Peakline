#!/bin/zsh

set -eu

readonly LABEL="com.noel.peakline-auto-refresh"
readonly DESTINATION_PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
readonly DOMAIN="gui/$(/usr/bin/id -u)"

/bin/launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
if [[ -f "$DESTINATION_PLIST" ]]; then
    trash_name="$LABEL.$(/bin/date -u '+%Y%m%dT%H%M%SZ').plist"
    /bin/mv "$DESTINATION_PLIST" "$HOME/.Trash/$trash_name"
fi

print "Peakline Auto Refresh is disabled and its LaunchAgent plist was moved to Trash."
print "Build logs and refresh state were retained under your Library folders."
