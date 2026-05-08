//
//  VPNRegionDiscoveryTests.swift
//  VPNTestUITests
//
//  Reads region names from the live region list (no hardcoded region list in tests).
//

import XCTest

final class VPNRegionDiscoveryTests: VPNTestBase {

    /// Opens IFU (or VPNTEST_APP / VPNTEST_BUNDLE_ID), opens the region list, scrolls it, prints every row label found.
    func testDiscoverRegionsFromList() throws {
        let app = ensureVPNAppReady()
        XCTAssertEqual(app.state, .runningForeground)

        dismissPaywallIfNeeded(app)
        sleep(2)

        let regions = openRegionListAndDiscoverRegionNames(app, listOpenTimeout: VPNTestConstants.waitForRegionListAfterLaunch + 10)
        if regions.isEmpty {
            logAccessibilitySummary(app)
            logConnectScreenDiagnostics(app)
        }
        XCTAssertGreaterThan(
            regions.count,
            0,
            "No region row titles detected. IFU rows often expose text in cell.staticTexts, not cell.label — if still empty, inspect with Accessibility Inspector or extend regionRowDisplayLabel in VPNTestBase."
        )

        let payload = regions.joined(separator: "\n")
        let attach = XCTAttachment(string: payload)
        attach.name = "discovered_regions.txt"
        attach.lifetime = .keepAlways
        add(attach)

        print("[VPNTest] Region discovery OK — \(regions.count) name(s). Attachment: discovered_regions.txt")
    }
}
