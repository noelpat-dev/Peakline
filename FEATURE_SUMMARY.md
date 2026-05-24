# Feature Summary

## Product Direction

Peakline is a personal, local-first lifting coach for Noel's Push/Pull/Legs training. It should make workout decisions easier, keep logging fast, show realistic targets, and explain coaching decisions without becoming a generic social fitness app or AI chatbot.

The current product value is the training loop: plan the next workout, log it quickly, review what happened, and use that history to make the next target clearer.

## Current Features

### Training Structure

- Push, Pull, and Legs are seeded as the core programme.
- Today and Coach recommend the next split from workout history.
- Splits show training-day cards, exercise counts, last-trained state, readiness/progression badges, and target rows.
- Exercise library and split editing support the personal programme.

### Workout Preview And Logging

- Start from Push, Pull, Legs, templates, reuse flows, or an empty workout.
- Choose Full, Quick, Recovery, or Heavy mode before logging.
- Preview exercises with duration estimate, last best set, target suggestions, notes, order, removal, and reorder controls.
- Live logging includes timer, pause/resume, current exercise focus, set entry, quick set controls, rest timer, skipped-exercise reasons, substitutions, and post-workout rating.
- Finished sessions show a celebration overlay and session summary.
- Workout dates are based on session start time, so late-night workouts stay on the correct training day.

### Coach And Progression

- `TargetSuggestionService` owns reusable progression targets for Workout, Coach, and Split rows.
- Coach recommendations are deterministic, local, and explainable.
- Coach surfaces next split, targets, weekly review, recovery warnings, workout adjustments, deload guidance, feedback, and action history.
- Recommendation copy should stay modest: use language like "possible plateau" or "fatigue risk" rather than certainty.

### History And Progress

- History includes calendar context, filters, workout details, editing, deletion, and session metadata.
- Progress includes latest best sets, estimated 1RM, best-set volume, set history, charts, and PR timeline.
- Analytics should stay lazy-loaded and readable as history grows.

### Nutrition, Hydration, Sleep, And Health

- Nutrition is local-first, with saved foods, food log snapshots, macro summaries, barcode lookup, Open Food Facts import, label OCR, parser review, source comparison, insights, and HealthKit bridge work.
- Hydration supports quick water logging and daily context.
- Sleep and recovery include sleep sessions, naps, scoring, recovery labels, and coaching context.
- HealthKit features must remain optional and gracefully handle unavailable, denied, or revoked permissions.

### Settings And Utilities

- Settings includes profile, training setup, themes, exercise library, plate calculator, progress, coach, HealthKit, backup/export, and local-data information.
- Theme accents include Fitness Green, Purple, Orange, and Blue.
- Appearance supports System, Light, and Dark.
- Local backup/export and workout CSV export support data portability.

### Exercise Icons

- Exact PNG source icons live in `GymTracker/IconSource/ExerciseIcons/`.
- Generated assets live in `GymTracker/Assets.xcassets/ExerciseIcons/`.
- `Scripts/prepare_exercise_icons.py` copies approved source PNGs into the asset catalog.
- `ExerciseIconMapper` maps exercise names to `ExerciseIconKey`.
- Exact-name icon mappings should come before broad muscle-group fallbacks.

## Remaining Practical Expansion

- Continue visual QA across light/dark mode and dense workout flows.
- Expand exact PNG coverage when source icons already exist.
- Keep scanner, OCR, and nutrition import paths stable and reviewable.
- Strengthen backup/export and migration safety before schema changes.
- Add richer analytics only when the current history and progress surfaces remain fast.
- Consider iCloud, deeper HealthKit, Apple Watch, or AI only after local-first behavior is excellent.

## Current Validation

The app should build with:

```bash
xcodebuild -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=B4892393-2EDB-4816-A09B-A18C3161823C' \
  build
```
