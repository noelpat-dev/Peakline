# Feature Summary

## Product Direction

GymTracker is being developed as a proactive, local-first lifting coach. It should remember training history, suggest what to do next, and help Noel progress through a Push/Pull/Legs programme without adding friction during workouts.

## Current Features

### Personal Push/Pull/Legs

- Personalised exercise library seeded from Noel's current training.
- Push, Pull, and Legs are treated as training days inside one Push/Pull/Legs programme.
- Today and Coach suggest the next day using PPL rotation logic.
- Abdominal Crunch is available across every split day.

### Workout Logging

- Start from Push, Pull, Legs, or an empty workout.
- Select exercises before starting.
- Selection order becomes the workout order.
- Live workout timer.
- One-exercise-at-a-time logging flow.
- Add set with weight, reps, and optional RPE.
- Previous-session weight and reps prefill when history exists.
- Sets with entered data are automatically treated as logged on save/finish.
- Post-workout facial rating.
- Rating-specific motivational completion message.

### History

- Calendar highlights completed gym days.
- Workout list shows completed exercise and set counts.
- Completed exercises appear above planned-but-unlogged exercises.
- Historic workouts can be edited without the live workout flow.
- Workouts can be deleted.
- Duration displays to the second when timestamps exist.
- Workout rating is shown in the workout detail.

### Progress

- Exercise list with latest best set.
- Exercise detail with:
  - Best set.
  - Estimated 1RM.
  - Best-set volume.
  - Set history.
  - Trend chart.
- Global Progress Charts screen groups charts by exercise.
- Charts are reachable from Today and Settings.

### Coach

- Recommends next PPL training day.
- Explains the recommendation.
- Gives exercise-level progressive-overload guidance.
- Shows weekly workout count, working sets, and best-set volume.

### Themes

- Theme settings are available under Settings > Themes.
- Colour options:
  - Workout Green `#7CFC00`.
  - Purple.
  - Orange.
  - Blue.
- Appearance options:
  - System.
  - Light.
  - Dark.

### Data

- SwiftData local persistence.
- iCloud/CloudKit is planned but intentionally not enabled in code yet because it requires Apple signing and iCloud container setup.

## Current Validation

The app builds successfully with:

```bash
xcodebuild -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=B4892393-2EDB-4816-A09B-A18C3161823C' \
  build
```
