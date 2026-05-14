# GymTracker

GymTracker is a personal iOS lifting tracker for Noel's Push/Pull/Legs training. The app is built with SwiftUI and SwiftData, stays local-first, and is moving toward a rule-based coaching experience rather than a generic workout log.

## Current Focus

- Personal Push/Pull/Legs rotation.
- Live workout logging with timer, set entry, and post-workout rating.
- History calendar and editable workout history.
- Progress charts per exercise.
- Rule-based Coach screen with PPL suggestions and progressive-overload guidance.
- Theme support with Workout Green `#7CFC00`, Purple, Orange, and Blue.

## Requirements

- macOS with Xcode installed.
- iOS 17+ simulator or real iPhone.
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

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md)
- [FEATURE_SUMMARY.md](FEATURE_SUMMARY.md)
- [ROADMAP.md](ROADMAP.md)
- [KNOWN_ISSUES.md](KNOWN_ISSUES.md)
- [NEXT_TASK.md](NEXT_TASK.md)
