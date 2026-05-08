#!/usr/bin/env bash
#
# Run VPN XCUITest suite on a connected real iPhone.
# Detects device automatically or uses VPNTEST_DEVICE_ID if set.
#

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/VPNTest"
SCHEME="VPNTest"
REPORT_PATH=""

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Run VPN app UI tests on a connected iPhone (app installed via TestFlight)."
    echo "Script will prompt you to launch the app from TestFlight before tests start."
    echo ""
    echo "Options:"
    echo "  -d, --device-id ID    Use this device (otherwise auto-detect first iPhone)"
    echo "  -o, --output PATH     Write JSON report to PATH (default: Documents/VPNTestReports)"
    echo "  -s, --smoke           Run only smoke test (verify script + app launch)"
    echo "  -t, --vpn-test        Run VPN test only: region selector → Fastest → connect → 1 min → disconnect"
    echo "  -q, --quick-connect   Quick connection: first region → connect → 15s → disconnect"
    echo "  -r, --soft-run        Soft run: first region → connect → 5s → disconnect"
    echo "  -m, --milestones      Milestone screenshots: home → region list scrolls → connect idle → connected → disconnect"
    echo "  -g, --discover-regions  Open region list, scroll, detect all row labels (no connect)"
    echo "  -f, --first-region-timing  First region → connect → measure UI to connected; disconnect → measure UI to idle (default 1s thresholds)"
    echo "  -p, --print-buttons      After first region select: dump all XCUIApplication.buttons (debug IFU layout)"
    echo "  -v, --trace-first-connect First region → connect → disconnect; print buttons after each step (verbose)"
    echo "      --region0-snapshot-cycle  First region → snapshot tap connect (vpn toggle off) → 5s → snapshot disconnect → log Alert/Sheet + buttons before/after dismiss"
    echo "  -3, --three-regions     Region catalog + rows 0→1→2 (list scrolled to top before each select), connect 5s, disconnect, post-disconnect popup log"
    echo "      --two-regions-hold5  First two list rows only (no full catalog scroll): each connect → 5s → disconnect; IFU feedback only; report + idle"
    echo "      --full-suite        Run entire VPNTestUITests target (all test classes; longer)"
    echo "      --region-services-catalog  Exclusive: print all region names, close list, open Services, print service names (not part of default full run)"
    echo "  -l, --list-devices    Print connected USB iPhone device ID and exit (use with -d)"
    echo "  -c, --check           Only check device detection and exit (no tests)"
    echo "  -h, --help            Show this help"
    echo ""
    echo "Environment:"
    echo "  VPNTEST_DEVICE_ID     Set device ID (used if -d not passed)"
    echo "  VPNTEST_SKIP_ENTER    Set to 1 to skip the \"Press ENTER\" prompt (automation / CI)"
    echo "  VPNTEST_APP           Short app key: ifu | idv | dashvpn (bundle map in VPNTestConstants.swift)"
    echo "  VPNTEST_BUNDLE_ID     Full bundle id override (wins over VPNTEST_APP)"
    echo "  VPNTEST_CONNECT_UI_THRESHOLD_SEC    Seconds: max time for connected UI after Connect tap (default 1)"
    echo "  VPNTEST_DISCONNECT_UI_THRESHOLD_SEC   Seconds: max time for idle UI after Disconnect tap (default 1)"
    echo ""
    echo "Example:"
    echo "  $0                   # Main pipeline: first region → disconnect → post-disconnect screen + popup dump; --three-regions for catalog + rows 0–2"
    echo "  $0 --smoke           # Quick check that testing pipeline works"
    echo "  $0 --vpn-test        # Single test: Fastest → connect → 1 min → disconnect"
    echo "  $0 --quick-connect   # Quick connection: first region → connect → 15s → disconnect"
    echo "  $0 --soft-run        # Soft run: first region → connect → 5s → disconnect"
    echo "  VPNTEST_APP=ifu $0 --milestones   # Screenshot sequence for IFU (org.freevpn.vpn.us)"
    echo "  VPNTEST_APP=ifu $0 --discover-regions   # Print region names from the app’s list UI"
    echo "  VPNTEST_APP=ifu $0 --first-region-timing   # First region + connect/disconnect UI timing (see thresholds above)"
    echo "  VPNTEST_APP=ifu $0 --print-buttons         # First region, then print every button label/id"
    echo "  VPNTEST_APP=ifu $0 --trace-first-connect    # First region connection test + button trace each step"
    echo "  VPNTEST_APP=ifu $0 --region0-snapshot-cycle  # Explicit snapshot connect → 5s → snapshot disconnect → popup + button inspection"
    echo "  VPNTEST_APP=ifu $0 --three-regions         # First three list rows: connect/disconnect each + summary report"
    echo "  VPNTEST_APP=ifu $0 --two-regions-hold5     # Each of first two rows: 5s connected; IFU feedback only (no Alert poll); report attachment"
    echo "  VPNTEST_APP=ifu $0 --region-services-catalog  # Region + Services name catalogs only (exclusive; not in default scheme run)"
    echo "  $0 -d <device-id>    # Use specific device (from --list-devices or Xcode)"
    exit 0
}

SMOKE=""
VPNTEST=""
QUICKCONNECT=""
SOFTRUN=""
MILESTONES=""
DISCOVER_REGIONS=""
FIRST_REGION_TIMING=""
PRINT_BUTTONS=""
TRACE_FIRST_CONNECT=""
THREE_REGIONS=""
TWO_REGIONS_HOLD5=""
REGION0_SNAPSHOT_CYCLE=""
FULL_SUITE=""
REGION_SERVICES_CATALOG=""
CHECK=""
LIST_DEVICES=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--device-id)
            DEVICE_ID="$2"
            shift 2
            ;;
        -o|--output)
            REPORT_PATH="$2"
            shift 2
            ;;
        -s|--smoke)
            SMOKE="1"
            shift
            ;;
        -t|--vpn-test)
            VPNTEST="1"
            shift
            ;;
        -q|--quick-connect)
            QUICKCONNECT="1"
            shift
            ;;
        -r|--soft-run)
            SOFTRUN="1"
            shift
            ;;
        -m|--milestones)
            MILESTONES="1"
            shift
            ;;
        -g|--discover-regions)
            DISCOVER_REGIONS="1"
            shift
            ;;
        -f|--first-region-timing)
            FIRST_REGION_TIMING="1"
            shift
            ;;
        -p|--print-buttons)
            PRINT_BUTTONS="1"
            shift
            ;;
        -v|--trace-first-connect)
            TRACE_FIRST_CONNECT="1"
            shift
            ;;
        -3|--three-regions)
            THREE_REGIONS="1"
            shift
            ;;
        --two-regions-hold5)
            TWO_REGIONS_HOLD5="1"
            shift
            ;;
        --region0-snapshot-cycle)
            REGION0_SNAPSHOT_CYCLE="1"
            shift
            ;;
        --full-suite)
            FULL_SUITE="1"
            shift
            ;;
        --region-services-catalog)
            REGION_SERVICES_CATALOG="1"
            shift
            ;;
        -l|--list-devices)
            LIST_DEVICES="1"
            shift
            ;;
        -c|--check)
            CHECK="1"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Resolve project path
if [[ ! -d "${PROJECT_DIR}" ]]; then
    echo "Error: Project not found at ${PROJECT_DIR}"
    exit 1
fi

# --- List devices and exit (uses same source as detection: xcodebuild) ---
if [[ -n "${LIST_DEVICES}" ]]; then
    echo "Connected USB iPhone (from Xcode destinations):"
    echo ""
    DEST_LIST=$(cd "${PROJECT_DIR}" && xcodebuild -scheme "${SCHEME}" -showdestinations 2>/dev/null || true)
    if echo "$DEST_LIST" | grep -q "platform:iOS,"; then
        echo "$DEST_LIST" | grep "platform:iOS," | grep -v "Simulator" | grep -v "placeholder" | while read -r line; do
            ID=$(echo "$line" | sed -n 's/.*id:\([0-9][0-9A-Fa-f-]*\)[,}].*/\1/p' | head -1)
            if [[ -n "$ID" ]]; then
                NAME=$(echo "$line" | sed -n 's/.*name:\([^}]*\)/\1/p' | sed 's/^ *//;s/ *$//;s/ *} *$//')
                echo "  $ID  $NAME"
                echo "  -> ./run_tests.sh -d $ID --soft-run"
            fi
        done
    fi
    echo ""
    echo "If no device appears: connect iPhone via USB, trust this Mac, then run again."
    echo "Or: Xcode → Window → Devices and Simulators → copy Identifier → ./run_tests.sh -d <id>"
    exit 0
fi

# Detect connected iPhone if no device specified
if [[ -z "${DEVICE_ID}" ]]; then
    DEVICE_ID="${VPNTEST_DEVICE_ID}"
fi

DEVICE_OS_VERSION=""
if [[ -z "${DEVICE_ID}" ]]; then
    echo "Detecting USB iPhone..."
    # Method 1: xcodebuild -showdestinations (most reliable; same list Xcode uses)
    DEST_LIST=$(cd "${PROJECT_DIR}" && xcodebuild -scheme "${SCHEME}" -showdestinations 2>/dev/null || true)
    if echo "$DEST_LIST" | grep -q "platform:iOS,"; then
        DEVICE_LINE=$(echo "$DEST_LIST" | grep "platform:iOS," | grep -v "Simulator" | grep -v "placeholder" | head -1)
        if [[ -n "${DEVICE_LINE}" ]]; then
            DEVICE_ID=$(echo "$DEVICE_LINE" | sed -n 's/.*id:\([0-9][0-9A-Fa-f-]*\)[,}].*/\1/p' | head -1)
        fi
    fi
    # Method 2: xctrace list devices
    if [[ -z "${DEVICE_ID}" ]] && command -v xcrun &>/dev/null; then
        RAW=$(xcrun xctrace list devices 2>/dev/null || true)
        [[ -z "${RAW}" ]] && RAW=$(instruments -s devices 2>/dev/null || true)
        if [[ -n "${RAW}" ]]; then
            DEVICE_LINE=$(echo "$RAW" | grep -i "iPhone" | grep -v "Simulator" | head -1)
            if [[ -n "${DEVICE_LINE}" ]]; then
                DEVICE_OS_VERSION=$(echo "$DEVICE_LINE" | sed -n 's/.*(\([0-9][0-9]*\.[0-9][0-9]*\)).*/\1/p' | head -1)
                DEVICE_ID=$(echo "$DEVICE_LINE" | sed -E 's/.*\(([0-9A-Fa-f-]{25,})\)[[:space:]]*$/\1/')
                [[ ! "${DEVICE_ID}" =~ ^[0-9A-Fa-f-]+$ ]] && DEVICE_ID=$(echo "$DEVICE_LINE" | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{8}' | head -1)
            fi
        fi
    fi
    # Method 3: xcdevice list (JSON)
    if [[ -z "${DEVICE_ID}" ]] && command -v xcrun &>/dev/null; then
        XCDEVICE_JSON=$(xcrun xcdevice list 2>/dev/null || true)
        if [[ -n "${XCDEVICE_JSON}" ]]; then
            DEVICE_ID=$(echo "$XCDEVICE_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for dev in d:
        if dev.get('simulator') == False and 'ios' in dev.get('platform','').lower():
            print(dev.get('identifier',''))
            break
except Exception: pass
" 2>/dev/null)
            if [[ -n "${DEVICE_ID}" ]]; then
                DEVICE_OS_VERSION=$(echo "$XCDEVICE_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for dev in d:
        if dev.get('simulator') == False and 'ios' in dev.get('platform','').lower():
            v = dev.get('operatingSystemVersion') or ''
            print(v.split()[0] if v else '')
            break
except Exception: pass
" 2>/dev/null)
            fi
        fi
    fi
fi

if [[ -z "${DEVICE_ID}" ]]; then
    echo "Error: No USB iPhone found. Connect your iPhone via USB, trust this Mac, then run again."
    echo ""
    echo "  $0 --list-devices   # Show device ID if Xcode sees it"
    echo "  $0 -d <device-id>   # From Xcode → Window → Devices and Simulators → Identifier"
    exit 1
fi

echo "Using device: ${DEVICE_ID}"
[[ -n "${DEVICE_OS_VERSION}" ]] && echo "Device iOS: ${DEVICE_OS_VERSION}"
echo ""

# --- Verify Xcode can run tests on this device (skip for --check) ---
if [[ -z "${CHECK}" ]]; then
    echo "Checking that Xcode can run tests on this device..."
    DEST_CHECK=$(cd "${PROJECT_DIR}" && xcodebuild -scheme "${SCHEME}" -destination "platform=iOS,id=${DEVICE_ID}" -showdestinations 2>&1) || true
    DEVICE_NOT_FOUND=""
    if echo "$DEST_CHECK" | grep -q "Unable to find a destination matching"; then
        DEVICE_NOT_FOUND=1
    fi
    if [[ -z "${DEVICE_NOT_FOUND}" ]]; then
        DEST_LIST=$(cd "${PROJECT_DIR}" && xcodebuild -scheme "${SCHEME}" -showdestinations 2>/dev/null || true)
        if ! echo "$DEST_LIST" | grep "platform:iOS" | grep -v Simulator | grep -q "${DEVICE_ID}"; then
            DEVICE_NOT_FOUND=1
        fi
    fi
    if [[ -n "${DEVICE_NOT_FOUND}" ]]; then
        echo ""
        echo "=============================================="
        echo "  ERROR: iPhone not found or not available"
        echo "=============================================="
        echo ""
        echo "  Device ID: ${DEVICE_ID}"
        echo ""
        echo "  Xcode does not see this iPhone. (It was detecting earlier?)"
        echo ""
        echo "  Try in order:"
        echo "    1. Unplug and replug the USB cable (use a data-capable cable, not charge-only)."
        echo "    2. Unlock the iPhone and keep it unlocked while running the script."
        echo "    3. On iPhone: if you see 'Trust This Computer?' tap Trust."
        echo "    4. Try a different USB port (prefer one directly on the Mac)."
        echo "    5. iOS 16+: Settings → Privacy & Security → Developer Mode → turn ON (restart if asked)."
        echo "    6. In Xcode: Window → Devices and Simulators — see if the device appears there."
        echo ""
        echo "  Then run:  $0 --list-devices   (to confirm Xcode sees the device)"
        echo "  If it appears, run the test again."
        if [[ -n "${VPNTEST_DEVICE_ID}" ]]; then
            echo ""
            echo "  (You have VPNTEST_DEVICE_ID set. To re-detect: unset VPNTEST_DEVICE_ID and run again.)"
        fi
        echo ""
        echo "=============================================="
        exit 1
    fi
    if echo "$DEST_CHECK" | grep -q "is not installed\|Ineligible destinations"; then
        XCODE_VERSION=$(xcodebuild -version 2>/dev/null | head -1 || true)
        echo ""
        echo "=============================================="
        echo "  ERROR: Xcode cannot run tests on this device"
        echo "=============================================="
        echo ""
        echo "  The test never runs on the phone, so nothing is"
        echo "  tapped in the app (no connect/disconnect)."
        echo ""
        # iOS 26.2 / 26.x "is not installed" with Xcode 26 = missing platform component
        if echo "$DEST_CHECK" | grep -q "Settings > Components\|26\.2 is not installed"; then
            echo "  Install the iOS platform component in Xcode:"
            echo ""
            echo "    1. Open Xcode"
            echo "    2. Xcode menu > Settings > Components (or Platforms)"
            echo "    3. Download / install the iOS version shown in the"
            echo "       error above (e.g. iOS 26.2)"
            echo ""
            echo "  Then run this script again."
        elif [[ -n "${DEVICE_OS_VERSION}" ]] && { [[ "${DEVICE_OS_VERSION}" =~ ^2[6-9]\. ]] || [[ "${DEVICE_OS_VERSION}" =~ ^[3-9][0-9]\. ]]; }; then
            echo "  Your iPhone is on iOS ${DEVICE_OS_VERSION}."
            echo "  ${XCODE_VERSION} may not support this iOS, or the platform is not installed."
            echo ""
            echo "  Try: Xcode > Settings > Components — install the iOS platform."
            echo "  Or upgrade Xcode from Mac App Store / developer.apple.com"
            echo ""
            echo "  Then run this script again."
        else
            echo "  Fix: Install the iOS platform in Xcode so it"
            echo "  matches your device:"
            echo ""
            echo "    1. Open Xcode"
            echo "    2. Xcode menu > Settings (or Preferences)"
            echo "    3. Go to the Platforms / Components tab"
            echo "    4. Install the iOS version that matches your iPhone"
            echo ""
            echo "  Then run this script again."
        fi
        echo "=============================================="
        exit 1
    fi
    if ! echo "$DEST_CHECK" | grep -q "${DEVICE_ID}"; then
        echo "  Warning: Device ${DEVICE_ID} not in Xcode destinations. You may see an error when tests run."
    else
        echo "  Device is eligible. Tests will run on your USB iPhone."
    fi
    echo ""
fi

# --- Check-only mode: verify detection and print command ---
if [[ -n "${CHECK}" ]]; then
    echo "=============================================="
    echo "  CHECK OK"
    echo "=============================================="
    echo ""
    echo "  Device:          ${DEVICE_ID}"
    echo "  Project:         ${PROJECT_DIR}"
    echo "  Scheme:          ${SCHEME}"
    echo ""
    echo "  To run quick connection test on device:"
    echo "    ./run_tests.sh --quick-connect"
    echo ""
    echo "  To run full tests:"
    echo "    ./run_tests.sh"
    echo "=============================================="
    exit 0
fi

# --- One prompt: test will build, then launch the app; you close paywalls when it opens ---
_wait_enter() {
    if ! read -r -p "  Press ENTER to continue... " < /dev/tty 2>/dev/null; then
        read -r -p "  Press ENTER to continue... " || exit 1
    fi
}
echo "=============================================="
echo "  READY TO RUN TEST"
echo "=============================================="
echo ""
echo "  When you press ENTER:"
echo "  1. The test will build and install on your iPhone."
echo "  2. The test will then LAUNCH the VPN app on your phone."
echo "  3. When the app opens, close any paywalls (tap X on each)."
echo "  4. The test waits up to 90 seconds for the region list, then runs."
echo ""
echo "  Press ENTER to start the build and test."
echo ""
if [[ -n "${VPNTEST_SKIP_ENTER}" ]]; then
    echo "  (VPNTEST_SKIP_ENTER is set — continuing without waiting for ENTER.)"
    echo ""
else
    _wait_enter
    echo ""
fi
echo "  Building and running test on device..."
echo "=============================================="
echo ""

DESTINATION="platform=iOS,id=${DEVICE_ID}"

cd "${PROJECT_DIR}"

XCODE_ARGS=(
    -scheme "${SCHEME}"
    -destination "${DESTINATION}"
    -allowProvisioningUpdates
    -allowProvisioningDeviceRegistration
)
if [[ -n "${SMOKE}" ]]; then
    XCODE_ARGS+=(-only-testing:VPNTestUITests/VPNTestUITests/testSmoke_AppLaunchesAndReady)
    echo "Running smoke test only (testSmoke_AppLaunchesAndReady)."
elif [[ -n "${VPNTEST}" ]]; then
    XCODE_ARGS+=(-only-testing:VPNTestUITests/VPNTestUITests/testVPNTest_SelectFastestConnectDisconnect1Min)
    echo "Running VPN test only: region selector → Fastest → connect → 1 min → disconnect."
elif [[ -n "${QUICKCONNECT}" ]]; then
    XCODE_ARGS+=(-only-testing:VPNTestUITests/VPNTestUITests/testQuickConnection_ConnectShortWaitDisconnect)
    echo "Running quick connection test: first region → connect → 15s → disconnect."
elif [[ -n "${SOFTRUN}" ]]; then
    XCODE_ARGS+=(-only-testing:VPNTestUITests/VPNTestUITests/testSoftRun_FirstRegionConnect5sDisconnect)
    echo "Running soft run: first region → connect → 5s → disconnect."
elif [[ -n "${MILESTONES}" ]]; then
    XCODE_ARGS+=(-only-testing:VPNTestUITests/VPNMilestoneScreenshotTests/testMilestoneScreenshots_ConnectLifecycle)
    echo "Running milestone screenshot test (VPNTEST_APP / VPNTEST_BUNDLE_ID passed through to xcodebuild)."
elif [[ -n "${DISCOVER_REGIONS}" ]]; then
    XCODE_ARGS+=(-only-testing:VPNTestUITests/VPNRegionDiscoveryTests/testDiscoverRegionsFromList)
    echo "Running region discovery: scroll list and record row labels from the running app."
elif [[ -n "${FIRST_REGION_TIMING}" ]]; then
    XCODE_ARGS+=(-only-testing:VPNTestUITests/VPNFirstRegionTimingTests/testFirstRegion_OpenConnectDisconnect_MonitorTransitionThresholds)
    echo "Running first-region connect/disconnect UI timing (default 1s thresholds; override with VPNTEST_*_THRESHOLD_SEC)."
elif [[ -n "${PRINT_BUTTONS}" ]]; then
    XCODE_ARGS+=(-only-testing:VPNTestUITests/VPNFirstRegionTimingTests/testPrintAllButtonsAfterFirstRegionSelected)
    echo "Running button dump after first region selection."
elif [[ -n "${TRACE_FIRST_CONNECT}" ]]; then
    XCODE_ARGS+=(-only-testing:VPNTestUITests/VPNFirstRegionTimingTests/testFirstRegionConnect_VerboseTrace)
    echo "Running first-region connect/disconnect with verbose button trace after each step."
elif [[ -n "${THREE_REGIONS}" ]]; then
    XCODE_ARGS+=(-only-testing:VPNTestUITests/VPNThreeRegionReportTests/testConnectFirstThreeRegions_ReportSummary)
    echo "Running region pipeline: catalog (index→name) + rows 0→1→2 (top scroll before each row), connect 5s, disconnect, post-disconnect popup yes/no + one indexed tap if alert/sheet."
elif [[ -n "${TWO_REGIONS_HOLD5}" ]]; then
    XCODE_ARGS+=(-only-testing:VPNTestUITests/VPNThreeRegionReportTests/testTwoRegions_Row0Disconnect_ClearPromo_Row1ConnectHold5s_Report)
    echo "Running two-region hold5: each row 5s connected, IFU feedback-only between rows, guarded disconnect after feedback."
elif [[ -n "${REGION0_SNAPSHOT_CYCLE}" ]]; then
    XCODE_ARGS+=(-only-testing:VPNTestUITests/VPNFirstRegionTimingTests/testFirstRegion_SnapshotConnect_Hold5s_Disconnect_ThenInspectButtonsAndPopup)
    echo "Running region-0 snapshot cycle: visible-button connect → 5s hold → snapshot disconnect → Alert/Sheet + button dumps."
elif [[ -n "${FULL_SUITE}" ]]; then
    XCODE_ARGS+=(-only-testing:VPNTestUITests)
    echo "Running full VPNTestUITests suite (all classes)."
elif [[ -n "${REGION_SERVICES_CATALOG}" ]]; then
    XCODE_ARGS+=(-only-testing:VPNTestUITests/VPNRegionAndServicesCatalogTests/testPrintAllRegionNamesThenAllServiceNames)
    echo "Running exclusive region + services catalog (skipped in scheme by default; -only-testing runs it). Use VPNTEST_APP=ifu for IFU."
else
    XCODE_ARGS+=(-only-testing:VPNTestUITests/VPNThreeRegionReportTests/testFirstRegionDisconnect_ThenInspectPopupAndScreen)
    echo "Running main pipeline: first region → disconnect → dump screen & popup (before dismiss), then dismiss if Alert/Sheet."
fi
[[ -n "${REPORT_PATH}" ]] && XCODE_ARGS+=(-resultBundlePath "${REPORT_PATH}")

XCODE_TEST_LOG=$(mktemp)
trap "rm -f '$XCODE_TEST_LOG'" EXIT
if ! xcodebuild test "${XCODE_ARGS[@]}" 2>&1 | tee "$XCODE_TEST_LOG"; then
    echo ""
    echo "=============================================="
    if grep -q '\*\* TEST FAILED \*\*' "$XCODE_TEST_LOG" 2>/dev/null; then
        echo "  Tests ran on the device but failed (assertion or timeout)."
        echo "  Open the .xcresult listed above in Xcode for logs and screenshot attachments."
    else
        echo "  Tests did not run on the device (or Xcode exited before finishing)."
        echo "  So the app may not have been driven as expected."
    fi
    echo "=============================================="
    if grep -q "Developer Mode disabled" "$XCODE_TEST_LOG" 2>/dev/null; then
        echo ""
        echo "  On your iPhone: Settings → Privacy & Security →"
        echo "  Developer Mode → turn ON, then restart if asked."
        echo "  Reconnect the device and run this script again."
    elif grep -q "requires a development team\|Signing for" "$XCODE_TEST_LOG" 2>/dev/null; then
        echo ""
        echo "  Set a development team in Xcode:"
        echo "  1. Open VPNTest/VPNTest.xcodeproj in Xcode"
        echo "  2. Select project VPNTest → TARGETS → VPNTestHost"
        echo "  3. Signing & Capabilities → Team → choose your Apple ID team"
        echo "  4. Do the same for target VPNTestUITests"
        echo "  5. Run this script again."
    else
        echo "  Fix the error above, then run this script again."
    fi
    echo "=============================================="
    exit 1
fi

echo ""
echo "Tests finished. JSON report is generated by the test bundle and written to the app container."
echo "To copy the report from device, use Xcode > Window > Devices and Simulators > Download Container for VPNTestUITests."
