#!/usr/bin/env bash
#
# installer.sh
# Basic setup checks for FreeVPN iOS UI testing.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "== FreeVPN iOS Test Setup =="
echo "Folder: ${SCRIPT_DIR}"
echo ""

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: This setup is for macOS only."
  exit 1
fi

require_cmd() {
  local cmd="$1"
  local help="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing: ${cmd}"
    echo "  ${help}"
    exit 1
  fi
}

require_cmd xcodebuild "Install Xcode from App Store, then open it once."
require_cmd xcrun "Install Xcode Command Line Tools: xcode-select --install"
require_cmd python3 "Install Python 3 (usually bundled on macOS)."

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode CLI path not configured."
  echo "Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  exit 1
fi

echo "Checking iOS SDK availability..."
if ! xcodebuild -showsdks | grep -q "iphoneos"; then
  echo "No iPhoneOS SDK detected in Xcode."
  echo "Open Xcode -> Settings -> Platforms/Components and install iOS platform."
  exit 1
fi

chmod +x "${SCRIPT_DIR}/run_tests.sh" \
         "${SCRIPT_DIR}/freevpn_region_test.sh" \
         "${SCRIPT_DIR}/freevpn_report_card.sh" \
         "${SCRIPT_DIR}/test_everything.sh" \
         "${SCRIPT_DIR}/verify_prompt_and_app_detection.sh"

echo ""
echo "Setup checks passed."
echo "Next:"
echo "  cd \"${SCRIPT_DIR}\""
echo "  ./run_tests.sh --list-devices"
echo "  VPNTEST_APP=ifu ./run_tests.sh --two-regions-hold5"
