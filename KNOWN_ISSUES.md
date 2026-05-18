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

## SwiftData Migration Risk

- There is no formal migration strategy yet for future model schema changes.
- Adding stored properties to existing `@Model` types can cause migration issues.
- Before adding fields such as `workoutMode` to `WorkoutSession`, test on simulator with existing data.
- If migration becomes unstable, prefer optional fields with defaults or non-persistent derived structs first.

## Charts

- Exercise charts need at least two completed sessions for the same exercise before a useful trend appears.
- If an exercise has only one logged session, the detail view should show text instead of a trend line.
- Keep charts lazy-loaded. Avoid rendering many Swift Charts on a single screen.

## Volume Metrics

- The app currently uses best-set volume to avoid inflated total tonnage.
- This is easier to read but less comprehensive than traditional total session volume.
- Future analytics may include both best-set volume and total tonnage as separate metrics.
- Codex should not replace existing volume logic without explaining the product reason.

## Coach

- Coach logic is still basic and rule-based.
- Fatigue detection, plateau detection, and deload recommendations are planned but not fully implemented.
- The app should not overstate certainty. Use wording like "possible plateau" or "fatigue risk" rather than medical or absolute claims.
- Coaching should remain explainable. Every recommendation needs a reason.

## Readiness / Workout Modes

- A multi-question readiness form was removed because it added friction without a clear training decision.
- Do not reintroduce separate readiness questions as the next step.
- The preferred replacement is a single workout mode selector:
  - Full.
  - Quick.
  - Recovery.
  - Heavy.

## Target Suggestion Duplication

- Workout selection and Coach can drift if they each calculate targets separately.
- Future work should centralise target logic in `TargetSuggestionService`.
- Views should display target suggestions, not calculate them.

## UI / Apple Fitness Inspiration

- The user wants a look inspired by Apple's Fitness/Workout apps.
- Do not copy Apple's exact Activity Rings, Fitness app screens, icons, or trademarked visual identity.
- Build an original GymTracker design using platform conventions:
  - Dark-first cards.
  - Large metrics.
  - Rounded surfaces.
  - SF Symbols.
  - Custom lifting-focused progress arcs.
- Destructive actions should remain standard system red, not the theme accent.

## Theme System

- Current theme support is mostly accent-colour driven.
- A full UI refresh will need semantic colours for cards, borders, muted text, warnings, and success states.
- Avoid hardcoding green everywhere.

## History Filters

- History filters are planned but not implemented.
- Be careful not to overcomplicate the History screen.
- Start with simple filter chips or a compact filter sheet.

## Rest Timer

- Rest timer is a valuable later feature.
- Background behaviour on iOS may be limited.
- Start with an in-app timer before trying notifications or background alerts.

## Plate Calculator

- Plate calculator is useful but should come after core coaching improvements.
- Needs kg-first support.
- Avoid cluttering the live logger.

## Validation

After every Codex task, run:

```bash
git diff --check
xcodebuild -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=B4892393-2EDB-4816-A09B-A18C3161823C' \
  build
```
