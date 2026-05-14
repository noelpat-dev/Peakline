# GymTracker

Local-first SwiftUI gym tracker scaffolded from `gym_tracker_ios_codex_development_brief.md`.

## Current Milestone

- SwiftUI iOS app shell with six main tabs.
- SwiftData model schema for the MVP entities.
- Starter exercise library.
- Push/Pull/Legs seed split templates.
- Settings disclaimer copy from the brief.
- Basic workout logger flow.
- Completed workout History tab.

## Next Milestone

Compile and refine on Mac/Xcode:

- Open `GymTracker.xcodeproj`.
- Build on an iOS simulator.
- Fix any compile issues from the Windows-authored project file.
- Continue from `NEXT_CODEX_CHAT.md`.

## Run And Test Locally

1. Install Xcode from the Mac App Store or Apple Developer downloads.
2. Open Xcode once and accept any first-launch prompts.
3. In Terminal, make sure command-line builds point at full Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -list -project GymTracker.xcodeproj
```

4. Open `GymTracker.xcodeproj` in Xcode.
5. Select an iPhone simulator, such as iPhone 16.
6. Press Cmd+B to build, then Cmd+R to run.

Functional smoke test:

- First launch should seed starter exercises plus Push, Pull, and Legs splits once.
- Workout tab should start a split workout, start an empty workout, and resume an unfinished workout.
- Logger should add/copy/delete sets, adjust weight/reps, add an extra exercise, copy last-session working sets after history exists, and finish the workout.
- History should show finished workouts and allow editing them.
- Splits should create/edit splits and add, delete, or reorder exercises.
- Progress and Coach become useful after at least one completed workout.

## Publish To Private GitHub

From this folder:

```bash
git init
git add .
git commit -m "Initial GymTracker iOS scaffold"
gh repo create GymTracker --private --source=. --remote=origin --push
```

If GitHub CLI is not installed, create a private empty repo named `GymTracker` on GitHub under `ParadovT`, then run:

```bash
git init
git add .
git commit -m "Initial GymTracker iOS scaffold"
git branch -M main
git remote add origin git@github.com:ParadovT/GymTracker.git
git push -u origin main
```

This local repo is already initialized and committed, so from this machine you should only need:

```bash
git push -u origin main
```
