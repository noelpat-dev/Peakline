# Gym Tracker iOS App — Codex Development Brief

## 1. Product Summary

Build a local-first iOS gym tracker that helps Noel:

- Follow a personal Push/Pull/Legs programme.
- Log gym sessions quickly.
- Record exercises, sets, reps, weight, RPE, duration, and notes.
- Track progress over time.
- Receive explainable next-session recommendations.
- Evaluate consistency, volume, strength progression, fatigue risk, and plateaus.
- Start workouts with minimal friction.

The product should evolve from a logger into a practical coaching app.

The first serious version should remain local-first and rule-based. Do not start with AI, accounts, cloud sync, Apple Watch, subscriptions, or social features.

## 2. Product North Star

GymTracker should answer three questions:

1. **What should I train today?**
2. **What did I do last time?**
3. **What exact target should I aim for next?**

Everything else should support those answers.

## 3. Visual Direction

The app should be inspired by Apple's Fitness and Workout apps in broad principles:

- Dark-first interface.
- Large metric typography.
- Rounded dashboard cards.
- High-contrast accent colours.
- Glanceable progress visuals.
- Simple, motivating feedback.
- SF Symbols and native iOS interaction patterns.

Important: do not copy Apple's exact Activity Rings, screen designs, icons, or branding. Build an original lifting-focused style.

See `UI_STYLE_GUIDE.md`.

## 4. Recommended Tech Stack

Use:

- Swift.
- SwiftUI.
- SwiftData for local persistence.
- Swift Charts for progress graphs.
- UserNotifications only for local reminders if needed later.

Avoid in the current version:

- Login/accounts.
- Backend.
- Cloud sync.
- AI API integration.
- Apple Watch app.
- HealthKit integration.
- Subscription/payments.
- Social features.

## 5. Apple Free Provisioning Constraint

The developer does not yet have paid Apple Developer Program access.

Assume local device testing through Xcode with free provisioning. The app may need to be reinstalled periodically because free provisioning profiles expire. Do not rely on TestFlight, App Store distribution, push notifications, iCloud, or advanced entitlements for the MVP.

Use local notifications only, not remote push notifications.

## 6. Current Product Shape

The current implementation includes:

- Push/Pull/Legs programme.
- Personal exercise library.
- Workout start flow.
- Exercise selection.
- One-exercise-at-a-time logger.
- Timer with pause support.
- Set logging.
- Previous performance prefill.
- Post-workout rating.
- History calendar and editable history.
- Progress charts.
- Basic rule-based Coach.
- Theme settings.

## 7. UX Principles

During a workout, the app must stay fast.

The user should be able to:

- Start a planned workout quickly.
- Select today's exercises.
- See last performance.
- See target suggestion.
- Add/copy sets quickly.
- Pause/resume timer.
- Finish without friction.

Avoid long forms during active workouts.

## 8. Main Screens

### 8.1 Today

Purpose: daily dashboard.

Show:

- Suggested split.
- Reason.
- Weekly training progress.
- Last workout summary.
- Quick start action.
- Progress/Coach shortcuts.

Planned UI:

- Large suggested split card.
- Fitness-style metric tiles.
- Custom weekly training arc.

### 8.2 Workout

Purpose: start or resume a session.

Current features:

- Start Push, Pull, Legs, or empty workout.
- Select exercises.
- Preserve selection order.
- Start live logger.

Planned features:

- Workout mode selector.
- Workout Preview screen.
- Target suggestions from shared service.
- Estimated duration.

### 8.3 Workout Preview

Purpose: bridge Coach and live logger.

Show:

- Selected split.
- Selected mode.
- Estimated duration.
- Exercise list.
- Last best set.
- Suggested target.
- Remove/reorder controls.
- Start workout button.

### 8.4 Live Workout Logger

Purpose: log session quickly.

Show:

- Persistent live header.
- Timer.
- Pause/resume.
- Current exercise index.
- Exercise target.
- Set rows.
- Add/copy/delete set actions.
- Finish action.

### 8.5 Splits

Purpose: manage Push/Pull/Legs days.

Show:

- Split cards.
- Exercise list.
- Target sets and rep range.
- Latest best set.
- Coach badge.
- Last performed date.

### 8.6 History

Purpose: review previous sessions.

Current features:

- Calendar.
- Workout list.
- Delete.
- Edit.
- Detail view.

Planned features:

- Filters by split.
- Filters by exercise.
- Filters by rating.
- Filters by date range.
- PR/improvement markers.

### 8.7 Progress

Purpose: performance analysis.

Current features:

- Exercise details.
- Estimated 1RM trend.
- Best set data.

Planned features:

- PR list.
- Weekly progress overview.
- Split consistency.
- Optional bodyweight chart.

### 8.8 Coach

Purpose: explain what to do next.

Show cards:

- Next Workout.
- Today's Targets.
- Recovery Warnings.
- Weekly Summary.
- Progress Opportunities.

Coach should give action-focused advice, not just analytics.

### 8.9 Settings

Purpose: manage preferences.

Show:

- Training setup.
- Themes.
- Exercise library.
- Progress/Coach links.
- Safety copy.
- Local data notes.

## 9. Core Data Model

Current model files:

```text
Models/
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

## 10. Planned Non-Persistent Types

### TargetSuggestion

Used by Workout, Coach, and Splits.

Fields:

- Exercise name.
- Last best set description.
- Suggested target weight.
- Suggested target reps.
- Recommendation type.
- Reason.
- Confidence.

### TargetRecommendationType

Cases:

- baseline.
- addReps.
- repeatTarget.
- increaseLoad.
- reduceLoad.
- possiblePlateau.
- fatigueRisk.

## 11. Planned Persistent or Semi-Persistent Types

### WorkoutMode

Enum:

- full.
- quick.
- recovery.
- heavy.

This may be stored on `WorkoutSession` later, but avoid unsafe migration until tested.

## 12. Recommendation Logic

### Next Split

Use PPL rotation:

- Push -> Pull -> Legs -> Push.
- If one split is missing from the current round, suggest that split.
- If a split has been missed for too long, prioritise it.

### Exercise Progression

Rules:

- No history: baseline target.
- Hit top of rep range: suggest load increase.
- Inside rep range: repeat or add reps.
- Below minimum reps: repeat, reduce, or lower volume.
- Two-session performance drop: fatigue risk.
- Three-session stall: possible plateau.

### Workout Mode Adjustments

Full:

- Use planned exercise list and normal target sets.

Quick:

- Prioritise compounds.
- Reduce accessory sets.
- Keep target messaging practical.

Recovery:

- Reduce set count.
- Avoid aggressive overload suggestions.
- Encourage lower effort.

Heavy:

- Prioritise compounds.
- Emphasise load progression.
- Keep accessory work secondary.

## 13. Progress Metrics

Calculate:

- Best set.
- Estimated 1RM with Epley formula.
- Best-set volume.
- Optional total tonnage later.
- Weekly completed workouts.
- Working sets.
- Split consistency.
- PRs.

## 14. Feature Priorities

### Immediate

1. Shared UI components.
2. TargetSuggestionService.
3. Light Coach UI refresh.

### Next

4. Workout modes.
5. Workout Preview.
6. Session Summary.

### Then

7. Split badges.
8. History filters.
9. PR list.
10. Rest timer.
11. Plate calculator.
12. Exercise substitutions.

### Later

13. Backup/export.
14. iCloud sync.
15. HealthKit.
16. Apple Watch.
17. AI weekly review.

## 15. Codex Implementation Order

### Pass 1: UI Foundation + Target Service

Implement:

- `FitnessCard`.
- `MetricTile`.
- `CoachBadgeView`.
- `ExerciseTargetRow`.
- `TargetSuggestionService`.
- Non-persistent target suggestion types.
- Light Coach integration.

### Pass 2: Workout Modes

Implement:

- `WorkoutMode` enum.
- `WorkoutModePlanner`.
- Mode selector before workout start.
- Mode-adjusted set count messaging.

### Pass 3: Workout Preview

Implement:

- Preview screen.
- Exercise target rows.
- Estimated duration.
- Remove/reorder.
- Start workout.

### Pass 4: Session Summary

Implement:

- `SessionSummaryBuilder`.
- Post-finish summary screen.
- Improvements and next split.

### Pass 5: Split and History Improvements

Implement:

- Split coach badges.
- History filters.
- PR markers.

## 16. Codex Guardrails

Codex should:

- Keep code compile-ready.
- Avoid broad unrelated refactors.
- Avoid changing persistence unless needed.
- Avoid reintroducing the multi-question readiness form.
- Avoid copying Apple's exact UI.
- Keep all coaching explainable.
- Use reusable services and shared components.

## 17. Validation

Run after each pass:

```bash
git diff --check
xcodebuild -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=B4892393-2EDB-4816-A09B-A18C3161823C' \
  build
```

## 18. Safety Copy

Include in onboarding or settings:

> This app provides general fitness tracking and training suggestions based on your logged workouts. It is not medical advice. Stop exercising and seek professional advice if you experience pain, dizziness, or symptoms that concern you.
