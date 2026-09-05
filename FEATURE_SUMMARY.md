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
- Exercise library and split editing support the personal programme instead of a generic template marketplace. Split exercise rows no longer expose template-note fields or quick-note chips; existing stored notes remain backup-compatible and available to logger/history consumers.

### Workout Preview And Logging

- Start from the recommended workout card, split cards, templates, the recent-session repeat action, or an empty workout.
- Workout Preview supports Full, Quick, Recovery, and Heavy modes.
- All four modes for every active split are prepared as complete immutable `WorkoutPreviewPreparedSnapshot` values during startup. Every Preview route must resolve and pin a prepared cache key before navigation, so Today, Coach, Workout, templates, repeats, and History reuse open one complete generation without a second loading shell.
- Preview includes a history-calibrated duration range, last best set, target suggestions, alternatives, addable exercises, notes, dedicated-handle reordering, removal controls, and Coach adjustment actions. Its pinned calibration prefers valid recent same-split/mode sessions, excludes sessions under 10 minutes or at least four hours, and falls back conservatively when history is sparse. During a drag, only the active exercise lifts and follows the finger, while a slim accent insertion cue marks the exact landing edge; release applies the route-local order once with one damped settle. Reduce Motion keeps the row spatially still while preserving the cue and immediate reorder. The mutation resets any incompatible one-workout Coach adjustment and carries that exact order through `WorkoutLaunchDraft` into Logger without changing the split template or prepared cache.
- Preview presents its real prepared mode, session snapshot, Coach Brief, and Start action immediately. The same generation's single full-detail eager order mounts on the next rendered frame (normally about 50 ms; 109 ms in the focused hydration UI run), with row-frame geometry ready before the first possible drag. An opened Preview never accepts source-data or cache publication while mounted.
- Live logging includes current exercise focus, set entry, quick controls, rest timer, substitutions, skipped-exercise reasons, pause and resume, and post-workout rating. Completing a set persists once before a 180 ms checkmark/accent confirmation and starts the configured local rest timer without waiting for motion. The active timer shows only its countdown, extension, and Skip controls; the single manual preset row remains in the dedicated Rest Timer section. The timer uses a warning-colour opacity pulse in its final ten seconds and crossfades to Rest Complete; weight and rep steppers use a 150 ms directional numeric roll. Incomplete sets remain editable without an inactive Draft badge; only meaningful Warm-up and Logged states are shown.
- Exercise-to-exercise Continue transitions rotate deterministically through 28 unique title/detail pairs for the session, use every pair before reuse, and prevent an immediate rollover repeat. Completion copy remains separate.
- Finished sessions show a celebration overlay and session summary. A recorded duration of four hours or more is intercepted before rating so the user can correct it, explicitly accept it, or return to logging. Completed-workout Edit provides hours-and-minutes duration correction and synchronizes the existing seconds, minutes, and end-time fields on Save. Ordinary completions retain the restrained rating-led presentation. When the already-prepared session summary contains genuine PR records, completion instead shows PR/exercise counts, rating feedback, duration, and a one-shot focused trophy starburst; it never performs another query or delays Done.
- Session dates are tied to the actual workout start time so late-night workouts stay on the correct training day.

### Coach And Progression

- `TargetSuggestionService` owns reusable progression targets across Workout Preview, Coach, and Splits.
- Coach recommendations are deterministic, local, and explainable.
- Coach includes readiness, next split context, weekly review, recovery warnings, workout adjustments, deload guidance, feedback capture, and action history.
- Every Coach entry renders from one complete cached immutable value snapshot, including the daily decision, recommended value-backed Preview split, presentation summaries, practical weekly summary, and Weekly Review. The actionable Today's Call hero and its first explanatory card install together without a warm-frame SwiftData query; deeper supporting sections and live observation attach afterward. Provisional guidance keeps the split name as the hero headline and carries uncertainty in one Provisional badge instead of duplicating or appending status to the H1. Readiness, View Brief, Weekly Insight, and Workout-to-Coach therefore open without an empty or placeholder shell and remain mounted in the app switcher.
- Daily Check-In presents from an immutable draft owned by Today; the live SwiftData record is resolved by stable ID only when Save is pressed. Coach consumes the resulting readiness snapshot but does not duplicate the Check-In section.
- Readiness Score v2 starts from a neutral prior of 70 and combines eligible training load, check-in, overnight sleep, hydration, and qualified nutrition evidence at base weights of 30%, 25%, 25%, 10%, and 10%. Missing inputs remain unavailable rather than receiving a fabricated average score: one signal can supply at most 40% of the result, two signals at most 80%, and three or more reliable signals can supply the full result while unused weight stays neutral.
- Sleep requires a completed overnight session ending on the evaluated day; naps only enhance that valid sleep. Training uses completed, non-future history from the preceding seven days. A neutral four-part check-in maps to 70, hydration influence grows with the current daily pacing phase, and nutrition requires an enabled calorie or protein target plus at least three qualified completed days from the previous week; its raw score is capped at 95 and its aggregate influence at 10%. Sleep, training, and check-in can receive a bounded ±8 personal adjustment after five valid samples in the preceding 28 days.
- Sparse evidence is labelled `Provisional` with “X of 5 signals included”; unavailable factor rows say `Not included`, and the explanation states that missing signals do not lower the score. Provisional readiness cannot independently trigger Push, Recovery Focus, deload urgency, or a low-readiness warning. Weekly readiness trends reuse the same v2 engine and omit provisional days.
- Recommendation copy stays intentionally modest and should avoid false certainty.

### History And Progress

- History leads with current-calendar-month gym attendance independent of filters: one visit per local day, an animated attendance count/ring with final-value accessibility, current/previous month duration and visits, and an editable 1–7 days/week goal converted with the current month's day count. The ring and supporting metrics share one adaptive composition so normal widths use the card efficiently while accessibility Dynamic Type stacks without clipping or measuring duplicate first-frame alternatives. Its bounded overview, filters, calendar aggregates, and recent rows are startup-prepared immutable snapshots; cached rows remain visible during freshness confirmation instead of reverting to a loading placeholder. Its reverse-date completed-session observation is capped at the same visible 120-session window, and flat rows omit swipe gestures and repeated shadows to keep vertical scrolling responsive.
- Workout completion freezes the completed logger behind its celebration and opens Session Summary from a prepared value snapshot, avoiding post-save SwiftData traversal during the transition.
- Progress includes latest best sets, estimated 1RM, best-set volume, set history, charts, and PR timeline.
- Analytics and charts should stay lazy-loaded and readable as workout history grows.

### Nutrition, Hydration, Sleep, And Health

- Nutrition is local-first, with exact-day browsing, read-only historical totals/meals, startup-prepared value-only Saved Foods, food log snapshots, macro and optional fibre targets, barcode lookup, Open Food Facts import, OCR label scan, parser review, source comparison, insights, and HealthKit bridge work. Nutrition and Hydration share a single-settle swipe-reveal interaction for consistent deletion gestures.
- Hydration supports quick water logging and daily context.
- Sleep is organised around explicit no-data, populated, and active-session states. The first frame prioritises the next useful action; populated nights lead with duration and modest source, quality, confidence, and Peakline-estimate context, followed by a bounded seven-night trend and progressively disclosed history, consistency, debt, naps, and genuine stage data only when available.
- Sleep Mode, morning confirmation, manual sleep editing, nap logging, the date-derived Nap Timer, session detail/edit/delete, and Sleep Settings share confirmed destructive actions and specific persistent validation feedback. Nap quality is optional, an active timer cannot be silently dismissed, and saved naps can never end in the future.
- Sleep presentation treats provisional daily readiness conservatively: a supportive sleep signal may be described without becoming permission to Push, prescribe Recovery Focus, or overstate the whole-day training decision.
- HealthKit remains optional and reports truthful availability, authorization-attempt, access, import, last-sync, no-new-data, and error states. Simulator-unavailable and denied/revoked paths degrade without claiming that Apple Health is connected.
- Firebase account backup uses email/password authentication plus a user passphrase to store encrypted full-app backups for reinstall recovery. The current backup envelope is schema version 3, while schema version 2 imports remain supported for compatibility.

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
- `AppMotion` maps view roles to three shared presets: `snappy` for local controls, `smooth` for structural transitions, and `expressive` for meaningful hero metrics and genuine PR presentation. Arrival stagger is capped at eight items; Today, History, Progress, Sleep, sheets, Logger, and deletion flows render final meaningful state immediately or opacity-only under Reduce Motion.
- Genuine PR completion remains the single expressive exception: its deterministic one-shot trophy burst is noninteractive and absent under Reduce Motion, while ordinary completion remains quiet.

### Exercise Icons

- Exercise Guide is a read-only, searchable catalogue of 302 exercises with equipment and primary-muscle filters. Each catalogue detail page shows three selectable poses with optional playback, equipment, muscle groups, tracking type, and an artwork-credits route; it does not add catalogue entries to the user's saved exercises.
- Exercise Library opens a combined editor with the illustration and pose controls at the top, followed by one set of exercise fields and expandable coach-specific preferences. Its top-right information button opens artwork credits. A short pose sequence plays on entry, stops after one cycle, and respects Reduce Motion; playback can also be paused or replayed. Matching catalogue exercises still expose details from Workout Preview and the logger.
- All 906 Workout Guide SVG frames are bundled offline in `GymTracker/Assets.xcassets/WorkoutGuide/`, pinned to upstream commit `aac599224bb9780305239607ef98540b7e0ce389`. `Scripts/import_workout_guide_assets.py` imports and checks the monochrome vector assets; template rendering uses the active Peakline accent in Light and Dark appearance.
- `ExerciseGuideCatalog` loads the bundled metadata once. Exact catalogue lookup stays separate from representative illustration lookup. All 47 legacy icon keys and all 35 starter exercises now display Workout Guide images, including split/category artwork; stored icon-key raw values remain compatible. Related variants intentionally share illustrations without replacing saved exercise data.
- Original source assets and `Scripts/prepare_exercise_icons.py` remain in the repository for historical reference and are no longer selected by the exercise renderer. Source PNGs live in `GymTracker/IconSource/ExerciseIcons/`; their image sets live in `GymTracker/Assets.xcassets/ExerciseIcons/`.
- The unified editor uses exercise primary/secondary muscles and movement as the shared source of truth for coach metadata. On open and exit it synchronizes only changed metadata, retains role/priority/split context/notes, and avoids per-frame or per-keystroke persistence work.
- Artwork credits and CC BY-SA 4.0 notices are bundled under `GymTracker/Resources/WorkoutGuide/` and documented in `THIRD_PARTY_NOTICES.md`. The catalogue contains metadata and poses, not written technique instructions.

### Performance Acceptance Coverage

- Peakline uses a wordmark-only native launch screen followed by a matching, theme-aware ascending-letter animation while correctness-critical local data is prepared. The one-shot animation is Core Animation driven, lasts at most five seconds, and exits as soon as preparation is ready.
- If launch preparation exceeds five seconds, the wordmark settles and Peakline shows a spinner with the current truthful stage. Reduce Motion keeps the wordmark static and uses an opacity-only exit.
- Startup resolves restore safety before seeding, skips cloud work for existing local content, uses metadata-only backup discovery for empty stores, and atomically publishes shared Workout, Coach, and active-rotation Preview snapshots before the tabs appear.
- Startup snapshot queries are bounded; deep charts, scanners, HealthKit, notification scheduling, and automatic backup remain deferred until the splash reveal is fully complete.
- Startup tracing covers account checks, backup metadata, local preparation, root snapshot preparation, critical readiness, presentation start/slow state, and reveal start/end.
- A focused acceptance verifier exists at `Scripts/verify_performance_acceptance.sh`.
- The verifier runs build, unit tests, boot-isolated default route/root tests, data-rich per-route tests, root correctness coverage, and log scanning.
- Current acceptance checks cover Today to Coach, Sleep, Nutrition, Progress, Hydration, Workout to Coach/Preview, one Preview mode change, one-back navigation, notification refresh timing, duplicate pushes, repeated Workout Preview onAppear refreshes, gesture timeouts, toolbar constraint warnings, and `unsafeForcedSync` regressions. Dedicated Sleep UI fixtures cover no-data, populated, active, morning-confirmation, editor-error, elapsed-nap, and HealthKit-unavailable behavior.
- The verifier summary also carries the Preview warm-cache hit count so Xcode versions that omit individual app console lines can still enforce the warm-cache requirement. When a run emits separate root and route summaries, the verifier uses the maximum reported hit count rather than treating the root-only zero as a route failure.
- Preview snapshot preparation precomputes used exercise IDs once, traverses workout history once for substitutions, and calculates the base target once per unique split input before applying mode adjustments. The parity fixture reduced target-service work from 24 calls to 7 without changing mode order, targets, alternatives, or cache semantics.
- Focused Splits UI coverage verifies the five-day active programme, Edit Rotation, split detail navigation, Add Split presentation, and Other Splits expansion/collapse.

## Current Product Strengths

- The main lifting loop is implemented end to end.
- Coach, Progress, Nutrition, Sleep, Hydration, and export utilities now sit on top of that core instead of replacing it.
- Recent performance cleanup materially improved route timing, notification refresh behavior, and Coach navigation stability.
- The 21 August warm-route architecture pass builds successfully and passes all 180 unit/reliability tests. Boot-isolated default Coach/Preview/root samples and data-rich Sleep, Nutrition, Progress, Hydration, and Preview samples pass the unchanged 300/500 ms budgets; physical-device memory and first-frame verification remains outstanding.
- The 22 August motion validation passed the Debug build, strict-concurrency lane, all 186 unit/reliability tests, a focused Logger set-completion/rest-timer flow, and cached-History UI coverage. The final canonical UI run passed at Today-to-Coach 178 ms, Coach-to-Preview 209 ms, warmed root transition 186 ms, and the dedicated root-tab sequence 290 ms, with two Preview warm-cache hits and zero mounted Preview recomputations.

## Remaining Practical Expansion

- Complete the remaining focused physical-device acceptance matrix on Noel's iPhone across Light, Dark, large Dynamic Type, VoiceOver, Reduce Motion, and Reduce Transparency.
- Expand exact illustration coverage for specialised equipment variants only when a matching source is available.
- Keep scanner, OCR, and nutrition import flows stable and reviewable.
- Keep Firebase backup, local export, and migration safety strong before risky schema changes.
- Validate the delete/reinstall/sign-in/restore path on Noel's iPhone after Firebase project setup.
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
