# Peakline Auto Refresh

This is a logged-in macOS LaunchAgent for Noel's personal-development install of Peakline. It checks every 15 minutes at minutes 2, 17, 32, and 47, and only starts a build when the profile recorded by its last successful install expires within 24 hours.

When due, it:

1. confirms the existing `com.noel.GymTracker` app is visible on Noel's paired iPhone;
2. quarantines only Peakline's near-expiry cached provisioning profile so automatic signing requests a fresh one;
3. builds a clean Debug device app with `xcodebuild -allowProvisioningUpdates`;
4. verifies the bundle ID, team/application identifier, profile expiry, and code signature;
5. confirms Peakline is not currently running, so an active workout is not interrupted;
6. uses `devicectl device install app` to update the existing app in place; and
7. records the successfully installed profile's expiration and UUID.

The automation contains no uninstall command. An in-place update with the same bundle ID and team preserves the app's persistent data container. This does not make caches or temporary files permanent, and no automation can protect data if the app is manually deleted.

Signing reuses the Xcode account and keychain session already stored locally on this Mac. The job reports code-signing credential health with a read-only identity check, but it never requests, stores, or automates an Apple ID password, two-factor authentication, session cookie, or API key. Xcode remains responsible for any account sign-in, 2FA, or other user-controlled prompt.

## Install

```bash
Scripts/PeaklineAutoRefresh/install_launch_agent.zsh
```

Installation runs an immediate check. With no prior managed state, the first check deliberately performs a refresh so future expiry tracking corresponds to a build this automation installed.

## Inspect

```bash
Scripts/PeaklineAutoRefresh/peakline_auto_refresh.zsh --status
launchctl print "gui/$(id -u)/com.noel.peakline-auto-refresh"
tail -n 100 "$HOME/Library/Logs/PeaklineAutoRefresh/launchd.log"
```

The status command reports the UTC time, outcome, and message from the last attempt even when no successful installation state has been recorded yet. It also reports signing readiness from Xcode's code-signing identities; `BLOCKED` means an Apple ID/signing identity must be configured in Xcode. This is informational because automatic signing may create an identity after an account is added.

If a due run cannot reach the iPhone and the read-only signing check also finds no valid identity, the result is recorded as `prerequisites_blocked` with one notification covering both actions. A missing identity does not by itself stop a device-connected build; `xcodebuild -allowProvisioningUpdates` is still allowed to let Xcode's automatic signing recover it.

Use `--dry-run` to evaluate whether a refresh is due without building or contacting the iPhone. Use `--force` for a manual safe refresh regardless of the recorded date.

## Disable

```bash
Scripts/PeaklineAutoRefresh/uninstall_launch_agent.zsh
```

The disable script unloads the job and moves its installed plist to Trash. It retains logs, profile backups, state, and DerivedData.

## Limits

- The Mac must be powered on, Noel must be logged in, and Xcode's account/signing access must work without a prompt.
- The paired iPhone must be reachable over USB or the configured local network, with Developer Mode and trust still enabled. A locked phone, network change, restart, or Apple account prompt can block an attempt.
- A LaunchAgent cannot guarantee a renewal while the Mac is shut down or logged out. Calendar events missed during sleep are coalesced and run after wake.
- If any preflight, signing, identity, expiry, signature, or install check fails, the existing app is not removed. The 15-minute schedule retries while the recorded build remains due.
- Attention notifications are throttled to at most one every six hours. Detailed output remains in `~/Library/Logs/PeaklineAutoRefresh`.
- Old Peakline-only profiles are retained in `~/Library/Application Support/PeaklineAutoRefresh/profile-backups` for recovery.
