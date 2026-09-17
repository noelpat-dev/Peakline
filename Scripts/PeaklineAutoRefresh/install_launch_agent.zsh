#!/bin/zsh

set -eu

readonly SCRIPT_DIR="${0:A:h}"
readonly LABEL="com.noel.peakline-auto-refresh"
readonly SOURCE_PLIST="$SCRIPT_DIR/$LABEL.plist"
readonly DESTINATION_PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
readonly TEMP_PLIST="$DESTINATION_PLIST.tmp.$$"
readonly DOMAIN="gui/$(/usr/bin/id -u)"

/usr/bin/plutil -lint "$SOURCE_PLIST" >/dev/null
/bin/mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/PeaklineAutoRefresh"
/bin/chmod 755 "$SCRIPT_DIR/peakline_auto_refresh.zsh"
trap '/bin/rm -f "$TEMP_PLIST"' EXIT
/bin/cp "$SOURCE_PLIST" "$TEMP_PLIST"
/bin/chmod 644 "$TEMP_PLIST"
/bin/mv -f "$TEMP_PLIST" "$DESTINATION_PLIST"

/bin/launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
/bin/launchctl bootstrap "$DOMAIN" "$DESTINATION_PLIST"
/bin/launchctl enable "$DOMAIN/$LABEL"

print "Peakline Auto Refresh is installed and enabled."
print "It checks every 15 minutes at minutes 2, 17, 32, and 47 and performs work only inside the one-day expiry window."
print "Status includes the UTC time, outcome, and message from the last attempt, even before a successful installation is recorded."
print "Status: $SCRIPT_DIR/peakline_auto_refresh.zsh --status"
