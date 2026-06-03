# Known Issues

Current file: `KNOWN_ISSUES.md`

## Xcode / Device Install

- Free Apple ID installs on a real iPhone usually expire after about 7 days.
- A paid Apple Developer account is recommended for longer-lived development builds and future CloudKit sync.
- If Xcode cannot run on a real device, confirm the device is unlocked, trusts the Mac, has a valid signing team, and uses a unique bundle identifier.

## SwiftData Migration And Async Safety

- There is still no formal migration strategy for future schema changes.
- Add stored model fields carefully. Prefer optional fields with defaults, fixtures, and migration coverage before shipping.
- Do not pass live SwiftData `@Model`, `@Query`, or `ModelContext` values into async work that can suspend. Build value snapshots first.
- Use the performance acceptance verifier after changing Today, Coach, Workout Preview, root lifecycle, notifications, or HealthKit bridge code to catch `unsafeForcedSync` regressions early.
- Historical workout display should continue to tolerate changed or missing exercises, splits, templates, and UUID snapshots.

## Nutrition Scanner And Imports

- Protect the Today-to-Nutrition scanner route: Today quick actions to Nutrition, Add Food, Scan Label, Scan Barcode, review, save, and return-to-log.
- Barcode, Open Food Facts, OCR, parser, and source-comparison values must remain editable and explicitly saved before becoming local truth.
- Navigate to saved or imported foods by stable IDs rather than live SwiftData model objects.
- HealthKit sample write and read verification still requires a physical iPhone.
- Open Food Facts remains read-only from Peakline's side.

## HealthKit And iCloud

- iCloud and CloudKit sync are not enabled in code.
- Future cloud work still needs signing, iCloud capability, a selected container, and migration testing.
- HealthKit should remain optional and degrade gracefully when unavailable, denied, or revoked.
- Edited synced nutrition logs may need review rather than automatic overwrite or duplicate sync.

## Coach And Recovery

- Coaching is deterministic and still evolving.
- Fatigue, plateau, deload, and recovery recommendations should not overstate certainty.
- Every recommendation needs a short reason.
- Do not reintroduce a multi-question readiness form. The workout mode choice remains the main lightweight user control.

## UI And Design System

- Continue checking light and dark mode across Today, Workout, Workout Preview, Logger, Splits, History, Settings, Themes, Nutrition, Sleep, and Hydration.
- Exact exercise icon mappings can drift if broad mapper rules run before exact-name rules.
- Destructive actions should remain semantic danger or system red, not the accent color.
- Nutrition and hydration delete swipe patterns should stay visually consistent.
- Some native editor surfaces may still use plain `Form` or `List`; that is acceptable unless readability or contrast breaks.

## Performance And Charts

- Keep live workout logging fast and avoid heavy recomputation in hot logging views.
- Today, Coach, Workout Preview, Splits, Nutrition, Sleep, and Progress remain performance-sensitive as history grows.
- Keep charts lazy-loaded.
- Exercise charts still need at least two completed sessions for a useful trend; one-session states should explain that clearly.
- Protect the current acceptance thresholds:
  `today.route.appear coach` under 500ms in the verifier path, `root.notification.refresh` under 50ms in the interactive path, and one Preview `refresh onAppear` per open.

## Data And Analytics

- The app currently emphasizes best-set volume because it is easier to read than raw total tonnage.
- Future analytics can add total tonnage, PR lists, split consistency, and weekly volume summaries, but should not replace current meaning without a strong product reason.
- Local backup and export should stay healthy before risky persistence changes.

## Validation

General:

```bash
git diff --check
xcodebuild -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

Performance-sensitive work:

```bash
Scripts/verify_performance_acceptance.sh
```

For documentation-only tasks, `git diff --check` is sufficient unless app or project files were accidentally changed.
