# Roadmap

Current file: `ROADMAP.md`

## Product North Star

Peakline should be the local-first training coach that tells Noel what to train, what target to aim for, whether to push or recover, and how training is progressing over time.

The app should stay centered on lifting: fast logging, an editable ordered training rotation, clear target suggestions, history, progress, nutrition and recovery context, practical coaching, and reliable encrypted backup/restore. Multi-device sync, AI, Apple Watch, and deeper external integrations stay behind local product quality.

## Current Status

- The Push, Pull, Legs, Upper, Lower active rotation is editable and shared across every recommendation surface.
- Workout Preview supports Full, Quick, Recovery, and Heavy modes.
- Live workout logging includes timer, pause and resume, set entry, rest timer, completion rating, celebration, and session summary.
- `TargetSuggestionService` aligns targets across Coach, Workout Preview, and Splits.
- Readiness Score v2 is evidence-aware: missing inputs stay unknown, sparse results are provisional, signal influence is capped by coverage and reliability, eligible personal baselines are bounded, and provisional readiness cannot independently prescribe aggressive or recovery training.
- History uses minimal attendance markers; Nutrition can browse previous days read-only; filters, progress charts, themes, exercise icons, sleep, hydration, HealthKit bridge work, local export, templates, notes, and coach intelligence are all present.
- Firebase email/password account backup is in place for encrypted full-app restore after reinstall while SwiftData remains the fast local database.
- The focused performance acceptance verifier is in place and should stay green as navigation and feature work continues.
- Profile is compact and adaptive, Gym Utilities has been replaced by purposeful Workout Tools plus Appearance, Workout Preview has real route-local drag ordering, and Logger transition motivation now rotates through 28 nonrepeating messages.
- The premium-athletic style guide is implemented across the shared design system and major Today, Workout, Splits, History, Settings, Coach, Progress, Nutrition, Sleep, Preview, Logger, completion, and Summary surfaces in both semantic appearances.
- The latest full performance verifier is green with 131 unit tests, Today-to-Coach at 214 ms, Coach-to-Preview at 272 ms, and root switching at 84 ms.

## Current Near-Term Priority

Keep the current app stable, readable, and coherent while the feature surface is already broad.

That means:

- protect the workout, coach, and preview flows from regressions
- keep nutrition scanner and import flows reviewable and navigation-safe
- keep account backup and restore reliable before schema changes
- maintain readable UI across light and dark mode
- keep performance-sensitive routes within the current acceptance thresholds

## Next Practical Priorities

- Run focused physical-device visual QA across the redesigned core surfaces in Light and Dark, including large Dynamic Type, VoiceOver, Reduce Motion, Reduce Transparency, compact Profile rows, Workout Tools/Appearance, the first Preview drag, motivational Continue transitions, and the PR-only completion.
- Preserve the `Scripts/verify_performance_acceptance.sh` workflow for any changes that touch Today, Workout, Coach, Preview, or root lifecycle behavior.
- Keep notification refresh, route warm-starts, and SwiftData async safety intact.
- Confirm exact PNG icon coverage for seeded exercises and add mappings where source assets already exist.
- Keep nutrition scanner and import paths stable: barcode, OCR, review, save, and return-to-log.
- Add or preserve focused reliability tests around workout logging, nutrition import and export, full-app backup, sleep recovery, HealthKit boundaries, and navigation.
- Complete physical-device Firebase validation: create account, save backup, delete app, reinstall, sign in, restore, and verify data returns.
- Keep backup and export healthy before risky persistence changes.
- Expand Nutrition next with backdated logging, copying meals/days, reusable meals and recipes, then goal-adherence trends.

## Later Backlog

- More exact exercise icon mappings.
- Workout template and exercise note polish.
- Optional total tonnage alongside best-set volume.
- PR list, split consistency, and weekly volume summaries.
- Further coach copy and layout polish without overstating certainty.
- Safer SwiftData migration strategy and sample fixtures.
- Optional future multi-device sync and conflict handling after encrypted backup restore is reliable.
- HealthKit expansion after local nutrition and sleep behavior stays stable.
- Add a separate `GymVisit` model and manual Check In for attendance without a completed workout; do not create empty workout sessions for attendance.
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
