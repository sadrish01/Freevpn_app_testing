//
//  VPNRegionAndServicesCatalogTests.swift
//  VPNTestUITests
//
//  Exclusive: open region list → print all region row names → dismiss → open Services → print service row names.
//  This class is marked **skipped** in `VPNTest.xcscheme` so a normal “Test” / full `./run_tests.sh` run does not
//  execute it. Run explicitly: `./run_tests.sh --region-services-catalog` (sets only-testing).
//

import XCTest

final class VPNRegionAndServicesCatalogTests: VPNTestBase {

    func testPrintAllRegionNamesThenAllServiceNames() throws {
        let app = ensureVPNAppReady()
        XCTAssertEqual(app.state, .runningForeground)
        dismissPaywallIfNeeded(app)
        prepareDisconnectedState(app)

        let regionNames = captureRegionListCatalog(app, listOpenTimeout: VPNTestConstants.waitForRegionListAfterLaunch + 12)
        XCTAssertGreaterThan(regionNames.count, 0, "No region names collected.")
        let regionCellsReported = resolveRegionListContainer(app)?.cells.count ?? 0

        XCTAssertTrue(
            dismissFullscreenListToMainVPNBestEffort(app, timeout: 14),
            "Could not dismiss region list back to main VPN screen."
        )
        sleep(1)

        XCTAssertTrue(
            openServicesListBestEffort(app, timeout: 24),
            "Could not open Services list. Extend VPNTestConstants.servicesEntryHints to match your app."
        )
        sleep(1)

        let serviceNames = captureServicesListCatalog(app)
        XCTAssertGreaterThan(
            serviceNames.count,
            0,
            "No service names collected. Wire servicesList accessibility id in the app or adjust resolveServicesListHost."
        )

        let bundle = """
        REGIONS (\(regionNames.count) titles; cells.count=\(regionCellsReported))
        \(regionNames.enumerated().map { "[\($0.offset)] \($0.element)" }.joined(separator: "\n"))

        SERVICES (\(serviceNames.count))
        \(serviceNames.enumerated().map { "[\($0.offset)] \($0.element)" }.joined(separator: "\n"))
        """
        let attach = XCTAttachment(string: bundle)
        attach.name = "region_and_services_catalog.txt"
        attach.lifetime = .keepAlways
        add(attach)

        _ = dismissFullscreenListToMainVPNBestEffort(app, timeout: 10)
    }
}
