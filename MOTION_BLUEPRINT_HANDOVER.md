# Peakline Motion Blueprint Handover

## Purpose

Implement a coherent, premium motion system for Peakline without delaying logging, saving, navigation, or prepared first frames.

The design philosophy is:

> Fast enough to trust between sets, alive enough to feel premium.

Every motion decision must obey three rules:

1. Acknowledge before animating: press feedback lands within 100 ms.
2. Motion explains structure: movement reflects where content came from or where it went.
3. One expressive moment per session: the genuine-PR celebration remains the only showstopper.

## Repository And Branch State

- Repository: `/Users/noelpatricks/Developer/Peakline`
- Required branch: `motion-blueprint`
- Branch head when this handover was written: `09276b9f25c65b0f63371636dae5108b45d3d89d`
- Current `main`: `ca18f3ad628b465f04d2ed89301598b22906d9ec`
- `motion-blueprint` is intentionally two commits behind `main`.
- Do not merge, rebase, cherry-pick, or work on `main` unless the user explicitly changes scope.
- Do not push unless explicitly asked.

The branch already contains the UI consistency work and an `AppMotion` system with 29 roles, Reduce Motion handling, transitions, press styles, numeric transitions, popup timing, swipe motion, Preview reorder motion, and PR celebration primitives. The task is to consolidate and extend that system rather than create a parallel animation framework.

## Source Blueprint Caveat

The supplied blueprint is truncated in Part 3 after this fragment:

> Press feedback (flat 0.985 scale, easeOut) ... Velocity-aware spring: press...

Implement every complete requirement below. For the truncated press-feedback row, use only the stated intent: preserve the sub-100 ms press acknowledgement, replace the mechanical ease-out release with the shared `snappy` spring, and avoid exaggerated bounce. Do not invent additional missing rehauls; record them as unavailable source context.

## Required Motion Foundation

Consolidate `AppMotion` around three named presets:

| Preset | Physics | Intended use |
|---|---|---|
| `snappy` | response `0.32`, damping `0.85` | presses, chips, steppers, swipes |
| `smooth` | response `0.42`, damping `0.92` | cards, sheets' inner content, row collapse |
| `expressive` | response `0.55`, damping `0.75` | hero metric changes and genuine PR only |

Add and enforce:

- Micro duration: no more than 120 ms.
- Standard duration: 220–280 ms.
- Expressive duration: 350–500 ms, except the existing bounded PR burst.
- Stagger: 35 ms per item, capped at eight items; remaining items enter as one group.
- Reduce Motion: remove spatial movement, rolling, drawing, stagger, bounce, pulse scaling, and peripheral celebration. Preserve meaning with instant state or a short opacity transition.

Keep role-based APIs for call sites. Avoid exposing raw spring values throughout views.

## Required Additions

### 1. Dashboard arrival

- Today, Coach, and Nutrition receive a one-time 10-point rise plus fade cascade.
- Use the shared stagger grammar.
- Run once per route appearance, not on every observed value refresh.
- The route remains immediately usable and the animation can be interrupted.
- Reduce Motion renders final positions immediately or with opacity only.

### 2. Metric count-ups

- Animate meaningful previous-to-new values for Today's recovery/readiness hero, History attendance, and Progress headline metrics.
- Use monospaced digits and a roughly 450 ms expressive transition.
- Do not animate from zero on every appearance when a valid previous value exists.
- VoiceOver exposes the final value and must not announce intermediate frames.
- Reduce Motion presents the final value immediately.

### 3. Logger set completion

- A completed set draws its checkmark over roughly 180 ms.
- Flash the accent surface once, then settle with `snappy`.
- Preserve the existing success haptic and immediate data mutation.
- Rest timer presentation follows with a local slide-up; saving must never wait for animation completion.

### 4. Rest timer urgency

- During the final ten seconds, move the ring to the warning colour.
- Use a slow one-second opacity pulse only.
- Crossfade cleanly to the Rest Complete state.
- Avoid alarms, scaling, or continuous broad invalidation.

### 5. Stepper value roll

- Weight and rep values use a 150 ms directional numeric/odometer transition.
- Increment rolls upward; decrement rolls downward.
- Preserve monospaced layout and existing control responsiveness.
- Reduce Motion swaps directly to the final value.

### 6. Deletion collapse

- Hydration, Saved Foods, and set rows collapse height with a fade after successful deletion.
- Persistence and error handling remain authoritative; do not visually remove a row before a failed mutation is resolved.
- Keep swipe ownership and accessibility delete actions intact.

### 7. Sheet inner-content entrance

- After native sheet presentation, inner content rises 12 points and fades once.
- Generalise the existing 70 ms popup-content delay rather than adding unrelated local constants.
- Dismissal and primary actions remain available immediately.

### 8. Chart draw-ins

- Progress trend line draws left to right over about 400 ms.
- Sleep week bars grow from baseline with a 40 ms bounded stagger.
- History attendance ring sweeps to its value.
- Run once per meaningful appearance, not on every scroll or query refresh.
- Final chart values, accessibility descriptions, and Reduce Motion output remain correct.

### 9. Today tab re-entry cue

- When Today becomes active and its source generation changed while away, affected cards receive one soft 300 ms surface-tint wash.
- Do not show a spinner or replay the dashboard entrance.
- Do not flash unchanged cards.

## Required Rehauls

### History placeholder

- Remove the recurring fake `Loading history` hourglass state when cached rows exist.
- Render cached rows immediately.
- When fresh rows confirm, use a subtle crossfade/per-row fade without replacing real content with a placeholder.

### Press feedback

- Replace flat mechanical ease-out release with the shared `snappy` spring.
- Keep press-down acknowledgement within 100 ms and the current restrained scale.
- One press creates one local response; no row-wide bounce, layout shift, or duplicate haptic.

## Architecture And Performance Guardrails

- Do not change the SwiftData schema.
- Do not animate route state mutations, saves, or logging operations behind a delay.
- Do not move stable-frame markers earlier or weaken the 300 ms warm/root and 500 ms deep-route thresholds.
- Do not reintroduce loading flashes on warmed routes.
- Do not animate broad root view trees or attach unscoped `.animation` modifiers.
- Use explicit `value:` animation dependencies and bounded state.
- Cancel delayed/stagger tasks on disappearance and prevent replay storms.
- Do not create one long-lived task or timer per list row.
- Keep charts and supporting sections lazy.
- Preserve native navigation, sheets, tab switching, accessibility actions, 44-point targets, and semantic theme colours.
- Preserve the current genuine-PR animation and its static Reduce Motion fallback.
- No arbitrary delays as the primary fix for lifecycle or freshness problems.

## Suggested Delivery Order

1. Audit and baseline the branch.
2. Consolidate `AppMotion` presets, duration ladder, stagger helpers, and Reduce Motion policy.
3. Migrate existing press/selection/swipe call sites to the shared presets.
4. Implement Logger, timer, and stepper microinteractions.
5. Implement deletion and sheet transitions.
6. Implement dashboard, metric, chart, and tab re-entry motion.
7. Remove History's fake cached-data placeholder.
8. Add focused tests, measure route/logging responsiveness, and run the full validation gate.

## Acceptance Matrix

- Normal motion and Reduce Motion.
- Light and Dark appearance.
- Maximum practical Dynamic Type.
- VoiceOver labels and final-value announcements.
- Today, Coach, Nutrition first appearance and repeat appearance.
- Logger set complete, rapid consecutive set taps, rest timer final ten seconds, rest completion.
- Weight and rep increments/decrements.
- Successful and failed deletion.
- Sheet presentation and immediate dismissal.
- Progress, Sleep, and History chart first appearance and re-entry.
- Today tab return with changed and unchanged data.
- Genuine PR and ordinary completion.

## Required Validation

```bash
git diff --check
xcodebuild -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
xcodebuild -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  test -only-testing:GymTrackerTests
Scripts/verify_performance_acceptance.sh
```

Also run focused motion/UI tests, strict-concurrency diagnostics, and manual simulator checks. Report actual timing samples and variance; do not claim zero latency.

## Expected Final Handover

- Root causes and motion inconsistencies confirmed.
- Motion architecture chosen.
- Files changed.
- Tests added or updated.
- Normal/Reduce Motion behavior by feature.
- Before/after timing samples for affected performance paths.
- Accessibility results.
- Remaining physical-device risks.
- Commit hash on `motion-blueprint`.
- Confirmation that `main` was not modified and nothing was pushed.
