# iOS Auto Refresh

This is a logged-in macOS LaunchAgent for Noel's personal-development iOS apps. The catalog in `apps.d/` currently contains Peakline and Kuro, and can be extended with another app plist without changing the refresh safeguards.

Each catalog entry supplies the display name, project root and Xcode project, scheme/configuration, bundle/team identity, device IDs, and isolated state/log/DerivedData directory names. The refresher validates the selected entry before doing any work. It derives the built app from `CFBundleIdentifier`, refuses missing or ambiguous products, and reads `CFBundleExecutable` from the verified build for the running-process guard.

When an app is due, the refresher:

1. confirms the existing bundle ID is installed on Noel's paired iPhone;
2. quarantines only that app's matching cached provisioning profile (a manual `--force` quarantines it regardless of remaining validity);
3. builds a clean Debug device app with `xcodebuild -allowProvisioningUpdates`;
4. verifies the bundle ID, team/application identifier, profile expiry, and code signature;
5. confirms the app is not currently running, so active app data is not interrupted;
6. uses `devicectl device install app` to update the existing app in place; and
7. records the successfully installed profile's expiration and UUID.

The automation contains no app uninstall command. An in-place update with the same bundle ID and team preserves the app's persistent data container. Existing Peakline state, log, and DerivedData paths remain under the original `PeaklineAutoRefresh` directories; Kuro uses isolated `KuroAutoRefresh` directories.

## Commands

The legacy no-argument commands still target Peakline:

```bash
Scripts/PeaklineAutoRefresh/peakline_auto_refresh.zsh
Scripts/PeaklineAutoRefresh/peakline_auto_refresh.zsh --status
Scripts/PeaklineAutoRefresh/peakline_auto_refresh.zsh --dry-run
Scripts/PeaklineAutoRefresh/peakline_auto_refresh.zsh --force
```

Select Kuro or run every catalog entry serially:

```bash
Scripts/PeaklineAutoRefresh/peakline_auto_refresh.zsh --app kuro --status
Scripts/PeaklineAutoRefresh/peakline_auto_refresh.zsh --app kuro --dry-run
Scripts/PeaklineAutoRefresh/peakline_auto_refresh.zsh --app kuro --force
Scripts/PeaklineAutoRefresh/peakline_auto_refresh.zsh --all --status
Scripts/PeaklineAutoRefresh/peakline_auto_refresh.zsh --all --dry-run
Scripts/PeaklineAutoRefresh/peakline_auto_refresh.zsh --all --force
Scripts/PeaklineAutoRefresh/peakline_auto_refresh.zsh --all
```

`--status` and `--dry-run` are read-only. `--all` continues after an individual app failure and returns a non-zero aggregate status if any app failed.

## Install

```bash
Scripts/PeaklineAutoRefresh/install_launch_agent.zsh
```

Installation lints and semantically validates every catalog plist before reloading the existing `com.noel.peakline-auto-refresh` LaunchAgent. The LaunchAgent invokes the refresher with `--all` every 15 minutes at minutes 2, 17, 32, and 47.

## Inspect or disable

```bash
launchctl print "gui/$(id -u)/com.noel.peakline-auto-refresh"
tail -n 100 "$HOME/Library/Logs/PeaklineAutoRefresh/launchd.log"
Scripts/PeaklineAutoRefresh/uninstall_launch_agent.zsh
```

The disable script unloads the job and moves its installed plist to Trash. It retains app logs, profile backups, state, and DerivedData.

## Limits

- The Mac must be powered on, Noel must be logged in, and Xcode's account/signing access must work without a prompt.
- The paired iPhone must be reachable over USB or the configured local network, with Developer Mode and trust still enabled.
- If any preflight, signing, identity, expiry, signature, or install check fails, the existing app is not removed. The schedule retries while the recorded build remains due.
- Attention notifications are throttled to at most one every six hours.
