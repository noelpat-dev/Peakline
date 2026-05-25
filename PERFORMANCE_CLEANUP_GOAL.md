You are working in the Peakline / GymTracker SwiftUI + SwiftData iOS repo.

Goal:
Perform Performance Cleanup Pass 2 based on the fresh Xcode trace after the first optimisation pass.

This is not a broad rewrite. Do not redo the previous work. Focus only on unresolved runtime issues from the new trace.

Fresh trace highlights:

Good improvements:
- today.coach.snapshot improved to 40ms.
- repeated Coach route appearances are now 36ms, 34ms, and 46ms.
- sleep.analytics cache hits now complete in 0ms.
- workout_start.sleep_readiness cache hit completes in 0ms.
- progress route is now around 24–44ms.
- workout_preview.render_snapshot is around 42–49ms.

Remaining problems:
- today.route.appear coach appeared in 1865ms on first Coach navigation.
- The log showed: Gesture: System gesture gate timed out.
- Potential Structural Swift Concurrency Issue: unsafeForcedSync called from Swift Concurrent context still appears.
- root.notification.refresh completed in 75ms later in the run.
- UIKit constraint warnings repeat many times:
  - Unable to simultaneously satisfy constraints
  - _UIButtonBarButton
  - _UIModernBarButton
  - UIView-Encapsulated-Layout-Width == 0
  - ButtonWrapper.width == _UIButtonBarButton.width
- Nutrition route still appears around 91–128ms.
- Hydration route still appears around 82–108ms.
- Sleep route still appears around 67–104ms.
- Deferred coach.snapshot still sometimes completes around 51–74ms.

Important:
The first performance pass improved caching, but the unsafeForcedSync warning is still present. Treat that as unresolved, not fixed.

Read active docs only:
- README.md
- FEATURE_SUMMARY.md
- ARCHITECTURE.md
- ROADMAP.md
- KNOWN_ISSUES.md
- UI_STYLE_GUIDE.md
- NEXT_TASK.md
- NEXT_CODEX_CHAT.md

Do not use archived docs as active instructions.

Tasks:

1. Investigate and fix the remaining unsafeForcedSync warning

Search for:
- unsafeForcedSync
- Task.yield
- Task {
- Task.detached
- MainActor.run
- @MainActor
- DispatchQueue.main.sync
- DispatchQueue.main.async
- withCheckedContinuation
- withUnsafeContinuation
- ModelContext
- @Query usage inside async tasks
- any SwiftData model access after await

Find the actual remaining source of:
Potential Structural Swift Concurrency Issue: unsafeForcedSync called from Swift Concurrent context.

Do not silence the warning.
Do not just wrap whole views/services in @MainActor unless that is genuinely the correct fix.
Do not access SwiftData model objects across concurrency boundaries.
If async work needs model data, snapshot value-type inputs on the main actor first, then compute using value types.
Ensure UI state mutations happen on MainActor.
Cancel stale tasks when views disappear or input signatures change.

2. Investigate the 1865ms Coach first-route spike

The trace showed:
- today.route.selection coach requested
- today.route.selection completed in 0ms
- today.route.appear coach appeared in 1865ms
- Gesture: System gesture gate timed out
- today.coach.content_mount completed in 0ms
- coach.sleep_analytics completed in 108ms
- coach.snapshot completed in 74ms

This suggests the 1865ms delay may not be only Coach snapshot computation.

Investigate:
- route appear instrumentation placement
- whether view construction/layout is blocking before content_mount
- toolbar/navigation items
- sheets/popovers/menus on Coach or root shell
- UIKit constraint warnings around navigation/toolbar buttons
- work happening before PerformanceTracer route appear completion
- task scheduling on main actor during navigation
- heavy state invalidation caused by route selection

Fix only if you can identify a safe, local cause.

3. Fix repeated UIKit constraint warnings

Search root navigation and toolbar code for:
- ToolbarItem
- toolbar
- navigationBarItems
- Menu
- Button
- Label
- Image-only toolbar buttons
- custom button wrappers
- zero-width frames
- fixedSize
- frame(width: 0)
- hidden toolbar buttons
- conditional toolbar items
- UIKit/AppKit bridges if any

The warnings mention:
- _UIButtonBarButton
- _UIModernBarButton
- ButtonWrapper.width
- UIView-Encapsulated-Layout-Width == 0

Find likely SwiftUI toolbar/navigation buttons that create zero-width bar button wrappers.

Preferred fixes:
- Avoid empty toolbar items.
- Avoid conditional toolbar items that temporarily render zero-width content.
- Replace empty/hidden toolbar button labels with stable labels.
- Give icon-only toolbar items clear labels and stable content.
- Avoid custom toolbar button wrappers with impossible frames.
- Keep accessibility labels.

Do not redesign navigation.

4. Move notification refresh away from interactive paths if safe

root.notification.refresh reached 75ms.

Find where root.notification.refresh runs.

Make sure it does not block:
- launch first frame
- route selection
- route appear
- tab switching
- gesture handling

Preferred fix:
- run after initial UI mount
- debounce scene-phase refresh
- skip refresh if sleep notification inputs have not changed
- make refresh idempotent
- avoid repeated refreshes during rapid route changes

Do not break sleep notifications.

5. Improve remaining route shells only if safe

After fixing the above, do a small pass on route appearances above 50ms:
- Nutrition 91–128ms
- Hydration 82–108ms
- Sleep 67–104ms
- Workout 81ms

Look for duplicate .task/.onAppear work and heavy dashboard snapshots before first frame.

Only apply small safe changes:
- defer non-critical dashboard work until after first render
- prevent duplicate onAppear/task runs
- cache repeated snapshots with clear invalidation
- avoid body computed work

Do not rewrite Nutrition, Hydration, Sleep, or Workout architecture in this pass.

6. Keep instrumentation useful

Keep logs for:
- cache hit/miss
- route first mount vs warm mount
- notification refresh skip/run reason
- coach first mount timing
- unsafeForcedSync investigation outcome if measurable

Avoid release log spam if there is a debug logging convention.

7. Do not touch unrelated systems

Do not:
- redesign UI
- change SwiftData schema
- remove features
- alter HealthKit permissions
- alter barcode/OCR behavior
- alter app icons/assets
- edit archived docs
- add networking
- add AI
- change product behaviour
- perform broad architecture rewrites

Validation:
Run:
git diff --check

Run:
xcodebuild -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build

If the simulator is unavailable, run:
xcrun simctl list devices available
and choose an available iPhone simulator.

If build succeeds, run:
xcodebuild -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:GymTrackerTests

Final report:
- files changed
- exact remaining unsafeForcedSync source found
- exact fix for unsafeForcedSync
- what caused the 1865ms Coach route spike, or why it could not be proven
- whether UIKit constraint warnings were fixed
- whether root.notification.refresh was moved/debounced/skipped
- old vs new timings if available
- any remaining route paths above 50ms
- validation result
- recommended next pass
