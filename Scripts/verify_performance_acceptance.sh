#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${TMPDIR:-/tmp}/gymtracker_performance_acceptance_$(date +%Y%m%d_%H%M%S)"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"

mkdir -p "$LOG_DIR"
cd "$ROOT_DIR"

echo "Performance acceptance logs: $LOG_DIR"

run_and_log() {
    local name="$1"
    shift

    echo "== $name =="
    "$@" 2>&1 | tee "$LOG_DIR/${name}.log"
}

run_and_log git_diff_check git diff --check

run_and_log build \
    xcodebuild \
    -project GymTracker.xcodeproj \
    -scheme GymTracker \
    -configuration Debug \
    -destination "$DESTINATION" \
    build

run_and_log unit_tests \
    xcodebuild \
    -project GymTracker.xcodeproj \
    -scheme GymTracker \
    -configuration Debug \
    -destination "$DESTINATION" \
    -parallel-testing-enabled NO \
    test -only-testing:GymTrackerTests

xcrun simctl shutdown all >/dev/null 2>&1 || true
xcrun simctl boot "$SIMULATOR_NAME" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_NAME" -b

run_and_log performance_ui_test \
    xcodebuild \
    -project GymTracker.xcodeproj \
    -scheme GymTracker \
    -configuration Debug \
    -destination "$DESTINATION" \
    -parallel-testing-enabled NO \
    test \
    -only-testing:GymTrackerUITests/CoachWorkoutPreviewUITests/testPerformanceAcceptanceRoutes \
    -only-testing:GymTrackerUITests/CoachWorkoutPreviewUITests/testPerformanceAcceptanceRootTabTransitionsRemainResponsive

cat "$LOG_DIR"/*.log > "$LOG_DIR/combined.log"

python3 - "$LOG_DIR/combined.log" <<'PY'
import re
import sys
from pathlib import Path

log_path = Path(sys.argv[1])
lines = log_path.read_text(errors="replace").splitlines()
text = "\n".join(lines)
failures = []

def fail(message):
    if message not in failures:
        failures.append(message)

for needle in [
    "Potential Structural Swift Concurrency Issue: unsafeForcedSync",
    "Gesture: System gesture gate timed out",
    "Unable to simultaneously satisfy constraints",
    "_UIButtonBarButton",
    "_UIModernBarButton",
    "ButtonWrapper.width",
    "UIView-Encapsulated-Layout-Width == 0",
    "Targets loading",
    "Coach details are preparing",
    "preview.route.shell_visible",
    "coach.inactive_placeholder",
]:
    if needle in text:
        fail(f"found forbidden log string: {needle}")

for match in re.finditer(r"today\.route\.appear coach appeared in (\d+)ms", text):
    value = int(match.group(1))
    if value > 500:
        fail(f"today.route.appear coach exceeded 500ms: {value}ms")

for match in re.finditer(r"root\.notification\.refresh completed in (\d+)ms", text):
    value = int(match.group(1))
    if value > 50:
        fail(f"root.notification.refresh exceeded 50ms: {value}ms")

for match in re.finditer(r"checkin\.sheet\.presentation stable_frame elapsed_ms=(\d+)", text):
    value = int(match.group(1))
    if value > 500:
        fail(f"Check-In stable sheet frame exceeded 500ms: {value}ms")

for match in re.finditer(r"motion\.checkin\.select response_ms=(\d+)", text):
    value = int(match.group(1))
    if value > 100:
        fail(f"Check-In rating response exceeded 100ms: {value}ms")

if "checkin.sheet.presentation duplicate request" in text:
    fail("Check-In presented more than once for one interaction")

for match in re.finditer(
    r"navigation\.interaction stable_frame[^\n]*elapsed_ms=(\d+)[^\n]*threshold_ms=(\d+)",
    text,
):
    elapsed = int(match.group(1))
    threshold = int(match.group(2))
    if elapsed > threshold:
        fail(
            f"Navigation stable frame exceeded threshold: {elapsed}ms > {threshold}ms"
        )

if "navigation.interaction duplicate_mutation" in text:
    fail("Navigation produced a duplicate route mutation")

history_scroll_active = False
for line in lines:
    if "history.scroll begin" in line:
        history_scroll_active = True
        continue
    if "history.scroll end" in line:
        history_scroll_active = False
        continue
    if history_scroll_active and "history.display_snapshot" in line:
        fail("History rebuilt its display snapshot during an active scroll")

preview_mounted = False
for line in lines:
    if "workout_preview.render_snapshot route_mounted" in line:
        preview_mounted = True
        continue
    if "workout_preview.render_snapshot route_dismissed" in line:
        preview_mounted = False
        continue
    if preview_mounted and (
        "workout_preview.render_snapshot refresh" in line
        or "workout_preview.render_snapshot make" in line
        or "workout_preview.render_snapshot signature" in line
        or "workout_preview.render_snapshot fetch" in line
        or "workout_preview.render_snapshot build" in line
        or "workout_preview.render_snapshot source_data" in line
        or "workout_preview.warm_cache published" in line
        or "workout_preview.warm_cache updated" in line
        or "workout_preview.warm_cache catalog prepared" in line
        or "workout_preview.warm_cache miss" in line
        or "workout_preview.warm_cache reject unresolved" in line
    ):
        fail("Workout Preview performed source-data or cache publication work while mounted")

preview_on_appear = sum(
    1
    for line in lines
    if "PERF_ACCEPTANCE workout_preview.render_snapshot refresh onAppear" in line
)
if preview_on_appear > 1:
    fail(f"WorkoutPreview refreshed onAppear more than once: {preview_on_appear}")

warm_cache_summaries = [
    int(value)
    for value in re.findall(r"previewWarmCacheHits=(\d+)", text)
]
warm_cache_hits = max(warm_cache_summaries, default=0)
if "PERF_ACCEPTANCE workout_preview.warm_cache hit" not in text and warm_cache_hits < 1:
    fail("Workout Preview did not report a warm-cache hit")

for match in re.finditer(r"PREVIEW_HYDRATION_METRIC[^\n]*hydrated=([0-9.]+)", text):
    value = float(match.group(1))
    if value > 0.5:
        fail(f"Workout Preview first hydrated frame exceeded 500ms: {value:.3f}s")

pending_workout_coach_append = False
for line in lines:
    if "workout.route.navigation path_changed depth=0" in line:
        pending_workout_coach_append = False
    if "workout.route.navigation appended route=coach" in line:
        if pending_workout_coach_append:
            fail("Workout -> Coach appended route=coach twice without path_changed depth=0")
        pending_workout_coach_append = True

for line in lines:
    if "PERF_ACCEPTANCE_UI_SUMMARY" in line and "performance_acceptance=FAIL" in line:
        fail(f"in-app performance acceptance failed: {line}")

if failures:
    print("Performance acceptance verifier failed:")
    for failure in failures:
        print(f" - {failure}")
    print(f"Full combined log: {log_path}")
    sys.exit(1)

print("Performance acceptance verifier passed.")
print(f"Full combined log: {log_path}")
PY
