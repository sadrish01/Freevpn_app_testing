//
//  VPNAppLaunchStabilityTests.swift
//  VPNTestUITests
//
//  Launch stability: launch app 20 times, keep open 60 seconds each, detect crashes.
//

import XCTest

final class VPNAppLaunchStabilityTests: VPNTestBase {

    private var successfulLaunches = 0
    private var crashCount = 0
    private var failures: [String] = []

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }

    func testLaunchStability_20Launches_60SecondsEach() throws {
        let iterations = VPNTestConstants.launchStabilityIterations
        let duration = VPNTestConstants.launchStabilityDurationSeconds
        let app = XCUIApplication(bundleIdentifier: VPNTestConstants.vpnAppBundleIdentifier)

        for iteration in 1...iterations {
            app.terminate()
            sleep(1)

            app.launch()
            let launched = app.wait(for: .runningForeground, timeout: VPNTestConstants.defaultTimeout)

            if !launched {
                crashCount += 1
                failures.append("Launch \(iteration)/\(iterations): app did not reach foreground")
                continue
            }

            sleep(duration)

            if !app.exists || app.state != .runningForeground {
                crashCount += 1
                failures.append("Launch \(iteration)/\(iterations): app crashed or left foreground after \(duration)s")
            } else {
                successfulLaunches += 1
            }
        }

        app.terminate()

        let successRate = iterations > 0 ? Double(successfulLaunches) / Double(iterations) : 0
        VPNTestReportCollector.shared.launchStability = VPNTestReport.LaunchStabilityResult(
            totalLaunches: iterations,
            successfulLaunches: successfulLaunches,
            successRate: successRate,
            crashCount: crashCount,
            failures: failures
        )

        XCTAssertGreaterThanOrEqual(
            successRate, 0.95,
            "Launch stability: \(successfulLaunches)/\(iterations) succeeded (\(crashCount) crashes). Failures: \(failures)"
        )
    }
}
