# Feature Summary

## Product Direction

Peakline is a personal, local-first lifting coach for Noel's Push/Pull/Legs training. It should remember training history, suggest the next split, show realistic targets, and keep workout logging fast enough to use in the gym.

The app should feel polished and focused: crisp cards, clear metrics, exact exercise imagery where available, and deterministic coaching. It should not become a generic social fitness app, nutrition tracker, or AI chatbot in the first serious version.

## Current Features

### Personal Push/Pull/Legs

- Push, Pull, and Legs are seeded as training days inside one PPL programme.
- Today and Coach recommend the next split from completed workout history.
- Splits show training-day cards, exercise counts, last-trained status, and readiness/progression badges.
- Abdominal Crunch can be added across split days.

### Workout Preview And Logging

- Start from Push, Pull, Legs, or an empty workout.
- Choose Full, Quick, Recovery, or Heavy mode before logging.
- Preview selected exercises before starting, including duration estimate, target suggestions, and exercise order.
- Reorder preview exercises by long-press dragging.
- Remove exercises from the preview with standard destructive styling.
- Live workout logger includes timer, pause/resume, current exercise focus, set entry, rest timer, and post-workout rating.
- Workout date is based on when the session started, so late-night workouts are logged on the correct training day.
- Finished sessions show a glass celebration overlay and a session summary.

### Target Suggestions And Coach

- `TargetSuggestionService` owns reusable progression rules for Workout, Coach, and split rows.
- Coach recommendations are local and deterministic.
- Recommendation types include baseline, add reps, repeat, increase load, reduce load, plateau risk, fatigue risk, ready, recent, and progress.
- Coach explains the next split, exercise targets, weekly summary, and recovery warnings without a multi-question readiness form.

### History

- Calendar highlights completed gym days.
- Workouts can be filtered by split, exercise, rating, and date range.
- Workout detail shows started date/time, duration, rating, completed exercises, and logged sets.
- Historic workouts can be edited or deleted without entering the live logging flow.

### Progress

- Exercise list with latest best set.
- Exercise detail includes best set, estimated 1RM, best-set volume, set history, and trend charts.
- Progress charts are reachable from Today and Settings.

### Settings And Themes

- Settings includes Profile, Training Setup, Themes, Exercise Library, Plate Calculator, Progress, Coach, and local-data information.
- Theme accent colours include Fitness Green, Purple, Orange, and Blue.
- Appearance supports System, Light, and Dark.
- Workout and History screens respect the selected app appearance.

### Exercise Icons

- Exact PNG source icons live in `GymTracker/IconSource/ExerciseIcons/`.
- Generated template assets live in `GymTracker/Assets.xcassets/ExerciseIcons/`.
- `Scripts/prepare_exercise_icons.py` copies approved source PNGs into the asset catalog.
- `ExerciseIconMapper` maps exercise names to `ExerciseIconKey`.
- `ExerciseIconView` and `ExerciseIconTile` render those assets across previews, splits, workout cards, and exercise rows.
- Abdominal Crunch and Cable Lateral Raise now use their exact PNG assets.

### Data

- SwiftData local persistence.
- iCloud/CloudKit is not enabled yet because it requires Apple signing, capabilities, and container setup.

## Remaining Practical Expansion

- Continue adding exact PNG coverage for exercises that still fall back to generic icons.
- Add local backup/export before any risky persistence changes.
- Add richer analytics only after the core logging and coaching screens feel stable.
- Consider iCloud, HealthKit, Apple Watch, or AI only after the local-first app is excellent.

## Current Validation

The app should build with:

```bash
xcodebuild -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=B4892393-2EDB-4816-A09B-A18C3161823C' \
  build
```
