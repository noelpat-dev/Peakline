# Architecture

## Technical Stack

- Platform: iOS
- UI: SwiftUI
- Persistence: SwiftData
- Charts: Swift Charts
- Architecture style: local-first, feature-folder SwiftUI views with shared SwiftData models
- Coaching strategy: deterministic rule-based logic, no AI APIs

## App Entry

```text
GymTracker/App/
  GymTrackerApp.swift
  RootTabView.swift
```

`GymTrackerApp` creates the SwiftData `ModelContainer` and wraps the app with `AppThemeProvider`. `RootTabView` owns the main tab structure:

- Today
- Workout
- Splits
- History
- Settings

Progress and Coach are currently reachable through Today and Settings to avoid iOS automatically nesting extra tabs under More.

## Models

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

Important relationships:

- `TrainingSplit` has many `SplitExercise` records.
- `WorkoutSession` has many `ExerciseLog` records.
- `ExerciseLog` has many `SetLog` records.
- `Exercise` is the reusable exercise library source.
- `SplitExercise` snapshots exercise name and target programming at split-template level.
- `ExerciseLog` snapshots exercise name and targets at workout-session level.

## Services

```text
GymTracker/Services/
  SeedDataService.swift
```

`SeedDataService` seeds the personalised exercise library and active Push/Pull/Legs training days. Future Coach V2 work should add a dedicated `CoachRecommendationEngine` service here.

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

### Today

Shows the next suggested PPL day, quick actions, weekly stats, and shortcuts to Coach and Progress & Charts.

### Workout

Contains split selection, exercise selection, live workout logging, set entry, timer, post-workout rating, and completion messaging.

### Splits

Presents Push/Pull/Legs as one programme with Push, Pull, and Legs as training days.

### History

Shows a calendar, workout list, workout detail, delete actions, and historic editing.

### Progress

Shows latest exercise performance plus per-exercise and global trend charts.

### Coach

Currently provides rule-based PPL rotation suggestions, progressive-overload advice, and weekly stats. Coach V2 should expand this into modular recommendation cards.

### Settings

Owns profile editing, exercise library, theme selection, Progress/Coach links, safety copy, and iCloud backup notes.

### Shared

Reusable UI utilities including the app theme system.

## Theme System

`AppTheme.swift` defines:

- Theme colour choices.
- Light/Dark/System appearance mode.
- Environment injection for `appTheme`.

The Workout Green primary accent is `#7CFC00`.

## Persistence

The app currently uses local SwiftData storage. iCloud/CloudKit sync is not enabled in code because it requires correct Apple signing and iCloud container capabilities. This keeps the app stable for free Apple ID development installs.
