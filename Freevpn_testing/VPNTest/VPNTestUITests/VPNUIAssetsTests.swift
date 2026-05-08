//
//  VPNUIAssetsTests.swift
//  VPNTestUITests
//
//  Verify UI assets: region list, region icons, connect button.
//

import XCTest

final class VPNUIAssetsTests: VPNTestBase {

    func testUIAssets_RegionList_RegionIcons_ConnectButton() throws {
        let app = ensureVPNAppReady()
        XCTAssertTrue(app.state == .runningForeground, "VPN app should be in foreground")

        var regionListLoaded = false
        var regionIconsExist = false
        var connectButtonExists = false
        var failures: [String] = []

        let regionList = app.tables[VPNTestConstants.AccessibilityIds.regionList]
        if regionList.waitForExistence(timeout: VPNTestConstants.elementWaitTimeout) {
            regionListLoaded = true
            if regionList.cells.count == 0 {
                failures.append("Region list exists but has 0 cells")
            }
        } else {
            let anyTable = app.tables.firstMatch
            if anyTable.waitForExistence(timeout: 5) {
                regionListLoaded = true
                failures.append("Region list used fallback (accessibilityId '\(VPNTestConstants.AccessibilityIds.regionList)' not found)")
            } else {
                failures.append("Region list did not load - no table found")
            }
        }

        let listToCheck = regionList.exists ? regionList : app.tables.firstMatch
        if listToCheck.exists {
            let iconCount = listToCheck.images.matching(identifier: VPNTestConstants.AccessibilityIds.regionIcon).count
            if iconCount > 0 {
                regionIconsExist = true
            } else {
                let anyImages = listToCheck.images.count
                if anyImages > 0 {
                    regionIconsExist = true
                    failures.append("Region icons found via fallback (accessibilityId '\(VPNTestConstants.AccessibilityIds.regionIcon)' not set)")
                } else {
                    failures.append("No region icons found in list")
                }
            }
        } else {
            failures.append("Cannot check icons: region list not found")
        }

        let connectButton = app.buttons[VPNTestConstants.AccessibilityIds.connectButton]
        if connectButton.waitForExistence(timeout: VPNTestConstants.elementWaitTimeout) {
            connectButtonExists = true
        } else {
            let connectLike = app.buttons["Connect"].firstMatch
            if connectLike.waitForExistence(timeout: 2) {
                connectButtonExists = true
                failures.append("Connect button found by label 'Connect' (set accessibilityIdentifier for consistency)")
            } else {
                failures.append("Connect button not found")
            }
        }

        let passed = regionListLoaded && regionIconsExist && connectButtonExists
        VPNTestReportCollector.shared.uiAssets = VPNTestReport.UIAssetsResult(
            regionListLoaded: regionListLoaded,
            regionIconsExist: regionIconsExist,
            connectButtonExists: connectButtonExists,
            passed: passed,
            failures: failures
        )

        XCTAssertTrue(regionListLoaded, "Region list should load: \(failures)")
        XCTAssertTrue(regionIconsExist, "Region icons should exist: \(failures)")
        XCTAssertTrue(connectButtonExists, "Connect button should exist: \(failures)")
    }
}
