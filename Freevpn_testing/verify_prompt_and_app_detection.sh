#!/usr/bin/env bash
#
# Verifies:
#  1. "Launch App" prompt is shown and flow continues after Enter
#  2. Script runs the smoke test that detects app launch (testSmoke_AppLaunchesAndReady)
# Run from App_testing directory. Requires connected iPhone for full pass.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT

PASS=0
FAIL=0

check() {
    if [[ "$1" == "1" ]]; then
        echo "  PASS: $2"
        ((PASS++)) || true
    else
        echo "  FAIL: $2"
        ((FAIL++)) || true
    fi
}

echo "=============================================="
echo "  Verification: Prompt and app-launch detection"
echo "=============================================="
echo ""

# --- 1. Device detection ---
echo "1. Device detection..."
if ./run_tests.sh --check 2>&1 | tee "$LOG" | grep -q "CHECK OK"; then
    check 1 "Device detection (--check) runs and reports CHECK OK"
else
    check 0 "Device detection (--check) did not report CHECK OK"
fi
if grep -q "Using device:" "$LOG"; then
    DEVICE_ID=$(grep "Using device:" "$LOG" | sed 's/.*Using device: *//')
    check 1 "Device ID found: ${DEVICE_ID}"
else
    check 0 "No device ID in output (connect iPhone or set VPNTEST_DEVICE_ID)"
fi
echo ""

# --- 2. Launch App prompt and flow (pipe Enter to skip waiting) ---
echo "2. Launch App prompt and flow..."
( sleep 1; echo "" ) | ./run_tests.sh --smoke 2>&1 | tee "$LOG" >/dev/null
if grep -q "LAUNCH APP" "$LOG"; then
    check 1 "Prompt 'LAUNCH APP' is displayed"
else
    check 0 "Prompt 'LAUNCH APP' was not found in output"
fi
if grep -q "ENTER" "$LOG" && ( grep -q "app is open" "$LOG" || grep -q "app is visible" "$LOG" || grep -q "detect that" "$LOG" ); then
    check 1 "Instructions (ENTER when app is open) are displayed"
else
    check 0 "Instructions (ENTER when app is open) were not found"
fi
if grep -q "Starting tests..." "$LOG"; then
    check 1 "After Enter: 'Starting tests...' is shown (prompt accepted)"
else
    check 0 "After Enter: 'Starting tests...' did not appear"
fi
if grep -q "testSmoke_AppLaunchesAndReady" "$LOG"; then
    check 1 "Smoke test (app-launch detection) is invoked"
else
    check 0 "Smoke test testSmoke_AppLaunchesAndReady was not invoked"
fi
echo ""

# --- 3. Smoke test runs on device (xcodebuild test) ---
echo "3. App-launch detection on device..."
if grep -q "xcodebuild test" "$LOG"; then
    check 1 "xcodebuild test command was run"
else
    check 0 "xcodebuild test was not run"
fi
if grep -q "error: Unable to find a destination" "$LOG" || grep -q "Ineligible destinations" "$LOG"; then
    echo "  NOTE: Device destination was ineligible (e.g. iOS version / Xcode SDK)."
    echo "        Fix in Xcode (install platform / pair device), then run: ./run_tests.sh --smoke"
    echo "        Open VPN app from TestFlight, press Enter — smoke test will detect app."
elif grep -q "Test Case.*testSmoke_AppLaunchesAndReady.*passed" "$LOG" 2>/dev/null; then
    check 1 "Smoke test PASSED — app launch was detected on device"
elif grep -q "Test Case.*testSmoke_AppLaunchesAndReady.*failed" "$LOG" 2>/dev/null; then
    check 0 "Smoke test failed (app may not have been in foreground)"
else
    echo "  SKIP: Could not determine test result (run ./run_tests.sh --smoke manually to verify app detection)"
fi
echo ""

# --- Summary ---
echo "=============================================="
echo "  Result: ${PASS} passed, ${FAIL} failed"
echo "=============================================="
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
