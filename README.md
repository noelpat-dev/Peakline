# Peakline

Peakline is a local-first SwiftUI and SwiftData lifting coach for Noel's Push/Pull/Legs training. It focuses on fast workout logging, practical progression targets, useful history, and deterministic coaching that stays on device.

## Product Goal

Peakline should answer three questions quickly:

1. What should I train today?
2. What did I do last time?
3. What target should I aim for next?

The app should feel polished and gym-ready: quick to open, easy to log in the middle of a session, and clear about why it suggests a target or recovery adjustment.

## Canonical Docs

Use these root docs as the active source of truth:

- [FEATURE_SUMMARY.md](FEATURE_SUMMARY.md) - current product and feature state.
- [ARCHITECTURE.md](ARCHITECTURE.md) - implementation map and guardrails.
- [ROADMAP.md](ROADMAP.md) - current priorities and later backlog.
- [UI_STYLE_GUIDE.md](UI_STYLE_GUIDE.md) - active visual design direction.
- [KNOWN_ISSUES.md](KNOWN_ISSUES.md) - current risks and validation notes.
- [NEXT_TASK.md](NEXT_TASK.md) - immediate implementation task.
- [NEXT_CODEX_CHAT.md](NEXT_CODEX_CHAT.md) - ready-to-paste Codex handoff prompt.

Historical prompts, phase reports, QA reports, and old planning briefs are indexed in [Docs/AUDIT_INDEX.md](Docs/AUDIT_INDEX.md). Archived files are for context only and should not be used as active Codex instructions unless a task specifically asks for them.

## Codex Workflow

For a new Codex session, start with:

- [NEXT_TASK.md](NEXT_TASK.md)
- [NEXT_CODEX_CHAT.md](NEXT_CODEX_CHAT.md)
- [FEATURE_SUMMARY.md](FEATURE_SUMMARY.md)
- [ARCHITECTURE.md](ARCHITECTURE.md)
- [ROADMAP.md](ROADMAP.md)
- [UI_STYLE_GUIDE.md](UI_STYLE_GUIDE.md)
- [KNOWN_ISSUES.md](KNOWN_ISSUES.md)

Default session rule:

```text
Only implement the task described in NEXT_TASK.md. Do not refactor unrelated files.
```

## Requirements

- macOS with Xcode installed.
- iOS 17+ simulator or real iPhone.
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
  -destination 'platform=iOS Simulator,id=B4892393-2EDB-4816-A09B-A18C3161823C' \
  build
```

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
