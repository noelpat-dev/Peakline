# Roadmap

This roadmap follows the current practical training-coach direction: progressive overload, clear Push/Pull/Legs rotation, fast logging, useful history, and an Apple Fitness-inspired interface.

## Product North Star

Peakline should become the app that tells Noel:

- What to train today.
- What target to aim for.
- Whether to push, repeat, or recover.
- How training is progressing over time.

The app should be useful without requiring accounts, cloud sync, AI APIs, social features, nutrition tracking, or Apple Watch support in the first serious version.

## Phase 0: Stabilise Current Build

Status: Mostly done.

Goals:

- Keep project compile-ready.
- Keep local SwiftData stable.
- Avoid broad refactors.
- Keep workout logging fast.

Tasks:

- Confirm current build works.
- Commit stable baseline before UI/coach work.
- Keep `git diff --check` clean.

## Phase 1: Apple Fitness-Inspired Design Foundation

Status: Mostly done.

Goal: create reusable UI components before redesigning screens.

Tasks:

1. Create shared components:
   - `FitnessCard`.
   - `MetricTile`.
   - `CoachBadgeView`.
   - `ExerciseTargetRow`.
   - `ProgressArcView`.
   - `SplitCardView`.

2. Update theme system:
   - Semantic card background.
   - Semantic border.
   - Muted text.
   - Warning/danger/success tokens.

3. Apply to limited screens first:
   - Today.
   - Coach.
   - Workout Preview once built.

Acceptance criteria:

- App still compiles.
- Existing app theme support still works.
- Destructive actions remain red.
- No exact clone of Apple Activity Rings.

## Phase 2: Shared Target Suggestion Logic

Status: Done, continuing to refine rules as real workouts expose edge cases.

Goal: remove duplicated target logic and make Coach/Workout consistent.

Tasks:

1. Create `TargetSuggestionService`.
2. Create `TargetSuggestion` non-persistent model.
3. Create `TargetRecommendationType` enum.
4. Use it in:
   - Workout exercise selection.
   - Coach exercise recommendations.
   - Future split badges.

Rules:

- If user hit top of rep range, suggest load increase.
- If user is within range, suggest repeat/add reps.
- If below minimum, suggest repeat or reduce.
- If performance drops twice, warn fatigue.
- If no improvement for three appearances, warn plateau.

Acceptance criteria:

- Coach and Workout show the same target for the same exercise.
- Every target has a short reason.
- No view contains duplicate progression logic.

## Phase 3: Workout Modes and Workout Preview

Status: Mostly done.

Goal: make the app adaptable without reintroducing a friction-heavy readiness form.

Workout modes:

- Full.
- Quick.
- Recovery.
- Heavy.

Tasks:

1. Add `WorkoutMode` enum.
2. Store selected mode on `WorkoutSession` if migration is safe.
3. Create `WorkoutModePlanner`.
4. Add mode selector before workout start.
5. Build Workout Preview screen.

Workout Preview should show:

- Split name.
- Selected mode.
- Estimated duration.
- Exercise order.
- Last best set.
- Suggested target.
- Remove/reorder controls.
- Start session.

Acceptance criteria:

- User can start a workout with Full mode as default.
- Quick mode reduces accessory volume.
- Recovery mode lowers volume and aggressive target messaging.
- Heavy mode prioritises compounds.
- The live logger still remains fast.

## Phase 4: Coach Cards V2

Status: Mostly done, needs ongoing copy and layout polish.

Goal: make Coach action-focused.

Cards:

- Next Workout.
- Today's Targets.
- Recovery Warnings.
- Weekly Summary.
- Progress Opportunities.
- Missed Split Warning.

Tasks:

1. Restyle Coach with shared `FitnessCard` components.
2. Use `TargetSuggestionService` for target cards.
3. Use workout mode context where available.
4. Shorten explanations.
5. Add clear CTAs.

Acceptance criteria:

- Coach tells the user what to do next.
- Coach explains why.
- Coach does not overwhelm with too much analytics.

## Phase 5: Session Summary Screen

Status: Done, polish as needed.

Goal: make finishing a workout more useful and motivating.

Tasks:

1. Create `SessionSummaryBuilder`.
2. Build post-finish summary screen.
3. Show:
   - Duration.
   - Completed exercises.
   - Working sets.
   - Rating.
   - Best set improvements.
   - Suggested next split.
   - Motivational message.

Acceptance criteria:

- Finishing a workout navigates to a summary.
- Summary can be dismissed to History or Today.
- History detail remains editable.

## Phase 6: Split UI Improvements

Status: Mostly done.

Goal: make Push/Pull/Legs pages feel useful, not static.

Tasks:

- Show last trained date per split.
- Show coach badge per split.
- Show target and latest best per exercise.
- Show progression badge per exercise.
- Keep editing simple.

Acceptance criteria:

- User can open Push/Pull/Legs and immediately understand readiness/progress.
- Split editing still works.

## Phase 7: History and Analytics Improvements

Status: Partially done.

Tasks:

- History filters:
  - Split.
  - Exercise.
  - Rating.
  - Date range.
- Add PR list.
- Add split consistency chart.
- Add weekly volume overview.
- Add optional total tonnage alongside best-set volume.

Acceptance criteria:

- History stays usable after many workouts.
- Analytics remain readable.
- Charts remain lazy-loaded.

## Phase 8: Gym Utilities

Status: Partially done.

Tasks:

- Rest timer: implemented.
- Plate calculator: implemented.
- Equipment-busy substitutions: implemented.
- Exercise notes/templates.
- Local backup/export.

Remaining practical utility:

1. Local backup/export.
2. Exercise notes/templates.
3. More analytics only after visual QA is stable.

## Current Near-Term Task

Status: Next.

Run visual QA and cleanup after the UI/icon overhaul:

- Verify light and dark mode across Today, Workout, Workout Preview, Logger, Splits, History, Settings, and Themes.
- Confirm exact icon coverage for seeded exercises.
- Fix small visual bugs only.
- Keep SwiftData schema stable.

## Phase 9: Optional Advanced Features

Do later only after the core app feels excellent.

- iCloud/CloudKit sync after Apple Developer/iCloud entitlement setup.
- HealthKit integration.
- Apple Watch companion app.
- AI-generated weekly review.
- Natural language training questions.
- Advanced periodisation blocks.
- Bodyweight and measurement trends.
- Progress photos.

## Current Top 5 Next Features

1. Apple Fitness-inspired shared UI components.
2. `TargetSuggestionService`.
3. Workout modes.
4. Workout Preview screen.
5. Session Summary screen.

## Codex Strategy

Do not ask Codex to implement the entire roadmap at once.

Use one vertical slice at a time:

1. Design system components.
2. Target suggestion service.
3. Workout mode model/planner.
4. Workout preview UI.
5. Coach card integration.
6. Session summary.

Each Codex session should end with:

```bash
git diff --check
xcodebuild -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=B4892393-2EDB-4816-A09B-A18C3161823C' \
  build
```
