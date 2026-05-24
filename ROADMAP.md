# Roadmap

## Product North Star

Peakline should be the local-first training coach that tells Noel what to train, what target to aim for, whether to push or recover, and how training is progressing over time.

The first serious version should stay focused on lifting: fast logging, Push/Pull/Legs structure, clear target suggestions, history, progress, and practical recovery guidance. Cloud sync, AI, Apple Watch, and deeper external integrations should wait until the local app is excellent.

## Current Status

- Personal Push/Pull/Legs flow is in place.
- Workout Preview supports Full, Quick, Recovery, and Heavy modes.
- Live workout logging includes timer, pause/resume, set entry, rest timer, completion rating, celebration, and session summary.
- `TargetSuggestionService` aligns targets across Coach, Workout Preview, and Splits.
- History, filters, progress charts, themes, exercise icons, sleep, hydration, nutrition, HealthKit bridge work, local export, templates, notes, and coach intelligence foundations exist.
- Current risk is not missing features so much as keeping the app stable, readable, fast, and visually consistent as the feature surface grows.

## Current Near-Term Task

Run a focused visual QA and cleanup pass after the recent UI, icon, nutrition, sleep, HealthKit, reliability, and coach work.

Check light and dark mode across:

- Today.
- Workout.
- Workout Preview.
- Live Workout Logger.
- Splits.
- History.
- Settings.
- Themes.
- Nutrition, Sleep, Hydration, and HealthKit settings where touched.

Fix only obvious polish or reliability issues: unreadable text, wrong surfaces, clipped rows, destructive controls using accent color, missing exact icons, scanner/navigation regressions, or excessive visual weight.

## Next Practical Priorities

- Keep current build compile-ready and `git diff --check` clean.
- Finish visual QA for the primary workout and dashboard flows.
- Confirm exact PNG icon coverage for seeded exercises and add mappings when source assets already exist.
- Keep nutrition scanner/import paths stable: barcode, OCR label scan, review, save, and return-to-log flows.
- Keep SwiftData async work snapshot-based so live models do not cross `await` boundaries.
- Add or preserve focused reliability tests around workout logging, nutrition import/export, sleep recovery, HealthKit boundaries, and navigation.
- Add local backup/export coverage before risky persistence changes.
- Continue improving history and analytics only where it stays readable and lazy-loaded.

## Later Backlog

- More exact exercise icon mappings.
- Exercise notes/templates and workout template polish.
- Optional total tonnage alongside best-set volume.
- PR list, split consistency, and weekly volume summaries.
- Deeper coach copy/layout polish without overstating certainty.
- Safer SwiftData migration strategy and sample fixtures.
- iCloud/CloudKit sync after signing, entitlements, and container setup.
- HealthKit expansion after local nutrition and sleep behavior remains stable.
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
  -destination 'platform=iOS Simulator,id=B4892393-2EDB-4816-A09B-A18C3161823C' \
  build
```

For documentation-only tasks, `git diff --check` is enough unless app or project files were accidentally changed.
