# Feature Summary

Current file: `FEATURE_SUMMARY.md`

## Product Direction

Peakline is a personal, local-first lifting coach for Noel's editable ordered training programme. It should make workout decisions easier, keep logging fast, show realistic targets, and explain coaching decisions without drifting into a generic social fitness app or AI chatbot.

The main value loop is:

1. Decide what to train next.
2. Preview and adjust the session.
3. Log the workout quickly.
4. Review what happened.
5. Use that history to make the next target clearer.

## Current Features

### Training Structure

- Push, Pull, Legs, Upper, and Lower are seeded into one editable active rotation.
- `TrainingRotationService` is the single recommendation source for Today, Workout, Coach, Splits, Weekly Review, Progress, and session summaries. It advances from the latest meaningful completed workout by stable split ID and wraps at the end.
- Existing split templates can be included, excluded, and reordered. Inactive templates remain under Other Splits.
- Splits show training-day cards, readiness and progression context, target rows, exercise counts, stable detail routes, and cached target calculations.
- Exercise library and split editing support the personal programme instead of a generic template marketplace.

### Workout Preview And Logging

- Start from the recommended workout card, split cards, templates, the recent-session repeat action, or an empty workout.
- Workout Preview supports Full, Quick, Recovery, and Heavy modes.
- All four modes for every active split are prepared as complete immutable `WorkoutPreviewPreparedSnapshot` values during startup. Every Preview route must resolve and pin a prepared cache key before navigation, so Today, Coach, Workout, templates, repeats, and History reuse open one complete generation without a second loading shell.
- Preview includes duration estimate, last best set, target suggestions, alternatives, addable exercises, notes, dedicated-handle reordering, removal controls, and Coach adjustment actions. During a drag, only the active exercise lifts and follows the finger, while a slim accent insertion cue marks the exact landing edge; release applies the route-local order once with one damped settle. Reduce Motion keeps the row spatially still while preserving the cue and immediate reorder. The mutation resets any incompatible one-workout Coach adjustment and carries that exact order through `WorkoutLaunchDraft` into Logger without changing the split template or prepared cache.
- Preview presents its real prepared mode, session snapshot, Coach Brief, and Start action immediately. The same generation's single full-detail eager order mounts on the next rendered frame (normally about 50 ms; 109 ms in the focused hydration UI run), with row-frame geometry ready before the first possible drag. An opened Preview never accepts source-data or cache publication while mounted.
- Live logging includes current exercise focus, set entry, quick controls, rest timer, substitutions, skipped-exercise reasons, pause and resume, and post-workout rating. Incomplete sets remain editable without an inactive Draft badge; only meaningful Warm-up and Logged states are shown.
- Exercise-to-exercise Continue transitions rotate deterministically through 28 unique title/detail pairs for the session, use every pair before reuse, and prevent an immediate rollover repeat. Completion copy remains separate.
- Finished sessions show a celebration overlay and session summary. Ordinary completions retain the restrained rating-led presentation. When the already-prepared session summary contains genuine PR records, completion instead shows PR/exercise counts, rating feedback, duration, and a one-shot focused trophy starburst; it never performs another query or delays Done.
- Session dates are tied to the actual workout start time so late-night workouts stay on the correct training day.

### Coach And Progression

- `TargetSuggestionService` owns reusable progression targets across Workout Preview, Coach, and Splits.
- Coach recommendations are deterministic, local, and explainable.
- Coach includes readiness, next split context, weekly review, recovery warnings, workout adjustments, deload guidance, feedback capture, and action history.
- Every Coach entry renders from one complete cached immutable value snapshot, including the daily decision, recommended value-backed Preview split, presentation summaries, practical weekly summary, and Weekly Review. The actionable Today's Call hero installs without a warm-frame SwiftData query; supporting sections and live observation attach after the first rendered frame. Readiness, View Brief, Weekly Insight, and Workout-to-Coach therefore open without an empty or placeholder shell and remain mounted in the app switcher.
- Daily Check-In presents from an immutable draft owned by Today; the live SwiftData record is resolved by stable ID only when Save is pressed. Coach consumes the resulting readiness snapshot but does not duplicate the Check-In section.
- Readiness Score v2 starts from a neutral prior of 70 and combines eligible training load, check-in, overnight sleep, hydration, and qualified nutrition evidence at base weights of 30%, 25%, 25%, 10%, and 10%. Missing inputs remain unavailable rather than receiving a fabricated average score: one signal can supply at most 40% of the result, two signals at most 80%, and three or more reliable signals can supply the full result while unused weight stays neutral.
- Sleep requires a completed overnight session ending on the evaluated day; naps only enhance that valid sleep. Training uses completed, non-future history from the preceding seven days. A neutral four-part check-in maps to 70, hydration influence grows with the current daily pacing phase, and nutrition requires an enabled calorie or protein target plus at least three qualified completed days from the previous week; its raw score is capped at 95 and its aggregate influence at 10%. Sleep, training, and check-in can receive a bounded ±8 personal adjustment after five valid samples in the preceding 28 days.
- Sparse evidence is labelled `Provisional` with “X of 5 signals included”; unavailable factor rows say `Not included`, and the explanation states that missing signals do not lower the score. Provisional readiness cannot independently trigger Push, Recovery Focus, deload urgency, or a low-readiness warning. Weekly readiness trends reuse the same v2 engine and omit provisional days.
- Recommendation copy stays intentionally modest and should avoid false certainty.

### History And Progress

- History uses consistent 44×44 workout-day markers without exposing split abbreviations in calendar cells. Its bounded overview, filters, calendar aggregates, and recent rows are startup-prepared immutable snapshots; its reverse-date completed-session observation is capped at the same visible 120-session window, and flat rows omit swipe gestures and repeated shadows to keep vertical scrolling responsive. Selected-day summaries, workout details, editing, deletion from detail, and session metadata remain available.
- Workout completion freezes the completed logger behind its celebration and opens Session Summary from a prepared value snapshot, avoiding post-save SwiftData traversal during the transition.
- Progress includes latest best sets, estimated 1RM, best-set volume, set history, charts, and PR timeline.
- Analytics and charts should stay lazy-loaded and readable as workout history grows.

### Nutrition, Hydration, Sleep, And Health

- Nutrition is local-first, with exact-day browsing, read-only historical totals/meals, startup-prepared value-only Saved Foods, food log snapshots, macro and optional fibre targets, barcode lookup, Open Food Facts import, OCR label scan, parser review, source comparison, insights, and HealthKit bridge work. Nutrition and Hydration share a single-settle swipe-reveal interaction for consistent deletion gestures.
- Hydration supports quick water logging and daily context.
- Sleep and recovery include sleep sessions, naps, readiness scoring, recovery labels, and coaching context.
- HealthKit remains optional and should fail gracefully when unavailable, denied, or revoked.
- Firebase account backup uses email/password authentication plus a user passphrase to store encrypted full-app backups for reinstall recovery. Backup/export schema version 2 preserves the optional active rotation index while version-1 restores remain supported.

### Settings And Utilities

- Settings uses a compact adaptive Profile that exposes only truthful stored preferences and personal-reference fields. The former ambiguous Gym Utilities area is now a full-width Workout Tools route for the metric Plate Calculator, with copy explaining its live-set prefill integration; appearance controls are grouped separately under Appearance.
- Settings also includes exercise library, progress, coach, HealthKit, Account & Backup, export, and local-data information. Preferred Split and Units are no longer presented as active controls while their existing model, backup, and migration fields remain compatible.
- Appearance supports System, Light, and Dark.
- Accent themes include Fitness Green, Purple, Orange, and Blue.
- The selected accent theme is applied live and persists instead of being reset to monochrome on launch.
- Root screens use one native inline navigation title. Row-level secondary actions use anchored menus, destructive confirmation remains explicit, and icon-only controls keep a 44-point hit target with accessibility labels.
- Account & Backup shows Firebase account state, backup health, manual encrypted save/restore, sign out, and local-data information.
- Local JSON and workout CSV export support data portability outside the account backup path.
- Input-heavy screens dismiss the keyboard interactively while scrolling without installing a page-wide tap gesture. Text keyboards retain native Done/Next return-key behaviour; Peakline does not add a custom keyboard toolbar, including for number and decimal pads.

### Visual System And Accessibility

- Peakline's implemented presentation baseline is calm, premium athletic, metric-led, dark-first, and equally intentional in Light Mode. `AppTheme` owns semantic colour and depth, while `AppTypography` uses Dynamic Type-backed rounded, bold, and monospaced system roles.
- Major surfaces follow one native title, at most one dominant hero, one obvious primary action, no more than three surface levels, and supporting content ordered by usefulness. Today, Workout, Splits, History, Progress, Nutrition, Sleep, Coach, Preview, Logger, Summary, and Settings have been migrated to that hierarchy.
- Normal content uses solid semantic `FitnessCard`, `MetricTile`, row, and badge surfaces. Native chrome and focused transient overlays may inherit adaptive system material; decorative glass, nested card stacks, repeated passive pills, heavy gradients, permanent glow, and broad screen animation are excluded.
- Shared actions retain 44-point targets and immediate restrained feedback. Responsive layouts use wrapping, `ViewThatFits`, and accessibility-size stacking; icon-only controls keep explicit labels, and Reduce Motion or Reduce Transparency preserves meaning and immediate actions.
- Genuine PR completion remains the single expressive exception: its deterministic one-shot trophy burst is noninteractive and absent under Reduce Motion, while ordinary completion remains quiet.

### Exercise Icons

- Exact PNG source icons live in `GymTracker/IconSource/ExerciseIcons/`.
- Generated assets live in `GymTracker/Assets.xcassets/ExerciseIcons/`.
- `Scripts/prepare_exercise_icons.py` copies approved source PNGs into the asset catalog.
- `ExerciseIconMapper` maps exercise names to `ExerciseIconKey`.
- Exact-name mappings should come before broad muscle-group fallbacks.

### Performance Acceptance Coverage

- Peakline uses a wordmark-only native launch screen followed by a matching, theme-aware ascending-letter animation while correctness-critical local data is prepared. The one-shot animation is Core Animation driven, lasts at most five seconds, and exits as soon as preparation is ready.
- If launch preparation exceeds five seconds, the wordmark settles and Peakline shows a spinner with the current truthful stage. Reduce Motion keeps the wordmark static and uses an opacity-only exit.
- Startup resolves restore safety before seeding, skips cloud work for existing local content, uses metadata-only backup discovery for empty stores, and atomically publishes shared Workout, Coach, and active-rotation Preview snapshots before the tabs appear.
- Startup snapshot queries are bounded; deep charts, scanners, HealthKit, notification scheduling, and automatic backup remain deferred until the splash reveal is fully complete.
- Startup tracing covers account checks, backup metadata, local preparation, root snapshot preparation, critical readiness, presentation start/slow state, and reveal start/end.
- A focused acceptance verifier exists at `Scripts/verify_performance_acceptance.sh`.
- The verifier runs build, unit tests, a focused UI acceptance flow, and log scanning.
- Current acceptance checks cover Today to Coach, Workout to Coach, Workout to Preview, one Preview mode change, one-back navigation, notification refresh timing, duplicate Coach pushes, repeated Workout Preview onAppear refreshes, gesture timeouts, toolbar constraint warnings, and `unsafeForcedSync` regressions.
- The verifier summary also carries the Preview warm-cache hit count so Xcode versions that omit individual app console lines can still enforce the warm-cache requirement.
- Preview snapshot preparation precomputes used exercise IDs once, traverses workout history once for substitutions, and calculates the base target once per unique split input before applying mode adjustments. The parity fixture reduced target-service work from 24 calls to 7 without changing mode order, targets, alternatives, or cache semantics.
- Focused Splits UI coverage verifies the five-day active programme, Edit Rotation, split detail navigation, Add Split presentation, and Other Splits expansion/collapse.

## Current Product Strengths

- The main lifting loop is implemented end to end.
- Coach, Progress, Nutrition, Sleep, Hydration, and export utilities now sit on top of that core instead of replacing it.
- Recent performance cleanup materially improved route timing, notification refresh behavior, and Coach navigation stability.
- The 9 August 2026 canonical verifier is green after the app-wide visual migration: 106 unit tests passed, Today-to-Coach measured 195 ms, Coach-to-Preview 249 ms, root-tab transitions 129 ms, Preview recorded two warm-cache hits, mounted Preview recomputation remained zero, and the combined-log audit found no forbidden patterns.

## Remaining Practical Expansion

- Complete the remaining unlocked physical-device acceptance matrix across Light, Dark, large Dynamic Type, VoiceOver, Reduce Motion, and Reduce Transparency.
- Expand exact exercise icon coverage where source assets already exist.
- Keep scanner, OCR, and nutrition import flows stable and reviewable.
- Keep Firebase backup, local export, and migration safety strong before risky schema changes.
- Validate the physical-device delete/reinstall/sign-in/restore path after Firebase project setup.
- Add richer analytics only when current history and progress surfaces remain fast.
- Consider deeper HealthKit, Apple Watch, or AI only after the local-first and backup behavior remains excellent.

## Current Validation

Build:

```bash
xcodebuild -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

Performance-sensitive regression check:

```bash
Scripts/verify_performance_acceptance.sh
```
