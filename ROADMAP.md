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
- Sleep now has a state-led no-data/populated/active hierarchy, focused Sleep Mode and morning flows, safe manual and nap editing, a date-derived Nap Timer, truthful optional HealthKit states, conservative provisional-readiness copy, bounded trends/history, and deterministic unit/UI fixtures without a SwiftData schema change.
- History now includes monthly gym-visit progress from the Profile weekly goal, current/previous duration and visits, local-day attendance markers, filters, details, and duration correction. Nutrition can browse previous days read-only; progress charts, themes, exercise icons, sleep, hydration, HealthKit bridge work, local export, templates, notes, and coach intelligence are all present.
- Firebase email/password account backup is in place for encrypted full-app restore after reinstall while SwiftData remains the fast local database.
- The focused performance acceptance verifier is in place and should stay green as navigation and feature work continues.
- Profile is compact and adaptive, Gym Utilities has been replaced by purposeful Workout Tools plus Appearance, Workout Preview has real route-local drag ordering, and Logger transition motivation now rotates through 28 nonrepeating messages.
- The premium-athletic style guide is implemented across the shared design system and major Today, Workout, Splits, History, Settings, Coach, Progress, Nutrition, Sleep, Preview, Logger, completion, and Summary surfaces in both semantic appearances.
- Preview duration ranges are calibrated from valid recent working-set history, and Logger intercepts four-hour timer outliers before rating while retaining an explicit long-session path.
- The 21 August warm-route architecture pass added coherent generations, prepared Nutrition/Progress/root first frames, explicit completion replay, and boot-isolated route coverage. The Debug build and all 180 unit/reliability tests pass; simulator samples are under the unchanged budgets, with physical-device memory and first-frame acceptance still outstanding.

## Current Near-Term Priority

Keep the current app stable, readable, and coherent while the feature surface is already broad.

That means:

- protect the workout, coach, and preview flows from regressions
- keep nutrition scanner and import flows reviewable and navigation-safe
- keep account backup and restore reliable before schema changes
- maintain readable UI across light and dark mode
- keep performance-sensitive routes within the current acceptance thresholds
- bring cold first-load Workout, History, and Settings tab transitions under the existing 300 ms gate without relaxing the threshold

## Next Practical Priorities

- Run focused physical-device visual QA across the redesigned core surfaces in Light and Dark, including Sleep no-data/populated/active states, Sleep settings/editors/timer/morning/detail, large Dynamic Type, VoiceOver, Reduce Motion, Reduce Transparency, monthly History goal editing, completed duration correction, the four-hour finish guard, realistic Preview estimates, compact Profile rows, Workout Tools/Appearance, the first Preview drag, motivational Continue transitions, and the PR-only completion.
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
