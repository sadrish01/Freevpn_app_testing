# FreeVPN iOS Testing Guide

This folder contains the iOS UI testing project and helper scripts.

## Folder Contents

- `VPNTest/` - Xcode project and XCTest UI test target.
- `run_tests.sh` - Main runner for device-based UI tests.
- `freevpn_region_test.sh` - Region flow helper script.
- `freevpn_report_card.sh` - Generates a quick report summary from test output.
- `test_everything.sh` - Convenience script for broader checks.
- `verify_prompt_and_app_detection.sh` - Checks prompt + app/device detection behavior.
- `freevpn_full_region_no_alt.log` / `freevpn_full_region_retest.log` - Previous run logs.

## One-time Setup

From this folder:

```bash
chmod +x installer.sh
./installer.sh
```

What `installer.sh` does:

- Verifies macOS environment.
- Verifies required tools (`xcodebuild`, `xcrun`, `python3`).
- Verifies iPhoneOS SDK availability in Xcode.
- Ensures all test scripts are executable.

## Common Commands

Run from `Freevpn_testing/`:

```bash
# Show connected physical iPhone device IDs
./run_tests.sh --list-devices

# Check device detection only (no test execution)
./run_tests.sh --check

# Main IFU two-region flow
VPNTEST_APP=ifu ./run_tests.sh --two-regions-hold5

# Three-region report flow
VPNTEST_APP=ifu ./run_tests.sh --three-regions

# Smoke test
./run_tests.sh --smoke
```

## Notes

- Tests are intended for a **real iPhone connected via USB**.
- Open Xcode once after updates and accept license prompts if asked.
- If a run fails, inspect the `.xcresult` path printed at the end of `run_tests.sh`.
