# Known Issues

Current file: `KNOWN_ISSUES.md`

## Xcode / Device Install

- Free Apple ID installs on a real iPhone usually expire after about 7 days.
- A paid Apple Developer account is still useful for longer-lived development builds, but the current backup path no longer requires paid iCloud, CloudKit, or Sign in with Apple capabilities.
- If Xcode cannot run on a real device, confirm the device is unlocked, trusts the Mac, has a valid signing team, and uses a unique bundle identifier.
- Physical-device installation cannot proceed while either the Mac login session or iPhone is locked.

## SwiftData Migration And Async Safety

- There is still no formal migration strategy for future schema changes.
- Add stored model fields carefully. Prefer optional fields with defaults, fixtures, and migration coverage before shipping.
- Do not pass live SwiftData `@Model`, `@Query`, or `ModelContext` values into async work that can suspend. Build value snapshots first.
- Use the performance acceptance verifier after changing Today, Coach, Workout Preview, root lifecycle, notifications, or HealthKit bridge code to catch `unsafeForcedSync` regressions early.
- Historical workout display should continue to tolerate changed or missing exercises, splits, templates, and UUID snapshots.

## Nutrition Scanner And Imports

- Protect the Today-to-Nutrition scanner route: Today quick actions to Nutrition, Add Food, Scan Label, Scan Barcode, review, save, and return-to-log.
- Barcode, Open Food Facts, OCR, parser, and source-comparison values must remain editable and explicitly saved before becoming local truth.
- Navigate to saved or imported foods by stable IDs rather than live SwiftData model objects.
- HealthKit sample write and read verification still requires a physical iPhone.
- Open Food Facts remains read-only from Peakline's side.

## HealthKit And Firebase Backup

- A real Firebase `GoogleService-Info.plist` is not committed to the repo; live account backup requires adding one from the Firebase project registered to the existing compatibility bundle identifier `com.noel.GymTracker`.
- If Firebase is not configured, the startup gate allows local-only use, but that data is not protected from app deletion until a real Firebase backup is saved.
- Email/Password Authentication and Cloud Firestore must be enabled in Firebase, with rules that restrict `users/{uid}` documents to that authenticated user.
- Forgetting the backup passphrase makes the encrypted remote backup unrecoverable after reinstall.
- Spark quotas can pause backup for the month if exceeded.
- Physical-device validation is still required for sign in, create data, save backup, delete app, reinstall, sign in again, restore, and confirm data returns.
- HealthKit should remain optional and degrade gracefully when unavailable, denied, or revoked.
- Edited synced nutrition logs may need review rather than automatic overwrite or duplicate sync.

## Coach And Recovery

- Coaching is deterministic and still evolving.
- Fatigue, plateau, deload, and recovery recommendations should not overstate certainty.
- Every recommendation needs a short reason.
- Preserve Readiness Score v2's missing-data rule: unavailable sleep, training, check-in, hydration, or nutrition is unknown, never 70, poor, or zero. A one-signal score remains provisional and cannot independently justify Push, Recovery Focus, deload urgency, or a low-readiness warning.
- Keep sleep tied to an overnight session ending on the evaluated day, reject future training/history records, exclude today from nutrition qualification, and retain the five-sample/28-day threshold plus ±8 cap for personal calibration. Relaxing these gates can make stale or repeated data look more certain than it is.
- Readiness refresh is calendar- and hydration-phase-sensitive. Preserve the one cancellable boundary task and recheck Provisional coverage, `Not included` rows, immediate Check-In refresh, midnight rollover, and pacing-boundary changes during the remaining physical-device acceptance pass.
- Do not reintroduce a multi-question readiness form. The workout mode choice remains the main lightweight user control.
- The Sleep rehaul now prevents provisional readiness from presenting Push/Recovery permission, but any future Sleep, Today, or Coach copy change must preserve that cross-surface rule. Sleep stages remain absent unless genuine stage data exists, and Apple Health must never be labelled connected solely from an import preference.

## UI And Design System

- The app-wide premium-athletic migration has simulator evidence across all five root tabs in Dark, representative Today/History/Settings surfaces in forced Light, and maximum accessibility text on Today and Settings. The redesigned populated Sleep dashboard was visually inspected on iPhone 17 and the dedicated Sleep suite exercised maximum accessibility text, contrast, Reduce Motion, and Reduce Transparency, but the Mac UI controller was locked and no smaller simulator was installed. Repeat Sleep's no-data, active, settings, editors, timer, morning, and detail matrix manually on an unlocked smallest-supported physical iPhone in Light and Dark with VoiceOver.
- Preserve the single-title rule: a screen should not render both a native navigation title and a duplicate `FitnessScreenHeader` title.
- Keep row ellipsis actions anchored to the originating row. Do not reintroduce screen-level action dialogs for exercise or split row menus.
- Keep visible measurement copy on the shared notation (`60 kg × 8`, `350 mL`, `100 g`) and use plural-aware count helpers.
- Exact exercise icon mappings can drift if broad mapper rules run before exact-name rules.
- Destructive actions should remain semantic danger or system red, not the accent color.
- Nutrition and hydration delete swipe patterns share one direct-offset implementation. Do not reintroduce `@GestureState` plus a second settled offset, which produces a visible double flick when the gesture state resets.
- Native editor `Form` and `List` surfaces should use the shared grouped content background so they do not drift from the selected theme.
- Manually verify the five-day programme chips, one-border split icons, compact History calendar, responsive Settings rows, and historical Nutrition controls on a smaller physical iPhone with Dynamic Type, VoiceOver, Reduce Transparency, and both appearance modes.
- Manually verify the genuine-PR completion in Light, Dark, large Dynamic Type, and VoiceOver. Reduce Motion must show a static gold trophy with PR copy and no moving sparks, rings, or trophy pop; Done must remain immediately tappable in every mode.

## Performance And Charts

- Keep live workout logging fast and avoid heavy recomputation in hot logging views.
- Duration calibration must continue to reject future, unfinished, zero-working-set, under-10-minute, and four-hour-or-longer sessions. Explicitly accepted long workouts remain valid History records but must not influence later Preview estimates.
- Completed-duration correction must continue to preserve `startedAt` and accumulated paused time while synchronizing seconds, rounded minutes, and `endedAt`; backup/export compatibility relies on the existing fields rather than a new schema field.
- Today, Coach, Workout Preview, Splits, History, Nutrition, Sleep, and Progress remain performance-sensitive as history grows. History snapshot rebuilding must remain outside active scroll intervals; deletion stays in Workout Detail rather than on row swipe actions. Saved Foods must remain value-backed while mounted and resolve SwiftData models only for mutations.
- Active Workout Preview content is bounded to the active rotation × four modes, with eight fallback/reuse entries. If that cap changes, re-run physical-device memory and first-frame acceptance checks rather than expanding startup work without measurement.
- Keep Preview source-data and cache publication outside the entire mounted route, not merely active scroll intervals. Retain one eager border-only detailed order and dedicated-handle drag ownership; row-wide drag gestures, duplicated orders, or lazy variable-height detailed rows can reintroduce scroll-indicator jitter. The order currently mounts from the pinned snapshot about 50 ms after the actionable top frame, and frame publication follows at about 100 ms; do not move frame setup back to the first drag, because that makes the lifted row a no-op.
- Coach must retain its last complete route snapshot while inactive or backgrounded. Its first actionable hero uses the value-backed recommended Preview split with no warm-frame SwiftData query; supporting sections and live observation attach afterward. Do not clear the destination for app-switcher privacy; Peakline's prepared health summary contains no credential or passphrase fields.
- Root-tab selection must remain observation-isolated from timing bookkeeping and `RootTabView`'s SwiftData-backed warm signatures. Keep the native switch free of whole-screen animation; prepared Workout, Splits, History, and Settings values must be visible before live queries attach.
- Keep charts lazy-loaded.
- Exercise charts still need at least two completed sessions for a useful trend; one-session states should explain that clearly.
- Protect the current acceptance thresholds:
  `today.route.appear coach` under 500ms in the verifier path, `root.notification.refresh` under 50ms in the interactive path, and one Preview `refresh onAppear` per open.
- Coach and hydrated Workout Preview are data-backed deep routes with a 500 ms navigation budget. Lightweight warm routes remain on the 300 ms budget; do not reclassify a route merely to hide a regression.
- Simulator performance remains thermally and service-load sensitive. Use independently booted route/root samples and report variance; do not weaken thresholds to accommodate an overloaded combined UI run. Physical-device first-frame and memory validation remains required for the expanded bounded startup payloads.

## Data And Analytics

- The app currently emphasizes best-set volume because it is easier to read than raw total tonnage.
- Future analytics can add total tonnage, PR lists, split consistency, and weekly volume summaries, but should not replace current meaning without a strong product reason.
- Firebase account backup, local backup, and export should stay healthy before risky persistence changes.

## Validation

General:

```bash
git diff --check
xcodebuild -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

Performance-sensitive work:

```bash
Scripts/verify_performance_acceptance.sh
```

For documentation-only tasks, `git diff --check` is sufficient unless app or project files were accidentally changed.

Physical-device QA remains outstanding because the connected iPhone was passcode locked during this run. Recheck all five redesigned root surfaces, the monthly History hero and weekly-goal sheet, completed duration editing, four-hour finish choices, Quick/Recovery estimate copy, Split Edit without template-note controls, the first Preview drag, menu anchoring, compact Profile and adaptive Settings rows, Workout Tools/Appearance copy, genuine-PR burst and static Reduce Motion fallback, immediate Done-to-Summary transition, Light/Dark appearance, Dynamic Type, VoiceOver, and Reduce Transparency on an unlocked device. The simulator's interactive inspection service also failed to start twice, so screenshots and UI-test accessibility queries supplied the automated visual evidence.
