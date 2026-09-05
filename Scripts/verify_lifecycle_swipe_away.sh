#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${TMPDIR:-/tmp}/gymtracker_lifecycle_swipe_away_$(date +%Y%m%d_%H%M%S)"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"

mkdir -p "$LOG_DIR"
cd "$ROOT_DIR"

echo "Lifecycle relaunch logs: $LOG_DIR"

run_and_log() {
    local name="$1"
    shift

    echo "== $name =="
    "$@" 2>&1 | tee "$LOG_DIR/${name}.log"
}

run_and_log build \
    xcodebuild \
    -project GymTracker.xcodeproj \
    -scheme GymTracker \
    -configuration Debug \
    -destination "$DESTINATION" \
    build

xcrun simctl shutdown all >/dev/null 2>&1 || true
xcrun simctl boot "$SIMULATOR_NAME" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_NAME" -b

run_and_log lifecycle_ui_test \
    xcodebuild \
    -project GymTracker.xcodeproj \
    -scheme GymTracker \
    -configuration Debug \
    -destination "$DESTINATION" \
    -parallel-testing-enabled NO \
    test -only-testing:GymTrackerUITests/AppLifecycleSwipeAwayUITests/testBackgroundTerminateAndRelaunchRemainsUsable

python3 - "$LOG_DIR/lifecycle_ui_test.log" <<'PY'
import sys
from pathlib import Path

log_path = Path(sys.argv[1])
lines = log_path.read_text(errors="replace").splitlines()
text = "\n".join(lines)

forbidden = [
    "Potential Structural Swift Concurrency Issue",
    "unsafeForcedSync",
    "SwiftData",
    "fatal error",
    "MainActor",
    "Gesture: System gesture gate timed out",
    "Unable to simultaneously satisfy constraints",
]

failures = []
for needle in forbidden:
    if needle in text:
        failures.append(f"found forbidden log string: {needle}")

if "LIFECYCLE_RELAUNCH_PASS" not in text:
    failures.append("expected the background/terminate/relaunch journey to finish")

if failures:
    print("Lifecycle relaunch verifier failed:")
    for failure in failures:
        print(f" - {failure}")

    print("Relevant log excerpt:")
    matched_lines = []
    for index, line in enumerate(lines):
        if any(needle in line for needle in forbidden) or "LIFECYCLE_RELAUNCH_PASS" in line:
            start = max(0, index - 3)
            end = min(len(lines), index + 4)
            matched_lines.extend((i, lines[i]) for i in range(start, end))

    seen = set()
    for index, line in matched_lines[:160]:
        if index in seen:
            continue
        seen.add(index)
        print(f"{index + 1}: {line}")

    print(f"Full lifecycle log: {log_path}")
    sys.exit(1)

print("lifecycle_relaunch=PASS")
print(f"Full lifecycle log: {log_path}")
PY
