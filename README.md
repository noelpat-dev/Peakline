# Peakline

Peakline is a personal iOS lifting coach for Noel's Push/Pull/Legs training. It is built with SwiftUI and SwiftData, stays local-first, and uses deterministic coaching rather than a generic workout log or cloud service.

## Product Goal

The app should answer three questions quickly:

1. **What should I train today?**
2. **What did I do last time?**
3. **What exact target should I aim for next?**

The long-term direction is a practical coaching app: fast logging during the workout, then useful guidance before and after each session.

## Current Focus

- Personal Push/Pull/Legs rotation and next-split recommendations.
- Workout Preview with Full, Quick, Recovery, and Heavy modes.
- Shared target suggestions for Coach, Splits, and Workout Preview.
- Live workout logging with timer, pause/resume, set entry, rest timer, and post-workout rating.
- Glass celebration overlay and session summary after finishing.
- History calendar, filters, editable workout history, and start-date based workout logging.
- Progress charts per exercise.
- Theme support with Fitness Green, Purple, Orange, and Blue.
- Exact PNG exercise icons sourced from `GymTracker/IconSource/ExerciseIcons/`.

## UI Direction

Peakline should feel visually close to the Apple Fitness / Workout style in broad principles:

- Dark-first screens.
- Big metric typography.
- Compact cards.
- High-contrast accent colours.
- Rounded, soft panels.
- Glanceable progress visuals.
- SF Symbols for app controls plus exact PNG assets for exercise-specific icons.
- Simple, motivating summaries.

Do not clone Apple's exact Activity Rings, icons, screen layouts, or branded colours. The app should use an original lifting-focused version of that design language.

See [UI_STYLE_GUIDE.md](UI_STYLE_GUIDE.md) for implementation details.

## Exercise Icon Assets

Exact source PNGs live in:

```text
GymTracker/IconSource/ExerciseIcons/
```

Generated asset-catalog icons live in:

```text
GymTracker/Assets.xcassets/ExerciseIcons/
```

To map a new or replaced icon:

1. Add the source filename to `Scripts/prepare_exercise_icons.py`.
2. Confirm the asset case in `GymTracker/Views/Shared/ExerciseIconKey.swift`.
3. Add the exact-name rule in `GymTracker/Services/ExerciseIconMapper.swift`.
4. Run:

```bash
python3 Scripts/prepare_exercise_icons.py
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
2. Select an iPhone simulator or your connected iPhone.
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

## Real iPhone Install

You can install with a free Apple ID through Xcode:

1. Plug in and unlock your iPhone.
2. Select the real device in Xcode.
3. Open the project target settings.
4. Go to `Signing & Capabilities`.
5. Enable automatic signing and select your personal team.
6. Press `Cmd+R`.

Free Apple ID installs usually expire after about 7 days. A paid Apple Developer account is recommended for longer-lived development installs and future iCloud/CloudKit capabilities.

## Codex Workflow

Use the documentation files as context compression for Codex.

Before a Codex session, provide:

- [FEATURE_SUMMARY.md](FEATURE_SUMMARY.md)
- [ARCHITECTURE.md](ARCHITECTURE.md)
- [ROADMAP.md](ROADMAP.md)
- [NEXT_TASK.md](NEXT_TASK.md)
- [NEXT_CODEX_CHAT.md](NEXT_CODEX_CHAT.md)
- [UI_STYLE_GUIDE.md](UI_STYLE_GUIDE.md)

Recommended session rule:

```text
Only implement the task described in NEXT_TASK.md. Do not refactor unrelated files.
```

After each successful milestone:

```bash
git add .
git commit -m "Describe completed feature"
```

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md)
- [FEATURE_SUMMARY.md](FEATURE_SUMMARY.md)
- [ROADMAP.md](ROADMAP.md)
- [KNOWN_ISSUES.md](KNOWN_ISSUES.md)
- [NEXT_TASK.md](NEXT_TASK.md)
- [NEXT_CODEX_CHAT.md](NEXT_CODEX_CHAT.md)
- [UI_STYLE_GUIDE.md](UI_STYLE_GUIDE.md)
- [gym_tracker_ios_codex_development_brief.md](gym_tracker_ios_codex_development_brief.md)
