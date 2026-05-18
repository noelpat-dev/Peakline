# GymTracker Codex Full Roadmap Execution Plan

## Purpose

This file is the single Codex handoff document for completing the current GymTracker roadmap in as few prompts as safely possible.

Use it when starting a fresh Codex session with the repo attached. It consolidates the current product direction, Apple Fitness-inspired visual direction, architecture guardrails, and implementation prompts.

The goal is not to make Codex randomly redesign the whole app. The goal is to make Codex complete the roadmap through a small number of large, controlled implementation passes.

---

## Product North Star

GymTracker should become a practical local-first lifting coach for Noel's Push/Pull/Legs training.

The app should answer three questions quickly:

1. **What should I train today?**
2. **What did I do last time?**
3. **What exact target should I aim for next?**

Everything added to the app should support one of those answers.

---

## Product Identity

GymTracker should feel like a lifting-focused version of the Apple Fitness / Workout experience:

- Dark-first.
- Card-based.
- Metric-heavy.
- Rounded and high contrast.
- Motivating but not childish.
- Native-feeling SwiftUI.
- Fast during a real gym session.

Important: do **not** copy Apple Fitness screens, exact Activity Rings, Apple icons, Apple branding, or Apple's exact colour system.

Build an original GymTracker lifting design language using Apple platform conventions.

---

## Non-Negotiable Technical Constraints

- SwiftUI only.
- SwiftData for persistence.
- Swift Charts for charts where needed.
- Local-first.
- No AI APIs.
- No networking.
- No social features.
- No subscriptions.
- No HealthKit yet.
- No Apple Watch yet.
- No iCloud/CloudKit work yet.
- No broad unrelated refactors.
- Keep the app compile-ready after every pass.
- Keep workout logging fast.
- Keep Push/Pull/Legs as the core structure.
- Do not reintroduce the old multi-question readiness form.

Recovery/readiness should be represented through one low-friction decision:

```text
Full / Quick / Recovery / Heavy
```

---

## Existing App Shape To Preserve

The current implementation already includes:

- Push/Pull/Legs programme.
- Personal exercise library.
- Workout start flow.
- Exercise selection.
- One-exercise-at-a-time live logger.
- Timer with pause support.
- Set logging.
- Previous performance prefill.
- Post-workout rating.
- History calendar and editable history.
- Progress charts.
- Basic rule-based Coach.
- Theme settings.

Do not delete or replace these flows unless necessary for the roadmap tasks.

---

# Headed Design System

## Design Goal

Create a clear GymTracker visual system that feels polished, focused, and useful.

The app should use large headings and dashboard-style sections so every major screen is easy to scan.

Each main screen should have:

1. A large screen heading.
2. A short explanatory subtitle or current-state summary.
3. One primary hero card.
4. Supporting metric cards.
5. Clear action buttons.

---

## Screen Header Pattern

Create a reusable header if practical:

```text
Views/Shared/FitnessScreenHeader.swift
```

Suggested API:

```swift
struct FitnessScreenHeader: View {
    let title: String
    let subtitle: String?
    let systemImage: String?
}
```

Use it on Today, Coach, Workout, Splits, Progress, and Session Summary where safe.

### Header style

- Large title.
- Rounded system font feel.
- Optional SF Symbol.
- Muted subtitle.
- Dark-first spacing.
- No busy gradients behind every heading.

---

## Shared UI Components To Build

Create or complete these reusable components:

```text
GymTracker/Views/Shared/FitnessCard.swift
GymTracker/Views/Shared/MetricTile.swift
GymTracker/Views/Shared/CoachBadgeView.swift
GymTracker/Views/Shared/ExerciseTargetRow.swift
GymTracker/Views/Shared/ProgressArcView.swift
GymTracker/Views/Shared/SplitCardView.swift
GymTracker/Views/Shared/LiveWorkoutHeader.swift
GymTracker/Views/Shared/FitnessScreenHeader.swift
GymTracker/Views/Shared/WorkoutModePicker.swift
```

### FitnessCard

Reusable rounded card container.

Requirements:

- Supports light and dark mode.
- Uses current app accent subtly.
- Has configurable padding.
- Accepts child content using `@ViewBuilder`.
- Works for Today, Coach, Workout Preview, Progress, History, and Summary.

### MetricTile

Compact metric display.

Show:

- Small label.
- Large value.
- Optional caption.
- Optional SF Symbol.

Example uses:

- Duration.
- Working sets.
- Weekly workouts.
- Best set.
- Estimated 1RM.

### CoachBadgeView

Small status badge.

Support states:

- baseline.
- addReps.
- repeatTarget.
- increaseLoad.
- reduceLoad.
- possiblePlateau.
- fatigueRisk.
- ready.
- recovery.
- missedSplit.
- pr.

### ExerciseTargetRow

Reusable row for Workout Preview, Coach, and Splits.

Display:

- Exercise name.
- Last best set.
- Suggested target.
- Badge.
- Short reason.

### ProgressArcView

Original GymTracker circular progress visual.

Do not clone Apple Activity Rings.

Possible arcs:

- Train: completed workouts this week.
- Progress: exercises with clear target opportunities.
- Balance: Push/Pull/Legs coverage.

### SplitCardView

Reusable card for Push, Pull, and Legs.

Display:

- Split name.
- Last trained date.
- Estimated duration.
- Exercise count.
- Coach badge.
- Start button.

### LiveWorkoutHeader

Persistent top section during live workout.

Display:

- Timer.
- Pause/resume.
- Current exercise index.
- Finish button.

### WorkoutModePicker

One-tap mode selector.

Modes:

- Full.
- Quick.
- Recovery.
- Heavy.

This replaces a multi-question readiness form.

---

## Colour Direction

Use semantic colours where possible.

Suggested semantic layer:

```swift
AppColors.backgroundPrimary
AppColors.backgroundSecondary
AppColors.cardBackground
AppColors.cardBorder
AppColors.primaryAccent
AppColors.secondaryAccent
AppColors.success
AppColors.warning
AppColors.danger
AppColors.mutedText
```

Default identity accent:

```text
Workout Green: #7CFC00
```

Rules:

- Do not make every card bright green.
- Use the accent for highlights and progress.
- Use system red for destructive actions.
- Use orange/yellow for fatigue, plateau, warning, or recovery states.
- Use muted gray for secondary explanations.

---

## Typography Direction

Use system fonts and dynamic type where practical.

Suggested hierarchy:

```swift
Screen title: .largeTitle.bold()
Hero metric: .system(size: 44, weight: .bold, design: .rounded)
Card title: .headline or .title3.bold()
Main metric: .title.bold()
Explanation: .subheadline or .footnote
Small label: .caption
```

---

# Core Services To Implement

## TargetSuggestionService

Create:

```text
GymTracker/Services/TargetSuggestionService.swift
```

Purpose:

- Centralise target logic.
- Stop Coach and Workout calculating different targets.
- Return target suggestions for Coach, Workout Preview, Splits, and exercise selection.

Create non-persistent types:

```swift
struct TargetSuggestion

enum TargetRecommendationType: String, Codable, CaseIterable {
    case baseline
    case addReps
    case repeatTarget
    case increaseLoad
    case reduceLoad
    case possiblePlateau
    case fatigueRisk
    case ready
}
```

Suggested `TargetSuggestion` fields:

```swift
let exerciseName: String
let lastBestSetDescription: String?
let suggestedWeight: Double?
let suggestedReps: Int?
let recommendationType: TargetRecommendationType
let reason: String
let confidence: Double
```

Rules:

- No history: baseline.
- Hit top of rep range: increase load.
- Inside target range: add reps or repeat target.
- Below minimum reps: repeat or reduce.
- Performance drops twice: fatigue risk.
- No improvement for three appearances: possible plateau.

Every suggestion must include a short reason.

---

## WorkoutModePlanner

Create:

```text
GymTracker/Services/WorkoutModePlanner.swift
```

Create:

```swift
enum WorkoutMode: String, Codable, CaseIterable {
    case full
    case quick
    case recovery
    case heavy
}
```

If storing mode on `WorkoutSession` causes migration risk, keep it non-persistent at first and pass it through the start flow.

Responsibilities:

- Adjust set count by mode.
- Adjust target messaging by mode.
- Estimate duration.
- Prioritise compounds in Quick and Heavy mode.
- Reduce accessories in Quick mode.
- Reduce volume and aggressive language in Recovery mode.

Mode rules:

### Full

- Use planned exercises.
- Use normal target sets.
- Use normal progression suggestions.

### Quick

- Prioritise the first compound/main movements.
- Reduce accessories.
- Reduce set count.
- Estimate 20–40 minutes.

### Recovery

- Reduce set count.
- Avoid aggressive load increases.
- Use wording like "lighter session" or "repeat target".

### Heavy

- Prioritise compounds.
- Emphasise load progression.
- Keep accessories secondary.

---

## SessionSummaryBuilder

Create:

```text
GymTracker/Services/SessionSummaryBuilder.swift
```

Responsibilities:

- Build post-workout summary data.
- Count completed exercises.
- Count working sets.
- Use exact duration if available.
- Show rating.
- Identify best-set improvements.
- Suggest next split.
- Produce a short motivational coaching takeaway.

---

## HistoryFilterService

Create:

```text
GymTracker/Services/HistoryFilterService.swift
```

Responsibilities:

- Filter workouts by split.
- Filter workouts by exercise name.
- Filter workouts by rating.
- Filter workouts by date range.

Keep this simple. Prefer chips or a compact sheet instead of a complicated search UI.

---

# Fewest Safe Codex Prompt Strategy

Do not use one giant prompt unless Codex has a very large context window and the full repo is available.

Use **four macro prompts**.

Each macro prompt should:

1. Read the docs.
2. Inspect relevant files.
3. Implement only the requested pass.
4. Avoid unrelated refactors.
5. Validate with `git diff --check` and `xcodebuild`.
6. Produce a summary and next-step notes.

---

# Macro Prompt 1 — Design Foundation + Target Suggestion + Coach Cards

Paste this into Codex first.

```text
You are working on the existing GymTracker SwiftUI iOS app.

Goal: complete the first major roadmap pass by building the shared Apple Fitness-inspired design foundation, centralising target suggestion logic, and lightly refreshing Coach.

Read these docs first:
- README.md
- FEATURE_SUMMARY.md
- ARCHITECTURE.md
- ROADMAP.md
- UI_STYLE_GUIDE.md
- KNOWN_ISSUES.md
- CODEX_FULL_ROADMAP_PLAN.md if present

Current product direction:
GymTracker is a local-first Push/Pull/Legs lifting coach. It should answer:
1. What should I train today?
2. What did I do last time?
3. What exact target should I aim for next?

Design direction:
Make the app feel inspired by Apple Fitness / Workout principles: dark-first, card-based, metric-heavy, rounded, high-contrast, and motivating. Do not copy Apple's exact Fitness screens, Activity Rings, icons, or branding.

Implement this pass only.

TASK A — Shared UI components
Create these files under GymTracker/Views/Shared/ if they do not exist:
- FitnessCard.swift
- MetricTile.swift
- CoachBadgeView.swift
- ExerciseTargetRow.swift
- ProgressArcView.swift
- SplitCardView.swift
- FitnessScreenHeader.swift

Requirements:
- SwiftUI only.
- Compile-ready.
- Reusable.
- Supports light/dark mode.
- Uses the existing app theme/accent where safe.
- Destructive actions must remain system red.
- No exact clone of Apple's Activity Rings.

TASK B — TargetSuggestionService
Create:
- GymTracker/Services/TargetSuggestionService.swift

Add non-persistent types if needed:
- TargetSuggestion
- TargetRecommendationType

TargetSuggestion should include:
- exerciseName
- lastBestSetDescription
- suggestedWeight
- suggestedReps
- recommendationType
- reason
- confidence

TargetRecommendationType should support:
- baseline
- addReps
- repeatTarget
- increaseLoad
- reduceLoad
- possiblePlateau
- fatigueRisk
- ready

Rules:
- No history: baseline.
- Hit top of rep range: increaseLoad.
- Inside target range: addReps or repeatTarget.
- Below minimum reps: repeatTarget or reduceLoad.
- Performance drops twice: fatigueRisk.
- No improvement for three appearances: possiblePlateau.

Every suggestion must include a clear short reason.

TASK C — Coach integration
Lightly update the existing Coach screen to use:
- FitnessCard
- MetricTile
- CoachBadgeView
- ExerciseTargetRow where safe

Coach should keep the same information but look more card-based and action-focused.

Do not redesign navigation.
Do not remove existing Coach functionality.
Do not implement Workout Preview yet.
Do not implement workout modes yet unless needed as a non-persistent enum for compilation.
Do not introduce a multi-question readiness form.
Do not change SwiftData models unless absolutely necessary.

Validation:
Run:

git diff --check
xcodebuild -project GymTracker.xcodeproj -scheme GymTracker -configuration Debug -destination 'platform=iOS Simulator,id=B4892393-2EDB-4816-A09B-A18C3161823C' build

If build fails, fix compile errors before stopping.

At the end report:
- Files created
- Files modified
- What changed
- Validation result
- What should be done in Macro Prompt 2

Suggested commit:
git add .
git commit -m "Add design foundation and target suggestion service"
```

---

# Macro Prompt 2 — Workout Modes + Workout Preview + Live Header

Paste this after Macro Prompt 1 is committed.

```text
You are continuing the existing GymTracker SwiftUI iOS app.

Goal: implement the main workout adaptation upgrade: Full / Quick / Recovery / Heavy modes, a proper Workout Preview screen, and a persistent live workout header.

Before coding:
- Read README.md, ARCHITECTURE.md, ROADMAP.md, UI_STYLE_GUIDE.md, KNOWN_ISSUES.md, and the result of the previous commit.
- Inspect the existing Workout views and current start flow.

Do not reintroduce the old multi-question readiness form. Workout mode is the low-friction replacement.

TASK A — WorkoutMode and WorkoutModePlanner
Create or complete:
- WorkoutMode enum
- GymTracker/Services/WorkoutModePlanner.swift
- GymTracker/Views/Shared/WorkoutModePicker.swift

If storing mode on WorkoutSession creates SwiftData migration risk, keep mode non-persistent for now and pass it through the start flow.

Mode rules:
- Full: planned exercises and normal target sets.
- Quick: prioritise compounds/main lifts, reduce accessories and set count, estimate 20–40 minutes.
- Recovery: reduce set count, avoid aggressive overload wording, encourage lower effort.
- Heavy: prioritise compounds and load progression, keep accessories secondary.

TASK B — Workout Preview screen
Create or update:
- GymTracker/Views/Workout/WorkoutPreviewView.swift

The preview should appear before live logging starts.

Show:
- Selected split name.
- Selected workout mode.
- Estimated duration.
- Exercise order.
- Last best set per exercise.
- Suggested target per exercise from TargetSuggestionService.
- Remove exercise control.
- Reorder exercise control if safe.
- Start workout button.

Use these shared components:
- FitnessCard
- MetricTile
- ExerciseTargetRow
- WorkoutModePicker
- CoachBadgeView

TASK C — Connect preview to existing start flow
Update the existing Workout start flow so:
- User chooses Push/Pull/Legs or empty workout as before.
- User can select exercises as before.
- User sees Workout Preview before the live logger.
- Starting from preview creates or opens the live workout session.
- Existing previous-performance prefill still works.

TASK D — LiveWorkoutHeader
Create or apply:
- GymTracker/Views/Shared/LiveWorkoutHeader.swift

Show during live workout:
- Active timer.
- Pause/resume.
- Current exercise count/index.
- Finish action.

Do not slow down set entry.
Do not remove the one-exercise-at-a-time logger.
Do not break history editing.
Do not perform unrelated UI refactors.
Do not change iCloud/CloudKit, HealthKit, or Apple Watch.

Validation:
Run:

git diff --check
xcodebuild -project GymTracker.xcodeproj -scheme GymTracker -configuration Debug -destination 'platform=iOS Simulator,id=B4892393-2EDB-4816-A09B-A18C3161823C' build

If build fails, fix compile errors before stopping.

At the end report:
- Files created
- Files modified
- Start flow changes
- Validation result
- What should be done in Macro Prompt 3

Suggested commit:
git add .
git commit -m "Add workout modes and workout preview"
```

---

# Macro Prompt 3 — Session Summary + Split UI + Coach Cards V2

Paste this after Macro Prompt 2 is committed.

```text
You are continuing GymTracker.

Goal: complete the coaching loop around finishing a workout, improve Split screens, and make Coach fully action-focused using the shared services/components.

Read:
- README.md
- FEATURE_SUMMARY.md
- ARCHITECTURE.md
- ROADMAP.md
- UI_STYLE_GUIDE.md
- KNOWN_ISSUES.md
- CODEX_FULL_ROADMAP_PLAN.md if present

TASK A — SessionSummaryBuilder
Create:
- GymTracker/Services/SessionSummaryBuilder.swift

It should build a summary from a completed WorkoutSession:
- exact duration if available
- exercises completed
- total working sets
- rating
- best set improvements if detectable
- possible PR markers
- suggested next split
- short coach-style takeaway

TASK B — Session Summary screen
Create:
- GymTracker/Views/Workout/SessionSummaryView.swift

After finishing a workout, navigate to this summary instead of only showing a popup.

Show:
- Duration to the second.
- Exercises completed.
- Working sets.
- Rating.
- Best improvements / PRs.
- Coach takeaway.
- Suggested next split.
- Buttons to go to Today or History.

History detail must remain editable and should not accidentally trigger the live workout/motivation flow.

TASK C — Split UI improvements
Update Splits to feel useful rather than static.

For each Push/Pull/Legs split, show:
- Larger SplitCardView.
- Last trained date.
- Exercise count.
- Estimated duration if possible.
- Coach badge.

For exercises inside a split, show:
- Target sets.
- Rep range.
- Latest best set.
- Target suggestion badge from TargetSuggestionService.

Keep split editing simple and working.

TASK D — Coach Cards V2
Finish Coach refresh.

Coach cards should include:
- Next Workout.
- Today's Targets.
- Recovery Warnings.
- Weekly Summary.
- Progress Opportunities.
- Missed Split Warning.

Rules:
- Use TargetSuggestionService for exercise targets.
- Use WorkoutModePlanner context where available.
- Use FitnessCard / MetricTile / CoachBadgeView / ExerciseTargetRow.
- Keep explanations short.
- Every recommendation needs a reason.
- Use cautious language like "possible plateau" or "fatigue risk".

Do not add AI.
Do not add networking.
Do not add HealthKit.
Do not add iCloud.
Do not overstate coaching certainty.
Do not perform broad unrelated refactors.

Validation:
Run:

git diff --check
xcodebuild -project GymTracker.xcodeproj -scheme GymTracker -configuration Debug -destination 'platform=iOS Simulator,id=B4892393-2EDB-4816-A09B-A18C3161823C' build

If build fails, fix compile errors before stopping.

At the end report:
- Files created
- Files modified
- Summary flow changes
- Split UI changes
- Coach changes
- Validation result
- What should be done in Macro Prompt 4

Suggested commit:
git add .
git commit -m "Add session summary and coach card improvements"
```

---

# Macro Prompt 4 — History/Analytics + Gym Utilities + Final Polish

Paste this after Macro Prompt 3 is committed.

```text
You are continuing GymTracker.

Goal: complete the remaining practical roadmap items: History filters, PR/analytics polish, rest timer, plate calculator, and final UI consistency pass.

Read:
- README.md
- FEATURE_SUMMARY.md
- ARCHITECTURE.md
- ROADMAP.md
- UI_STYLE_GUIDE.md
- KNOWN_ISSUES.md
- CODEX_FULL_ROADMAP_PLAN.md if present

TASK A — HistoryFilterService and History filters
Create:
- GymTracker/Services/HistoryFilterService.swift

Add simple filters to History:
- Split day.
- Exercise name.
- Rating.
- Date range.

Keep UI simple:
- chips, segmented controls, or compact filter sheet.
- Do not make History cluttered.

TASK B — PR and analytics polish
Add lightweight PR/improvement markers where safe:
- Workout detail.
- Session Summary.
- Progress.

Support:
- best set improvement.
- estimated 1RM improvement if already calculated.
- weekly workout overview.
- split consistency if easy from existing data.

Keep Swift Charts lazy-loaded. Do not render many charts at once.

TASK C — Rest timer
Add a simple in-app rest timer.

Requirements:
- Start manually from live workout.
- Quick durations such as 60, 90, 120 seconds.
- Visible during live workout.
- Do not rely on background notifications yet.
- Do not interrupt set logging.

TASK D — Plate calculator
Add a kg-first plate calculator utility.

Requirements:
- Bar weight default 20kg.
- Target weight input.
- Plate breakdown per side.
- Accessible from Workout or Settings, but do not clutter the live logger.

TASK E — Final UI consistency pass
Apply shared visual components where safe:
- Today.
- Coach.
- Workout Preview.
- Session Summary.
- Splits.
- History cards.

Do not redesign every screen from scratch.
Do not copy Apple's exact UI.
Do not change destructive button styling away from system red.
Do not add iCloud/CloudKit, HealthKit, Apple Watch, AI, subscriptions, or social features.

Validation:
Run:

git diff --check
xcodebuild -project GymTracker.xcodeproj -scheme GymTracker -configuration Debug -destination 'platform=iOS Simulator,id=B4892393-2EDB-4816-A09B-A18C3161823C' build

If build fails, fix compile errors before stopping.

At the end report:
- Files created
- Files modified
- Features completed
- Remaining recommended future features
- Validation result

Suggested commit:
git add .
git commit -m "Add history filters utilities and final UI polish"
```

---

# Optional Macro Prompt 5 — Backup / Export Only If Core App Feels Stable

Use only after the app is stable and the main experience works well.

```text
You are continuing GymTracker.

Goal: add simple local backup/export support without cloud sync.

Requirements:
- No iCloud.
- No backend.
- No login.
- Export local workout data to a file if practical.
- Prefer CSV or JSON.
- Add import only if safe.
- Do not risk corrupting SwiftData.
- Add clear user-facing warnings before import/replace behaviour.

Validate with git diff --check and xcodebuild.
```

---

# Implementation Acceptance Criteria For Whole Roadmap

The roadmap should be considered complete when:

## Coaching

- Coach gives next split recommendation.
- Coach explains why.
- Coach shows target suggestions.
- Coach uses shared target logic.
- Coach has fatigue/plateau/recovery warnings using cautious wording.
- Coach is card-based and easy to scan.

## Workout

- User can select Push/Pull/Legs.
- User can select exercises.
- User can select Full / Quick / Recovery / Heavy.
- User sees Workout Preview before live logging.
- Preview shows last best and suggested target.
- Live logger remains fast.
- Timer/pause still works.
- Finish creates a useful Session Summary.

## Splits

- Split cards show last trained date, exercise count, and coach badge.
- Exercises show target sets, rep range, latest best set, and progression badge.
- Split editing still works.

## History

- Calendar and list still work.
- Workout detail still works.
- Historic editing still works.
- Filters exist for split, exercise, rating, and date range.
- PR/improvement markers appear where safe.

## Progress

- Existing exercise charts still work.
- Charts remain lazy-loaded.
- PR/improvement data is clearer.

## UI

- App feels dark-first and card-based.
- Large metrics are used where useful.
- SF Symbols are used tastefully.
- The design is original and not an Apple clone.
- Theme accent still works.
- Delete/destructive actions remain red.

## Utilities

- Rest timer exists and does not interrupt logging.
- Plate calculator exists and is kg-first.

## Stability

- App compiles.
- No broad unrelated refactors.
- No unnecessary SwiftData migration risk.
- No iCloud/CloudKit work.
- No HealthKit.
- No AI API.

---

# Validation Command

Run this after every macro prompt:

```bash
git diff --check
xcodebuild -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=B4892393-2EDB-4816-A09B-A18C3161823C' \
  build
```

If the simulator ID no longer exists, Codex should run:

```bash
xcrun simctl list devices available
```

Then choose an available iPhone simulator destination.

---

# Handoff Rule If Codex Runs Out Of Context

If Codex cannot finish a macro prompt because of context or token limits, tell it to create or update:

```text
SESSION_HANDOFF.md
```

The handoff should include:

- What was completed.
- What files were changed.
- What still needs finishing.
- Any compile errors.
- The exact next prompt to continue.

Then start a fresh Codex session with:

- The repo.
- This file.
- README.md.
- FEATURE_SUMMARY.md.
- ARCHITECTURE.md.
- ROADMAP.md.
- UI_STYLE_GUIDE.md.
- KNOWN_ISSUES.md.
- SESSION_HANDOFF.md.

---

# Git Commit Plan

Suggested commits:

```bash
git commit -m "Add design foundation and target suggestion service"
git commit -m "Add workout modes and workout preview"
git commit -m "Add session summary and coach card improvements"
git commit -m "Add history filters utilities and final UI polish"
git commit -m "Add local export support"
```

Commit after every successful macro prompt.

---

# Final Notes For Codex

Keep GymTracker practical.

Do not turn it into:

- a social app,
- a nutrition app,
- an AI chatbot,
- a HealthKit/Apple Watch project,
- a cloud sync project,
- or a generic workout template marketplace.

The best version of this app is simple:

- choose the right split,
- know what happened last time,
- know what target to hit today,
- log quickly,
- finish with a useful summary,
- and come back next session with better guidance.
