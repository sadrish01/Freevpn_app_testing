//
//  VPNFirstRegionTimingTests.swift
//  VPNTestUITests
//
//  Open region list → first region → Connect → measure time until connected UI appears.
//  Disconnect → measure time until connected UI is gone.
//  Default threshold: 1s each (VPN often slower — set VPNTEST_CONNECT_UI_THRESHOLD_SEC / VPNTEST_DISCONNECT_UI_THRESHOLD_SEC).
//

import XCTest

final class VPNFirstRegionTimingTests: VPNTestBase {

    /// Open list → first region → **print every button** (IFU exposes `vpn toggle off` etc.). No connect timing assert.
    func testPrintAllButtonsAfterFirstRegionSelected() throws {
        let app = ensureVPNAppReady()
        XCTAssertEqual(app.state, .runningForeground)

        dismissPaywallIfNeeded(app)
        prepareDisconnectedState(app)

        XCTAssertTrue(
            openRegionList(app, timeout: VPNTestConstants.waitForRegionListAfterLaunch + 10),
            "Could not open region list."
        )
        sleep(1)

        XCTAssertTrue(selectFirstRegionInList(app, timeout: 25), "Could not select first region.")
        sleep(2)

        // Same readiness as main pipeline: linear `app.buttons` snapshot (prints every visible row when ready).
        XCTAssertTrue(
            waitForMainConnectScreenFromButtonSnapshot(app, timeout: 25),
            "Main VPN screen not ready after region select (button snapshot)."
        )

        logTraceStep("After first region — main screen (detailed trace below snapshot)", app)

        XCTAssertGreaterThan(app.buttons.count, 0, "Expected at least one button on main screen after region select.")
    }

    /// Row **0** → main screen (already logged in `selectRegionListRowByIndex`) → **always** connect via **`tapConnectFromVisibleButtonSnapshot`** (e.g. IFU index 3 `vpn toggle off`, not the IFU “skip connect on row 0” path) → wait connected → **5s** → **`tapDisconnectFromVisibleButtonSnapshot`** → log **Alert / Sheet** + full button dump, then `logPostDisconnectPopupYesNoAndDismissIfPresent`, then idle assert.
    func testFirstRegion_SnapshotConnect_Hold5s_Disconnect_ThenInspectButtonsAndPopup() throws {
        let app = ensureVPNAppReady()
        XCTAssertEqual(app.state, .runningForeground)
        dismissPaywallIfNeeded(app)
        prepareDisconnectedState(app)

        XCTAssertTrue(openRegionList(app, timeout: 28), "Region list did not open.")
        sleep(1)
        guard let host = resolveRegionListContainer(app) else {
            XCTFail("No region list host after openRegionList.")
            return
        }
        scrollRegionListToTop(host: host, maxSwipeDown: 8)
        usleep(300_000)
        let cell0 = host.cells.element(boundBy: 0)
        XCTAssertTrue(cell0.waitForExistence(timeout: 8), "List cell at index 0 missing.")
        print("[VPNTest] snapshot-cycle: cell[0]=\"\(regionRowDisplayLabel(cell0))\"")

        let (selOk, label) = selectRegionListRowByIndex(app, rowIndex: 0, listTimeout: 28, skipOpenRegionList: true, assumeListAlreadyAtTop: true)
        XCTAssertTrue(selOk, "select row 0 failed (label=\"\(label)\").")

        print("[VPNTest] snapshot-cycle: connect — single tap from **`tapConnectFromVisibleButtonSnapshot`** (prefers `vpn toggle`+`off`, then `vpn toggle`, then Connect-like label)")
        XCTAssertTrue(tapConnectFromVisibleButtonSnapshot(app), "Snapshot connect failed (no suitable `app.buttons` row).")

        let connectWait: TimeInterval = VPNTestConstants.isIFUTarget ? 65 : 45
        XCTAssertTrue(waitForVPNConnectedUI(app, timeout: connectWait), "Connected UI did not appear within \(connectWait)s.")
        print("[VPNTest] snapshot-cycle: connected — sustaining **5s**")

        sleep(5)
        print("[VPNTest] ═══ snapshot-cycle: buttons while still connected (end of 5s hold) ═══")
        logConnectScreenDiagnostics(app)
        logAllButtonsDetailed(app, maxButtons: 80)
        print("[VPNTest] ═══ snapshot-cycle: disconnect — `tapDisconnectFromVisibleButtonSnapshot` ═══")
        XCTAssertTrue(tapDisconnectFromVisibleButtonSnapshot(app), "Snapshot disconnect failed.")
        _ = measureSecondsUntil(timeout: 25, pollUs: 15_000, predicate: { self.isVPNDisconnectedOrDialogPresent(app) })

        print("[VPNTest] ═══ POST-DISCONNECT: popups + buttons (before dismiss helper) ═══")
        let alertVis = app.alerts.firstMatch.waitForExistence(timeout: 2)
        let sheetVis = app.sheets.firstMatch.waitForExistence(timeout: 1)
        print("[VPNTest] POST-DISCONNECT: system Alert visible = \(alertVis)")
        print("[VPNTest] POST-DISCONNECT: Sheet visible = \(sheetVis)")
        if alertVis {
            let al = app.alerts.firstMatch
            let titles = al.staticTexts.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
            print("[VPNTest] POST-DISCONNECT: alert staticTexts (non-empty) = \(titles)")
        }
        if sheetVis {
            let sh = app.sheets.firstMatch
            let texts = sh.staticTexts.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
            print("[VPNTest] POST-DISCONNECT: sheet staticTexts (non-empty) = \(texts.prefix(12))")
        }
        print("[VPNTest] POST-DISCONNECT: isVPNConnectedUI = \(isVPNConnectedUI(app))")
        logAccessibilitySummary(app)
        logConnectScreenDiagnostics(app)
        logAllButtonsDetailed(app, maxButtons: 64)
        print("[VPNTest] ═══ END post-disconnect pre-dismiss dump ═══")

        let hadOverlay = logPostDisconnectPopupYesNoAndDismissIfPresent(app, pollForOverlaySeconds: 16)
        print("[VPNTest] POST-DISMISS: logPostDisconnectPopupYesNoAndDismissIfPresent returned hadOverlay=\(hadOverlay)")

        print("[VPNTest] ═══ POST-DISMISS: buttons again ═══")
        logConnectScreenDiagnostics(app)
        logAllButtonsDetailed(app, maxButtons: 48)

        XCTAssertTrue(
            waitForIdleConnectVPNVisible(app, timeout: 28),
            "After disconnect + popup handling, idle Connect VPN / vpn-toggle-off should be visible."
        )
        print("[VPNTest] snapshot-cycle: PASSED (connect 5s disconnect + inspect + idle)")
    }

    /// First region → connect → disconnect, with **full button trace** after each step (trim later once stable).
    func testFirstRegionConnect_VerboseTrace() throws {
        let app = ensureVPNAppReady()
        XCTAssertEqual(app.state, .runningForeground)
        logTraceStep("1. App ready (foreground)", app)

        dismissPaywallIfNeeded(app)
        sleep(1)
        logTraceStep("2. After dismissPaywallIfNeeded", app)

        prepareDisconnectedState(app)
        logTraceStep("3. After prepareDisconnectedState", app)

        XCTAssertTrue(
            openRegionList(app, timeout: VPNTestConstants.waitForRegionListAfterLaunch + 10),
            "Could not open region list."
        )
        sleep(1)
        logTraceStep("4. After openRegionList", app)

        XCTAssertTrue(selectFirstRegionInList(app, timeout: 25), "Could not select first region.")
        sleep(1)
        XCTAssertTrue(waitForMainConnectScreen(app, timeout: 25), "Main VPN screen not ready.")
        logTraceStep("5. After selectFirstRegion + main screen (before Connect tap)", app)

        XCTAssertTrue(tapVPNToggle(app, forDisconnect: false, timeout: 15), "Connect / vpn toggle tap failed.")
        usleep(300_000)
        logTraceStep("6. Immediately after Connect tap (vpn toggle off)", app)

        XCTAssertTrue(
            waitForVPNConnectedUI(app, timeout: VPNTestConstants.transitionMeasureHardTimeout),
            "Connected UI did not appear within \(VPNTestConstants.transitionMeasureHardTimeout)s."
        )
        sleep(1)
        logTraceStep("7. After connected UI detected", app)

        let disconnectTapped = tapVPNDisconnectBestEffort(app, timeout: 22)
        if !disconnectTapped {
            logTraceStep("8b. Disconnect strategies failed — screen state", app)
        }
        XCTAssertTrue(disconnectTapped, "Disconnect tap failed (see 8b trace if printed).")
        usleep(300_000)
        logTraceStep("8. Immediately after Disconnect tap", app)

        XCTAssertNotNil(
            measureSecondsUntil(timeout: VPNTestConstants.transitionMeasureHardTimeout, pollUs: 10_000, predicate: { !self.isVPNConnectedUI(app) }),
            "Disconnected UI did not appear within \(VPNTestConstants.transitionMeasureHardTimeout)s."
        )
        sleep(1)
        logTraceStep("9. After disconnected UI confirmed", app)

        print("[VPNTest] testFirstRegionConnect_VerboseTrace — PASSED (connect + disconnect).")
    }

    func testFirstRegion_OpenConnectDisconnect_MonitorTransitionThresholds() throws {
        let app = ensureVPNAppReady()
        XCTAssertEqual(app.state, .runningForeground)

        dismissPaywallIfNeeded(app)
        prepareDisconnectedState(app)

        XCTAssertTrue(
            openRegionList(app, timeout: VPNTestConstants.waitForRegionListAfterLaunch + 10),
            "Could not open region list."
        )
        sleep(1)

        XCTAssertTrue(selectFirstRegionInList(app, timeout: 25), "Could not select first region.")
        sleep(1)
        XCTAssertTrue(waitForMainConnectScreen(app, timeout: 20), "Main screen with connect control not ready.")

        XCTAssertTrue(tapVPNToggle(app, forDisconnect: false, timeout: 15), "Connect tap failed.")

        guard let connectSec = measureSecondsUntil(
            timeout: VPNTestConstants.transitionMeasureHardTimeout,
            pollUs: 5_000,
            predicate: { self.isVPNConnectedUI(app) }
        ) else {
            logAllButtonsDetailed(app, maxButtons: 120)
            logConnectScreenDiagnostics(app)
            XCTFail("Connected UI never appeared within \(VPNTestConstants.transitionMeasureHardTimeout)s.")
            return
        }

        let connectThreshold = VPNTestConstants.uiThresholdConnectTransitionSeconds
        let connectOk = connectSec <= connectThreshold
        print("[VPNTest] CONNECT UI: \(String(format: "%.3f", connectSec))s — within \(connectThreshold)s: \(connectOk ? "YES" : "NO")")
        XCTAssertTrue(
            connectOk,
            "Connected UI took \(String(format: "%.3f", connectSec))s (threshold \(connectThreshold)s). Set VPNTEST_CONNECT_UI_THRESHOLD_SEC if VPN UI is slower."
        )

        XCTAssertTrue(tapVPNDisconnectBestEffort(app, timeout: 18), "Disconnect tap failed.")

        guard let discSec = measureSecondsUntil(
            timeout: VPNTestConstants.transitionMeasureHardTimeout,
            pollUs: 5_000,
            predicate: { !self.isVPNConnectedUI(app) }
        ) else {
            XCTFail("Disconnected UI never appeared within \(VPNTestConstants.transitionMeasureHardTimeout)s.")
            return
        }

        let discThreshold = VPNTestConstants.uiThresholdDisconnectTransitionSeconds
        let discOk = discSec <= discThreshold
        print("[VPNTest] DISCONNECT UI: \(String(format: "%.3f", discSec))s — within \(discThreshold)s: \(discOk ? "YES" : "NO")")
        XCTAssertTrue(
            discOk,
            "Disconnect UI took \(String(format: "%.3f", discSec))s (threshold \(discThreshold)s). Set VPNTEST_DISCONNECT_UI_THRESHOLD_SEC if needed."
        )
    }
}
