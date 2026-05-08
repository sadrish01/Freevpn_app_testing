#!/usr/bin/env bash
# freevpn up → wait 5s → status; freevpn down → wait 5s → status; summary report card
set -e

echo "══════════════════════════════════════════════════════════"
echo "  FREEVPN CLI — REPORT CARD"
echo "══════════════════════════════════════════════════════════"
echo ""

echo "--- BEFORE (baseline) ---"
freevpn status
BASE_IP=$(freevpn status 2>/dev/null | awk -F': ' '/Your IP/{print $2}' | tr -d ' ')
BASE_VPN=$(freevpn status 2>/dev/null | awk -F': ' '/^VPN/{print $2}' | tr -d ' ')
echo ""

echo "--- CONNECT: freevpn up ---"
freevpn up
echo ""

echo "--- WAIT 5s after connect ---"
sleep 5
echo ""

echo "--- STATUS after 5s (connected check) ---"
freevpn status
POST_UP_IP=$(freevpn status 2>/dev/null | awk -F': ' '/Your IP/{print $2}' | tr -d ' ')
POST_UP_VPN=$(freevpn status 2>/dev/null | awk -F': ' '/^VPN/{print $2}' | tr -d ' ')
echo ""

echo "--- DISCONNECT: freevpn down ---"
freevpn down
echo ""

echo "--- WAIT 5s after disconnect ---"
sleep 5
echo ""

echo "--- STATUS after 5s (disconnected check) ---"
freevpn status
POST_DOWN_IP=$(freevpn status 2>/dev/null | awk -F': ' '/Your IP/{print $2}' | tr -d ' ')
POST_DOWN_VPN=$(freevpn status 2>/dev/null | awk -F': ' '/^VPN/{print $2}' | tr -d ' ')
echo ""

echo "══════════════════════════════════════════════════════════"
echo "  SUMMARY REPORT CARD"
echo "══════════════════════════════════════════════════════════"
echo "  Baseline IP:      ${BASE_IP:-n/a}"
echo "  Baseline VPN:     ${BASE_VPN:-n/a}"
echo "  ────────────────────────────────────────────────────────"
echo "  After up + 5s:    VPN=${POST_UP_VPN:-n/a}   IP=${POST_UP_IP:-n/a}"
if [[ "${POST_UP_VPN}" == "Connected" ]]; then
  echo "  Connect check:    PASS (VPN shows Connected after 5s)"
else
  echo "  Connect check:    FAIL (expected Connected)"
fi
if [[ -n "${BASE_IP}" && -n "${POST_UP_IP}" && "${BASE_IP}" != "${POST_UP_IP}" ]]; then
  echo "  IP vs baseline:   CHANGED (${BASE_IP} → ${POST_UP_IP})"
elif [[ "${POST_UP_VPN}" == "Connected" ]]; then
  echo "  IP vs baseline:   same or n/a (tunnel may reuse path)"
fi
echo "  ────────────────────────────────────────────────────────"
echo "  After down + 5s:  VPN=${POST_DOWN_VPN:-n/a}   IP=${POST_DOWN_IP:-n/a}"
if [[ "${POST_DOWN_VPN}" == "Disconnected" ]]; then
  echo "  Disconnect check: PASS (VPN shows Disconnected after 5s)"
else
  echo "  Disconnect check: FAIL (expected Disconnected)"
fi
echo "══════════════════════════════════════════════════════════"
