#!/usr/bin/env bash
#
# Run this on your Mac with iPhone connected via USB.
# Verifies: device detection, Xcode destination, then runs the VPN test.
# When you see "LAUNCH APP": open your VPN app from TestFlight, then press ENTER.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "=============================================="
echo "  Testing: device, destination, then VPN test"
echo "=============================================="
echo ""

# 1. Device detection
echo "Step 1: Checking device..."
if ! ./run_tests.sh --check > /tmp/vpn_check.log 2>&1; then
    echo "  FAIL: Device not found or script error."
    cat /tmp/vpn_check.log
    exit 1
fi
echo "  OK: Device detected."
grep "Using device:" /tmp/vpn_check.log || true
grep "Device iOS:" /tmp/vpn_check.log || true
echo ""

# 2. Destination check (run test script; it will exit before Launch App if destination is bad)
echo "Step 2: Checking Xcode can run on this device..."
DEVICE_ID=$(grep "Using device:" /tmp/vpn_check.log | sed 's/.*Using device: *//' | head -1)
if [[ -z "${DEVICE_ID}" ]]; then
    echo "  Could not get device ID. Run: ./run_tests.sh --check"
    exit 1
fi

DEST_CHECK=$(cd VPNTest && xcodebuild -scheme VPNTest -destination "platform=iOS,id=${DEVICE_ID}" -showdestinations 2>&1) || true
if echo "$DEST_CHECK" | grep -q "Ineligible destinations\|is not installed"; then
    echo "  FAIL: Xcode cannot run tests on this device."
    echo "$DEST_CHECK" | grep -A2 "Ineligible\|error:"
    exit 1
fi
echo "  OK: Device is eligible for testing."
echo ""

# 3. Run VPN test (user must open app when prompted and press Enter)
echo "Step 3: Running VPN test on device."
echo "  When you see 'LAUNCH APP': open your VPN app from TestFlight on the iPhone,"
echo "  then press ENTER here."
echo ""
./run_tests.sh --vpn-test
