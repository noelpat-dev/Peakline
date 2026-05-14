# Roadmap

This roadmap follows the updated Coach V2 expansion spec in `NEXT_CODEX_CHAT.md`.

## Phase 1: Coach V2 Foundation

1. Add `CoachRecommendationEngine`.
   - Recommend next split.
   - Explain recommendation reasoning.
   - Evaluate exercise progression.
   - Detect fatigue.
   - Detect plateaus.
   - Detect missed split frequency.

2. Add `ReadinessCheck` SwiftData model.
   - Date.
   - Energy level.
   - Soreness level.
   - Available minutes.
   - Motivation level.

3. Build readiness check UI before workout start.
   - Fast tap-based input.
   - Minimal friction.
   - Store latest readiness values.

4. Rebuild Coach screen with modular cards.
   - Next Workout card.
   - Readiness card.
   - Exercise Recommendations card.
   - Weekly Summary card.
   - Recovery Warning card.

## Phase 2: Workout Adaptation

1. Build richer workout preview screen.
   - Selected split overview.
   - Coach recommendation.
   - Estimated duration.
   - Exercise list.
   - Suggested targets.
   - Last performance summaries.
   - Remove/reorder exercises.
   - Workout mode switching.

2. Add workout modes.
   - Full Workout.
   - Quick Workout.
   - Recovery Workout.
   - Heavy Workout.

3. Improve split UI.
   - Target sets.
   - Rep range.
   - Primary muscle group.
   - Last performed date.
   - Latest best set.
   - Coach badge.

## Phase 3: Coaching Intelligence

1. Expand progression logic.
   - Increase load.
   - Repeat load.
   - Reduce load.
   - Detect two-session performance drop.
   - Detect three-session plateau.

2. Add fatigue scoring.
   - Use recent ratings.
   - Use performance drops.
   - Use time since last workout.
   - Use readiness values.

3. Add deload recommendations.
   - Condition-based deload prompt.
   - Explain why deload is suggested.
   - Adapt next workout volume.

## Later Ideas

- iCloud/CloudKit sync after Apple Developer/iCloud entitlement setup.
- Export/import local backup file.
- Bodyweight progress charts.
- Rest-day persistence.
- More detailed volume and fatigue analytics.
