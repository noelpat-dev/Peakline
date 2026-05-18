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

GymTracker should become a personal, local-first lifting coach for Noel's Push/Pull/Legs training. The app should keep the fast workout logger that already exists, but the long-term value should come from coaching: clear next-session targets, useful split recommendations, simple fatigue warnings, and a clean Apple Fitness-inspired visual style.

The app should not become a generic social fitness app, a nutrition app, or an AI chatbot in the first serious version.

## Current Implementation Focus

The next development cycle should focus on four connected improvements:

1. **Apple Fitness-inspired UI refresh**
   - Dark-first dashboard feel.
   - High-contrast cards.
   - Rounded panels.
   - Large metric typography.
   - Accent-driven progress visuals.
   - Smooth, simple SwiftUI transitions.

2. **Workout modes**
   - Full.
   - Quick.
   - Recovery.
   - Heavy.

3. **Shared target suggestion logic**
   - Workout selection and Coach should use the same target rules.
   - Avoid duplicate progression logic inside views.

4. **Better coaching cards**
   - Next workout.
   - Exercise targets.
   - Recovery warnings.
   - Weekly summary.
   - Session recap after finishing.

## Important Product Constraint

A multi-question readiness form was previously removed because it added too much friction. Do not reintroduce it as several separate questions. If recovery/readiness logic returns later, it should be expressed through one low-friction decision such as workout mode selection: Full, Quick, Recovery, or Heavy.

## Current Codex Goal

Use [NEXT_TASK.md](NEXT_TASK.md) as the immediate Codex task and [NEXT_CODEX_CHAT.md](NEXT_CODEX_CHAT.md) as the next full prompt.
