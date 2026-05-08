# VPN App iOS Automation Testing Framework

XCUITest-based automation for testing a VPN app installed via TestFlight on a connected real iPhone.

## Requirements

- Xcode 15+ (with iOS SDK)
- macOS
- iPhone connected via USB with the VPN app installed (e.g. from TestFlight)
- VPN app’s **bundle identifier** and **accessibility identifiers** (see Configuration)

## Project Structure

```
App_testing/
├── VPNTest/
│   ├── VPNTest.xcodeproj/
│   ├── VPNTestHost/           # Minimal host app (required by Xcode for UI tests)
│   └── VPNTestUITests/        # Test target
│       ├── VPNTestConstants.swift   # Bundle ID, accessibility IDs, counts
│       ├── VPNTestReport.swift      # JSON report model and generation
│       ├── VPNTestBase.swift
│       ├── VPNAppLaunchStabilityTests.swift
│       ├── VPNRegionConnectionTests.swift
│       ├── VPNUIAssetsTests.swift
│       └── ...
├── run_tests.sh               # Run tests (auto-detect device or use -d)
└── README.md
```

## Configuration

1. **Bundle identifier**  
   In `VPNTest/VPNTestUITests/VPNTestConstants.swift`, set:
   - `vpnAppBundleIdentifier` to your VPN app’s bundle ID (e.g. from TestFlight/build settings).

2. **Accessibility identifiers**  
   In the same file, under `AccessibilityIds`, set identifiers to match your app’s UI (use Accessibility Inspector or your app’s source):
   - `regionList` – table/list of regions
   - `regionCell` – (optional) region cell identifier
   - `connectButton` – connect/disconnect button
   - `regionIcon` – (optional) region icon in cells

3. **Optional tuning**  
   In `VPNTestConstants.swift` you can change:
   - `launchStabilityIterations` (default 20) and `launchStabilityDurationSeconds` (60)
   - `regionConnectionRegionCount` (5), `regionConnectionRoundsPerRegion` (50), `regionConnectionDurationSeconds` (60)

## Tests

| Test | Description |
|------|-------------|
| **Launch stability** | Launches the app 20 times, keeps it open 60 seconds each time, detects crashes. |
| **Region connection** | Uses the first 5 regions in the UI table: connect → stay 60s → disconnect, 50 rounds per region. |
| **UI assets** | Checks that the region list loads, region icons exist, and the connect button exists. |

## Running Tests

### Option 1: Shell script (recommended)

The script **prompts you to launch the app from TestFlight** before tests start:

1. Run the script (device is auto-detected if one iPhone is connected via USB).
2. When you see **"LAUNCH APP"**, open TestFlight on your iPhone and open your VPN app.
3. When the app is open, press **ENTER** in the terminal to start testing.

```bash
# Make executable once
chmod +x run_tests.sh

# Full test run (after Launch App prompt)
./run_tests.sh

# Smoke test only – quick check that the script and app launch work
./run_tests.sh --smoke

# Use a specific device
./run_tests.sh -d 00008103-001A55203E88801E

# Or set env
export VPNTEST_DEVICE_ID=00008103-001A55203E88801E
./run_tests.sh
```

The script runs:

```bash
xcodebuild test -scheme VPNTest -destination 'platform=iOS,id=<device-id>'
```

### Option 2: Direct xcodebuild

1. Get device ID:  
   `xcrun xctrace list devices`  
   (or Xcode → Window → Devices and Simulators)

2. Run:

```bash
cd VPNTest
xcodebuild test -scheme VPNTest -destination 'platform=iOS,id=<device-id>'
```

### Option 3: Xcode

1. Open `VPNTest/VPNTest.xcodeproj` in Xcode.
2. Select the **VPNTest** scheme and a connected iPhone as destination.
3. Product → Test (⌘U).

## JSON Report

After the run, the test bundle writes a JSON report (e.g. under the app’s Documents in the container). It includes:

- **launchStability**: totalLaunches, successfulLaunches, successRate, crashCount, failures
- **regionConnection**: regionsTested, roundsPerRegion, totalAttempts, successfulConnections, successRate, crashCount, failures, perRegionResults
- **uiAssets**: regionListLoaded, regionIconsExist, connectButtonExists, passed, failures
- **summary**: overallPassed, totalCrashes, totalFailures

To get the report from the device:

- Xcode → Window → Devices and Simulators → select device → select **VPNTestHost** (or the test host app) → Download Container. The report is under `Documents/VPNTestReports/`.

## Debugging: What the test sees on the iPhone

When **Connect VPN** is not found or not tappable, the test prints **diagnostics** to the Xcode/terminal output:

- **Buttons**: id, label, and `hittable` for each button.
- **Switches**: id, label, value, and `hittable` (the green toggle is a UISwitch).
- **StaticTexts** whose label contains "connect".

Use this to see what the test sees and why the tap might fail (e.g. wrong id, label not set, or `hittable == false`).

**Optional: Pause before Connect** so you can look at the app on the device:

```bash
VPNTEST_PAUSE_BEFORE_CONNECT=1 ./run_tests.sh --quick-connect
```

After selecting the region, the test will wait **15 seconds** and print *"Look at the app on the device"* — compare the screen with the diagnostics that follow.

**Step log** — the test prints Step 1…7 so you can see where it stopped (e.g. "Step 2: Opening region list…" then failure = region list didn’t open).

## Notes

- The **VPN app must be installed** on the device (e.g. via TestFlight); the tests launch it by bundle identifier.
- **Accessibility identifiers** must match your app; otherwise region and connect tests will fail or need constants updated.
- Run on a **real device**; VPN and network behavior differ on the simulator.
