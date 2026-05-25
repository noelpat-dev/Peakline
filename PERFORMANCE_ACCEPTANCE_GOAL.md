You are working in the Peakline / GymTracker SwiftUI + SwiftData iOS repo.

Goal:
Create and use a repeatable performance/regression acceptance loop so Codex can keep fixing the current runtime issues until they are actually resolved.

Do not rely only on manual Xcode observation.
Create a script and/or UI test that can run repeatedly and fail when the known regressions are still present.

Current known failures from latest trace:
- Today → Coach first route can appear in 2371ms.
- `Gesture: System gesture gate timed out` still appears.
- `Potential Structural Swift Concurrency Issue: unsafeForcedSync called from Swift Concurrent context` still appears around app backgrounding.
- WorkoutPreview previously showed repeated render snapshot / loading issues.
- Workout → Coach duplicate route issue should stay fixed.

Create an acceptance validator.

Preferred implementation:
1. Add or update a UI test that exercises:
   - cold launch
   - Today → Coach
   - Workout → Coach
   - Workout → Preview
   - change Workout Preview mode once
   - back navigation from Coach
   - app background/reopen if feasible in UI tests

2. Add a shell script:
   Scripts/verify_performance_acceptance.sh

The script should:
- run `git diff --check`
- run the Debug build
- run the relevant UI/unit tests
- capture app/test logs if possible
- scan logs for known failure strings
- exit non-zero if any failure remains

Failure strings:
- `Potential Structural Swift Concurrency Issue: unsafeForcedSync`
- `Gesture: System gesture gate timed out`
- `Unable to simultaneously satisfy constraints`
- `_UIButtonBarButton`
- `_UIModernBarButton`
- `ButtonWrapper.width`
- `UIView-Encapsulated-Layout-Width == 0`

Timing failures:
- fail if `today.route.appear coach appeared in` is above 500ms
- fail if `root.notification.refresh completed in` is above 50ms, unless explicitly marked deferred work
- fail if WorkoutPreview logs multiple `refresh onAppear` completions for a single open
- fail if Workout → Coach logs multiple adjacent `appended route=coach` without a `path_changed depth=0` between them

If xcodebuild log capture cannot reliably catch app console logs:
- add DEBUG-only in-app validation counters to PerformanceTracer
- expose enough logs during UI tests to make the script fail reliably
- do not ship user-facing changes

Loop rules:
After creating the verifier:
1. Run `Scripts/verify_performance_acceptance.sh`.
2. If it fails, inspect the exact failed condition.
3. Apply the smallest fix for that failed condition only.
4. Run the verifier again.
5. Repeat until the verifier passes, or stop after 3 consecutive attempts on the same failing condition and report the blocker.

Do not:
- do broad performance rewrites
- change SwiftData schemas
- redesign UI
- edit archived docs
- remove working performance fixes
- silence warnings without fixing causes

Final acceptance:
The task is done only when:
- `Scripts/verify_performance_acceptance.sh` exits 0
- build passes
- tests pass
- no unsafeForcedSync appears in captured logs
- no gesture gate timeout appears in captured logs
- no toolbar constraint warning appears in captured logs
- Today → Coach and Workout → Coach use one route push and one back swipe
- WorkoutPreview does not repeatedly refresh on initial open

Final report:
- verifier created
- exact command to run it
- final pass/fail result
- failures found and fixed
- remaining limitations if log capture is imperfect
