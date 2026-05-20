# App Feature Summary

This file is kept as a compatibility note for earlier Codex sessions.

The canonical product summary now lives in:

- [FEATURE_SUMMARY.md](FEATURE_SUMMARY.md)

The implementation plan now lives in:

- [ROADMAP.md](ROADMAP.md)
- [NEXT_TASK.md](NEXT_TASK.md)
- [NEXT_CODEX_CHAT.md](NEXT_CODEX_CHAT.md)

The technical direction now lives in:

- [ARCHITECTURE.md](ARCHITECTURE.md)
- [gym_tracker_ios_codex_development_brief.md](gym_tracker_ios_codex_development_brief.md)
- [UI_STYLE_GUIDE.md](UI_STYLE_GUIDE.md)
- [KNOWN_ISSUES.md](KNOWN_ISSUES.md)

## Current Product Direction

Peakline should be a personal, local-first lifting coach for Noel's Push/Pull/Legs training. The app should keep the fast workout logger that already exists, but the long-term value should come from coaching: clear next-session targets, useful split recommendations, simple fatigue warnings, exact exercise visuals, and a clean Apple Fitness-inspired visual style.

The app should not become a generic social fitness app, a nutrition app, or an AI chatbot in the first serious version.

## Current Implementation Focus

The next development cycle should focus on a visual QA and polish pass now that the main UI/coaching foundations are in place:

1. **Light and dark mode QA**
   - Today.
   - Workout.
   - Workout Preview.
   - Live Workout Logger.
   - Splits.
   - History.
   - Settings.

2. **Exact exercise icon coverage**
   - Source PNGs live in `GymTracker/IconSource/ExerciseIcons/`.
   - Generated assets live in `GymTracker/Assets.xcassets/ExerciseIcons/`.
   - Add source filenames to `Scripts/prepare_exercise_icons.py`.
   - Map exercise names through `ExerciseIconMapper`.

3. **Small polish fixes only**
   - Unreadable text.
   - Wrong card surfaces.
   - Destructive buttons using accent blue.
   - Icons that are too small or generic when an exact PNG exists.

## Important Product Constraint

A multi-question readiness form was previously removed because it added too much friction. Do not reintroduce it as several separate questions. If recovery/readiness logic returns later, it should be expressed through one low-friction decision such as workout mode selection: Full, Quick, Recovery, or Heavy.

## Current Codex Goal

Use [NEXT_TASK.md](NEXT_TASK.md) as the immediate Codex task and [NEXT_CODEX_CHAT.md](NEXT_CODEX_CHAT.md) as the next full prompt.
