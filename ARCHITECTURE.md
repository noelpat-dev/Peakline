# Architecture

## Overview

GymTracker is a personal iOS lifting tracker built around a Push/Pull/Legs workflow, progressive overload, workout history, and lightweight rule-based coaching. The app is local-first and designed for one primary user rather than a broad public audience.

The current product shape is:

- Pick a split day: Push, Pull, or Legs.
- Select only the exercises planned for today.
- Log one exercise at a time during a live workout.
- Track sets, reps, kg, optional RPE, rating, and exact active duration.
- Review history, progress charts, and coach suggestions.
- Customize the visual theme.

## Technical Stack

- Platform: iOS
- UI: SwiftUI
- Persistence: SwiftData
- Charts: Swift Charts
- Architecture style: feature-folder SwiftUI views with shared SwiftData models and small services
- Coaching strategy: deterministic rule-based logic, no AI APIs
- Data strategy: local-first SwiftData storage

## App Entry

```text
GymTracker/App/
  GymTrackerApp.swift
  RootTabView.swift
```

`GymTrackerApp` creates the SwiftData `ModelContainer` and wraps the app in `AppThemeProvider`.

`RootTabView` owns the main tab structure:

- Today
- Workout
- Splits
- History
- Settings

Progress and Coach are reachable through Today and Settings rather than being primary tabs, which keeps the bottom navigation focused and avoids iOS pushing extra tabs into More.

## Data Model

```text
GymTracker/Models/
  UserProfile.swift
  TrainingSplit.swift
  Exercise.swift
  WorkoutSession.swift
  ExerciseLog.swift
  SetLog.swift
  BodyweightLog.swift
  Recommendation.swift
  Enums.swift
```

Core relationships:

- `TrainingSplit` has many `SplitExercise` records.
- `SplitExercise` stores split-template targets: exercise snapshot name, order, sets, rep range, rest, and notes.
- `Exercise` is the reusable exercise library source.
- `WorkoutSession` has many `ExerciseLog` records.
- `ExerciseLog` snapshots exercise targets for a specific workout.
- `ExerciseLog` has many `SetLog` records.
- `SetLog` stores weight, reps, RPE, completion, and set number.

Important `WorkoutSession` fields:

- `startedAt` and `endedAt` store clock timestamps.
- `pausedAt` and `accumulatedPausedSeconds` support pausing the live timer.
- `durationSeconds` stores exact active workout duration after finishing.
- `durationMinutes` remains for compatibility and summary use.
- `perceivedDifficulty` stores the post-workout facial rating score.

## Services

```text
GymTracker/Services/
  SeedDataService.swift
  CoachRecommendationEngine.swift
```

`SeedDataService` seeds the personal exercise library and active Push/Pull/Legs split templates. It contains the current baseline exercises, rep ranges, target sets, and notes.

`CoachRecommendationEngine` owns deterministic coaching logic outside the views. It currently:

- Recommends the next Push/Pull/Legs day.
- Explains why that split is suggested.
- Produces exercise-level progression recommendations.
- Detects simple fatigue and weekly set-count warnings.
- Flags missed split frequency.
- Detects early plateau signals.
- Produces weekly summary insights.

## Views

```text
GymTracker/Views/
  Today/
  Workout/
  Splits/
  History/
  Progress/
  Coach/
  Settings/
  Shared/
```

## Today

The Today screen is the app’s overview. It shows the suggested training day, recent weekly context, and shortcuts into Coach and Progress.

Design purpose:

- Fast answer to “what should I train?”
- A lightweight dashboard, not a landing page.

## Workout

Workout contains the main session flow:

- Resume unfinished workout.
- Start from Push, Pull, or Legs.
- Select today’s exercises manually.
- Preserve selected exercise order.
- Add optional Abdominal Crunch across split days.
- Log one current exercise at a time.
- Add sets with previous set/session values copied forward.
- Pause and resume the active workout timer.
- Finish with a facial workout rating.
- Show a motivational transition popup between exercises and after finishing.

The timer now tracks active time rather than raw wall-clock time, so paused time does not inflate the final session duration.

Current design note:

- The previous readiness section was removed because it added friction without a clear enough purpose. Future readiness work should be redesigned as a single low-friction control or coach interpretation rather than several segmented rows.

## Splits

Splits presents Push, Pull, and Legs as training days within the personal PPL programme.

Design purpose:

- Keep the mental model simple.
- Avoid treating Push/Pull/Legs as unrelated programmes.

## History

History includes:

- Calendar with workout days highlighted.
- Completed workout list.
- Swipe-to-delete for previous workouts.
- Workout detail summaries.
- Historic workout editing without the live continue/motivation flow.
- Exact duration display when available.

Delete swipe actions use standard Apple destructive red rather than the selected app theme colour.

## Progress

Progress includes:

- Exercise list.
- Per-exercise trend details.
- Swift Charts for estimated 1RM and best-set history.

The chart navigation is intentionally lazy: the app opens an exercise picker first and renders charts only after selecting one exercise. This avoids freezing from trying to mount many Swift Charts at once.

## Coach

Coach uses `CoachRecommendationEngine` and currently shows:

- Next Workout card.
- Exercise Recommendations card.
- Recovery Warnings card.
- Weekly Summary card.

Removed/paused idea:

- Readiness check was removed from the visible UX. It can return later, but it should be redesigned around a clearer training decision, such as “Full / Quick / Recovery / Heavy,” instead of asking several separate questions.

## Settings

Settings owns:

- Training setup.
- Themes.
- Exercise library.
- Progress/Coach links.
- Safety copy.
- Profile and local data notes.

## Theme System

```text
GymTracker/Views/Shared/AppTheme.swift
```

The theme system provides:

- Accent colour selection.
- Light/Dark/System appearance.
- Environment access through `appTheme`.
- App-wide `.tint(...)` application.

Current Workout Green primary accent:

```text
#7CFC00
```

Because the app applies a global tint, destructive actions should explicitly use `.tint(.red)` when Apple’s standard delete styling is expected.

## Assets

```text
GymTracker/Assets.xcassets/
  AppIcon.appiconset/
  AccentColor.colorset/
```

The app icon is a white-background green lifting symbol. Accent colour is aligned with Workout Green.

## Persistence

The app currently uses local SwiftData storage. iCloud/CloudKit sync is not enabled in code because it requires correct Apple signing, capabilities, and container setup. This keeps the project stable for free Apple ID installs and simulator testing.

## Current Design Constraints

- Keep workout start fast.
- Avoid adding controls that slow down a real gym session.
- Keep Push/Pull/Legs as the core structure.
- Use kg by default.
- Keep set logging dense and direct.
- Keep chart rendering lazy.
- Use standard iOS destructive styling for deletion.
- Keep coaching deterministic and explainable.

## Good Next Design Directions

- Replace readiness with workout modes: Full, Quick, Recovery, Heavy.
- Add a cleaner pre-workout preview showing selected exercises, prior bests, and suggested targets.
- Add a persistent live-session header with timer, pause, exercise count, and finish action.
- Add per-exercise progression badges: increase load, repeat, reduce, possible plateau.
- Add a session summary screen after finishing instead of only a popup.
- Add richer history filtering by split day, exercise, and rating.
- Add bodyweight trend charts if bodyweight logging becomes a regular habit.
