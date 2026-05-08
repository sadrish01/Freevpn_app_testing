//
//  VPNTestReport.swift
//  VPNTestUITests
//
//  JSON test report model and generation.
//

import Foundation
import XCTest

/// Collects test results and generates JSON report
struct VPNTestReport: Codable {
    let timestamp: String
    let deviceId: String?
    let deviceName: String?
    let launchStability: LaunchStabilityResult
    let regionConnection: RegionConnectionResult
    let uiAssets: UIAssetsResult
    let summary: SummaryResult

    struct LaunchStabilityResult: Codable {
        let totalLaunches: Int
        let successfulLaunches: Int
        let successRate: Double
        let crashCount: Int
        let failures: [String]
    }

    struct RegionConnectionResult: Codable {
        let regionsTested: Int
        let roundsPerRegion: Int
        let totalAttempts: Int
        let successfulConnections: Int
        let successRate: Double
        let crashCount: Int
        let failures: [String]
        let perRegionResults: [String: RegionResult]?
    }

    struct RegionResult: Codable {
        let regionName: String
        let rounds: Int
        let successCount: Int
        let successRate: Double
        let failures: [String]
    }

    struct UIAssetsResult: Codable {
        let regionListLoaded: Bool
        let regionIconsExist: Bool
        let connectButtonExists: Bool
        let passed: Bool
        let failures: [String]
    }

    struct SummaryResult: Codable {
        let overallPassed: Bool
        let totalCrashes: Int
        let totalFailures: Int
    }

    func toJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func write(to path: String) {
        let json = toJSON()
        try? json.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

/// Global report collector - populated by test classes and written at end
final class VPNTestReportCollector {
    static let shared = VPNTestReportCollector()

    var launchStability: VPNTestReport.LaunchStabilityResult?
    var regionConnection: VPNTestReport.RegionConnectionResult?
    var uiAssets: VPNTestReport.UIAssetsResult?
    var deviceId: String?
    var deviceName: String?

    private init() {}

    func buildReport() -> VPNTestReport {
        let launch = launchStability ?? VPNTestReport.LaunchStabilityResult(
            totalLaunches: 0, successfulLaunches: 0, successRate: 0, crashCount: 0, failures: []
        )
        let region = regionConnection ?? VPNTestReport.RegionConnectionResult(
            regionsTested: 0, roundsPerRegion: 0, totalAttempts: 0, successfulConnections: 0,
            successRate: 0, crashCount: 0, failures: [], perRegionResults: nil
        )
        let ui = uiAssets ?? VPNTestReport.UIAssetsResult(
            regionListLoaded: false, regionIconsExist: false, connectButtonExists: false,
            passed: false, failures: []
        )
        let totalCrashes = launch.crashCount + region.crashCount
        let totalFailures = launch.failures.count + region.failures.count + ui.failures.count
        let summary = VPNTestReport.SummaryResult(
            overallPassed: ui.passed && totalCrashes == 0 && launch.successRate >= 0.95,
            totalCrashes: totalCrashes,
            totalFailures: totalFailures
        )
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return VPNTestReport(
            timestamp: formatter.string(from: Date()),
            deviceId: deviceId,
            deviceName: deviceName,
            launchStability: launch,
            regionConnection: region,
            uiAssets: ui,
            summary: summary
        )
    }

    func writeReport(to path: String? = nil) {
        let reportPath = path ?? reportDefaultPath()
        buildReport().write(to: reportPath)
        print("VPNTest report written to: \(reportPath)")
    }

    private func reportDefaultPath() -> String {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let docDir = urls.first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let reportDir = docDir.appendingPathComponent("VPNTestReports", isDirectory: true)
        try? fileManager.createDirectory(at: reportDir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "vpn_test_report_\(formatter.string(from: Date())).json"
        return reportDir.appendingPathComponent(name).path
    }

    func reset() {
        launchStability = nil
        regionConnection = nil
        uiAssets = nil
    }
}

/// Writes JSON report when test bundle finishes
final class VPNTestReportObserver: NSObject, XCTestObservation {
    private static var registered = false

    static func registerIfNeeded() {
        guard !registered else { return }
        registered = true
        XCTestObservationCenter.shared.addTestObserver(VPNTestReportObserver())
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        VPNTestReportCollector.shared.writeReport()
    }
}
