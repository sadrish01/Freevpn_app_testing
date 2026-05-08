//
//  VPNRegionConnectionTests.swift
//  VPNTestUITests
//
//  Region connection: first 5 regions, connect 60s, disconnect, 50 rounds per region.
//

import XCTest

final class VPNRegionConnectionTests: VPNTestBase {

    private var successfulConnections = 0
    private var totalAttempts = 0
    private var connectionCrashCount = 0
    private var failures: [String] = []
    private var perRegionResults: [String: VPNTestReport.RegionResult] = [:]

    func testRegionConnection_5Regions_50RoundsEach() throws {
        let app = ensureVPNAppReady()
        XCTAssertTrue(app.state == .runningForeground, "VPN app should be in foreground")

        let regionCount = VPNTestConstants.regionConnectionRegionCount
        let roundsPerRegion = VPNTestConstants.regionConnectionRoundsPerRegion
        let duration = VPNTestConstants.regionConnectionDurationSeconds

        dismissPaywallIfNeeded(app)
        sleep(1)
        openRegionList(app, timeout: VPNTestConstants.waitForRegionListAfterLaunch)

        let regionList = app.tables[VPNTestConstants.AccessibilityIds.regionList]
        var listElement: XCUIElement = regionList
        if !regionList.waitForExistence(timeout: 3) || regionList.cells.count == 0 {
            if app.tables.firstMatch.waitForExistence(timeout: 3), app.tables.firstMatch.cells.count > 0 {
                listElement = app.tables.firstMatch
            }
        }
        let regionCells = listElement.cells
        let count = regionCells.count
        XCTAssertGreaterThanOrEqual(count, regionCount, "Need at least \(regionCount) regions in list, found \(count)")

        let cellsToUse = min(regionCount, max(1, count))
        var regionNames: [String] = []

        for index in 0..<cellsToUse {
            let cell = regionCells.element(boundBy: index)
            if cell.waitForExistence(timeout: 3) {
                regionNames.append(cell.label.isEmpty ? "Region_\(index + 1)" : cell.label)
            } else {
                regionNames.append("Region_\(index + 1)")
            }
        }

        for (regionIndex, regionName) in regionNames.enumerated() {
            var regionSuccess = 0
            var regionFailures: [String] = []

            for round in 1...roundsPerRegion {
                if app.state != .runningForeground {
                    connectionCrashCount += 1
                    failures.append("Region '\(regionName)' round \(round): app not in foreground")
                    app.launch()
                    _ = app.wait(for: .runningForeground, timeout: VPNTestConstants.defaultTimeout)
                }

                openRegionList(app, timeout: 10)
                sleep(1)

                var table = app.tables[VPNTestConstants.AccessibilityIds.regionList]
                if !table.waitForExistence(timeout: 2) || table.cells.count == 0 {
                    table = app.tables.firstMatch
                }
                let cells = table.cells
                if regionIndex >= cells.count {
                    regionFailures.append("Round \(round): region cell not found (index \(regionIndex), count \(cells.count))")
                    totalAttempts += 1
                    continue
                }

                let cell = cells.element(boundBy: regionIndex)
                if !cell.waitForExistence(timeout: 3) {
                    regionFailures.append("Round \(round): cell did not appear")
                    totalAttempts += 1
                    continue
                }
                cell.tap()
                sleep(2)

                let connectButton = app.buttons[VPNTestConstants.AccessibilityIds.connectButton]
                if !connectButton.waitForExistence(timeout: 5) {
                    regionFailures.append("Round \(round): connect button not found")
                    totalAttempts += 1
                    continue
                }
                connectButton.tap()
                totalAttempts += 1

                sleep(duration)

                if app.state != .runningForeground {
                    connectionCrashCount += 1
                    regionFailures.append("Round \(round): app crashed during connection")
                    app.launch()
                    continue
                }

                connectButton.tap()
                if connectButton.waitForExistence(timeout: 3) {
                    connectButton.tap()
                }
                successfulConnections += 1
                regionSuccess += 1
                sleep(2)
            }

            let regionRate = roundsPerRegion > 0 ? Double(regionSuccess) / Double(roundsPerRegion) : 0
            perRegionResults[regionName] = VPNTestReport.RegionResult(
                regionName: regionName,
                rounds: roundsPerRegion,
                successCount: regionSuccess,
                successRate: regionRate,
                failures: regionFailures
            )
        }

        app.terminate()

        let successRate = totalAttempts > 0 ? Double(successfulConnections) / Double(totalAttempts) : 0
        VPNTestReportCollector.shared.regionConnection = VPNTestReport.RegionConnectionResult(
            regionsTested: regionCount,
            roundsPerRegion: roundsPerRegion,
            totalAttempts: totalAttempts,
            successfulConnections: successfulConnections,
            successRate: successRate,
            crashCount: connectionCrashCount,
            failures: failures,
            perRegionResults: perRegionResults.isEmpty ? nil : perRegionResults
        )

        XCTAssertGreaterThanOrEqual(
            successRate, 0.90,
            "Region connection: \(successfulConnections)/\(totalAttempts) succeeded. Failures: \(failures.prefix(5))..."
        )
    }
}
