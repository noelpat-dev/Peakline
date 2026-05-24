# Known Issues

## Xcode / Device Install

- Free Apple ID installs on a real iPhone usually expire after about 7 days.
- A paid Apple Developer account is recommended for longer-lived development builds and future CloudKit sync.
- If Xcode cannot run on a real device, confirm the device is unlocked, trusts the Mac, has a valid signing team, and uses a unique bundle identifier.

## SwiftData Migration And Async Safety

- There is no formal migration strategy yet for future schema changes.
- Add stored model fields carefully; prefer optional fields with defaults, sample fixtures, and migration tests before shipping.
- Do not pass live SwiftData `@Model`, `@Query`, or `ModelContext` values into async work that can suspend. Build value snapshots synchronously first.
- Regression check after startup, notification, HealthKit, nutrition sync, or navigation changes: watch Xcode logs for `unsafeForcedSync`.
- Historical workout display should tolerate missing or changed exercises, splits, templates, and UUID snapshots.

## Nutrition Scanner And Imports

- Protect the Today-to-Nutrition scanner route: Today quick actions to Nutrition, Add Food, Scan Label, Scan Barcode, review, save, and return-to-log.
- If Xcode logs a missing `navigationDestination` for `TodayRoute`, treat it as navigation state drift, not a scanner/OCR bug.
- Barcode, Open Food Facts, OCR, parser, and source-comparison values must remain editable and explicitly saved before becoming local truth.
- Navigate to saved/imported foods by stable IDs rather than live SwiftData model objects.
- HealthKit sample write/read verification requires a physical iPhone.
- Open Food Facts is read-only; Peakline should not upload corrections.

## HealthKit And iCloud

- iCloud/CloudKit sync is not enabled in code. Future work needs signing, iCloud capability, a selected container, and migration testing.
- HealthKit should remain optional and degrade gracefully when unavailable, denied, or revoked.
- Edited synced nutrition logs may need review rather than automatic overwrite or duplicate sync.

## Coach And Recovery

- Coaching is deterministic and still evolving.
- Fatigue, plateau, deload, and recovery recommendations should not overstate certainty.
- Every recommendation needs a short reason.
- Do not reintroduce a multi-question readiness form. Use the single workout mode choice: Full, Quick, Recovery, or Heavy.

## UI And Design System

- Continue checking light/dark mode across Today, Workout, Workout Preview, Logger, Splits, History, Settings, Themes, Nutrition, Sleep, and Hydration.
- Exact exercise icon mappings can drift when broad mapper rules run before exact-name rules.
- Destructive actions should remain semantic danger/system red, not the active accent.
- Nutrition and hydration delete swipe patterns should stay visually consistent.
- Shared metric/text components should use `AppTheme` semantic text tokens instead of raw `.primary` or `.secondary` where possible.
- Some native editor surfaces may still use plain `Form` or `List`; this is acceptable unless readability or theme contrast breaks.

## Performance And Charts

- Keep live workout logging fast; avoid heavy animation or expensive recomputation in hot logging views.
- Large views such as workout logger, sleep, nutrition, and progress remain performance-sensitive as history grows.
- Keep charts lazy-loaded.
- Exercise charts need at least two completed sessions for a useful trend; one-session states should show explanatory text.
- Progress chart axes and grid labels should stay readable in dark mode and custom appearances.

## Data And Analytics

- The app currently emphasizes best-set volume because it is easier to read than raw total tonnage.
- Future analytics can add total tonnage, PR lists, split consistency, and weekly volume summaries, but should not replace existing volume meaning without a product reason.
- Local backup/export should be kept healthy before risky persistence changes.

## Validation

After implementation tasks, run:

```bash
git diff --check
xcodebuild -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=B4892393-2EDB-4816-A09B-A18C3161823C' \
  build
```

For documentation-only tasks, `git diff --check` is sufficient unless app or project files were accidentally changed.
