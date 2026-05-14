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

## Publish To Private GitHub

From this folder:

```bash
git init
git add .
git commit -m "Initial GymTracker iOS scaffold"
gh repo create GymTracker --private --source=. --remote=origin --push
```

If GitHub CLI is not installed, create a private empty repo on GitHub, then run:

```bash
git init
git add .
git commit -m "Initial GymTracker iOS scaffold"
git branch -M main
git remote add origin git@github.com:YOUR_USERNAME/GymTracker.git
git push -u origin main
```
