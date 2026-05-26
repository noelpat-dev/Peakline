# Peakline

Peakline is a local-first SwiftUI and SwiftData lifting coach built around Noel's Push/Pull/Legs training. The app focuses on fast workout logging, practical progression targets, explainable coaching, useful history, and recovery context that stays on device.

## Product Goal

Peakline should answer three questions quickly:

1. What should I train today?
2. What did I do last time?
3. What target should I aim for next?

The app should feel gym-ready: quick to open, easy to use mid-session, and clear about why it suggests a target, mode change, or recovery adjustment.

## Canonical Docs

Use these root docs as the active source of truth:

- [FEATURE_SUMMARY.md](FEATURE_SUMMARY.md) for current product and feature state.
- [ARCHITECTURE.md](ARCHITECTURE.md) for implementation map and guardrails.
- [ROADMAP.md](ROADMAP.md) for current priorities and later backlog.
- [UI_STYLE_GUIDE.md](UI_STYLE_GUIDE.md) for the active visual direction.
- [KNOWN_ISSUES.md](KNOWN_ISSUES.md) for current risks and regression checks.
- [PERFORMANCE_ACCEPTANCE_GOAL.md](PERFORMANCE_ACCEPTANCE_GOAL.md) for the performance acceptance workflow and verifier.
- [NEXT_TASK.md](NEXT_TASK.md) for the immediate task.
- [NEXT_CODEX_CHAT.md](NEXT_CODEX_CHAT.md) for the ready-to-paste Codex handoff prompt.

Historical prompts, phase reports, QA reports, and older planning docs are indexed in [Docs/AUDIT_INDEX.md](Docs/AUDIT_INDEX.md). Archived files are for reference only and should not be treated as active instructions unless a task explicitly calls for them.

## Current App Surface

The current app includes:

- Today dashboard with quick actions into Coach, Workout, Nutrition, Progress, Sleep, and Hydration.
- Workout start flow, Workout Preview, live workout logging, templates, substitutions, skipped reasons, and session summary.
- Coach dashboard with warm-start snapshot behavior, weekly review, action history, and deterministic recommendations.
- Splits, History, and Progress surfaces.
- Nutrition logging, barcode import, OCR label scan, parser review, source comparison, and HealthKit bridge work.
- Sleep and nap tracking, hydration tracking, themes, export utilities, and exact exercise icon support.

## Codex Workflow

For a new Codex session, start with:

- [NEXT_TASK.md](NEXT_TASK.md)
- [NEXT_CODEX_CHAT.md](NEXT_CODEX_CHAT.md)
- [FEATURE_SUMMARY.md](FEATURE_SUMMARY.md)
- [ARCHITECTURE.md](ARCHITECTURE.md)
- [ROADMAP.md](ROADMAP.md)
- [UI_STYLE_GUIDE.md](UI_STYLE_GUIDE.md)
- [KNOWN_ISSUES.md](KNOWN_ISSUES.md)
- [PERFORMANCE_ACCEPTANCE_GOAL.md](PERFORMANCE_ACCEPTANCE_GOAL.md) when the work touches performance-sensitive flows

Default rule:

```text
Only implement the task described in NEXT_TASK.md unless the user explicitly redirects scope.
```

## Requirements

- macOS with Xcode installed.
- iOS 17+ simulator or a real iPhone.
- SwiftUI.
- SwiftData.
- Swift Charts.
- For real-device installs, use Xcode signing with an Apple ID.

## Run Locally

Open the project:

```bash
open GymTracker.xcodeproj
```

In Xcode:

1. Select the `GymTracker` scheme.
2. Select an iPhone simulator or connected iPhone.
3. Press `Cmd+B` to build.
4. Press `Cmd+R` to run.

Command-line build:

```bash
xcodebuild -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

## Validation

General validation:

```bash
git diff --check
xcodebuild -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

Performance-sensitive validation:

```bash
Scripts/verify_performance_acceptance.sh
```

That verifier runs a build, unit tests, the focused UI acceptance test, and log scanning for the recent performance and navigation regressions.

## Exercise Icons

Exact source PNGs live in:

```text
GymTracker/IconSource/ExerciseIcons/
```

Generated asset-catalog icons live in:

```text
GymTracker/Assets.xcassets/ExerciseIcons/
```

When mapping a new source icon, update `Scripts/prepare_exercise_icons.py`, confirm `ExerciseIconKey`, update `ExerciseIconMapper`, then run:

```bash
python3 Scripts/prepare_exercise_icons.py
```

## Real iPhone Install

Free Apple ID installs usually expire after about 7 days. A paid Apple Developer account is recommended for longer-lived development installs and future iCloud or CloudKit work.
