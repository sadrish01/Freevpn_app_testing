# -*- coding: utf-8 -*-
"""
DashVPN region connectivity test — SikuliX (Jython) UI automation.

Run from SikuliX IDE: open this .sikuli bundle and Run.
Requires: DashVPN installed, captured PNGs in this folder, baseline IP without VPN.

Python 2.7 (Jython) compatible: uses print_function.
"""
from __future__ import print_function

import json
import os
import shutil
import time

# SikuliX API (provided by runtime when executed inside SikuliX)
try:
    from sikuli import *
except ImportError:
    # Allows static analysis outside Sikuli; real runs must use SikuliX IDE / sikulixapi
    pass

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# macOS application name as shown in /Applications (without .app) or bundle id via App.open
APP_NAME = "DashVPN"
APP_OPEN_CMD = 'open -a "DashVPN"'  # fallback if App API fails

# Image matching defaults (override per Pattern in helpers)
DEFAULT_SIMILARITY = 0.72
CONNECTED_WAIT_SEC = 5.0
STABLE_CONNECTION_SEC = 15.0
DISCONNECT_WAIT_SEC = 12.0
CONNECT_RETRY_COUNT = 1  # number of extra attempts after first failure (total = 1 + this)

# Logging
LOG_DIR = "dash_vpn_test_logs"
FAILURE_SHOT_DIR = os.path.join(LOG_DIR, "failures")

# Region definitions: add one PNG per row in the UI (or unique list item crop).
# expected_country: ISO 3166-1 alpha-2 from ipinfo.io "country" field (e.g. "US", "DE")
# expected_region: optional substring match against ipinfo "region" (None = skip)
REGIONS = [
    {
        "id": "us",
        "label": "United States",
        "select_image": "region_item_us.png",
        "expected_country": "US",
        "expected_region": None,
    },
    {
        "id": "uk",
        "label": "United Kingdom",
        "select_image": "region_item_uk.png",
        "expected_country": "GB",
        "expected_region": None,
    },
    {
        "id": "demo_placeholder",
        "label": "Demo Region (replace PNG)",
        "select_image": "region_item_demo.png",
        "expected_country": "US",
        "expected_region": None,
    },
]

# Image asset filenames (all relative to this .sikuli folder)
IMG_CONNECT = "ui_connect.png"
IMG_DISCONNECT = "ui_disconnect.png"
IMG_REGION_DROPDOWN = "ui_region_dropdown.png"
IMG_CONNECTED_STATE = "ui_connected.png"  # button text change, badge, or status text
IMG_DISCONNECTED_STATE = "ui_disconnected.png"  # optional: post-disconnect UI

# ---------------------------------------------------------------------------
# Globals (test run)
# ---------------------------------------------------------------------------

_baseline_ip = None
_results = []


def _pattern(img_name, similarity=None):
    sim = DEFAULT_SIMILARITY if similarity is None else similarity
    return Pattern(img_name).similar(sim)


def _ensure_dirs():
    if not os.path.exists(LOG_DIR):
        os.makedirs(LOG_DIR)
    if not os.path.exists(FAILURE_SHOT_DIR):
        os.makedirs(FAILURE_SHOT_DIR)


def _log(msg):
    line = "[%s] %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg)
    print(line)
    _ensure_dirs()
    with open(os.path.join(LOG_DIR, "run.log"), "a") as f:
        f.write(line + "\n")


def save_failure_screenshot(tag):
    """Save full screen capture on failure paths."""
    _ensure_dirs()
    try:
        fn = capture(Screen())
        if fn and os.path.exists(fn):
            dest = os.path.join(
                FAILURE_SHOT_DIR,
                "fail_%s_%s.png" % (tag, int(time.time())),
            )
            shutil.copy(fn, dest)
            _log("Saved failure screenshot: %s" % dest)
        else:
            _log("capture() did not return a valid temp file; skipping file copy")
    except Exception as e:
        _log("save_failure_screenshot error: %s" % e)


def get_ip_info():
    """
    Return dict with keys: ip, country, region, org, raw (full JSON string).
    Uses curl via os.popen for Jython compatibility.
    """
    raw = ""
    try:
        stream = os.popen("curl -s --max-time 10 ipinfo.io/json")
        raw = stream.read()
        stream.close()
    except Exception as e:
        return {"error": str(e), "ip": None, "country": None, "region": None, "raw": raw}

    if not raw or not raw.strip():
        return {"error": "empty response", "ip": None, "country": None, "region": None, "raw": raw}

    try:
        data = json.loads(raw)
    except Exception as e:
        return {"error": "json parse: %s" % e, "ip": None, "country": None, "region": None, "raw": raw}

    return {
        "error": None,
        "ip": data.get("ip"),
        "country": data.get("country"),
        "region": data.get("region"),
        "org": data.get("org"),
        "raw": raw,
    }


def launch_app():
    """
    Focus DashVPN if running; otherwise open it and wait for primary UI.
    """
    Settings.MinSimilarity = DEFAULT_SIMILARITY
    app = App(APP_NAME)
    try:
        if app.isRunning():
            _log("App already running; focusing")
            app.focus()
        else:
            _log("App not running; opening")
            try:
                app.open()
            except Exception:
                _log("App.open() failed; trying shell open")
                os.system(APP_OPEN_CMD)
            wait(2)
            app = App(APP_NAME)
            app.focus()
    except Exception as e:
        _log("launch_app App() error: %s; fallback open" % e)
        os.system(APP_OPEN_CMD)
        wait(3)

    # Wait for either connect or disconnect control to appear (app UI ready)
    c = exists(_pattern(IMG_CONNECT), 20) or exists(_pattern(IMG_DISCONNECT), 5)
    if not c:
        _log("WARNING: Neither connect nor disconnect button found after launch")
    else:
        _log("Launch complete; primary controls visible")


def disconnect():
    """Click disconnect and wait for disconnected / connect-ready UI."""
    if exists(_pattern(IMG_DISCONNECT), 3):
        click(_pattern(IMG_DISCONNECT))
        _log("Clicked disconnect")
    else:
        _log("disconnect(): disconnect control not visible (may already be disconnected)")

    # Prefer explicit disconnected marker; else wait for connect to reappear
    ok = False
    if os.path.exists(IMG_DISCONNECTED_STATE):
        try:
            wait(_pattern(IMG_DISCONNECTED_STATE), DISCONNECT_WAIT_SEC)
            ok = True
        except FindFailed:
            ok = False
    if not ok:
        try:
            wait(_pattern(IMG_CONNECT), DISCONNECT_WAIT_SEC)
            ok = True
        except FindFailed:
            ok = False
    if not ok:
        _log("disconnect(): timeout waiting for disconnected UI")
    else:
        _log("Disconnected state observed")
    wait(2)


def _open_region_list():
    if exists(_pattern(IMG_REGION_DROPDOWN), 8):
        click(_pattern(IMG_REGION_DROPDOWN))
        wait(1)
        return True
    _log("Region dropdown/list control not found")
    return False


def _select_region_item(region_cfg):
    img = region_cfg["select_image"]
    if not os.path.exists(img):
        raise RuntimeError("Missing region image: %s" % img)
    r = find(_pattern(img))
    click(r)
    wait(0.8)
    return True


def _wait_connected():
    """Wait up to CONNECTED_WAIT_SEC for connected UI."""
    try:
        wait(_pattern(IMG_CONNECTED_STATE), float(CONNECTED_WAIT_SEC))
        return True
    except FindFailed:
        return False


def connect_region(region_cfg):
    """
    Select region, connect, wait for connected UI. Returns (success, message).
    Implements one connect retry before returning failure.
    """
    label = region_cfg.get("label", region_cfg.get("id", "unknown"))

    max_attempts = 1 + int(CONNECT_RETRY_COUNT)
    for attempt in range(max_attempts):
        try:
            if not _open_region_list():
                if attempt < max_attempts - 1:
                    _log("region list open failed; retrying (%s/%s)" % (attempt + 1, max_attempts))
                    wait(2)
                    continue
                return False, "region list open failed"
            _select_region_item(region_cfg)
            wait(0.5)
            if not exists(_pattern(IMG_CONNECT), 8):
                if attempt < max_attempts - 1:
                    _log("connect button missing; retrying (%s/%s)" % (attempt + 1, max_attempts))
                    disconnect()
                    wait(2)
                    continue
                return False, "connect button not found after region select"
            click(_pattern(IMG_CONNECT))
            _log("Connect clicked for %s (attempt %s/%s)" % (label, attempt + 1, max_attempts))
            if _wait_connected():
                return True, "connected"
            if attempt < max_attempts - 1:
                _log("Connect timeout; retrying after disconnect")
                disconnect()
                wait(2)
                continue
            return False, "connect timeout (no connected UI within %ss)" % int(CONNECTED_WAIT_SEC)
        except FindFailed as e:
            if attempt < max_attempts - 1:
                _log("FindFailed on attempt %s/%s: %s; retrying" % (attempt + 1, max_attempts, e))
                disconnect()
                wait(2)
                continue
            return False, "FindFailed: %s" % e
        except Exception as e:
            return False, "error: %s" % e

    return False, "connect failed after retries"


def verify_connection(region_cfg):
    """
    After connected UI: wait stable window, curl ipinfo, compare country/region.
    Returns (passed, message, ipinfo_dict).
    """
    wait(float(STABLE_CONNECTION_SEC))
    info = get_ip_info()
    if info.get("error"):
        return False, "ipinfo failed: %s" % info.get("error"), info

    exp_c = region_cfg.get("expected_country")
    if exp_c and (info.get("country") or "").upper() != exp_c.upper():
        return (
            False,
            "country mismatch: expected %s got %s" % (exp_c, info.get("country")),
            info,
        )

    exp_r = region_cfg.get("expected_region")
    if exp_r:
        actual = (info.get("region") or "") + " " + (info.get("country") or "")
        if exp_r.lower() not in actual.lower():
            return False, "region mismatch: expected substring %r in %r" % (exp_r, actual.strip()), info

    return True, "ip/country ok", info


def verify_baseline_ip():
    """After disconnect: IP should match baseline captured before tests."""
    global _baseline_ip
    info = get_ip_info()
    if info.get("error"):
        return False, "baseline check ipinfo error: %s" % info.get("error"), info
    cur = info.get("ip")
    if _baseline_ip and cur and cur != _baseline_ip:
        return False, "IP did not revert to baseline (was %s now %s)" % (_baseline_ip, cur), info
    return True, "baseline ok", info


def generate_report():
    """Print and log summary for current _results list."""
    total = len(_results)
    passed = sum(1 for r in _results if r["status"] == "PASS")
    failed = total - passed

    print("")
    print("========== DashVPN Region Test Summary ==========")
    print("Total regions tested: %s" % total)
    print("Passed: %s" % passed)
    print("Failed: %s" % failed)
    print("--------------------------------------------------")

    for r in _results:
        print("[%s] %s — %s" % (r["status"], r.get("label", r.get("id")), r.get("reason", "")))
        if r.get("detail"):
            print("    detail: %s" % r["detail"])

    print("==================================================")

    _ensure_dirs()
    rep_path = os.path.join(LOG_DIR, "summary_%s.txt" % int(time.time()))
    with open(rep_path, "w") as out:
        out.write("Total: %s  Passed: %s  Failed: %s\n\n" % (total, passed, failed))
        for r in _results:
            out.write(
                "[%s] %s — %s\n"
                % (r["status"], r.get("label", r.get("id")), r.get("reason", ""))
            )
            if r.get("detail"):
                out.write("  detail: %s\n" % r["detail"])
    _log("Wrote report: %s" % rep_path)


def run_all_regions():
    """Full flow: baseline, per-region connect/verify/disconnect, final summary."""
    global _baseline_ip, _results
    _results = []
    _ensure_dirs()

    launch_app()
    disconnect()  # ensure clean state before baseline
    wait(2)

    bi = get_ip_info()
    if bi.get("error") or not bi.get("ip"):
        _log("FATAL: cannot read baseline IP: %s" % bi)
        print("FATAL: set VPN OFF and ensure network; curl ipinfo.io/json must work.")
        return
    _baseline_ip = bi.get("ip")
    _log("Baseline IP (no VPN): %s (%s)" % (_baseline_ip, bi.get("country")))

    for region_cfg in REGIONS:
        rid = region_cfg.get("id", "?")
        label = region_cfg.get("label", rid)
        entry = {"id": rid, "label": label, "status": "FAIL", "reason": "", "detail": ""}

        launch_app()
        ok, msg = connect_region(region_cfg)
        if not ok:
            entry["reason"] = msg
            save_failure_screenshot("connect_%s" % rid)
            _results.append(entry)
            _log("FAIL %s: %s" % (label, msg))
            disconnect()
            continue

        ok2, msg2, info = verify_connection(region_cfg)
        if not ok2:
            entry["reason"] = msg2
            entry["detail"] = info.get("raw", "")[:500]
            save_failure_screenshot("verify_%s" % rid)
            _results.append(entry)
            _log("FAIL %s: %s" % (label, msg2))
            disconnect()
            continue

        disconnect()
        ok3, msg3, _ = verify_baseline_ip()
        if not ok3:
            entry["reason"] = "post-test baseline: %s" % msg3
            save_failure_screenshot("baseline_%s" % rid)
            _results.append(entry)
            _log("FAIL %s: %s" % (label, entry["reason"]))
            continue

        entry["status"] = "PASS"
        entry["reason"] = "all checks ok; ip %s" % (info.get("ip"),)
        _results.append(entry)
        _log("PASS %s" % label)

    generate_report()


# Entry point when executed in SikuliX
if __name__ == "__main__":
    run_all_regions()
