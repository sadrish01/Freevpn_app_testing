#!/usr/bin/env bash
set -euo pipefail

DEVICE_ID="${DEVICE_ID:-00008130-001128E914D2001C}"
SCHEME="${SCHEME:-VPNTest}"
MODE="full"
APP="${APP:-IFU}"
BOOST="${BOOST:-off}"
ADBLOCK="${ADBLOCK:-off}"

usage() {
  echo "Usage: ./app_testing.sh [app=IFU|IDV] [boost on|off] [adblock on|off] [--quick-connect|--soft-connect|full|check-settings]"
}

normalize_toggle() {
  local value
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    on|true|1|yes|enable|enabled)
      echo "on"
      ;;
    off|false|0|no|disable|disabled)
      echo "off"
      ;;
    *)
      echo "Invalid toggle value '$1'. Use on or off." >&2
      exit 64
      ;;
  esac
}

expect_toggle_for=""
for arg in "$@"; do
  if [[ -n "$expect_toggle_for" ]]; then
    case "$expect_toggle_for" in
      boost)
        BOOST="$(normalize_toggle "$arg")"
        ;;
      adblock)
        ADBLOCK="$(normalize_toggle "$arg")"
        ;;
    esac
    expect_toggle_for=""
    continue
  fi

  case "$arg" in
    app=*|APP=*)
      APP="${arg#*=}"
      ;;
    --app=*)
      APP="${arg#*=}"
      ;;
    boost=*|BOOST=*)
      BOOST="$(normalize_toggle "${arg#*=}")"
      ;;
    adblock=*|ADBLOCK=*)
      ADBLOCK="$(normalize_toggle "${arg#*=}")"
      ;;
    boost|BOOST)
      expect_toggle_for="boost"
      ;;
    adblock|ADBLOCK)
      expect_toggle_for="adblock"
      ;;
    --quick-connect|-quick-connect|--soft-connect|-soft-connect|full|check-settings|--check-settings|-check-settings)
      [[ "$arg" == "-quick-connect" ]] && arg="--quick-connect"
      [[ "$arg" == "-soft-connect" ]] && arg="--soft-connect"
      [[ "$arg" == "-check-settings" || "$arg" == "--check-settings" ]] && arg="check-settings"
      MODE="$arg"
      ;;
    "")
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

if [[ -n "$expect_toggle_for" ]]; then
  echo "Missing on/off after '$expect_toggle_for'."
  usage
  exit 64
fi

APP="$(printf '%s' "$APP" | tr '[:lower:]' '[:upper:]')"
case "$APP" in
  IFU)
    VPN_APP_BUNDLE_ID="${VPN_APP_BUNDLE_ID:-org.freevpn.vpn.us}"
    ;;
  IDV)
    VPN_APP_BUNDLE_ID="${VPN_APP_BUNDLE_ID:-com.actmobile.dashvpn}"
    ;;
  *)
    usage
    echo "Unknown app '$APP'. Use IFU or IDV."
    exit 64
    ;;
esac

case "$MODE" in
  --quick-connect)
    VPN_REGION_LIMIT="${VPN_REGION_LIMIT:-2}"
    ;;
  --soft-connect)
    VPN_REGION_LIMIT="${VPN_REGION_LIMIT:-4}"
    ;;
  check-settings)
    VPN_REGION_LIMIT="${VPN_REGION_LIMIT:-0}"
    ;;
  full|"")
    VPN_REGION_LIMIT="${VPN_REGION_LIMIT:-250}"
    ;;
  *)
    usage
    exit 64
    ;;
esac

echo "Running $APP ($VPN_APP_BUNDLE_ID) with mode=$MODE, region_limit=$VPN_REGION_LIMIT, boost=$BOOST, adblock=$ADBLOCK"

export VPN_APP_BUNDLE_ID
export VPN_REGION_LIMIT
export VPN_HOLD_SECONDS="${VPN_HOLD_SECONDS:-10}"
export VPN_START_INDEX="${VPN_START_INDEX:-1}"
export VPN_ANCHOR_REGION="${VPN_ANCHOR_REGION:-}"
export VPN_BOOST="$BOOST"
export VPN_ADBLOCK="$ADBLOCK"
export VPN_TEST_MODE="$MODE"

SCHEME_FILE="VPNTest.xcodeproj/xcshareddata/xcschemes/VPNTest.xcscheme"
TEST_FILE="VPNTestUITests/VPNRegionPipelineTests.swift"
perl -0pi -e 's/(key = "VPN_APP_BUNDLE_ID"\s+value = ")[^"]+/$1$ENV{VPN_APP_BUNDLE_ID}/s;
              s/(key = "VPN_REGION_LIMIT"\s+value = ")[^"]+/$1$ENV{VPN_REGION_LIMIT}/s;
              s/(key = "VPN_HOLD_SECONDS"\s+value = ")[^"]+/$1$ENV{VPN_HOLD_SECONDS}/s;
              s/(key = "VPN_START_INDEX"\s+value = ")[^"]+/$1$ENV{VPN_START_INDEX}/s;
              s/(key = "VPN_ANCHOR_REGION"\s+value = ")[^"]*/$1$ENV{VPN_ANCHOR_REGION}/s;' "$SCHEME_FILE"
perl -0pi -e 's/static let vpnAppBundleID = "[^"]+"/static let vpnAppBundleID = "$ENV{VPN_APP_BUNDLE_ID}"/;
              s/static let regionLimit = [0-9]+/static let regionLimit = $ENV{VPN_REGION_LIMIT}/;
              s/static let holdSeconds = [0-9]+/static let holdSeconds = $ENV{VPN_HOLD_SECONDS}/;
              s/static let startIndex = [0-9]+/static let startIndex = $ENV{VPN_START_INDEX}/;
              s/static let anchorRegion = "[^"]*"/static let anchorRegion = "$ENV{VPN_ANCHOR_REGION}"/;
              s/static let boostMode = "[^"]*"/static let boostMode = "$ENV{VPN_BOOST}"/;
              s/static let adblockMode = "[^"]*"/static let adblockMode = "$ENV{VPN_ADBLOCK}"/;
              s/static let testMode = "[^"]*"/static let testMode = "$ENV{VPN_TEST_MODE}"/;' "$TEST_FILE"

xcodebuild test \
  -project VPNTest.xcodeproj \
  -scheme "$SCHEME" \
  -destination "id=$DEVICE_ID" \
  -allowProvisioningUpdates \
  2>&1 | tee xcodebuild-vpn-test.log
