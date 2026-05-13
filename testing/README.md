# App Testing Script

This repo contains an Xcode UI test wrapper for validating VPN region connections and settings pages on a USB-connected iPhone.

The main entry point is:

```bash
./app_testing.sh [app=IFU|IDV] [boost on|off] [adblock on|off] [--quick-connect|--soft-connect|full|check-settings]
```

## Supported Apps

| App argument | Bundle ID | App |
| --- | --- | --- |
| `app=IFU` | `org.freevpn.vpn.us` | Free VPN US |
| `app=IDV` | `com.actmobile.dashvpn` | VPN - Dash |

If no app is provided, the script defaults to `IFU`.

## Prerequisites

1. Connect the iPhone to the Mac over USB.
2. Trust the Mac on the iPhone if prompted.
3. Keep the target VPN app installed on the iPhone.
4. Make sure Xcode can run UI tests on the device.
5. Run commands from this folder:

```bash
cd /Users/sadrish/Documents/App_testing/testing
```

The default device ID is set inside `app_testing.sh`. To override it:

```bash
DEVICE_ID=<iphone-device-id> ./app_testing.sh app=IFU --quick-connect
```

## Common Commands

### Quick Region Test

Tests the first 2 regions.

```bash
./app_testing.sh app=IFU --quick-connect
./app_testing.sh app=IDV --quick-connect
```

Single-dash form also works:

```bash
./app_testing.sh app=IFU -quick-connect
```

### Soft Region Test

Tests the first 4 regions.

```bash
./app_testing.sh app=IFU --soft-connect
./app_testing.sh app=IDV --soft-connect
```

### Full Region Test

Tests up to 250 regions.

```bash
./app_testing.sh app=IFU full
./app_testing.sh app=IDV full
```

### Boost and Adblock On

Turns on Boost and Adblock before testing.

```bash
./app_testing.sh app=IFU boost on adblock on --quick-connect
./app_testing.sh app=IDV boost on adblock on --quick-connect
```

Equivalent `key=value` form:

```bash
./app_testing.sh app=IFU boost=on adblock=on --quick-connect
```

### Boost and Adblock Off

If no Boost/Adblock arguments are passed, both default to `off`.

```bash
./app_testing.sh app=IFU --quick-connect
./app_testing.sh app=IDV --quick-connect
```

Explicit off:

```bash
./app_testing.sh app=IFU boost off adblock off --quick-connect
```

## Settings Page Checks

Use `check-settings` when you only want to validate settings/options pages.

```bash
./app_testing.sh app=IFU check-settings
./app_testing.sh app=IDV check-settings
```

For IFU, the script checks:

- `My IP`
- `Speed Test`
- `About us`
- `Privacy policy`
- `Terms of use`

For IDV, the script checks:

- `What is My Geo IP?`
- `What is My Network Speed?`

Each option is tapped, the destination page is checked for loaded content, then the page is closed and the next option is tested.

## Region Test Behavior

For each selected region, the script:

1. Opens the region selector.
2. Selects the next region by list order.
3. Waits for connection.
4. Waits for IP/location or connected-state evidence.
5. Holds the connection for the configured hold time.
6. Disconnects.
7. Closes feedback or session-ended pages if shown.
8. Verifies the app returns to the default disconnected state.
9. Prints a `PASS` or `FAIL` line for that region.

IDV has special handling for its region wheel/list: the highlighted row is tapped to commit selection.

## Advanced Environment Variables

These can be placed before the command.

| Variable | Default | Meaning |
| --- | --- | --- |
| `DEVICE_ID` | Set in script | iPhone destination device ID |
| `SCHEME` | `VPNTest` | Xcode scheme |
| `VPN_REGION_LIMIT` | Based on mode | Number of regions to test |
| `VPN_HOLD_SECONDS` | `10` | Seconds to stay connected per region |
| `VPN_START_INDEX` | `1` | One-based region index to start from |
| `VPN_ANCHOR_REGION` | empty | Previous region name when continuing later |

Examples:

```bash
VPN_REGION_LIMIT=10 ./app_testing.sh app=IDV full
VPN_HOLD_SECONDS=15 ./app_testing.sh app=IFU --quick-connect
VPN_START_INDEX=3 ./app_testing.sh app=IDV --soft-connect
```

## Reports and Logs

The console output is the primary report. Look for lines like:

```text
[1] catalog="(ordinal 1)" selected="US East" - PASS - IP="..." Location="..." held 10s, feedback closed, default identity restored
[settings] What is My Geo IP? succeeded
```

The full Xcode output is also saved here:

```text
xcodebuild-vpn-test.log
```

Xcode result bundles are printed at the end of each run, for example:

```text
/Users/sadrish/Library/Developer/Xcode/DerivedData/VPNTest-.../Logs/Test/Test-VPNTest-....xcresult
```

## Troubleshooting

### Test runner failed to initialize

If Xcode reports:

```text
Timed out while enabling automation mode
```

rerun the same command. This is usually a device/Xcode automation session issue before test logic starts.

### App opens a browser or service selector

Stop the current run and return the app to the home screen, then rerun the command.

To stop running tests:

```bash
pkill -f 'xcodebuild test -project VPNTest.xcodeproj'
pkill -f 'app_testing.sh'
```

### Verify no tests are still running

```bash
ps aux | rg -i 'xcodebuild|VPNTestUITests|app_testing'
```

Only the `rg` command itself should appear.

## Notes for Team Members

- Always run from the repo folder.
- Do not interact with the phone while the test is running.
- Keep the iPhone unlocked and on the target app if possible.
- `TEST SUCCEEDED` means the XCTest completed; still review per-region `PASS` or `FAIL` lines in the log.
- For feature testing, pass `boost on adblock on` explicitly.
- For normal baseline testing, omit feature arguments or pass `boost off adblock off`.
