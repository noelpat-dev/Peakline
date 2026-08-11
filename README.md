# Peakline

[![iOS CI](https://github.com/noelpat-dev/Peakline/actions/workflows/ios-ci.yml/badge.svg?branch=main)](https://github.com/noelpat-dev/Peakline/actions/workflows/ios-ci.yml)
![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-111827)
![Built with](https://img.shields.io/badge/built%20with-SwiftUI%20%2B%20SwiftData-F05138)

Peakline is a local-first iOS lifting coach I am building to make the training loop clearer and more useful:

1. Decide what to train next.
2. Preview and adjust the session.
3. Log the workout quickly.
4. Review what happened.
5. Use that history to choose a better next target.

The product is designed for the gym rather than for a social feed. It keeps the core workout path fast, makes coaching explainable, and treats personal training data as local source-of-truth data.

> Peakline is an active portfolio project by [Noel](https://github.com/noelpat-dev). It is being developed as a production-minded app, with particular attention to SwiftUI responsiveness, persistence safety, accessibility, and honest product boundaries.

## What Peakline does

### Training and workouts

- Maintains an editable Push, Pull, Legs, Upper, and Lower training rotation.
- Recommends the next meaningful workout consistently across Today, Coach, Workout, Splits, Progress, and History.
- Supports Full, Quick, Recovery, and Heavy workout modes.
- Provides a detailed workout preview with target suggestions, last-best-set context, alternatives, notes, addable exercises, and real handle-based reordering.
- Offers fast live logging with set entry, rest timing, pause/resume, substitutions, skipped-exercise reasons, completion rating, and a prepared session summary.
- Supports workout templates, recent-session repeat, exercise notes, and a metric plate calculator.

### Coaching and progress

- Uses deterministic local rules instead of opaque or remote AI calls.
- Explains progression targets and readiness recommendations with the evidence available on the device.
- Includes readiness scoring, recovery guidance, weekly review, action history, deload context, and feedback capture.
- Keeps History useful with attendance markers, filters, session details, editing, and deletion flows.
- Shows best sets, estimated 1RM, best-set volume, set history, charts, and a PR timeline.

### Nutrition, recovery, and data ownership

- Tracks nutrition, optional fibre targets, hydration, sleep, naps, and recovery context.
- Supports barcode lookup, Open Food Facts import, nutrition-label OCR, parser review, and source comparison before imported data is saved.
- Treats HealthKit as optional and degrades gracefully when permission or device data is unavailable.
- Supports local JSON/workout CSV export and encrypted account-linked Firebase backup for reinstall recovery.
- Keeps the real Firebase configuration out of source control; the app can still run in local-only mode.

## Engineering highlights

- **Local-first architecture:** SwiftData is the fast local source of truth. Firebase stores an encrypted backup copy rather than becoming a dependency for everyday navigation or logging.
- **Prepared value snapshots:** startup and performance-sensitive routes prepare immutable value-backed snapshots before navigation, reducing repeated SwiftData traversal and keeping the first actionable frame responsive.
- **Deterministic coaching:** target suggestions, training rotation, readiness evidence rules, and recommendation copy are testable local services with bounded certainty.
- **Performance as a feature:** the repository includes a focused acceptance verifier for route timing, warm-cache reuse, duplicate refreshes, notification work, UI timeouts, and unsafe synchronous SwiftData access.
- **Shared design system:** semantic theme tokens, Dynamic Type-backed typography, native navigation, 44-point controls, restrained motion, and Reduce Motion/Reduce Transparency fallbacks are shared across the major app surfaces.
- **Reliability coverage:** unit and UI tests cover workout logging, backup/restore, nutrition export, coaching, warm-start snapshots, History, Splits, scanner navigation, and lifecycle behavior.

## Technical stack

| Area | Choice |
| --- | --- |
| Platform | iOS 17+ |
| UI | SwiftUI |
| Persistence | SwiftData |
| Charts | Swift Charts |
| Coaching | Deterministic local services |
| Backup | Firebase Authentication + Cloud Firestore |
| Backup security | On-device compression and passphrase encryption |
| Health data | Optional HealthKit bridge |
| CI | GitHub Actions on macOS with Xcode |

## Architecture at a glance

```text
SwiftUI views
    ↓ present state and collect input
Feature services
    ↓ coaching, calculations, imports, exports, backup, snapshots
SwiftData models
    ↓ local source of truth
Prepared value snapshots
    ↓ stable, responsive navigation and rendering
Shared theme, motion, accessibility, and performance utilities
```

The main implementation boundaries are documented in [ARCHITECTURE.md](ARCHITECTURE.md). The current product surface is summarised in [FEATURE_SUMMARY.md](FEATURE_SUMMARY.md), and the active priorities are in [ROADMAP.md](ROADMAP.md).

## Current status

The main lifting loop is implemented end to end and the app is in an active quality and acceptance phase. The current focus is physical-device validation across Light and Dark appearance, large Dynamic Type, VoiceOver, Reduce Motion, Reduce Transparency, Firebase restore, and the most performance-sensitive workout routes.

The canonical 9 August 2026 performance run recorded 106 passing unit tests, Today-to-Coach at 195 ms, Coach-to-Preview at 249 ms, root-tab switching at 129 ms, two Preview warm-cache hits, zero mounted Preview refreshes, and no acceptance failures. These figures are a dated engineering baseline, not a promise that every device will produce the same timing.

## Run locally

Requirements:

- macOS with Xcode installed.
- An iOS 17+ simulator or a signed physical iPhone.
- A Firebase `GoogleService-Info.plist` only if account backup is being exercised. It is intentionally ignored by Git.

Open the project:

```bash
open GymTracker.xcodeproj
```

Then select the `GymTracker` scheme and an iPhone simulator or connected iPhone.

Command-line build:

```bash
xcodebuild \
  -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

Performance-sensitive validation:

```bash
Scripts/verify_performance_acceptance.sh
```

The product and repository are branded **Peakline**. Existing Xcode project, scheme, source-directory, test-target, and bundle-identifier names still use `GymTracker` as a compatibility detail for the current local install and build setup; they are not separate products.

## Repository guide

- [FEATURE_SUMMARY.md](FEATURE_SUMMARY.md) — implemented product and feature state.
- [ARCHITECTURE.md](ARCHITECTURE.md) — implementation map and architectural guardrails.
- [UI_STYLE_GUIDE.md](UI_STYLE_GUIDE.md) — visual, interaction, accessibility, and motion standards.
- [KNOWN_ISSUES.md](KNOWN_ISSUES.md) — known risks and regression boundaries.
- [PERFORMANCE_ACCEPTANCE_GOAL.md](PERFORMANCE_ACCEPTANCE_GOAL.md) — acceptance thresholds and verifier workflow.
- [ROADMAP.md](ROADMAP.md) — near-term priorities and longer-term ideas.
- [Docs/AUDIT_INDEX.md](Docs/AUDIT_INDEX.md) — index of historical reports and archived planning material.

Historical prompts and phase reports are retained for context only; the root docs above describe the current project.

## Portfolio notes

Peakline is intentionally more than a collection of screens. The repository shows how I approach a growing SwiftUI product: establish clear ownership boundaries, keep persistence local and recoverable, measure hot paths, make uncertainty visible, and keep the experience usable under real gym conditions.

The next meaningful milestone is a complete unlocked-device acceptance pass, followed by continued reliability work around encrypted restore, nutrition imports, and safe SwiftData evolution.
