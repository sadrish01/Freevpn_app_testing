import XCTest
import Vision
import UIKit

final class VPNRegionPipelineTests: XCTestCase {
    private let vpnBundleID = RuntimeConfig.string("VPN_APP_BUNDLE_ID") ?? GeneratedDefaults.vpnAppBundleID
    private let limit = RuntimeConfig.int("VPN_REGION_LIMIT") ?? GeneratedDefaults.regionLimit
    private let holdSeconds = TimeInterval(RuntimeConfig.int("VPN_HOLD_SECONDS") ?? GeneratedDefaults.holdSeconds)
    private let startIndex = RuntimeConfig.int("VPN_START_INDEX") ?? GeneratedDefaults.startIndex
    private let boostMode = (RuntimeConfig.string("VPN_BOOST") ?? GeneratedDefaults.boostMode).lowercased()
    private let adblockMode = (RuntimeConfig.string("VPN_ADBLOCK") ?? GeneratedDefaults.adblockMode).lowercased()
    private let testMode = (RuntimeConfig.string("VPN_TEST_MODE") ?? GeneratedDefaults.testMode).lowercased()
    private lazy var vpn = XCUIApplication(bundleIdentifier: vpnBundleID)
    private var pickerCursorPage = 0
    private var previousSelectedRegionName: String?
    private var selectedRegionKeys = Set<String>()
    private var strictPreviousAnchor = false

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRegionPipeline() throws {
        if testMode == "check-settings" {
            try runSettingsCheck()
            return
        }

        log("[VPNTest] ========== VPN region pipeline (index-driven + 10x connect 10s disconnect) ==========")

        if vpn.state != .runningForeground {
            vpn.activate()
        }
        XCTAssertTrue(vpn.wait(for: .runningForeground, timeout: 20), "VPN app did not become foreground")
        closeCommonInterruptions()
        Thread.sleep(forTimeInterval: 3)
        log("[VPNTest] OCR startup: \(debugOCR())")
        _ = closePremiumPaywallIfPresent()
        if ifuSettingsMenuIsVisible() {
            closeIFUSettings()
        }

        if vpnBundleID == "com.actmobile.dashvpn", pickerIsOpen() {
            log("[VPNTest] IDV picker is already open; starting region tests from picker")
        } else {
            XCTAssertTrue(verifyHomeScreenWithOneRelaunchRetry(), "VPN home screen was not stable for 5s before region tests")
            log("[VPNTest] homepage stable for 5s; starting region tests")
        }

        XCTAssertTrue(applyBoostAndAdblockModes(), "Boost/Adblock preflight failed")
        prepareDisconnectedBaseline()
        log("[VPNTest] OCR baseline: \(debugOCR())")
        let defaultIdentity = pickerIsOpen() ? Identity(ip: "", location: "") : waitForReadableIdentity(timeout: 5)
        log("[VPNTest] default identity: IP=\"\(defaultIdentity.ip)\", Location=\"\(defaultIdentity.location)\"")

        let runLimit = limit == Int.max ? 250 : limit
        let firstIndex = max(startIndex, 1)
        let lastIndex = firstIndex + runLimit - 1
        log("[VPNTest] planned ordinal range: \(firstIndex)...\(lastIndex)")
        let anchorRegion = RuntimeConfig.string("VPN_ANCHOR_REGION") ?? GeneratedDefaults.anchorRegion
        if firstIndex > 1, !anchorRegion.isEmpty {
            let anchor = anchorRegion
            previousSelectedRegionName = anchor
            selectedRegionKeys.insert(normalizedRegionName(anchor))
            strictPreviousAnchor = true
            log("[VPNTest] continuation anchor: \(anchor)")
        }

        var tested = 0
        var consecutiveSelectionFailures = 0
        for ordinal in firstIndex...lastIndex {
            guard let selected = selectRegionByOrdinal(ordinal) else {
                consecutiveSelectionFailures += 1
                log("[\(ordinal)] catalog=\"(ordinal \(ordinal))\" selected=\"\" - FAIL - could not select region, IP=\"\", Location=\"\", held 0s, feedback not shown, default identity not restored")
                if consecutiveSelectionFailures >= 3 {
                    log("[VPNTest] stopping after 3 consecutive selection failures")
                    break
                }
                continue
            }
            consecutiveSelectionFailures = 0

            if selected.localizedCaseInsensitiveContains("IPv6") {
                log("[\(ordinal)] catalog=\"(ordinal \(ordinal))\" selected=\"\(selected)\" - SKIP - IPv6 region")
                continue
            }

            log("[VPNTest] selected \(selected); waiting for automatic connection")
            tested += 1
            runRegion(index: ordinal, catalog: "(ordinal \(ordinal))", selected: selected, defaultIdentity: defaultIdentity)
        }

        XCTAssertGreaterThan(tested, 0, "No non-IPv6 regions were tested")
    }

    private func runRegion(index: Int, catalog: String, selected: String, defaultIdentity: Identity) {
        var failure: String?
        var connectedIdentity = Identity(ip: "", location: "")
        var held = false
        var feedbackClosed = false
        var restored = false

        if !ensureConnected() {
            failure = "did not reach Connected state"
        } else {
            connectedIdentity = waitForChangedIdentity(from: defaultIdentity, timeout: 35)
            if idvHasConnectedEvidence(for: selected) {
                connectedIdentity = idvIdentityFallback(from: connectedIdentity, selected: selected)
                if !holdConnected(for: holdSeconds) {
                    failure = "did not stay connected for \(Int(holdSeconds))s"
                } else {
                    held = true
                }
            } else if connectedIdentity.ip == defaultIdentity.ip || connectedIdentity.ip.isEmpty {
                failure = "IP did not change"
            } else if connectedIdentity.location == defaultIdentity.location || connectedIdentity.location.isEmpty {
                failure = "location did not change"
            } else if !holdConnected(for: holdSeconds) {
                failure = "did not stay connected for \(Int(holdSeconds))s"
            } else {
                held = true
            }
        }

        if serverIssuesPageIsVisible() {
            feedbackClosed = closeServerIssuesIfPresent()
        } else if sessionEndedFeedbackIsVisible() {
            _ = waitForDisconnected(timeout: 1)
        } else if isConnectedLike() {
            feedbackClosed = disconnectAndCloseFeedback()
        } else if textExists("Disconnecting") || textExists("Connecting") || networkSwitchIsActive() {
            _ = waitForDisconnected(timeout: 20)
        }
        feedbackClosed = feedbackClosed || closeFeedbackIfPresent()
        restored = waitForDefaultIdentity(defaultIdentity, timeout: 20)

        if failure == nil, !restored {
            failure = "default identity not restored after disconnect"
        }

        if let failure {
            log("[\(index)] catalog=\"\(catalog)\" selected=\"\(selected)\" - FAIL - \(failure), IP=\"\(connectedIdentity.ip)\", Location=\"\(connectedIdentity.location)\", held \(held ? Int(holdSeconds) : 0)s, feedback \(feedbackClosed ? "closed" : "not shown"), default identity \(restored ? "restored" : "not restored")")
        } else {
            log("[\(index)] catalog=\"\(catalog)\" selected=\"\(selected)\" - PASS - IP=\"\(connectedIdentity.ip)\", Location=\"\(connectedIdentity.location)\" held \(Int(holdSeconds))s, feedback closed, default identity restored")
        }
    }

    private func selectRegionByOrdinal(_ oneBasedOrdinal: Int) -> String? {
        if vpnBundleID == "com.actmobile.dashvpn" {
            return selectIDVRegionByOrdinal(oneBasedOrdinal)
        }

        guard openRegionList() else { return nil }

        if previousSelectedRegionName == nil {
            alignPickerToFirstPageIfNeeded()
            var rows = visibleRegionRows()
            var rowKeys = Set(rows.map { normalizedRegionName($0.text) })
            log("[VPNTest] ordinal \(oneBasedOrdinal) visible rows: \(rows.map { "\($0.text)@\($0.centerY)" }.joined(separator: " | "))")
            for attempt in 1...10 where rows.count < oneBasedOrdinal {
                vpn.swipeUp()
                Thread.sleep(forTimeInterval: 0.6)
                let nextRows = visibleRegionRows()
                log("[VPNTest] ordinal \(oneBasedOrdinal) accumulation attempt \(attempt): \(nextRows.map { "\($0.text)@\($0.centerY)" }.joined(separator: " | "))")
                for row in nextRows {
                    let key = normalizedRegionName(row.text)
                    if rowKeys.insert(key).inserted {
                        rows.append(row)
                    }
                }
            }
            let targetIndex = oneBasedOrdinal - 1
            if rows.indices.contains(targetIndex) {
                return selectOrSkipRegion(rows[targetIndex])
            }
            let firstRegion = rows.first(where: { normalizedRegionName($0.text) == "us east" }) ?? rows.first
            guard let firstRegion else { return nil }
            return selectOrSkipRegion(firstRegion)
        }

        let previousKey = normalizedRegionName(previousSelectedRegionName ?? "")
        for attempt in 1...10 {
            let rows = visibleRegionRows()
            log("[VPNTest] ordinal \(oneBasedOrdinal) attempt \(attempt) visible rows: \(rows.map { "\($0.text)@\($0.centerY)" }.joined(separator: " | "))")

            if let previousIndex = rows.firstIndex(where: { normalizedRegionName($0.text) == previousKey }) {
                if let next = rows.dropFirst(previousIndex + 1).first(where: { !selectedRegionKeys.contains(normalizedRegionName($0.text)) }) {
                    strictPreviousAnchor = false
                    return selectOrSkipRegion(next)
                }
                strictPreviousAnchor = false
                vpn.swipeUp()
                Thread.sleep(forTimeInterval: 0.6)
                continue
            }

            if strictPreviousAnchor {
                log("[VPNTest] continuation anchor \"\(previousSelectedRegionName ?? "")\" not visible yet; scrolling")
                vpn.swipeUp()
                Thread.sleep(forTimeInterval: 0.6)
                continue
            }

            if let next = rows.first(where: { !selectedRegionKeys.contains(normalizedRegionName($0.text)) }) {
                log("[VPNTest] previous region \"\(previousSelectedRegionName ?? "")\" not visible; selecting first untested visible row")
                return selectOrSkipRegion(next)
            }

            vpn.swipeUp()
            Thread.sleep(forTimeInterval: 0.6)
        }

        log("[VPNTest] ordinal \(oneBasedOrdinal) could not find next untested region after \"\(previousSelectedRegionName ?? "")\"")
        return nil
    }

    private func selectOrSkipRegion(_ row: OCRLine) -> String {
        let name = row.text
        previousSelectedRegionName = name
        selectedRegionKeys.insert(normalizedRegionName(name))
        if name.localizedCaseInsensitiveContains("IPv6") {
            log("[VPNTest] pre-skip IPv6 row without tapping: \(name)")
            return name
        }
        vpn.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: row.centerY)).tap()
        Thread.sleep(forTimeInterval: 2)
        if vpnBundleID == "com.actmobile.dashvpn" {
            commitIDVRegionSelection(name)
        }
        return name
    }

    private func selectIDVRegionByOrdinal(_ oneBasedOrdinal: Int) -> String? {
        guard openRegionList() else { return nil }

        if previousSelectedRegionName != nil {
            return selectNextIDVVisibleRegion(after: previousSelectedRegionName ?? "", ordinal: oneBasedOrdinal)
        }

        alignIDVPickerToTop()

        var rows = visibleRegionRows()
        var seen = Set(rows.map { normalizedRegionName($0.text) })
        var orderedRows = rows
        log("[VPNTest] IDV ordinal \(oneBasedOrdinal) initial rows: \(rows.map { "\($0.text)@\($0.centerY)" }.joined(separator: " | "))")

        for attempt in 1...12 where orderedRows.count < oneBasedOrdinal {
            vpn.swipeUp()
            Thread.sleep(forTimeInterval: 0.55)
            rows = visibleRegionRows()
            log("[VPNTest] IDV ordinal \(oneBasedOrdinal) scroll-down attempt \(attempt): \(rows.map { "\($0.text)@\($0.centerY)" }.joined(separator: " | "))")
            var added = false
            for row in rows {
                let key = normalizedRegionName(row.text)
                if seen.insert(key).inserted {
                    orderedRows.append(row)
                    added = true
                }
            }
            if !added, rows.isEmpty {
                break
            }
        }

        let targetIndex = oneBasedOrdinal - 1
        guard orderedRows.indices.contains(targetIndex) else {
            log("[VPNTest] IDV ordinal \(oneBasedOrdinal) unavailable after bounded scroll; rows: \(orderedRows.map(\.text).joined(separator: " | "))")
            return nil
        }

        let targetName = orderedRows[targetIndex].text
        guard selectIDVWheelRegion(named: targetName) else {
            return nil
        }

        previousSelectedRegionName = targetName
        selectedRegionKeys.insert(normalizedRegionName(targetName))
        return targetName
    }

    private func selectNextIDVVisibleRegion(after previous: String, ordinal: Int) -> String? {
        let previousKey = normalizedRegionName(previous)

        for attempt in 1...8 {
            let rows = visibleRegionRows()
            log("[VPNTest] IDV ordinal \(ordinal) continuation attempt \(attempt): \(rows.map { "\($0.text)@\($0.centerY)" }.joined(separator: " | "))")

            if let previousIndex = rows.firstIndex(where: { normalizedRegionName($0.text) == previousKey }),
               let next = rows.dropFirst(previousIndex + 1).first(where: { !selectedRegionKeys.contains(normalizedRegionName($0.text)) }) {
                return selectAndRememberIDV(row: next)
            }

            if let next = rows.first(where: { !selectedRegionKeys.contains(normalizedRegionName($0.text)) }) {
                log("[VPNTest] IDV previous \"\(previous)\" not visible; selecting first untested visible row")
                return selectAndRememberIDV(row: next)
            }

            vpn.swipeUp()
            Thread.sleep(forTimeInterval: 0.55)
        }

        log("[VPNTest] IDV ordinal \(ordinal) could not continue after \"\(previous)\"")
        return nil
    }

    private func selectAndRememberIDV(row: OCRLine) -> String? {
        let name = row.text
        guard selectIDVWheelRegion(named: name) else { return nil }
        previousSelectedRegionName = name
        selectedRegionKeys.insert(normalizedRegionName(name))
        return name
    }

    private func alignIDVPickerToTop() {
        guard pickerIsOpen() else { return }
        var lastSignature = ""
        var stableTopCount = 0

        for attempt in 1...6 {
            let rows = visibleRegionRows()
            let signature = rows.map { normalizedRegionName($0.text) }.joined(separator: "|")
            if let fastest = rows.first(where: { normalizedRegionName($0.text) == "fastest" }),
               fastest.centerY < 0.46,
               rows.count >= 6 {
                log("[VPNTest] IDV top aligned on attempt \(attempt): \(rows.map(\.text).joined(separator: " | "))")
                return
            }

            if signature == lastSignature {
                stableTopCount += 1
                if stableTopCount >= 2 { return }
            } else {
                stableTopCount = 0
                lastSignature = signature
            }

            vpn.swipeDown()
            Thread.sleep(forTimeInterval: 0.45)
        }
    }

    private func selectIDVWheelRegion(named name: String) -> Bool {
        let target = normalizedRegionName(name)
        let highlightY: CGFloat = 0.51

        for attempt in 1...14 {
            if idvAlreadySelectedDialogIsVisible() {
                log("[VPNTest] IDV region already selected while scrolling; closing dialog")
                vpn.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.54)).tap()
                Thread.sleep(forTimeInterval: 1)
                if let action = idvConnectActionText(), idvConnectAction(action, matches: name) {
                    log("[VPNTest] IDV using already-selected action \(action)")
                    vpn.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.92)).tap()
                    Thread.sleep(forTimeInterval: 1.5)
                    return true
                }
            }

            let rows = visibleRegionRows()
            log("[VPNTest] IDV wheel select \"\(name)\" attempt \(attempt): \(rows.map { "\($0.text)@\($0.centerY)" }.joined(separator: " | "))")

            if let row = rows.first(where: { normalizedRegionName($0.text) == target }) {
                if abs(row.centerY - highlightY) > 0.025 {
                    log("[VPNTest] IDV moving \"\(name)\" into highlight with row tap @\(String(format: "%.2f", row.centerY))")
                    vpn.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: row.centerY)).tap()
                    Thread.sleep(forTimeInterval: 1)
                    continue
                }

                log("[VPNTest] IDV tapping highlighted region \"\(name)\" @\(String(format: "%.2f", row.centerY))")
                vpn.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: row.centerY)).tap()
                Thread.sleep(forTimeInterval: 1.5)
                if waitForIDVPickerToCloseOrConnecting(timeout: 5) {
                    return true
                }
                if let action = idvConnectActionText(), idvConnectAction(action, matches: name) {
                    log("[VPNTest] IDV highlighted tap left picker open; using matching action \(action)")
                    vpn.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.92)).tap()
                    Thread.sleep(forTimeInterval: 1.5)
                    return true
                }
                return false
            }

            vpn.swipeUp()
            Thread.sleep(forTimeInterval: 0.55)
        }

        log("[VPNTest] IDV wheel could not select \"\(name)\"; OCR: \(debugOCR())")
        return false
    }

    private func idvConnectAction(_ action: String, matches name: String) -> Bool {
        if normalizedRegionName(name) == "fastest" {
            return true
        }
        let comparableAction = normalizedRegionName(action)
            .replacingOccurrences(of: "connect to", with: "")
            .replacingOccurrences(of: "alternate ip in", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let comparableName = normalizedRegionName(name)
        return comparableAction.contains(comparableName) || comparableName.contains(comparableAction)
    }

    private func waitForIDVPickerToCloseOrConnecting(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let text = ocrText()
            if connectedTextIsVisible(in: text)
                || text.localizedCaseInsensitiveContains("Connecting")
                || text.localizedCaseInsensitiveContains("Fetching IP")
                || text.localizedCaseInsensitiveContains("Switching")
                || !pickerIsOpen(in: text) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        log("[VPNTest] IDV picker did not close/start connecting after highlighted tap; OCR: \(debugOCR())")
        return false
    }

    private func applyBoostAndAdblockModes() -> Bool {
        log("[VPNTest] feature round: boost \(boostMode) | adblock \(adblockMode)")
        if vpnBundleID == "com.actmobile.dashvpn" {
            return applyIDVHomeFeatureToggles()
        }

        return applyIFUSettingsFeatureToggles()
    }

    private func runSettingsCheck() throws {
        log("[VPNTest] ========== VPN settings link check ==========")

        if vpn.state != .runningForeground {
            vpn.activate()
        }
        XCTAssertTrue(vpn.wait(for: .runningForeground, timeout: 20), "VPN app did not become foreground")
        closeCommonInterruptions()
        Thread.sleep(forTimeInterval: 2)
        _ = closePremiumPaywallIfPresent()
        if settingsMenuIsVisible() {
            closeSettingsMenu()
        }
        XCTAssertTrue(verifyHomeScreenWithOneRelaunchRetry(), "VPN home screen was not stable before settings checks")

        let options: [SettingsOption]
        if vpnBundleID == "com.actmobile.dashvpn" {
            options = [
                SettingsOption(name: "What is My Geo IP?", matchTexts: ["What is My Geo IP"], expectedSignals: ["Geo IP", "IP", "Address"]),
                SettingsOption(name: "What is My Network Speed?", matchTexts: ["What is My Network Speed"], expectedSignals: ["Network Speed", "Speed", "Download", "Upload"])
            ]
        } else {
            options = [
                SettingsOption(name: "My IP", matchTexts: ["My IP", "MylP"], expectedSignals: ["My IP", "MylP", "IP", "Address"]),
                SettingsOption(name: "Speed Test", matchTexts: ["Speed Test"], expectedSignals: ["Speed", "Test", "Download"]),
                SettingsOption(name: "About us", matchTexts: ["About us", "About Us"], expectedSignals: ["About", "Free VPN", "VPN"]),
                SettingsOption(name: "Privacy policy", matchTexts: ["Privacy policy", "Privacy Policy"], expectedSignals: ["Privacy", "Policy"]),
                SettingsOption(name: "Terms of use", matchTexts: ["Terms of use", "Terms of Use"], expectedSignals: ["Terms", "Use"])
            ]
        }

        var failed: [String] = []
        for option in options {
            if checkSettingsOption(option) {
                log("[settings] \(option.name) succeeded")
            } else {
                log("[settings] \(option.name) failed")
                failed.append(option.name)
            }
        }

        if settingsMenuIsVisible() {
            closeSettingsMenu()
        }
        XCTAssertTrue(failed.isEmpty, "Settings checks failed: \(failed.joined(separator: ", "))")
    }

    private func checkSettingsOption(_ option: SettingsOption) -> Bool {
        guard openSettingsMenu() else {
            log("[VPNTest] settings check failed before \(option.name): settings did not open; OCR: \(debugOCR())")
            return false
        }

        guard let row = findSettingsRow(option) else {
            log("[VPNTest] settings row not found for \(option.name); OCR: \(debugOCR())")
            closeSettingsMenu()
            return false
        }

        vpn.coordinate(withNormalizedOffset: CGVector(dx: min(max(row.centerX, 0.22), 0.82), dy: row.centerY)).tap()
        Thread.sleep(forTimeInterval: 1.5)
        let loaded = waitForSettingsDestinationLoaded(option, timeout: 30)
        if !loaded {
            log("[VPNTest] \(option.name) did not finish loading; OCR: \(debugOCR())")
        }

        let closed = closeSettingsDestinationToSettings()
        if !closed {
            log("[VPNTest] \(option.name) destination did not close cleanly; OCR: \(debugOCR())")
        }
        return loaded && closed
    }

    private func findSettingsRow(_ option: SettingsOption) -> OCRLine? {
        for attempt in 1...8 {
            let rows = ocrLines()
            if let row = rows.first(where: { line in
                option.matchTexts.contains { settingsRow(line.text, matches: $0) }
            }) {
                return row
            }

            let text = rows.map(\.text).joined(separator: " | ")
            log("[VPNTest] settings row \(option.name) not visible on attempt \(attempt); OCR: \(text)")
            if text.localizedCaseInsensitiveContains("Info & Legal")
                && (option.name.localizedCaseInsensitiveContains("My IP") || option.name.localizedCaseInsensitiveContains("Speed Test")) {
                vpn.swipeDown()
            } else {
                vpn.swipeUp()
            }
            Thread.sleep(forTimeInterval: 0.7)
        }

        return nil
    }

    private func settingsRow(_ text: String, matches name: String) -> Bool {
        if text.localizedCaseInsensitiveContains(name) {
            return true
        }

        let compactText = text
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "|", with: "l")
        let compactName = name
            .lowercased()
            .replacingOccurrences(of: " ", with: "")

        if compactName == "myip" {
            return compactText == "myip"
                || compactText == "mylp"
                || compactText == "my1p"
        }

        return false
    }

    private func waitForSettingsDestinationLoaded(_ option: SettingsOption, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let text = ocrText()
            if option.name.localizedCaseInsensitiveContains("Terms"),
               text.localizedCaseInsensitiveContains("Terms of Use") {
                return true
            }
            let hasExpectedText = option.expectedSignals.contains {
                text.localizedCaseInsensitiveContains($0)
            }
            let stillSettings = ifuSettingsMenuIsVisible()
            let loading = text.localizedCaseInsensitiveContains("Loading")
                || text.localizedCaseInsensitiveContains("Fetching")
            let browserLoaded = ifuBrowserIsVisible()
                && !text.localizedCaseInsensitiveContains("Search or enter website")
            let documentLoaded = hasExpectedText && !stillSettings && !loading

            if browserLoaded || documentLoaded {
                return true
            }
            Thread.sleep(forTimeInterval: 0.5)
        }

        return false
    }

    private func closeSettingsDestinationToSettings() -> Bool {
        for tap in [
            CGVector(dx: 0.07, dy: 0.09),
            CGVector(dx: 0.10, dy: 0.10),
            CGVector(dx: 0.50, dy: 0.94)
        ] {
            vpn.coordinate(withNormalizedOffset: tap).tap()
            Thread.sleep(forTimeInterval: 1)
            _ = closePremiumPaywallIfPresent()
            if settingsMenuIsVisible() {
                return true
            }
            if homeScreenIsVisible() {
                return openSettingsMenu()
            }
        }

        vpn.swipeDown()
        Thread.sleep(forTimeInterval: 1)
        if settingsMenuIsVisible() { return true }
        return homeScreenIsVisible() && openSettingsMenu()
    }

    private func openSettingsMenu() -> Bool {
        if vpnBundleID == "com.actmobile.dashvpn" {
            return openIDVSettings()
        }
        return openIFUSettings()
    }

    private func settingsMenuIsVisible() -> Bool {
        if vpnBundleID == "com.actmobile.dashvpn" {
            return idvSettingsMenuIsVisible()
        }
        return ifuSettingsMenuIsVisible()
    }

    private func closeSettingsMenu() {
        if vpnBundleID == "com.actmobile.dashvpn" {
            closeIDVSettings()
        } else {
            closeIFUSettings()
        }
    }

    private func applyIFUSettingsFeatureToggles() -> Bool {
        guard openIFUSettings() else {
            log("[VPNTest] IFU feature preflight failed: settings did not open; OCR: \(debugOCR())")
            return false
        }

        let boostOK = setSettingsSwitch(label: "Boost Speed", enabled: boostMode == "on")
        let adblockOK = setSettingsSwitch(label: "Adblock", enabled: adblockMode == "on")
        log("[VPNTest] IFU feature preflight: boost \(boostOK ? boostMode : "not \(boostMode)"), adblock \(adblockOK ? adblockMode : "not \(adblockMode)")")

        closeIFUSettings()
        _ = closePremiumPaywallIfPresent()
        return boostOK && adblockOK
    }

    private func openIFUSettings() -> Bool {
        if ifuSettingsMenuIsVisible() {
            return true
        }

        if ifuBrowserIsVisible()
            || ifuSettingsMenuIsVisible() {
            closeIFUSettings()
        }

        for attempt in 1...3 {
            vpn.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.09)).tap()
            Thread.sleep(forTimeInterval: 1.2)
            if ocrText().localizedCaseInsensitiveContains("VPN US Menu")
                && ocrText().localizedCaseInsensitiveContains("Boost Speed") {
                log("[VPNTest] IFU settings opened on attempt \(attempt)")
                return true
            }
        }

        return false
    }

    private func ifuBrowserIsVisible() -> Bool {
        let text = ocrText()
        return text.localizedCaseInsensitiveContains("TRENDING CONTENT")
            || text.localizedCaseInsensitiveContains("BOOKMARKS")
            || text.localizedCaseInsensitiveContains("Search or enter website")
    }

    private func ifuSettingsMenuIsVisible() -> Bool {
        guard vpnBundleID != "com.actmobile.dashvpn" else { return false }
        let text = ocrText()
        return text.localizedCaseInsensitiveContains("VPN US Menu")
            && (text.localizedCaseInsensitiveContains("Boost Speed")
                || text.localizedCaseInsensitiveContains("Adblock Plus")
                || text.localizedCaseInsensitiveContains("Private Browser Settings")
                || text.localizedCaseInsensitiveContains("Tools")
                || text.localizedCaseInsensitiveContains("Info & Legal")
                || text.localizedCaseInsensitiveContains("Terms of use")
                || text.localizedCaseInsensitiveContains("Privacy Policy"))
    }

    private func openIDVSettings() -> Bool {
        if idvSettingsMenuIsVisible() {
            return true
        }

        _ = closeIDVServicePageIfPresent()
        if pickerIsOpen() {
            vpn.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.94)).tap()
            Thread.sleep(forTimeInterval: 1)
        }

        let lines = ocrLines()
        var taps: [CGVector] = []
        if let menu = lines.first(where: { $0.centerY < 0.16 && ($0.text == "≡" || $0.text.localizedCaseInsensitiveContains("Menu")) }) {
            taps.append(CGVector(dx: menu.centerX, dy: menu.centerY))
        }
        taps.append(contentsOf: [
            CGVector(dx: 0.92, dy: 0.12),
            CGVector(dx: 0.92, dy: 0.14),
            CGVector(dx: 0.90, dy: 0.12),
            CGVector(dx: 0.86, dy: 0.14)
        ])

        for attempt in 1...3 {
            if tapIDVSettingsButtonElement() {
                Thread.sleep(forTimeInterval: 1.2)
                if idvSettingsMenuIsVisible() {
                    log("[VPNTest] IDV settings opened via button on attempt \(attempt)")
                    return true
                }
            }

            for tap in taps {
                vpn.coordinate(withNormalizedOffset: tap).tap()
                Thread.sleep(forTimeInterval: 1.2)
                if idvSettingsMenuIsVisible() {
                    log("[VPNTest] IDV settings opened on attempt \(attempt)")
                    return true
                }
            }
        }

        log("[VPNTest] IDV settings did not open; OCR: \(debugOCR())")
        return false
    }

    private func tapIDVSettingsButtonElement() -> Bool {
        for label in ["menu button white", "settings"] {
            let button = vpn.buttons[label]
            if button.exists {
                log("[VPNTest] tapping IDV settings button element: \"\(label)\"")
                button.tap()
                return true
            }
        }

        let menuButtons = vpn.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "menu"))
        if menuButtons.count > 0 {
            let button = menuButtons.element(boundBy: 0)
            log("[VPNTest] tapping IDV menu-like button element: \"\(button.label)\"")
            button.tap()
            return true
        }

        log("[VPNTest] IDV settings button element not found")
        return false
    }

    private func idvSettingsMenuIsVisible() -> Bool {
        guard vpnBundleID == "com.actmobile.dashvpn" else { return false }
        let text = ocrText()
        let settingsSignals = [
            "Tools", "My IP", "MylP", "Speed Test", "Info & Legal",
            "About Us", "About us", "Privacy Policy", "Privacy policy", "Terms of use",
            "Settings", "About VPN", "Alternate IP", "Enable Boost Speed",
            "Enable Super Ad Block", "Manage Premium Plan", "Restore Previous Purchase"
        ]
        return settingsSignals.contains { text.localizedCaseInsensitiveContains($0) }
            && !idvServicePageIsVisible(in: text)
            && !pickerIsOpen(in: text)
    }

    private func closeIDVSettings() {
        let taps = [
            CGVector(dx: 0.90, dy: 0.10),
            CGVector(dx: 0.90, dy: 0.14),
            CGVector(dx: 0.50, dy: 0.93)
        ]

        for tap in taps {
            vpn.coordinate(withNormalizedOffset: tap).tap()
            Thread.sleep(forTimeInterval: 1)
            if homeScreenIsVisible() && !idvSettingsMenuIsVisible() {
                return
            }
        }
    }

    private func setSettingsSwitch(label: String, enabled: Bool) -> Bool {
        for attempt in 1...3 {
            if settingsSwitchIsEnabled(label: label) == enabled {
                return true
            }

            if let toggle = settingsSwitchElement(label: label) {
                toggle.tap()
                Thread.sleep(forTimeInterval: 1)
                continue
            }

            guard let line = ocrLines().first(where: { $0.text.localizedCaseInsensitiveContains(label) }) else {
                log("[VPNTest] settings switch \"\(label)\" not found on attempt \(attempt)")
                return false
            }

            vpn.coordinate(withNormalizedOffset: CGVector(dx: 0.83, dy: line.centerY)).tap()
            Thread.sleep(forTimeInterval: 1)
        }

        return settingsSwitchIsEnabled(label: label) == enabled
    }

    private func settingsSwitchIsEnabled(label: String) -> Bool {
        if let toggle = settingsSwitchElement(label: label),
           let value = toggle.value as? String {
            return value == "1" || value.localizedCaseInsensitiveContains("on")
        }

        let switches = vpn.switches.allElementsBoundByIndex
        guard let line = ocrLines().first(where: { $0.text.localizedCaseInsensitiveContains(label) }) else {
            return false
        }
        let screenHeight = max(vpn.frame.height, 1)

        if let toggle = switches.min(by: {
            abs(($0.frame.midY / screenHeight) - line.centerY) < abs(($1.frame.midY / screenHeight) - line.centerY)
        }) {
            if let value = toggle.value as? String {
                return value == "1" || value.localizedCaseInsensitiveContains("on")
            }
        }

        return false
    }

    private func settingsSwitchElement(label: String) -> XCUIElement? {
        vpn.switches.allElementsBoundByIndex.first {
            $0.label.localizedCaseInsensitiveContains(label)
        }
    }

    private func closeIFUSettings() {
        if closePremiumPaywallIfPresent() {
            return
        }

        let taps = [
            CGVector(dx: 0.90, dy: 0.10),
            CGVector(dx: 0.07, dy: 0.93),
            CGVector(dx: 0.16, dy: 0.96)
        ]

        for tap in taps {
            vpn.coordinate(withNormalizedOffset: tap).tap()
            Thread.sleep(forTimeInterval: 1)
            if homeScreenIsVisible() {
                return
            }
        }

        _ = closePremiumPaywallIfPresent()
    }

    private func premiumPaywallIsVisible() -> Bool {
        let text = ocrText()
        return text.localizedCaseInsensitiveContains("GO PREMIUM")
            || text.localizedCaseInsensitiveContains("RESTORE PREVIOUS PURCHASES")
            || (text.localizedCaseInsensitiveContains("Ultra-Fast Servers")
                && text.localizedCaseInsensitiveContains("WEEKLY")
                && text.localizedCaseInsensitiveContains("MONTHLY"))
    }

    private func closePremiumPaywallIfPresent() -> Bool {
        guard premiumPaywallIsVisible() else { return false }
        log("[VPNTest] closing premium paywall")
        for tap in [
            CGVector(dx: 0.07, dy: 0.09),
            CGVector(dx: 0.10, dy: 0.10),
            CGVector(dx: 0.90, dy: 0.10)
        ] {
            vpn.coordinate(withNormalizedOffset: tap).tap()
            Thread.sleep(forTimeInterval: 1.2)
            if !premiumPaywallIsVisible() {
                return true
            }
        }
        return !premiumPaywallIsVisible()
    }

    private func applyIDVHomeFeatureToggles() -> Bool {
        _ = closeIDVServicePageIfPresent()
        guard homeScreenIsVisible() else {
            log("[VPNTest] IDV feature preflight failed: home screen not visible; OCR: \(debugOCR())")
            return false
        }

        let adblockOK = setIDVHomeFeature(named: "Ad Block", enabled: adblockMode == "on", fallback: CGVector(dx: 0.34, dy: 0.22))
        let boostOK = setIDVHomeFeature(named: "Accelerate", enabled: boostMode == "on", fallback: CGVector(dx: 0.66, dy: 0.22))
        log("[VPNTest] IDV feature preflight: adblock \(adblockOK ? adblockMode : "not \(adblockMode)"), boost \(boostOK ? boostMode : "not \(boostMode)")")

        _ = closeIDVServicePageIfPresent()
        return adblockOK && boostOK && homeScreenIsVisible()
    }

    private func setIDVHomeFeature(named name: String, enabled: Bool, fallback: CGVector) -> Bool {
        let before = ocrText()
        if !before.localizedCaseInsensitiveContains(name) {
            return false
        }

        guard enabled else {
            return true
        }

        let line = ocrLines().first { $0.text.localizedCaseInsensitiveContains(name) }
        let tap = line.map { CGVector(dx: $0.centerX, dy: $0.centerY) } ?? fallback
        vpn.coordinate(withNormalizedOffset: tap).tap()
        Thread.sleep(forTimeInterval: 1.5)
        _ = closeIDVServicePageIfPresent()

        let after = ocrText()
        return after.localizedCaseInsensitiveContains(name)
            || homeScreenIsVisible()
            || connectedTextIsVisible(in: after)
    }

    private func commitIDVRegionSelection(_ name: String) {
        guard pickerIsOpen() else { return }

        if idvAlreadySelectedDialogIsVisible() {
            log("[VPNTest] IDV region already selected; closing dialog")
            vpn.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.54)).tap()
            Thread.sleep(forTimeInterval: 1)
        }

        if let action = idvConnectActionText() {
            log("[VPNTest] IDV committing selected region via \(action)")
            vpn.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.92)).tap()
            Thread.sleep(forTimeInterval: 2)
            return
        }

        log("[VPNTest] IDV could not find bottom Connect to action for \(name); OCR: \(debugOCR())")
    }

    private func idvConnectActionText() -> String? {
        ocrLines()
            .map(\.text)
            .first { $0.localizedCaseInsensitiveContains("Connect to") }
    }

    private func idvAlreadySelectedDialogIsVisible() -> Bool {
        ocrText().localizedCaseInsensitiveContains("Region already selected")
    }

    private func tapAndRememberRegion(_ row: OCRLine) -> String {
        vpn.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: row.centerY)).tap()
        Thread.sleep(forTimeInterval: 2)
        previousSelectedRegionName = row.text
        selectedRegionKeys.insert(normalizedRegionName(row.text))
        return row.text
    }

    private func alignPickerPage(targetPage: Int) {
        guard pickerIsOpen() else { return }
        if targetPage == 0 {
            alignPickerToFirstPageIfNeeded()
            pickerCursorPage = 0
            return
        }

        if targetPage < pickerCursorPage {
            for _ in 0..<(pickerCursorPage - targetPage) {
                vpn.swipeDown()
                Thread.sleep(forTimeInterval: 0.45)
            }
        } else if targetPage > pickerCursorPage {
            for _ in 0..<(targetPage - pickerCursorPage) {
                vpn.swipeUp()
                Thread.sleep(forTimeInterval: 0.55)
            }
        }
        pickerCursorPage = targetPage
    }

    private func alignPickerToFirstPageIfNeeded() {
        for attempt in 0..<6 {
            let rows = visibleRegionRows()
            if rows.contains(where: { normalizedRegionName($0.text) == "us east" }) {
                return
            }
            let rowNames = rows.map(\.text).joined(separator: " | ")
            log("[VPNTest] first page alignment attempt \(attempt + 1); visible rows: \(rowNames)")
            vpn.swipeDown()
            Thread.sleep(forTimeInterval: 0.45)
        }
    }

    private func buildRegionCatalog() -> [RegionCatalogEntry] {
        guard openRegionList() else {
            log("[VPNTest] catalog scan failed: picker did not open")
            return []
        }

        scrollPickerToTop()

        var names: [String] = []
        var seen = Set<String>()
        var stablePages = 0

        for page in 0..<30 {
            let rows = visibleRegionRows()
            let rowNames = rows.map(\.text)
            log("[VPNTest] catalog page \(page + 1): \(rowNames.joined(separator: " | "))")

            let before = names.count
            for name in rowNames {
                let key = normalizedRegionName(name)
                guard !key.isEmpty, !seen.contains(key) else { continue }
                seen.insert(key)
                names.append(name)
            }

            stablePages = names.count == before ? stablePages + 1 : 0
            if stablePages >= 2 { break }

            vpn.swipeUp()
            Thread.sleep(forTimeInterval: 0.8)
        }

        if names.first == "North America" {
            names.insert(contentsOf: ["US East", "Fastest"], at: 0)
        } else if names.first == "Fastest" {
            names.insert("US East", at: 0)
        }

        return names.enumerated().map { offset, name in
            RegionCatalogEntry(index: offset + 1, name: name)
        }
    }

    private func selectRegion(named name: String) -> Bool {
        guard openRegionList() else { return false }
        scrollPickerToTop()

        let target = normalizedRegionName(name)
        for page in 0..<30 {
            let rows = visibleRegionRows()
            log("[VPNTest] select \"\(name)\" page \(page + 1): \(rows.map(\.text).joined(separator: " | "))")
            if let row = rows.first(where: { normalizedRegionName($0.text) == target }) {
                vpn.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: row.centerY)).tap()
                Thread.sleep(forTimeInterval: 2)
                return true
            }

            vpn.swipeUp()
            Thread.sleep(forTimeInterval: 0.7)
        }

        if selectRegionBySearch(name) {
            return true
        }

        log("[VPNTest] could not find region \"\(name)\"; OCR: \(debugOCR())")
        return false
    }

    private func selectRegionBySearch(_ name: String) -> Bool {
        guard pickerIsOpen() || openRegionList() else { return false }
        let lines = ocrLines()
        let searchLine = lines.first { $0.text.localizedCaseInsensitiveContains("Search") }
        let searchY = searchLine?.centerY ?? 0.34
        log("[VPNTest] fallback search select \"\(name)\"")
        vpn.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: searchY)).tap()
        Thread.sleep(forTimeInterval: 0.5)
        vpn.typeText(name)
        Thread.sleep(forTimeInterval: 1.5)

        let target = normalizedRegionName(name)
        let rows = visibleRegionRows()
        log("[VPNTest] search results \"\(name)\": \(rows.map(\.text).joined(separator: " | "))")
        if let row = rows.first(where: { normalizedRegionName($0.text) == target }) {
            vpn.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: row.centerY)).tap()
            Thread.sleep(forTimeInterval: 2)
            return true
        }

        vpn.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: name.count))
        return false
    }

    private func scrollPickerToTop() {
        guard pickerIsOpen() else { return }
        for _ in 0..<14 {
            vpn.swipeDown()
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    private func openRegionList() -> Bool {
        if pickerIsOpen() { return true }
        _ = closeServerIssuesIfPresent()
        _ = closeIDVServicePageIfPresent()
        if pickerIsOpen() { return true }
        let lines = ocrLines()
        var taps: [CGVector] = []
        if let currentLocation = lines.first(where: { $0.text.localizedCaseInsensitiveContains("Current Location") }) {
            let rowY = min(currentLocation.centerY + 0.025, 0.34)
            taps.append(CGVector(dx: 0.30, dy: rowY))
            taps.append(CGVector(dx: 0.50, dy: rowY))
            taps.append(CGVector(dx: 0.84, dy: rowY))
        }
        if let selectedLocation = lines.first(where: { line in
            let minY: CGFloat = vpnBundleID == "com.actmobile.dashvpn" ? 0.65 : 0.18
            return line.centerY > minY && line.centerY < 0.80 && isLikelySelectedLocation(line.text)
        }) {
            taps.append(CGVector(dx: min(max(selectedLocation.centerX, 0.20), 0.85), dy: selectedLocation.centerY))
            taps.append(CGVector(dx: 0.84, dy: selectedLocation.centerY))
        }
        if vpnBundleID == "com.actmobile.dashvpn" {
            taps.append(contentsOf: [
                CGVector(dx: 0.29, dy: 0.78),
                CGVector(dx: 0.50, dy: 0.78),
                CGVector(dx: 0.84, dy: 0.78)
            ])
        }
        taps.append(contentsOf: [
            CGVector(dx: 0.84, dy: 0.33),
            CGVector(dx: 0.50, dy: 0.33),
            CGVector(dx: 0.84, dy: 0.43),
            CGVector(dx: 0.50, dy: 0.43)
        ])
        for tap in taps {
            log("[VPNTest] opening picker tap @\(String(format: "%.2f", tap.dx)),\(String(format: "%.2f", tap.dy))")
            vpn.coordinate(withNormalizedOffset: tap).tap()
            Thread.sleep(forTimeInterval: 1.5)
            if pickerIsOpen() { return true }
        }
        log("[VPNTest] picker did not open; OCR: \(debugOCR())")
        return false
    }

    private func isLikelySelectedLocation(_ text: String) -> Bool {
        let ignored = ["VPN", "Powered", "Current", "Service", "Off", "Earn", "Status", "Connect", "BOOST", "PREMIUM", "BROWSER", "WhatsApp", "Fetching", "IP", "ADS", "Ad Block", "Accelerate"]
        return text.count > 1
            && text.rangeOfCharacter(from: .letters) != nil
            && !text.contains(".")
            && !text.contains(":")
            && !text.contains(",")
            && !ignored.contains(where: { text.localizedCaseInsensitiveContains($0) })
    }

    private func pickerIsOpen() -> Bool {
        pickerIsOpen(in: ocrText())
    }

    private func pickerIsOpen(in text: String) -> Bool {
        return text.localizedCaseInsensitiveContains("Choose Where")
            || text.localizedCaseInsensitiveContains("Search")
            || text.localizedCaseInsensitiveContains("Connect to")
    }

    private func waitForMainScreen(timeout: TimeInterval) -> Bool {
        waitForText(containing: "Connect VPN", timeout: timeout) || waitForText(containing: "Current Location", timeout: 1)
    }

    private func verifyHomeScreenWithOneRelaunchRetry() -> Bool {
        _ = closeServerIssuesIfPresent()
        _ = closeFeedbackIfPresent()
        if waitForHomeScreenStable(for: 5, timeout: 35) {
            return true
        }

        log("[VPNTest] homepage stable check failed; relaunching app for one retry")
        vpn.terminate()
        Thread.sleep(forTimeInterval: 2)
        vpn.activate()
        guard vpn.wait(for: .runningForeground, timeout: 20) else {
            log("[VPNTest] app did not return foreground during homepage retry")
            return false
        }
        closeCommonInterruptions()
        Thread.sleep(forTimeInterval: 2)
        _ = closeServerIssuesIfPresent()
        _ = closeFeedbackIfPresent()
        return waitForHomeScreenStable(for: 5, timeout: 35)
    }

    private func waitForHomeScreenStable(for seconds: TimeInterval, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var stableStart: Date?

        while Date() < deadline {
            if homeScreenIsVisible() {
                if stableStart == nil {
                    stableStart = Date()
                }
                if let stableStart, Date().timeIntervalSince(stableStart) >= seconds {
                    return true
                }
            } else {
                stableStart = nil
            }
            Thread.sleep(forTimeInterval: 0.5)
        }

        log("[VPNTest] homepage was not stable for \(Int(seconds))s; OCR: \(debugOCR())")
        return false
    }

    private func homeScreenIsVisible() -> Bool {
        let text = ocrText()
        let hasNoBlockingOverlay = !pickerIsOpen(in: text)
            && !serverIssuesPageIsVisible(in: text)
            && !sessionEndedFeedbackIsVisible(in: text)
            && !ratingFeedbackIsVisible(in: text)
            && !idvServicePageIsVisible(in: text)
        let ifuHome = (text.localizedCaseInsensitiveContains("VPN US")
            || text.localizedCaseInsensitiveContains("Free VPN.org"))
            && text.localizedCaseInsensitiveContains("Current Service")
            && text.localizedCaseInsensitiveContains("Status")
            && (text.localizedCaseInsensitiveContains("Connect VPN")
                || text.localizedCaseInsensitiveContains("Connected")
                || text.localizedCaseInsensitiveContains("Connecting VPN"))
        let idvHome = vpnBundleID == "com.actmobile.dashvpn"
            && text.localizedCaseInsensitiveContains("Unsecured Connection")
            && text.localizedCaseInsensitiveContains("VPN")
            && (text.localizedCaseInsensitiveContains("Ad Block")
                || text.localizedCaseInsensitiveContains("Accelerate")
                || text.localizedCaseInsensitiveContains("General"))

        return hasNoBlockingOverlay && (ifuHome || idvHome)
    }

    private func waitForBaselineReady(timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let text = ocrLines().map(\.text).joined(separator: " | ")
            let ifuReady = text.localizedCaseInsensitiveContains("Current Location")
                && text.localizedCaseInsensitiveContains("Connect VPN")
            let idvReady = vpnBundleID == "com.actmobile.dashvpn"
                && text.localizedCaseInsensitiveContains("Unsecured Connection")
                && text.localizedCaseInsensitiveContains("VPN")
            if (ifuReady || idvReady),
               !text.localizedCaseInsensitiveContains("Fetching IP"),
               !text.localizedCaseInsensitiveContains("Disconnecting VPN"),
               !text.localizedCaseInsensitiveContains("Switching") {
                return
            }
            Thread.sleep(forTimeInterval: 1)
        }
        log("[VPNTest] baseline did not fully settle; continuing with OCR: \(debugOCR())")
    }

    private func prepareDisconnectedBaseline() {
        _ = closePremiumPaywallIfPresent()
        _ = closeServerIssuesIfPresent()
        _ = closeFeedbackIfPresent()

        if pickerIsOpen() {
            log("[VPNTest] picker already open at startup; ordinal selection will reset it")
            return
        }

        if isConnectedLike() || textExists("Connecting") || textExists("Disconnecting") {
            log("[VPNTest] preflight disconnect from existing connected state")
            tapDisconnectToggle()
            _ = waitForDisconnected(timeout: 25)
            _ = closeFeedbackIfPresent()
        }

        if isConnectedLike() || textExists("Connecting") || textExists("Disconnecting") {
            log("[VPNTest] preflight disconnect after cleanup")
            tapDisconnectToggle()
            _ = waitForDisconnected(timeout: 25)
            _ = closeFeedbackIfPresent()
            Thread.sleep(forTimeInterval: 2)
        }

        waitForBaselineReady(timeout: 35)
    }

    private func ensureConnected() -> Bool {
        if isConnectedLike() { return true }

        if waitForConnectedOrTerminal(until: Date().addingTimeInterval(10)) { return true }
        log("[VPNTest] not Connected within 10s; allowing 10s alternate IP window")

        if waitForConnectedOrTerminal(until: Date().addingTimeInterval(10)) { return true }
        log("[VPNTest] connect timed out after 10s + 10s alternate IP window; OCR: \(debugOCR())")
        return false
    }

    private func waitForConnectedOrTerminal(until deadline: Date) -> Bool {
        while Date() < deadline {
            let text = ocrText()
            if connectedTextIsVisible(in: text) { return true }
            if sessionEndedFeedbackIsVisible(in: text) && !networkSwitchIsActive(in: text) {
                log("[VPNTest] connect ended before Connected; OCR: \(debugOCR(from: text))")
                return false
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    private func settleSelectedRegionForConnect() {
        Thread.sleep(forTimeInterval: 1)
        for attempt in 1...2 {
            _ = closeFeedbackIfPresent()
            let text = ocrText()
            if text.localizedCaseInsensitiveContains("Connect VPN"),
               !text.localizedCaseInsensitiveContains("Connecting"),
               !text.localizedCaseInsensitiveContains("Disconnecting") {
                return
            }

            if text.localizedCaseInsensitiveContains("Connected")
                || text.localizedCaseInsensitiveContains("Connecting")
                || text.localizedCaseInsensitiveContains("Disconnecting") {
                log("[VPNTest] selected region is not connect-ready; cleanup attempt \(attempt)")
                tapDisconnectToggle()
                _ = waitForDisconnected(timeout: 20)
                _ = closeFeedbackIfPresent()
            }
        }
    }

    private func holdConnected(for seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if !isConnectedLike() || sessionEndedFeedbackIsVisible() {
                log("[VPNTest] hold broke before \(Int(seconds))s; OCR: \(debugOCR())")
                return false
            }
            Thread.sleep(forTimeInterval: 1)
        }
        return true
    }

    private func isConnectedLike() -> Bool {
        let text = ocrText()
        if text.localizedCaseInsensitiveContains("Connect VPN"),
           !text.localizedCaseInsensitiveContains("Disconnecting") {
            return false
        }
        return connectedTextIsVisible(in: text)
    }

    private func connectedTextIsVisible(in text: String) -> Bool {
        if text.localizedCaseInsensitiveContains("Connected") {
            return true
        }
        return vpnBundleID == "com.actmobile.dashvpn"
            && text.localizedCaseInsensitiveContains("VPN Safe Connection")
    }

    private func connectAttemptStarted() -> Bool {
        let text = ocrText()
        return text.localizedCaseInsensitiveContains("Connected")
            || text.localizedCaseInsensitiveContains("Connecting")
            || text.localizedCaseInsensitiveContains("Switching")
            || text.localizedCaseInsensitiveContains("network switch")
    }

    private func tapConnectToggle(alternate: Bool = false) {
        let lines = ocrLines()
        if let toggle = lines.first(where: {
            $0.centerY > 0.78 && $0.centerY < 0.92 &&
            $0.text.localizedCaseInsensitiveContains("Connect VPN")
        }) {
            let y = max(toggle.centerY - 0.01, 0.82)
            vpn.coordinate(withNormalizedOffset: CGVector(dx: alternate ? 0.72 : 0.82, dy: y)).tap()
            return
        }

        vpn.coordinate(withNormalizedOffset: CGVector(dx: alternate ? 0.72 : 0.82, dy: 0.85)).tap()
    }

    private func tapDisconnectToggle(alternate: Bool = false) {
        if vpnBundleID == "com.actmobile.dashvpn" {
            vpn.coordinate(withNormalizedOffset: CGVector(dx: alternate ? 0.50 : 0.13, dy: 0.93)).tap()
            return
        }

        let lines = ocrLines()
        if let toggle = lines.first(where: {
            $0.centerY > 0.78 && $0.centerY < 0.92 &&
            ($0.text.localizedCaseInsensitiveContains("Connected")
                || $0.text.localizedCaseInsensitiveContains("Disconnect"))
        }) {
            let y = max(toggle.centerY - 0.01, 0.82)
            vpn.coordinate(withNormalizedOffset: CGVector(dx: alternate ? 0.50 : 0.82, dy: y)).tap()
            return
        }

        vpn.coordinate(withNormalizedOffset: CGVector(dx: alternate ? 0.50 : 0.82, dy: 0.85)).tap()
    }

    private func disconnectAndCloseFeedback() -> Bool {
        tapDisconnectToggle()
        if !waitForDisconnected(timeout: 20) {
            tapDisconnectToggle(alternate: true)
            _ = waitForDisconnected(timeout: 10)
        }
        return closeFeedbackIfPresent()
    }

    private func waitForDisconnected(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let text = ocrText()
            if serverIssuesPageIsVisible(in: text) {
                _ = closeServerIssuesIfPresent()
                return true
            }
            if sessionEndedFeedbackIsVisible(in: text) {
                return true
            }
            if text.localizedCaseInsensitiveContains("Connect VPN"),
               !text.localizedCaseInsensitiveContains("Disconnecting"),
               !text.localizedCaseInsensitiveContains("Connected") {
                return true
            }
            Thread.sleep(forTimeInterval: 1)
        }
        log("[VPNTest] disconnect cleanup timed out; OCR: \(debugOCR())")
        return false
    }

    private func readIdentity() -> Identity {
        let lines = ocrLines()
        let strictIP = lines.first { $0.text.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil }?.text
        let looseIP = lines.first {
            vpnBundleID == "com.actmobile.dashvpn"
                && $0.text.range(of: #"^\d[\d.]{6,}\d$"#, options: .regularExpression) != nil
        }?.text
        let ip = strictIP ?? looseIP ?? ""
        if vpnBundleID == "com.actmobile.dashvpn" {
            let location = lines.first { label in
                label.centerY > 0.70 && label.centerY < 0.82 &&
                isLikelySelectedLocation(label.text)
            }?.text ?? ""
            return Identity(ip: ip, location: location)
        }

        let location = lines.first { label in
            label.centerY > 0.18 && label.centerY < 0.25 &&
            label.text.contains(",") &&
            !label.text.localizedCaseInsensitiveContains("Powered by")
        }?.text ?? ""
        return Identity(ip: ip, location: location)
    }

    private func waitForReadableIdentity(timeout: TimeInterval) -> Identity {
        var last = Identity(ip: "", location: "")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let identity = readIdentity()
            if !identity.ip.isEmpty {
                last = identity
            }
            if !identity.ip.isEmpty,
               !identity.location.isEmpty,
               !textExists("Fetching IP"),
               !textExists("Connecting"),
               !textExists("Disconnecting") {
                return identity
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        log("[VPNTest] default identity not fully readable; last IP=\"\(last.ip)\", Location=\"\(last.location)\", OCR: \(debugOCR())")
        return last
    }

    private func waitForChangedIdentity(from defaultIdentity: Identity, timeout: TimeInterval) -> Identity {
        var last = Identity(ip: "", location: "")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if sessionEndedFeedbackIsVisible() {
                return last
            }

            let identity = readIdentity()
            if !identity.ip.isEmpty || (vpnBundleID == "com.actmobile.dashvpn" && !identity.location.isEmpty) {
                last = identity
            }
            if !identity.ip.isEmpty,
               identity.ip != defaultIdentity.ip,
               !identity.location.isEmpty,
               identity.location != defaultIdentity.location {
                return identity
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        log("[VPNTest] identity did not change in time; last IP=\"\(last.ip)\", Location=\"\(last.location)\", OCR: \(debugOCR())")
        return last
    }

    private func idvHasConnectedEvidence(for selected: String) -> Bool {
        guard vpnBundleID == "com.actmobile.dashvpn" else { return false }
        let text = ocrText()
        guard connectedTextIsVisible(in: text) else { return false }

        let selectedKey = normalizedRegionName(selected)
        if selectedKey.isEmpty || selectedKey == "fastest" {
            return true
        }

        if text.localizedCaseInsensitiveContains(selected) {
            return true
        }

        return ocrLines().contains { line in
            line.centerY > 0.70 && line.centerY < 0.82 &&
            normalizedRegionName(line.text) == selectedKey
        }
    }

    private func idvIdentityFallback(from identity: Identity, selected: String) -> Identity {
        guard vpnBundleID == "com.actmobile.dashvpn" else { return identity }
        return Identity(
            ip: identity.ip.isEmpty ? "OCR unavailable (VPN Safe Connection)" : identity.ip,
            location: identity.location.isEmpty ? selected : identity.location
        )
    }

    private func waitForDefaultIdentity(_ defaultIdentity: Identity, timeout: TimeInterval) -> Bool {
        guard !defaultIdentity.ip.isEmpty else {
            return waitForDisconnectedHome(timeout: timeout)
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if readIdentity().ip == defaultIdentity.ip { return true }
            Thread.sleep(forTimeInterval: 1)
        }
        return false
    }

    private func waitForDisconnectedHome(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let text = ocrText()
            let disconnectedIFU = text.localizedCaseInsensitiveContains("Connect VPN")
                && !text.localizedCaseInsensitiveContains("Connected")
                && !text.localizedCaseInsensitiveContains("Disconnecting")
            let disconnectedIDV = vpnBundleID == "com.actmobile.dashvpn"
                && text.localizedCaseInsensitiveContains("Unsecured Connection")
                && !connectedTextIsVisible(in: text)
                && !networkSwitchIsActive(in: text)
            if disconnectedIFU || disconnectedIDV {
                return true
            }
            Thread.sleep(forTimeInterval: 1)
        }
        log("[VPNTest] default disconnected home did not return; OCR: \(debugOCR())")
        return false
    }

    private func closeFeedbackIfPresent() -> Bool {
        Thread.sleep(forTimeInterval: 1)
        if closeServerIssuesIfPresent() { return true }
        if closeIDVServicePageIfPresent() { return true }
        let shouldCloseAdsBlocked = vpnBundleID != "com.actmobile.dashvpn" && textExists("Ads blocked")
        guard sessionEndedFeedbackIsVisible() || shouldCloseAdsBlocked || ratingFeedbackIsVisible() else {
            return true
        }

        if ratingFeedbackIsVisible() {
            vpn.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.60)).tap()
            Thread.sleep(forTimeInterval: 1)
            return !ratingFeedbackIsVisible()
        }

        vpn.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.58)).tap()
        Thread.sleep(forTimeInterval: 1)
        if !sessionEndedFeedbackIsVisible() {
            return true
        }

        vpn.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.21)).tap()
        Thread.sleep(forTimeInterval: 1)
        if sessionEndedFeedbackIsVisible() {
            vpn.swipeDown()
            Thread.sleep(forTimeInterval: 1)
        }
        return !sessionEndedFeedbackIsVisible()
    }

    private func closeIDVServicePageIfPresent() -> Bool {
        guard vpnBundleID == "com.actmobile.dashvpn" else { return false }
        let text = ocrText()
        guard idvServicePageIsVisible(in: text) else {
            return false
        }

        log("[VPNTest] closing IDV service page")
        for tap in [
            CGVector(dx: 0.19, dy: 0.93),
            CGVector(dx: 0.91, dy: 0.93),
            CGVector(dx: 0.50, dy: 0.93)
        ] {
            vpn.coordinate(withNormalizedOffset: tap).tap()
            Thread.sleep(forTimeInterval: 1.2)
            if !idvServicePageIsVisible(in: ocrText()) {
                return true
            }
        }
        return !idvServicePageIsVisible(in: ocrText())
    }

    private func idvServicePageIsVisible(in text: String) -> Bool {
        text.localizedCaseInsensitiveContains("Select a Service")
            || text.localizedCaseInsensitiveContains("Choose the streaming service")
            || text.localizedCaseInsensitiveContains("change regions if it doesn't work")
    }

    private func sessionEndedFeedbackIsVisible() -> Bool {
        textExists("VPN session ended") || textExists("Try Alternate Server")
    }

    private func sessionEndedFeedbackIsVisible(in text: String) -> Bool {
        text.localizedCaseInsensitiveContains("VPN session ended")
            || text.localizedCaseInsensitiveContains("Try Alternate Server")
    }

    private func serverIssuesPageIsVisible() -> Bool {
        serverIssuesPageIsVisible(in: ocrText())
    }

    private func serverIssuesPageIsVisible(in text: String) -> Bool {
        if vpnBundleID == "com.actmobile.dashvpn", pickerIsOpen(in: text) {
            return false
        }
        return text.localizedCaseInsensitiveContains("Server Connection Issues")
            || text.localizedCaseInsensitiveContains("Try Another Region")
            || text.localizedCaseInsensitiveContains("Alternate IP")
            || text.localizedCaseInsensitiveContains("Reset VPN Prof")
    }

    private func closeServerIssuesIfPresent() -> Bool {
        var text = ocrText()
        guard serverIssuesPageIsVisible(in: text) else { return false }

        log("[VPNTest] closing server connection issues page")
        for _ in 0..<3 {
            if !serverIssuesPageIsVisible(in: text) { return true }

            if let cancel = ocrLines().first(where: { $0.text.localizedCaseInsensitiveContains("Cancel") }) {
                vpn.coordinate(withNormalizedOffset: CGVector(dx: cancel.centerX, dy: cancel.centerY)).tap()
            } else {
                vpn.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.70)).tap()
            }

            Thread.sleep(forTimeInterval: 1.5)
            text = ocrText()
        }

        if serverIssuesPageIsVisible(in: text) {
            vpn.swipeDown()
            Thread.sleep(forTimeInterval: 1)
        }

        return !serverIssuesPageIsVisible()
    }

    private func ratingFeedbackIsVisible() -> Bool {
        ratingFeedbackIsVisible(in: ocrText())
    }

    private func ratingFeedbackIsVisible(in text: String) -> Bool {
        return text.localizedCaseInsensitiveContains("Enjoying our VPN")
            || text.localizedCaseInsensitiveContains("Leave a Review")
            || text.localizedCaseInsensitiveContains("Maybe later")
    }

    private func networkSwitchIsActive() -> Bool {
        networkSwitchIsActive(in: ocrText())
    }

    private func networkSwitchIsActive(in text: String) -> Bool {
        let activeSignals = [
            "Switching", "network switch", "Finding best connection", "Applying security",
            "Finalizing new connection", "Fetching IP", "Connecting you", "Disconnecting VPN"
        ]
        return activeSignals.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private func visibleRegionRows() -> [OCRLine] {
        if vpnBundleID == "com.actmobile.dashvpn", idvServicePageIsVisible(in: ocrText()) {
            return []
        }

        let ignored = [
            "Choose", "Fetching", "Search", "Connect to", "Current", "Service", "Status",
            "Connect VPN", "Connected", "Connecting", "Disconnecting", "Powered by", "VPN US",
            "Ads blocked", "session ended", "Try Alternate", "Alternate IP", "Buy Premium",
            "Premium", "Ratings", "Reviews", "Get", "App Store", "ORIGINAL", "Change Region",
            "Region already selected", "Okay"
        ]

        return ocrLines()
            .filter { line in
                let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let idvNoise = vpnBundleID == "com.actmobile.dashvpn"
                    && (trimmed == "* *"
                        || trimmed == "*"
                        || trimmed.rangeOfCharacter(from: .letters) == nil)
                return line.centerY > 0.31 && line.centerY < 0.98 &&
                line.centerY < 0.93 &&
                trimmed.count > 2 &&
                !idvNoise &&
                !trimmed.contains(".") &&
                !trimmed.contains(",") &&
                !ignored.contains(where: { trimmed.localizedCaseInsensitiveContains($0) })
            }
            .sorted { $0.centerY < $1.centerY }
    }

    private func normalizedRegionName(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func waitForText(containing text: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if textExists(text) { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    private func textExists(_ text: String) -> Bool {
        ocrLines().contains { $0.text.localizedCaseInsensitiveContains(text) }
    }

    private func ocrText() -> String {
        ocrLines().map(\.text).joined(separator: " | ")
    }

    private func ocrLines() -> [OCRLine] {
        ensureVPNForegroundForOCR()
        return autoreleasepool {
            guard let image = UIImage(data: XCUIScreen.main.screenshot().pngRepresentation),
                  let cgImage = image.cgImage else {
                return []
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            do {
                try handler.perform([request])
            } catch {
                return []
            }

            return (request.results ?? []).compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let box = observation.boundingBox
                return OCRLine(
                    text: candidate.string.trimmingCharacters(in: .whitespacesAndNewlines),
                    centerX: CGFloat(box.midX),
                    centerY: 1.0 - CGFloat(box.midY)
                )
            }
        }
    }

    private func ensureVPNForegroundForOCR() {
        guard vpn.state != .runningForeground else { return }
        vpn.activate()
        _ = vpn.wait(for: .runningForeground, timeout: 5)
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func debugOCR() -> String {
        ocrLines()
            .map { "\($0.text)@\(String(format: "%.2f", $0.centerX)),\(String(format: "%.2f", $0.centerY))" }
            .joined(separator: " | ")
    }

    private func debugOCR(from text: String) -> String {
        text
    }

    private func closeCommonInterruptions() {
        let possibleButtons = ["Allow", "OK", "Not Now", "Cancel", "Close"]
        for title in possibleButtons where vpn.buttons[title].exists {
            vpn.buttons[title].tap()
        }
    }

    private func log(_ text: String) {
        print(text)
        fflush(stdout)
    }
}

private struct Identity {
    let ip: String
    let location: String
}

private struct OCRLine {
    let text: String
    let centerX: CGFloat
    let centerY: CGFloat
}

private struct RegionCatalogEntry {
    let index: Int
    let name: String
}

private struct SettingsOption {
    let name: String
    let matchTexts: [String]
    let expectedSignals: [String]
}

private enum RuntimeConfig {
    static func string(_ key: String) -> String? {
        if let env = ProcessInfo.processInfo.environment[key], !env.isEmpty {
            return env
        }
        let prefix = "-\(key)="
        return ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix(prefix) })
            .map { String($0.dropFirst(prefix.count)) }
    }

    static func int(_ key: String) -> Int? {
        string(key).flatMap(Int.init)
    }
}

private enum GeneratedDefaults {
    static let vpnAppBundleID = "org.freevpn.vpn.us"
    static let regionLimit = 250
    static let holdSeconds = 10
    static let startIndex = 1
    static let anchorRegion = ""
    static let boostMode = "on"
    static let adblockMode = "on"
    static let testMode = "full"
}
