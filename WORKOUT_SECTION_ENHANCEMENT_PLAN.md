# GymTracker Workout Section Enhancement Plan

## Purpose

The Workout section should become the strongest part of GymTracker. It should not feel like a basic place to start Push, Pull, or Legs. It should feel like a live training assistant that helps the user prepare, execute, adjust, and review a workout quickly.

The current app already has a useful base:

- Start Push, Pull, Legs, or an empty workout.
- Select exercises before starting.
- Preserve the order exercises are selected.
- Show previous best performance and a suggested target before starting.
- Use a live workout timer.
- Log one exercise at a time.
- Add sets with weight, reps, and optional RPE.
- Prefill previous-session weight and reps when history exists.
- Finish with a workout rating and motivational message.

The issue is that the Workout section still feels like a logger rather than a guided workout flow.

This plan upgrades it into a full workout experience.

---

## Product Goal

The Workout section should answer these questions during the full session lifecycle:

1. **Before training:** What should I do today, and how hard should I go?
2. **During training:** What set should I do next, and am I on track?
3. **After training:** Did I improve, and what should I do next time?

The app should stay fast and avoid friction. Do not reintroduce a multi-question readiness form. Use one-tap workout modes instead.

---

## Design Direction

The Workout section should use the Apple Fitness-inspired GymTracker style already planned:

- Dark-first interface.
- Large metric typography.
- Rounded cards.
- High-contrast Workout Green accent.
- SF Symbols.
- Clear progress indicators.
- Large tap targets.
- Minimal typing during a live workout.

Do not copy Apple's exact Fitness app screens, Activity Rings, icons, or branded visual identity. Build an original lifting-focused version.

---

# Feature Roadmap

## Phase 1 — Workout Home Redesign

### Goal
Make the Workout tab feel like the user's training command centre.

### Current Problem
The current Workout section is functional but limited. It starts workouts, but it does not give enough context, urgency, or coaching before the user begins.

### New Workout Home Layout

Create a `WorkoutHomeView` with:

1. **Active Workout Card**
   - Show only if an unfinished workout exists.
   - Large timer / elapsed active time.
   - Split name.
   - Exercises completed.
   - Resume button.
   - End/discard option.

2. **Recommended Workout Card**
   - Suggested next split.
   - Short reason.
   - Start button.
   - Link to Coach details.

3. **Split Start Cards**
   - Push.
   - Pull.
   - Legs.
   - Empty Workout.

Each split card should show:

- Last trained date.
- Estimated duration.
- Exercise count.
- Coach badge, such as Ready, Repeat, Progress, Fatigue Risk, or Plateau.

4. **Recent Session Card**
   - Last workout split.
   - Duration.
   - Rating.
   - Best set improvement if any.

### Acceptance Criteria

- User can still start Push, Pull, Legs, or empty workout quickly.
- Resume active workout is visually obvious.
- Recommended split is clear.
- Workout tab feels like a dashboard, not a plain menu.
- No existing workout logging functionality is removed.

---

## Phase 2 — Workout Modes

### Goal
Let the user adapt the session in one tap without a friction-heavy readiness form.

### Modes

#### Full
Default mode.

Use normal split exercise list and target set counts.

#### Quick
For limited time.

Rules:

- Prioritise compound or main exercises.
- Reduce accessory exercises.
- Reduce accessory set count.
- Estimate 20–40 minutes.
- Messaging: "Short session. Hit the important lifts first."

#### Recovery
For tired or sore days.

Rules:

- Reduce working sets.
- Avoid aggressive load increases.
- Encourage controlled reps.
- Use lighter target language.
- Messaging: "Lower stress session. Keep form clean and avoid forcing PRs."

#### Heavy
For higher-effort days.

Rules:

- Prioritise compound lifts.
- Keep accessories secondary.
- Highlight progression opportunities.
- Messaging: "Push the main lifts, then keep accessories efficient."

### Implementation

Add enum in `Enums.swift`:

```swift
enum WorkoutMode: String, Codable, CaseIterable, Identifiable {
    case full
    case quick
    case recovery
    case heavy

    var id: String { rawValue }
}
```

Create:

```text
GymTracker/Services/WorkoutModePlanner.swift
```

Responsibilities:

- Adjust exercise priority by mode.
- Adjust target set count by mode.
- Adjust recommendation language by mode.
- Estimate duration.
- Avoid persistence changes at first if migration is risky.

### Acceptance Criteria

- Full mode is default.
- User chooses a mode before preview/start.
- Quick mode reduces workout length.
- Recovery mode avoids aggressive overload suggestions.
- Heavy mode emphasises main lifts.
- No multi-question readiness form appears.

---

## Phase 3 — Workout Preview Screen

### Goal
Create a bridge between Coach and the live workout logger.

### Screen Name

`WorkoutPreviewView`

### Entry Points

- Workout tab split card.
- Today suggested workout card.
- Coach next workout card.
- Splits screen start button.

### Layout

1. **Header**
   - Split name.
   - Selected workout mode.
   - Estimated duration.
   - Start button.

2. **Mode Selector**
   - Full.
   - Quick.
   - Recovery.
   - Heavy.

3. **Coach Summary Card**
   - "Recommended target: repeat most lifts, push Bench Press."
   - One sentence only.

4. **Exercise Target List**
   Each exercise row should show:

   - Exercise name.
   - Last best set.
   - Suggested target.
   - Badge: Increase, Add Reps, Repeat, Reduce, Plateau, Fatigue Risk.
   - Short reason.

5. **Exercise Controls**
   - Remove exercise.
   - Reorder exercise.
   - Add optional exercise.
   - Add core exercise.

6. **Start Workout Button**
   - Sticky at bottom if possible.

### Acceptance Criteria

- User sees last performance before starting.
- User sees exact target before starting.
- User can remove/reorder exercises.
- User can switch mode and see target/volume changes.
- Starting a workout creates the same existing `WorkoutSession` and `ExerciseLog` structure.

---

## Phase 4 — Shared Target Suggestion Service

### Goal
Workout, Coach, Splits, and Preview should all show the same exercise target.

### Problem
If every view calculates suggestions separately, Coach and Workout can disagree.

### Service

Create:

```text
GymTracker/Services/TargetSuggestionService.swift
```

### Non-Persistent Types

```swift
struct TargetSuggestion {
    let exerciseName: String
    let lastBestSetDescription: String?
    let suggestedWeight: Double?
    let suggestedReps: Int?
    let recommendationType: TargetRecommendationType
    let reason: String
    let confidence: Double
}

enum TargetRecommendationType: String, Codable, CaseIterable {
    case baseline
    case addReps
    case repeatTarget
    case increaseLoad
    case reduceLoad
    case possiblePlateau
    case fatigueRisk
}
```

### Rules

No history:

- Recommendation: baseline.
- Reason: "No previous data. Start with the planned rep range."

Hit top of rep range:

- Recommendation: increaseLoad.
- Reason: "You reached the top of the rep range last time."

Within rep range:

- Recommendation: addReps or repeatTarget.
- Reason: "You are progressing within the target range."

Below minimum reps:

- Recommendation: repeatTarget or reduceLoad.
- Reason: "Last performance was below the target range."

Two-session performance drop:

- Recommendation: fatigueRisk.
- Reason: "Performance has dropped across recent sessions."

Three-session stall:

- Recommendation: possiblePlateau.
- Reason: "No clear improvement across recent appearances."

### Acceptance Criteria

- Workout Preview uses this service.
- Coach uses this service.
- Split badges can use this service later.
- Views display suggestions but do not calculate progression themselves.

---

## Phase 5 — Live Workout Header

### Goal
Make the live workout screen feel more controlled and polished.

### Component

Create:

```text
GymTracker/Views/Shared/LiveWorkoutHeader.swift
```

### Header Contents

- Active timer.
- Pause/resume button.
- Current exercise index, for example `2 of 5`.
- Current workout mode.
- Finish button.
- Optional progress bar through exercises.

### Behaviour

- Header stays visible at top of live workout.
- Timer uses active duration, not paused time.
- Finish remains accessible but not too easy to tap accidentally.

### Acceptance Criteria

- User always knows workout time.
- User always knows where they are in the workout.
- Pause/resume is visible.
- Finish is visible.
- Live logger remains fast.

---

## Phase 6 — Better Set Entry

### Goal
Make logging sets much faster.

### Improvements

1. **Quick Adjust Buttons**
   - `-2.5kg`
   - `+2.5kg`
   - `-1 rep`
   - `+1 rep`
   - Copy previous set.
   - Copy last session.

2. **Set Row States**
   - Planned.
   - Completed.
   - Warm-up.
   - Missed / skipped.

3. **One-Tap Completion**
   - Tap checkbox to mark set complete.
   - If weight/reps exist, save automatically.

4. **Set Suggestions**
   For next set:

   - "Repeat 60kg x 8."
   - "Try 60kg x 9 if set 1 felt easy."
   - "Drop to 57.5kg if RPE was too high."

5. **Exercise Notes Drawer**
   - Small optional notes field.
   - Hidden by default.
   - Does not clutter main set entry.

### Acceptance Criteria

- User can log a set with minimal typing.
- Previous values are easy to copy.
- Warm-up sets remain separate from working sets.
- Set entry remains dense and gym-friendly.

---

## Phase 7 — Rest Timer

### Goal
Add a practical in-session utility that improves the workout experience.

### Behaviour

- Starts automatically after completing a working set if enabled.
- Uses default rest seconds from `SplitExercise` if available.
- User can choose quick rest options:
  - 60s.
  - 90s.
  - 120s.
  - 180s.
- User can skip or add time.
- In-app timer first. Avoid background notification complexity initially.

### UI

Show as a compact card or bottom sheet:

- Countdown.
- Exercise name.
- Next set number.
- Add 30s.
- Skip.

### Implementation

Create:

```text
GymTracker/Services/RestTimerManager.swift
GymTracker/Views/Workout/RestTimerView.swift
```

### Acceptance Criteria

- Completing a set can trigger rest timer.
- Timer can be skipped.
- Timer does not block set entry.
- App remains usable without enabling rest timer.

---

## Phase 8 — Plate Calculator

### Goal
Help the user load barbells quickly.

### Behaviour

- Input target weight.
- Default bar weight: 20kg.
- Default available plates:
  - 20kg.
  - 15kg.
  - 10kg.
  - 5kg.
  - 2.5kg.
  - 1.25kg.
- Show plates per side.

### Entry Points

- From set row.
- From exercise target row.
- From live workout tools menu.

### Implementation

Create:

```text
GymTracker/Services/PlateCalculator.swift
GymTracker/Views/Workout/PlateCalculatorView.swift
```

### Acceptance Criteria

- User can calculate plates from a target set weight.
- Supports kg-first.
- Does not clutter normal set logging.

---

## Phase 9 — Exercise Substitutions

### Goal
Make the app useful when equipment is busy or an exercise is not suitable today.

### User Flow

On an exercise in Preview or Live Workout:

- Tap `Substitute`.
- Choose reason:
  - Equipment busy.
  - Exercise hurts.
  - No time.
  - Prefer alternative.
- App shows alternatives with same primary muscle / movement pattern.

### Example

If Bench Press unavailable:

- Dumbbell Bench Press.
- Machine Chest Press.
- Push-Up.

### Implementation

Create:

```text
GymTracker/Services/ExerciseSubstitutionService.swift
```

Use existing exercise metadata where possible:

- Primary muscle.
- Secondary muscles.
- Movement pattern.
- Equipment.
- Compound/isolation.

### Acceptance Criteria

- User can swap an exercise before starting.
- User can swap during workout.
- The workout session logs the substituted exercise correctly.
- Original split template is not changed unless user explicitly chooses to update it.

---

## Phase 10 — Session Summary Screen

### Goal
Make workout completion more useful than a motivational popup.

### Screen Name

`SessionSummaryView`

### Data Service

Create:

```text
GymTracker/Services/SessionSummaryBuilder.swift
```

### Show

- Duration to the second.
- Split trained.
- Workout mode.
- Completed exercises.
- Working sets.
- Rating.
- Best set improvements.
- PRs or near-PRs.
- Coach takeaway.
- Suggested next split.

### Example Takeaway

"Strong Push session. Bench matched your top target and lateral raises improved by 2 reps. Next suggested workout: Pull."

### Actions

- Done.
- View History Detail.
- Start next recommended split later.

### Acceptance Criteria

- Finishing a workout opens summary.
- Summary can be dismissed to Today, Workout, or History.
- History editing still works.
- Rating-specific motivation is preserved but moved into a richer summary.

---

## Phase 11 — In-Workout Coaching

### Goal
Give lightweight guidance during the workout without becoming annoying.

### Coaching Moments

1. **Before exercise**
   - "Last best: 60kg x 10. Target today: 60kg x 11 or 62.5kg x 8."

2. **After set**
   - "Good. Repeat this weight."
   - "If that felt easy, add 1 rep next set."
   - "Large drop. Consider resting longer."

3. **Before finishing**
   - "You skipped 2 planned exercises. Finish anyway?"

### Acceptance Criteria

- Coaching is short and actionable.
- No long explanations during live workout.
- User can ignore coaching and continue logging.

---

## Phase 12 — Workout Editing and Reuse

### Goal
Make workouts easier to repeat, revise, and recover from mistakes.

### Features

1. **Repeat Last Workout**
   - Start from previous session's exercise list and targets.

2. **Save Workout as Template**
   - Save custom workout structure.

3. **Update Split from Workout**
   - If user substituted exercises, optionally update the split template.

4. **Undo Finish / Reopen Session**
   - Useful if user accidentally finishes.

5. **Skipped Exercise Reason**
   - Not enough time.
   - Equipment busy.
   - Too fatigued.
   - Injury/discomfort.

### Acceptance Criteria

- User can recover from accidental changes.
- User can reuse a good workout.
- Split templates remain stable unless explicitly updated.

---

# Recommended Implementation Order for Codex

## Codex Pass 1 — Workout Modes + Planner

Implement:

- `WorkoutMode` enum.
- `WorkoutModePlanner` service.
- Mode selector in workout start flow.
- Mode-adjusted set count and messaging.

Do not persist `workoutMode` on `WorkoutSession` yet unless migration is tested.

## Codex Pass 2 — Target Suggestions + Preview

Implement:

- `TargetSuggestionService` if not already done.
- `WorkoutPreviewView`.
- `ExerciseTargetRow` usage.
- Estimated duration.
- Exercise remove/reorder.
- Start workout from preview.

## Codex Pass 3 — Live Workout UX

Implement:

- `LiveWorkoutHeader`.
- Quick set adjustment buttons.
- Better set row states.
- Exercise notes drawer.
- Improved finish confirmation.

## Codex Pass 4 — Session Summary

Implement:

- `SessionSummaryBuilder`.
- `SessionSummaryView`.
- PR/improvement detection.
- Suggested next split after finish.
- Navigation from finish to summary.

## Codex Pass 5 — Utilities

Implement:

- Rest timer.
- Plate calculator.
- In-workout tools menu.

## Codex Pass 6 — Substitutions and Reuse

Implement:

- Exercise substitution service.
- Substitute flow in Preview and Live Workout.
- Repeat last workout.
- Save workout as template.
- Optional update split from workout.

---

# Codex Prompt: Workout Section Upgrade

Paste this into Codex when you want to start the Workout section enhancement.

```text
You are working on the existing GymTracker SwiftUI iOS app.

Goal:
Upgrade the Workout section from a basic workout starter/logger into a guided workout experience.

Important context:
- The app is local-first.
- It uses SwiftUI and SwiftData.
- It follows Noel's Push/Pull/Legs workflow.
- It already has workout logging, exercise selection, previous performance prefill, timer pause/resume, history, progress, and basic Coach.
- Do not add AI APIs, networking, HealthKit, Apple Watch, subscriptions, or cloud sync.
- Do not reintroduce the removed multi-question readiness form.
- Use one-tap workout modes instead: Full, Quick, Recovery, Heavy.
- Keep workout logging fast and dense.
- Avoid large unrelated refactors.
- Keep code compile-ready.

Implement this vertical slice first:

1. Add `WorkoutMode` enum.
2. Add `WorkoutModePlanner` service.
3. Add a mode selector to the workout start flow.
4. Add `WorkoutPreviewView` before the live logger.
5. Preview should show:
   - selected split
   - selected mode
   - estimated duration
   - exercises in order
   - last best set
   - suggested target
   - remove/reorder controls
   - start workout button
6. Use existing workout creation logic when starting from preview.
7. Do not persist new fields on SwiftData models unless migration is tested and safe.
8. Do not remove existing workout start or logging functionality.

If `TargetSuggestionService` already exists, use it.
If it does not exist, create a small non-persistent service foundation that returns:
- exercise name
- last best set description
- suggested weight
- suggested reps
- recommendation type
- reason
- confidence

Validation:
Run:

git diff --check
xcodebuild -project GymTracker.xcodeproj -scheme GymTracker -configuration Debug -destination 'platform=iOS Simulator,id=B4892393-2EDB-4816-A09B-A18C3161823C' build

At the end, report:
- files created
- files modified
- what changed
- whether validation passed
- what should be implemented next
```

---

# Priority Recommendation

Do not start with rest timer or plate calculator first.

The best next step is:

1. Workout modes.
2. Workout preview.
3. Shared target suggestions.
4. Live workout header.
5. Session summary.

This gives the Workout section a complete before/during/after flow. Rest timer, plate calculator, and substitutions become much more useful after that foundation is in place.

