# Known Issues

## Xcode / Device Install

- Free Apple ID installs on a real iPhone usually expire after about 7 days.
- A paid Apple Developer account is recommended for longer-lived development builds and future CloudKit sync.
- If Xcode cannot run on a real device, check:
  - Device is unlocked.
  - Device trusts the Mac.
  - Signing & Capabilities has a valid personal team.
  - Bundle identifier is unique.

## iCloud Sync

- iCloud/CloudKit sync is not currently enabled in code.
- A previous CloudKit-backed SwiftData attempt could trigger runtime warnings without proper entitlements.
- Current implementation intentionally uses local SwiftData for stability.
- Future iCloud work should be done after enabling iCloud capability and selecting a CloudKit container in Xcode.

## Charts

- Exercise charts need at least two completed sessions for the same exercise before a useful trend appears.
- If an exercise has only one logged session, the detail view shows text instead of a trend line.

## Volume Metrics

- The app currently uses best-set volume to avoid inflated total tonnage.
- This is easier to read but less comprehensive than traditional total session volume.
- Future analytics may include both best-set volume and total tonnage as separate metrics.

## Coach

- Coach logic is still basic and rule-based.
- Fatigue detection, readiness-aware adaptation, plateau detection, and deload recommendations are planned but not fully implemented.

## Data Model

- There is no migration strategy yet for future model schema changes.
- Before adding new SwiftData models, confirm migration behaviour on simulator and real device.

## UI

- Progress charts are reachable from Today > Progress & Charts and Settings > Training Setup > Progress, but they are not a dedicated tab.
- The app intentionally keeps the tab count low to avoid iOS moving items into the automatic More tab.
