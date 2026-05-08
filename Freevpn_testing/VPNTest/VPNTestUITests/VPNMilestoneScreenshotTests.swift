//
//  VPNMilestoneScreenshotTests.swift
//  VPNTestUITests
//
//  Captures a fixed visual sequence for IFU / Dash-family apps (shared VPN2 + regionList + connectButton):
//  01 home → 02 region list (scroll strips) → 03 connect idle → 04 connected (disconnect visible) → 05 after disconnect.
//
//  Run: VPNTEST_APP=ifu ./run_tests.sh --milestones
//  Screenshots: XCTest attachments (.xcresult) + printed paths under NSTemporaryDirectory (milestone_*.png).
//

import XCTest

final class VPNMilestoneScreenshotTests: VPNTestBase {

    /// Milestone screenshots only (no strict VPN success assertion on ip).
    func testMilestoneScreenshots_ConnectLifecycle() throws {
        let app = ensureVPNAppReady()
        XCTAssertEqual(app.state, .runningForeground, "VPN app should be in foreground")

        dismissPaywallIfNeeded(app)
        sleep(2)
        captureMilestoneScreenshot(app: app, name: "01_home")

        XCTAssertTrue(
            openRegionList(app, timeout: VPNTestConstants.waitForRegionListAfterLaunch + 10),
            "Open region list failed — extend VPNTestConstants.regionSelectorHints for this SKU."
        )
        sleep(2)

        guard let listHost = resolveRegionListContainer(app) else {
            XCTFail("Region list container not found after openRegionList.")
            return
        }

        let discovered = discoverRegionsInOpenList(host: listHost)
        print("[VPNTest] Milestone: discovered \(discovered.count) distinct region row(s) from live list UI.")

        for _ in 0..<6 { listHost.swipeDown(velocity: .fast); usleep(120_000) }
        sleep(1)
        captureMilestoneScreenshot(app: app, name: "02_region_list_top")

        for i in 1...5 {
            listHost.swipeUp(velocity: .default)
            sleep(1)
            captureMilestoneScreenshot(app: app, name: "02_region_list_scroll_\(String(format: "%02d", i))")
        }

        XCTAssertTrue(
            selectFirstRegionInList(app, timeout: 25),
            "Select first region failed — cell not tappable or connect screen never appeared. See console + attachments."
        )
        sleep(2)

        let connectId = VPNTestConstants.AccessibilityIds.connectButton
        XCTAssertTrue(
            app.buttons[connectId].firstMatch.waitForExistence(timeout: 12)
                || app.switches[connectId].firstMatch.waitForExistence(timeout: 2)
                || app.buttons["Connect VPN"].firstMatch.waitForExistence(timeout: 3),
            "Connect control not on screen before tap."
        )
        captureMilestoneScreenshot(app: app, name: "03_connect_idle_before_tap")

        XCTAssertTrue(tapVPNToggle(app, forDisconnect: false, timeout: 15), "Connect tap failed.")
        sleep(2)

        let connected = waitForVPNConnectedUI(app, timeout: 45)
        if !connected {
            logConnectScreenDiagnostics(app)
        }
        XCTAssertTrue(connected, "Connected UI not detected — cannot capture disconnect-only state.")
        captureMilestoneScreenshot(app: app, name: "04_connected_disconnect_visible")

        XCTAssertTrue(tapVPNDisconnectBestEffort(app, timeout: 18), "Disconnect failed.")
        sleep(3)
        captureMilestoneScreenshot(app: app, name: "05_home_after_disconnect")

        print("[VPNTest] Milestone sequence complete. Open .xcresult in Xcode → Tests → attachments, or collect milestone_*.png from temp paths printed above.")
    }
}
