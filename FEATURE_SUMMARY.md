# Feature Summary

Current file: `FEATURE_SUMMARY.md`

## Product Direction

Peakline is a personal, local-first lifting coach for Noel's Push/Pull/Legs training. It should make workout decisions easier, keep logging fast, show realistic targets, and explain coaching decisions without drifting into a generic social fitness app or AI chatbot.

The main value loop is:

1. Decide what to train next.
2. Preview and adjust the session.
3. Log the workout quickly.
4. Review what happened.
5. Use that history to make the next target clearer.

## Current Features

### Training Structure

- Push, Pull, and Legs are seeded as the core programme.
- Today and Coach recommend the next split from workout history.
- Splits show training-day cards, readiness and progression context, target rows, exercise counts, stable detail routes, and cached target calculations.
- Exercise library and split editing support the personal programme instead of a generic template marketplace.

### Workout Preview And Logging

- Start from the recommended workout card, split cards, templates, reuse flows, or an empty workout.
- Workout Preview supports Full, Quick, Recovery, and Heavy modes.
- Preview includes duration estimate, last best set, target suggestions, notes, reorder and removal controls, and Coach adjustment actions.
- Live logging includes current exercise focus, set entry, quick controls, rest timer, substitutions, skipped-exercise reasons, pause and resume, and post-workout rating.
- Finished sessions show a celebration overlay and session summary.
- Session dates are tied to the actual workout start time so late-night workouts stay on the correct training day.

### Coach And Progression

- `TargetSuggestionService` owns reusable progression targets across Workout Preview, Coach, and Splits.
- Coach recommendations are deterministic, local, and explainable.
- Coach includes readiness, next split context, weekly review, recovery warnings, workout adjustments, deload guidance, feedback capture, and action history.
- Coach route warm-starts from a cached value snapshot so Today and Workout can open it without a full visible cold rebuild in the normal path.
- Recommendation copy stays intentionally modest and should avoid false certainty.

### History And Progress

- History includes calendar context, filters, workout details, editing, deletion, and session metadata.
- Progress includes latest best sets, estimated 1RM, best-set volume, set history, charts, and PR timeline.
- Analytics and charts should stay lazy-loaded and readable as workout history grows.

### Nutrition, Hydration, Sleep, And Health

- Nutrition is local-first, with saved foods, food log snapshots, macro summaries, barcode lookup, Open Food Facts import, OCR label scan, parser review, source comparison, insights, and HealthKit bridge work.
- Hydration supports quick water logging and daily context.
- Sleep and recovery include sleep sessions, naps, readiness scoring, recovery labels, and coaching context.
- HealthKit remains optional and should fail gracefully when unavailable, denied, or revoked.

### Settings And Utilities

- Settings includes profile, training setup, themes, exercise library, plate calculator, progress, coach, HealthKit, backup and export, and local-data information.
- Appearance supports System, Light, and Dark.
- Accent themes include Fitness Green, Purple, Orange, and Blue.
- Local backup and workout CSV export support data portability.

### Exercise Icons

- Exact PNG source icons live in `GymTracker/IconSource/ExerciseIcons/`.
- Generated assets live in `GymTracker/Assets.xcassets/ExerciseIcons/`.
- `Scripts/prepare_exercise_icons.py` copies approved source PNGs into the asset catalog.
- `ExerciseIconMapper` maps exercise names to `ExerciseIconKey`.
- Exact-name mappings should come before broad muscle-group fallbacks.

### Performance Acceptance Coverage

- A focused acceptance verifier exists at `Scripts/verify_performance_acceptance.sh`.
- The verifier runs build, unit tests, a focused UI acceptance flow, and log scanning.
- Current acceptance checks cover Today to Coach, Workout to Coach, Workout to Preview, one Preview mode change, one-back navigation, notification refresh timing, duplicate Coach pushes, repeated Workout Preview onAppear refreshes, gesture timeouts, toolbar constraint warnings, and `unsafeForcedSync` regressions.
- Focused Splits UI coverage verifies tab entry, Push/Pull/Legs cards, split detail navigation, Add Split presentation, and Other Splits expansion/collapse.

## Current Product Strengths

- The main lifting loop is implemented end to end.
- Coach, Progress, Nutrition, Sleep, Hydration, and export utilities now sit on top of that core instead of replacing it.
- Recent performance cleanup materially improved route timing, notification refresh behavior, and Coach navigation stability.

## Remaining Practical Expansion

- Keep visual QA moving across light and dark mode.
- Expand exact exercise icon coverage where source assets already exist.
- Keep scanner, OCR, and nutrition import flows stable and reviewable.
- Strengthen backup, export, and migration safety before risky schema changes.
- Add richer analytics only when current history and progress surfaces remain fast.
- Consider iCloud, deeper HealthKit, Apple Watch, or AI only after the local-first behavior remains excellent.

## Current Validation

Build:

```bash
xcodebuild -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

Performance-sensitive regression check:

```bash
Scripts/verify_performance_acceptance.sh
```
