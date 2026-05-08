//
//  VPNTestUITests.swift
//  VPNTestUITests
//
//  Smoke test (run after "Launch App" prompt): verifies app is running and test pipeline works.
//

import XCTest

final class VPNTestUITests: VPNTestBase {

    /// Smoke test: run after user has opened the app on the device and pressed Enter.
    /// Detects that the app is launched (in foreground). If you opened the app before pressing Enter, it will detect it.
    /// Use with: ./run_tests.sh --smoke
    func testSmoke_AppLaunchesAndReady() throws {
        let app = ensureVPNAppReady()
        XCTAssertTrue(app.exists, "VPN app should exist (install from TestFlight and open it before pressing Enter)")
        XCTAssertTrue(
            app.state == .runningForeground,
            "App launch not detected — open the VPN app on the device before pressing Enter, then run again"
        )
    }

    /// VPN test: open region list → select region at index 1 (skip "Connect to Fastest") → Connect VPN → 1 min → disconnect.
    /// Use with: ./run_tests.sh --vpn-test
    func testVPNTest_SelectFastestConnectDisconnect1Min() throws {
        let app = ensureVPNAppReady()
        XCTAssertTrue(app.state == .runningForeground, "VPN app should be in foreground")

        dismissPaywallIfNeeded(app)
        sleep(2)

        // 1. Open region list (tap region selector)
        XCTAssertTrue(openRegionList(app, timeout: VPNTestConstants.waitForRegionListAfterLaunch),
                     "Region list did not open.")
        sleep(2)

        // 2. Select first region from the list
        XCTAssertTrue(selectFirstRegionInList(app, timeout: 8),
                     "Could not select first region from list.")
        sleep(3)

        // 3. Wait for Connect VPN button and tap (Connect VPN only, not "Connect to Fastest")
        _ = app.buttons[VPNTestConstants.AccessibilityIds.connectButton].firstMatch.waitForExistence(timeout: 15)
        _ = app.staticTexts["Connect VPN"].firstMatch.waitForExistence(timeout: 5)
        sleep(1)
        guard tapVPNToggle(app, forDisconnect: false, timeout: 10) else {
            XCTFail("Connect VPN button not found.")
            return
        }
        sleep(3)

        // 4. Stay connected 1 minute (UI is green "Connected" by now)
        sleep(60)

        // 5. Snapshot: find green "Connected" area and tap switch beside it to disconnect
        _ = tapDisconnectSwitchWhenConnectedVisible(app, timeout: 10)
    }

    /// Quick connection: open region list → select first region → connect → wait 15s → disconnect.
    /// Use with: ./run_tests.sh --quick-connect
    func testQuickConnection_ConnectShortWaitDisconnect() throws {
        let testStart = Date()
        var connectTimeSeconds: TimeInterval?
        var connectTappedAt: Date?
        var sessionDurationSeconds: TimeInterval?
        defer {
            let total = Date().timeIntervalSince(testStart)
            print("[VPNTest] ─── Summary ───")
            if let t = connectTimeSeconds { print("[VPNTest]   Connect button found and tapped in \(String(format: "%.1f", t))s") }
            else { print("[VPNTest]   Connect: not reached or failed") }
            if let d = sessionDurationSeconds { print("[VPNTest]   VPN session connected for \(String(format: "%.1f", d))s") }
            else { print("[VPNTest]   VPN session duration: n/a") }
            print("[VPNTest]   Total test time: \(String(format: "%.1f", total))s")
            print("[VPNTest] ───────────────")
        }

        let app = ensureVPNAppReady()
        XCTAssertTrue(app.state == .runningForeground, "VPN app should be in foreground")

        // 1. Dismiss paywall; let UI settle (real device is slower)
        print("[VPNTest] Step 1: Dismissing paywall (if any)...")
        dismissPaywallIfNeeded(app)
        sleep(3)

        // 2. Open region list (tap region selector so the list appears)
        print("[VPNTest] Step 2: Opening region list...")
        XCTAssertTrue(openRegionList(app, timeout: VPNTestConstants.waitForRegionListAfterLaunch),
                     "Region list did not open. Ensure the region selector (e.g. Fastest, US East) is visible and tappable.")
        sleep(2)

        // 3. Select the first region from the list
        print("[VPNTest] Step 3: Selecting first region from list...")
        XCTAssertTrue(selectFirstRegionInList(app, timeout: 8),
                     "Could not select first region. Ensure the region list table is visible and has at least one row.")
        sleep(3)

        // 4. Wait for main VPN screen (list dismisses, Connect VPN control appears)
        print("[VPNTest] Step 4: Waiting for main screen (Connect VPN / Status)...")
        let connectId = VPNTestConstants.AccessibilityIds.connectButton
        let waitMainDeadline = Date().addingTimeInterval(30)
        var mainScreenVisible = false
        while Date() < waitMainDeadline {
            if app.buttons[connectId].firstMatch.exists, app.buttons[connectId].firstMatch.isHittable { mainScreenVisible = true; break }
            if app.staticTexts["Connect VPN"].firstMatch.exists, app.staticTexts["Connect VPN"].firstMatch.isHittable { mainScreenVisible = true; break }
            if app.buttons["Connect VPN"].firstMatch.exists, app.buttons["Connect VPN"].firstMatch.isHittable { mainScreenVisible = true; break }
            if app.switches.count > 0, app.switches.firstMatch.exists { mainScreenVisible = true; break }
            if app.staticTexts["Status"].firstMatch.exists { mainScreenVisible = true; break }
            usleep(500_000)
        }
        if !mainScreenVisible {
            print("[VPNTest] Main screen did not appear within 30s. Dumping what the test sees:")
            logConnectScreenDiagnostics(app)
        }
        sleep(3)

        // Optional: pause so you can look at the iPhone screen (set VPNTEST_PAUSE_BEFORE_CONNECT=1)
        if ProcessInfo.processInfo.environment["VPNTEST_PAUSE_BEFORE_CONNECT"] == "1" {
            print("[VPNTest] Pausing 15s (VPNTEST_PAUSE_BEFORE_CONNECT=1). Look at the app on the device.")
            sleep(15)
        }

        // 5. Connect — tap Connect VPN (button preferred, then switch)
        print("[VPNTest] Step 5: Looking for Connect VPN and tapping...")
        logConnectScreenDiagnostics(app)
        let connectSearchStart = Date()
        var connectTapped = tapVPNToggle(app, forDisconnect: false, timeout: 12)
        if connectTapped {
            connectTimeSeconds = Date().timeIntervalSince(connectSearchStart)
        }
        if !connectTapped {
            let byId = app.buttons[connectId].firstMatch
            if byId.waitForExistence(timeout: 5) {
                if byId.isHittable { byId.tap() } else { byId.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
                connectTapped = true
                connectTimeSeconds = Date().timeIntervalSince(connectSearchStart)
            }
        }
        if !connectTapped {
            let connectLabel = "Connect VPN"
            let btn = app.buttons[connectLabel].firstMatch
            if btn.waitForExistence(timeout: 3) {
                if btn.isHittable { btn.tap() } else { btn.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
                connectTapped = true
                connectTimeSeconds = Date().timeIntervalSince(connectSearchStart)
            }
        }
        if !connectTapped {
            let st = app.staticTexts["Connect VPN"].firstMatch
            if st.waitForExistence(timeout: 3) {
                if st.isHittable { st.tap() } else { st.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
                connectTapped = true
                connectTimeSeconds = Date().timeIntervalSince(connectSearchStart)
            }
        }
        if !connectTapped, app.switches.count > 0, app.switches.firstMatch.waitForExistence(timeout: 2) {
            let sw = app.switches.firstMatch
            if sw.isHittable { sw.tap() } else { sw.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
            connectTapped = true
            connectTimeSeconds = Date().timeIntervalSince(connectSearchStart)
        }
        if !connectTapped, (app.buttons["Connected"].firstMatch.waitForExistence(timeout: 2) || app.staticTexts["Connected"].firstMatch.waitForExistence(timeout: 2)) {
            connectTapped = true
            print("[VPNTest] Already connected.")
        }
        guard connectTapped else {
            print("[VPNTest] Connect failed. Diagnostics (what the test sees on screen):")
            logConnectScreenDiagnostics(app)
            logAccessibilitySummary(app)
            XCTFail("Connect VPN not found or not tappable. Check the diagnostics above: buttons/switches and their id/label/hittable. Identifier to set in app: '\(connectId)'.")
            return
        }
        connectTappedAt = Date()
        if connectTimeSeconds == nil { connectTimeSeconds = Date().timeIntervalSince(connectSearchStart) }

        // 6. Wait 2–3s for VPN to connect and UI to change (grey → green "Connected"), then wait for green state
        print("[VPNTest] Step 6: Waiting 3s for connection and UI to turn green...")
        sleep(3)
        let connectedDeadline = Date().addingTimeInterval(15)
        while Date() < connectedDeadline {
            if app.staticTexts["Connected"].firstMatch.exists { break }
            if app.buttons["Connected"].firstMatch.exists { break }
            usleep(400_000)
        }
        print("[VPNTest] Waiting 10s while connected...")
        sleep(10)

        // 7. Snapshot after Connect: find the green "Connected" area and tap the switch beside it to disconnect
        print("[VPNTest] Step 7: Snapshot — finding Connected area, tapping green switch to disconnect...")
        let disconnectTapped = tapDisconnectSwitchWhenConnectedVisible(app, timeout: 10)
        if disconnectTapped, let connectedAt = connectTappedAt {
            sessionDurationSeconds = Date().timeIntervalSince(connectedAt)
            print("[VPNTest] Disconnected.")
        }
        XCTAssertTrue(disconnectTapped, "Disconnect: when 'Connected' is visible, tap the switch beside it.")

        // Summary — print explicitly so it always appears in test output
        let total = Date().timeIntervalSince(testStart)
        print("")
        print("[VPNTest] ========== Summary ==========")
        if let t = connectTimeSeconds { print("[VPNTest]   Connect: found and tapped in \(String(format: "%.1f", t))s") }
        else { print("[VPNTest]   Connect: not reached or failed") }
        if let d = sessionDurationSeconds { print("[VPNTest]   VPN session connected: \(String(format: "%.1f", d))s") }
        else { print("[VPNTest]   VPN session duration: n/a") }
        print("[VPNTest]   Total test time: \(String(format: "%.1f", total))s")
        print("[VPNTest]   Disconnect: \(disconnectTapped ? "tapped" : "not found")")
        print("[VPNTest] ==============================")
        print("")
    }

    /// Soft run: open app → first region in list → Connect → stay connected 5s → Disconnect.
    /// Use with: ./run_tests.sh --soft-run
    func testSoftRun_FirstRegionConnect5sDisconnect() throws {
        let app = ensureVPNAppReady()
        XCTAssertTrue(app.state == .runningForeground, "VPN app should be in foreground")

        print("[VPNTest] Soft run: paywall dismiss → region list → first region → connect → 5s → disconnect")

        dismissPaywallIfNeeded(app)
        sleep(2)

        XCTAssertTrue(
            openRegionList(app, timeout: VPNTestConstants.waitForRegionListAfterLaunch),
            "Region list did not open."
        )
        sleep(2)

        XCTAssertTrue(
            selectFirstRegionInList(app, timeout: 10),
            "Could not select first region from list."
        )
        sleep(3)

        let connectId = VPNTestConstants.AccessibilityIds.connectButton
        _ = app.buttons[connectId].firstMatch.waitForExistence(timeout: 15)
        _ = app.staticTexts["Connect VPN"].firstMatch.waitForExistence(timeout: 5)
        sleep(1)

        guard tapVPNToggle(app, forDisconnect: false, timeout: 12) else {
            logConnectScreenDiagnostics(app)
            XCTFail("Connect control not found.")
            return
        }

        // Wait for connected UI (label, switch ON, or disconnect affordance) — real devices / builds vary.
        let sawConnected = waitForVPNConnectedUI(app, timeout: 45)
        if !sawConnected {
            logConnectScreenDiagnostics(app)
        }
        XCTAssertTrue(sawConnected, "Connected state not detected within 45s after tapping connect (switch ON or Connected/Disconnect UI).")

        print("[VPNTest] Soft run: connected — waiting 5s...")
        sleep(5)

        let disconnected = tapVPNDisconnectBestEffort(app, timeout: 15)
        if !disconnected {
            logConnectScreenDiagnostics(app)
        }
        XCTAssertTrue(disconnected, "Could not disconnect after soft-run session.")
        print("[VPNTest] Soft run: finished.")
    }

    func testExample() throws {
        XCTAssertTrue(true)
    }
}
