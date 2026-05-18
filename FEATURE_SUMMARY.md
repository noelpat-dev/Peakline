# Feature Summary

## Product Direction

GymTracker is being developed as a proactive, local-first lifting coach. It should remember training history, suggest what to do next, and help Noel progress through a Push/Pull/Legs programme without adding friction during workouts.

The app should feel like a lifting-focused version of the Apple Fitness experience: dark, crisp, motivating, card-based, metric-heavy, and easy to scan. It should not copy Apple's exact screens, Activity Rings, icons, or branding.

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
- Exercise selection shows last best performance and a suggested target before starting.
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
- Uses deterministic, local, rule-based logic.

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

## Planned Feature Expansion

### 1. Apple Fitness-Inspired UI Refresh

Goal: make the app feel more polished, modern, and motivating.

Planned changes:

- Dark-first home/dashboard screens.
- Large bold metrics for today's workout, duration, sets, and PRs.
- Rounded cards with subtle borders/materials.
- Consistent card components for Coach, Progress, History, and Workout Preview.
- Lifting-focused circular progress visuals for weekly workouts and split completion.
- SF Symbols for split types, recovery warnings, PRs, and time.
- Custom GymTracker progress arcs instead of Apple Activity Rings.

### 2. Workout Modes

Replace multi-question readiness with a simple mode choice.

Modes:

- **Full**: normal planned workout.
- **Quick**: fewer accessories and reduced set count.
- **Recovery**: lower volume, lighter target language, no aggressive overload.
- **Heavy**: prioritise compounds and progression targets.

User benefit: the app adapts to real life without slowing down the start of a session.

### 3. Shared Target Suggestion Service

Create a reusable service so Coach and Workout use the same rules.

The service should return:

- Last best set.
- Suggested target weight.
- Suggested target reps.
- Recommendation type.
- Short explanation.
- Confidence level.

Recommendation types:

- Baseline.
- Add reps.
- Repeat.
- Increase load.
- Reduce.
- Possible plateau.
- Fatigue risk.

### 4. Workout Preview Screen

Before starting a workout, show:

- Selected split.
- Selected workout mode.
- Estimated duration.
- Exercises in order.
- Last best performance per exercise.
- Suggested target per exercise.
- Remove/reorder controls.
- Start session button.

This should become the bridge between Coach and the live workout logger.

### 5. Coach Cards V2

Coach should be card-based and action-focused.

Cards:

- Next Workout.
- Today's Targets.
- Recovery Warnings.
- Weekly Summary.
- Progress Opportunities.
- Missed Split Warning.

The Coach screen should not only report data. It should help the user decide what to do.

### 6. Split UI Improvements

Each split day should show:

- Target sets.
- Rep range.
- Primary muscle.
- Last performed date.
- Latest best set.
- Coach badge.

Badges:

- Ready.
- Recently trained.
- Progress opportunity.
- Repeat target.
- Possible plateau.
- Fatigue risk.

### 7. Session Summary Screen

After finishing, show a full summary instead of only a popup.

Show:

- Duration to the second.
- Exercises completed.
- Working sets.
- Best set improvements.
- Rating.
- Coach-style takeaway.
- Suggested next split.

### 8. History Filters

Add filters:

- Split day.
- Exercise.
- Rating.
- Date range.

User benefit: easier review once the log grows.

### 9. Useful Gym Utilities

Later additions:

- Rest timer.
- Plate calculator.
- Exercise substitution when equipment is busy.
- Local backup/export.
- Bodyweight trend if bodyweight logging becomes consistent.

## Current Validation

The app builds successfully with:

```bash
xcodebuild -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=B4892393-2EDB-4816-A09B-A18C3161823C' \
  build
```
