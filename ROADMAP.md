# Roadmap

## Product North Star

Peakline should be the local-first training coach that tells Noel what to train, what target to aim for, whether to push or recover, and how training is progressing over time.

The app should stay centered on lifting: fast logging, Push/Pull/Legs structure, clear target suggestions, history, progress, nutrition and recovery context, and practical coaching. Cloud sync, AI, Apple Watch, and deeper external integrations stay behind local product quality.

## Current Status

- Personal Push/Pull/Legs flow is in place.
- Workout Preview supports Full, Quick, Recovery, and Heavy modes.
- Live workout logging includes timer, pause and resume, set entry, rest timer, completion rating, celebration, and session summary.
- `TargetSuggestionService` aligns targets across Coach, Workout Preview, and Splits.
- History, filters, progress charts, themes, exercise icons, sleep, hydration, nutrition, HealthKit bridge work, local export, templates, notes, and coach intelligence are all present.
- The focused performance acceptance verifier is in place and should stay green as navigation and feature work continues.

## Current Near-Term Priority

Keep the current app stable, readable, and coherent while the feature surface is already broad.

That means:

- protect the workout, coach, and preview flows from regressions
- keep nutrition scanner and import flows reviewable and navigation-safe
- maintain readable UI across light and dark mode
- keep performance-sensitive routes within the current acceptance thresholds

## Next Practical Priorities

- Run focused visual QA across the core surfaces in light and dark mode.
- Preserve the `Scripts/verify_performance_acceptance.sh` workflow for any changes that touch Today, Workout, Coach, Preview, or root lifecycle behavior.
- Keep notification refresh, route warm-starts, and SwiftData async safety intact.
- Confirm exact PNG icon coverage for seeded exercises and add mappings where source assets already exist.
- Keep nutrition scanner and import paths stable: barcode, OCR, review, save, and return-to-log.
- Add or preserve focused reliability tests around workout logging, nutrition import and export, sleep recovery, HealthKit boundaries, and navigation.
- Keep backup and export healthy before risky persistence changes.

## Later Backlog

- More exact exercise icon mappings.
- Workout template and exercise note polish.
- Optional total tonnage alongside best-set volume.
- PR list, split consistency, and weekly volume summaries.
- Further coach copy and layout polish without overstating certainty.
- Safer SwiftData migration strategy and sample fixtures.
- iCloud or CloudKit sync after signing, entitlements, container setup, and migration coverage.
- HealthKit expansion after local nutrition and sleep behavior stays stable.
- Apple Watch companion app.
- AI-generated weekly review or natural-language training questions.
- Advanced periodisation blocks.
- Bodyweight, measurements, and progress photos.

## Validation

For normal implementation tasks:

```bash
git diff --check
xcodebuild -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

For performance-sensitive changes:

```bash
Scripts/verify_performance_acceptance.sh
```

For documentation-only tasks, `git diff --check` is enough unless app or project files were accidentally changed.
