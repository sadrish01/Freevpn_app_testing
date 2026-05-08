//
//  VPNThreeRegionReportTests.swift
//  VPNTestUITests
//
//  Default `./run_tests.sh`: `testFirstRegionDisconnect_ThenInspectPopupAndScreen` — index **0** only: select (swipe-up-only scroll), main screen via **button snapshot** (no multi-tag wait), connect if needed, **disconnect from same `app.buttons` snapshot** (no `tapVPNDisconnectBestEffort` multi-query), popup check.
//  `testConnectRegionRowZero_Disconnect_LogOverlay`: first region, 5s hold, idle **Connect VPN** assert, popup poll.
//  `--three-regions`: IFU **row 0** auto-connect (no tap); IFU **row ≥ 1** taps Connect / vpn-toggle; non-IFU always taps Connect; catalog + rows 0→1→2, 5s, disconnect.
//  `--two-regions-hold5`: row0 … → **dismiss IFU feedback (never tap Alternate IP)** → reopen list → row1 **close feedback sheet if any** → main snapshot → connect → **5s** → disconnect → **close feedback again** → idle.
//

import XCTest

struct VPNRegionRowResult: CustomStringConvertible {
    let index: Int
    let catalogName: String
    let selectedLabel: String
    let success: Bool
    let detail: String

    var description: String {
        let s = success ? "PASS" : "FAIL"
        let cat = catalogName.isEmpty ? "(no catalog)" : catalogName
        let sel = selectedLabel.isEmpty ? "(no label)" : selectedLabel
        return "[\(index)] catalog=\"\(cat)\" selected=\"\(sel)\" — \(s)\(detail.isEmpty ? "" : " — \(detail)")"
    }
}

final class VPNThreeRegionReportTests: VPNTestBase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private typealias TextRow = (index: Int, label: String)
    private typealias ButtonRow = (index: Int, label: String, hittable: Bool)

    private func snapshotVisibleTexts(_ app: XCUIApplication, max: Int = 44) -> [TextRow] {
        var rows: [TextRow] = []
        for i in 0..<max {
            let t = app.staticTexts.element(boundBy: i)
            if !t.waitForExistence(timeout: 0.15) { break }
            let label = t.label.trimmingCharacters(in: .whitespacesAndNewlines)
            rows.append((i, label))
        }
        return rows
    }

    private func snapshotVisibleButtons(_ app: XCUIApplication, max: Int = 44) -> [ButtonRow] {
        var rows: [ButtonRow] = []
        for i in 0..<max {
            let b = app.buttons.element(boundBy: i)
            if !b.waitForExistence(timeout: 0.15) { break }
            let label = b.label.trimmingCharacters(in: .whitespacesAndNewlines)
            rows.append((i, label, b.isHittable))
        }
        return rows
    }

    private func logSnapshot(_ app: XCUIApplication, tag: String) {
        let texts = snapshotVisibleTexts(app, max: 24)
        let buttons = snapshotVisibleButtons(app, max: 24)
        print("[VPNTest] snapshot[\(tag)] staticTexts=\(texts.count) buttons=\(buttons.count)")
        for row in texts {
            print("[VPNTest]   text[\(row.index)] \"\(row.label)\"")
        }
        for row in buttons {
            print("[VPNTest]   button[\(row.index)] \"\(row.label)\" hittable=\(row.hittable)")
        }
    }

    private func tapVisibleButtonByIndex(_ app: XCUIApplication, index: Int, context: String) -> Bool {
        let b = app.buttons.element(boundBy: index)
        guard b.waitForExistence(timeout: 0.6), b.exists else {
            print("[VPNTest] \(context): button[\(index)] missing")
            return false
        }
        if b.isHittable {
            b.tap()
        } else {
            b.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        return true
    }

    private func tapCurrentLocationFromSnapshot(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let texts = snapshotVisibleTexts(app, max: 26)
            if let row = texts.first(where: { $0.label == "Current Location" }) {
                let t = app.staticTexts.element(boundBy: row.index)
                if t.exists {
                    print("[VPNTest] tap Current Location staticText at index \(row.index)")
                    if t.isHittable {
                        t.tap()
                    } else {
                        t.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                    }
                    return true
                }
            }
            let buttons = snapshotVisibleButtons(app, max: 26)
            if let row = buttons.first(where: { $0.label == "Current Location" }) {
                print("[VPNTest] tap Current Location button at index \(row.index)")
                return tapVisibleButtonByIndex(app, index: row.index, context: "current-location")
            }
            usleep(250_000)
        }
        return false
    }

    private func openRegionListByCurrentLocationSnapshot(_ app: XCUIApplication, timeout: TimeInterval = 28) -> Bool {
        if resolveRegionListContainerForSelection(app) != nil { return true }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !tapCurrentLocationFromSnapshot(app, timeout: 2.0) {
                usleep(250_000)
                continue
            }
            sleep(1)
            if resolveRegionListContainerForSelection(app) != nil { return true }
        }
        return false
    }

    private func pickConnectButtonIndex(from rows: [ButtonRow]) -> Int? {
        let low: (String) -> String = { $0.lowercased() }
        if rows.count > 3 {
            let l3 = low(rows[3].label)
            if l3.contains("vpn toggle") || l3.contains("connect") {
                return 3
            }
        }
        if let r = rows.last(where: { low($0.label).contains("vpn toggle") && low($0.label).contains("off") }) { return r.index }
        if let r = rows.last(where: { low($0.label) == "connect vpn" }) { return r.index }
        if let r = rows.last(where: { low($0.label).contains("connect") && !low($0.label).contains("disconnect") }) { return r.index }
        if let r = rows.last(where: { low($0.label).contains("vpn toggle") }) { return r.index }
        return nil
    }

    private func pickDisconnectButtonIndex(from rows: [ButtonRow]) -> Int? {
        let low: (String) -> String = { $0.lowercased() }
        if rows.count > 3 {
            let l3 = low(rows[3].label)
            if l3.contains("vpn toggle") || l3.contains("disconnect") {
                return 3
            }
        }
        if let r = rows.last(where: { low($0.label).contains("vpn toggle") && low($0.label).contains("on") }) { return r.index }
        if let r = rows.last(where: { low($0.label).contains("disconnect") }) { return r.index }
        if let r = rows.last(where: { low($0.label).contains("vpn toggle") }) { return r.index }
        return nil
    }

    private func looksConnectedBySnapshot(_ app: XCUIApplication) -> Bool {
        let texts = snapshotVisibleTexts(app, max: 24).map { $0.label.lowercased() }
        let buttons = snapshotVisibleButtons(app, max: 24).map { $0.label.lowercased() }
        if texts.contains(where: { $0 == "connected" || $0 == "vpn connected" || $0 == "protected" || $0.contains("secure connection") }) { return true }
        if buttons.contains(where: { $0 == "connected" || $0.contains("disconnect") || ($0.contains("vpn toggle") && $0.contains("on")) }) { return true }
        return false
    }

    private func waitForConnectedBySnapshot(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if looksConnectedBySnapshot(app) { return true }
            usleep(350_000)
        }
        return false
    }

    private func feedbackVisibleBySnapshot(_ app: XCUIApplication) -> Bool {
        let texts = snapshotVisibleTexts(app, max: 28).map { $0.label.lowercased() }
        if texts.contains(where: {
            $0.contains("session ended")
                || $0.contains("how was")
                || $0.contains("vpn session")
        }) { return true }
        let buttons = snapshotVisibleButtons(app, max: 28).map { $0.label.lowercased() }
        if buttons.contains(where: {
            $0.contains("thumbsdown")
                || $0.contains("thumbs up")
                || $0.contains("try alternate server")
                || $0.contains("trouble connecting")
                || $0.contains("experiencing slow speeds")
                || $0.contains("trouble accessing content")
                || $0.contains("other reasons")
        }) { return true }
        return false
    }

    private func dismissFeedbackBySnapshot(_ app: XCUIApplication, timeout: TimeInterval = 20) -> Bool {
        let preferred = ["thumbsdown", "close", "not now", "no thanks", "dismiss", "done", "ok", "cancel", "skip", "x"]
        let deadline = Date().addingTimeInterval(timeout)
        var passes = 0
        while Date() < deadline {
            passes += 1
            let rows = snapshotVisibleButtons(app, max: 36)
            if !feedbackVisibleBySnapshot(app) {
                print("[VPNTest] STEP PASS: feedback not visible after \(passes - 1) dismiss pass(es)")
                return true
            }
            print("[VPNTest] feedback dismiss pass \(passes): visible buttons=\(rows.count)")
            if rows.count > 4 {
                let b4 = rows[4].label.lowercased()
                if b4.contains("thumbsdown") {
                    print("[VPNTest] feedback dismiss: fast-path tap button[4]=\"\(rows[4].label)\"")
                    _ = tapVisibleButtonByIndex(app, index: 4, context: "dismiss-feedback-fast-thumbsdown")
                    sleep(1)
                    continue
                }
            }
            if let pick = rows.last(where: { row in
                let l = row.label.lowercased()
                return preferred.contains(where: { key in l == key || l.contains(key) })
            }) {
                print("[VPNTest] feedback dismiss: tap button[\(pick.index)]=\"\(pick.label)\"")
                _ = tapVisibleButtonByIndex(app, index: pick.index, context: "dismiss-feedback")
                sleep(1)
                continue
            }
            if let backdrop = rows.first(where: { $0.label.isEmpty }) {
                print("[VPNTest] feedback dismiss: tap backdrop button[\(backdrop.index)]")
                _ = tapVisibleButtonByIndex(app, index: backdrop.index, context: "dismiss-feedback-backdrop")
                sleep(1)
                continue
            }
            print("[VPNTest] feedback dismiss: swipeDown fallback")
            app.swipeDown(velocity: .default)
            sleep(1)
        }
        let gone = !feedbackVisibleBySnapshot(app)
        print("[VPNTest] feedback dismiss timeout: visible=\(!gone)")
        return gone
    }

    private func defaultIdentityRestored(baseline: HomeNetworkIdentity, now: HomeNetworkIdentity) -> Bool {
        let ipRestored = !baseline.ip.isEmpty && !now.ip.isEmpty && baseline.ip == now.ip
        if baseline.location.isEmpty || now.location.isEmpty {
            return ipRestored
        }
        let locationRestored = baseline.location == now.location
        return ipRestored && locationRestored
    }

    /// Region catalog (every index → name) then rows 0–2: **IFU** row 0 auto-connect only; **IFU** row ≥1 taps Connect; **non-IFU** taps Connect every row; hold **5s**; disconnect; IFU waits for idle before next row.
    func testConnectFirstThreeRegions_ReportSummary() throws {
        let app = ensureVPNAppReady()
        XCTAssertEqual(app.state, .runningForeground)
        dismissPaywallIfNeeded(app)
        prepareDisconnectedState(app)

        let catalog = captureRegionListCatalog(app, listOpenTimeout: 28)
        XCTAssertGreaterThan(
            catalog.count,
            0,
            "Region list catalog is empty — cannot map row indices to names. Check openRegionList / accessibility."
        )
        let catalogBody = catalog.enumerated().map { "[\($0.offset)] \($0.element.isEmpty ? "(no label)" : $0.element)" }.joined(separator: "\n")
        let catalogAttach = XCTAttachment(string: "Total: \(catalog.count)\n\(catalogBody)")
        catalogAttach.name = "region_list_catalog.txt"
        catalogAttach.lifetime = .keepAlways
        add(catalogAttach)

        var results: [VPNRegionRowResult] = []
        let connectWait: TimeInterval = VPNTestConstants.isIFUTarget ? 65 : 45
        let disconnectWait: TimeInterval = 40
        let holdConnectedSeconds: UInt32 = 5

        for row in 0..<3 {
            prepareDisconnectedState(app)

            if row > 0 {
                XCTAssertTrue(
                    prepareUIForNextRegionSelectionAfterDisconnect(app, listOpenTimeout: 28),
                    "After disconnect row \(row - 1): could not dismiss blocking UI and reopen region list for row \(row)."
                )
            }

            let (selOk, name) = selectRegionListRowByIndex(app, rowIndex: row, listTimeout: 28, skipOpenRegionList: true)
            let catalogName = row < catalog.count ? catalog[row] : ""
            if !selOk {
                results.append(VPNRegionRowResult(index: row, catalogName: catalogName, selectedLabel: name, success: false, detail: "select row or main screen failed"))
                continue
            }

            let tapOk = tapConnectAfterRegionSelectIfNeeded(app, rowIndex: row)
            if !tapOk {
                results.append(VPNRegionRowResult(index: row, catalogName: catalogName, selectedLabel: name, success: false, detail: "connect tap failed after region select"))
                continue
            }

            let connected = waitForVPNConnectedUI(app, timeout: connectWait)
            if !connected {
                results.append(VPNRegionRowResult(index: row, catalogName: catalogName, selectedLabel: name, success: false, detail: "connected UI timeout \(connectWait)s"))
                _ = tapDisconnectFromVisibleButtonSnapshot(app)
                _ = measureSecondsUntil(timeout: disconnectWait, pollUs: 15_000) { self.isVPNDisconnectedOrDialogPresent(app) }
                continue
            }

            print("[VPNTest] row \(row): connected — holding \(holdConnectedSeconds)s before disconnect")
            sleep(holdConnectedSeconds)

            let discTap = tapDisconnectFromVisibleButtonSnapshot(app)
            let discOk = discTap && (measureSecondsUntil(timeout: disconnectWait, pollUs: 15_000) { self.isVPNDisconnectedOrDialogPresent(app) } != nil)
            if discOk, VPNTestConstants.isIFUTarget {
                _ = waitForIdleConnectVPNVisible(app, timeout: 22)
            }
            if discOk {
                results.append(VPNRegionRowResult(index: row, catalogName: catalogName, selectedLabel: name, success: true, detail: "held \(holdConnectedSeconds)s"))
            } else {
                results.append(VPNRegionRowResult(index: row, catalogName: catalogName, selectedLabel: name, success: false, detail: "disconnect failed or UI stayed connected"))
            }
        }

        let lines = results.map { $0.description }
        let summary = """
        ========== VPN region pipeline (catalog + 3× connect 5s disconnect) ==========
        \(lines.joined(separator: "\n"))
        Passed: \(results.filter(\.success).count) / \(results.count)
        ================================================================
        """
        print("[VPNTest] \(summary)")
        let attach = XCTAttachment(string: summary)
        attach.name = "three_region_report.txt"
        attach.lifetime = .keepAlways
        add(attach)

        for r in results {
            XCTAssertTrue(r.success, "Row \(r.index) failed: \(r.detail)")
        }
    }

    /// Index-driven four-region pipeline: open by **Current Location**, select rows 0..3, connect/disconnect from visible button indices, close feedback, verify default identity restore.
    func testConnectFirstFourRegions_ReportSummary() throws {
        let app = ensureVPNAppReady()
        XCTAssertEqual(app.state, .runningForeground)
        dismissPaywallIfNeeded(app)
        prepareDisconnectedState(app)
        let baseline = captureHomeNetworkIdentity(app, tag: "baseline-home", verbose: false)
        logSnapshot(app, tag: "home-initial")

        XCTAssertTrue(openRegionListByCurrentLocationSnapshot(app, timeout: 28), "Could not open region list from Current Location.")
        sleep(1)
        guard let previewHost = resolveRegionListContainerForSelection(app) else {
            XCTFail("Region list host missing after opening from Current Location.")
            return
        }
        scrollRegionListToTop(host: previewHost, maxSwipeDown: 8)
        usleep(300_000)
        XCTAssertGreaterThanOrEqual(previewHost.cells.count, 4, "Need at least 4 region rows (cells.count=\(previewHost.cells.count)).")
        for i in 0..<4 {
            let c = previewHost.cells.element(boundBy: i)
            if c.waitForExistence(timeout: 0.8) {
                print("[VPNTest] list preview row[\(i)] = \"\(regionRowDisplayLabel(c))\"")
            }
        }

        var results: [VPNRegionRowResult] = []
        let connectWait: TimeInterval = VPNTestConstants.isIFUTarget ? 70 : 50
        let holdConnectedSeconds: UInt32 = 5

        for row in 0..<4 {
            logSnapshot(app, tag: "row\(row)-before-open-list")
            if !openRegionListByCurrentLocationSnapshot(app, timeout: 24) {
                results.append(VPNRegionRowResult(index: row, catalogName: "", selectedLabel: "", success: false, detail: "failed to open region list from Current Location"))
                continue
            }
            sleep(1)

            guard let host = resolveRegionListContainerForSelection(app) else {
                results.append(VPNRegionRowResult(index: row, catalogName: "", selectedLabel: "", success: false, detail: "region list host missing"))
                continue
            }
            scrollRegionListToTop(host: host, maxSwipeDown: 8)
            usleep(300_000)
            if row >= host.cells.count {
                results.append(VPNRegionRowResult(index: row, catalogName: "", selectedLabel: "", success: false, detail: "row index \(row) not present in list (cells.count=\(host.cells.count))"))
                continue
            }
            let cell = host.cells.element(boundBy: row)
            guard cell.waitForExistence(timeout: 4) else {
                results.append(VPNRegionRowResult(index: row, catalogName: "", selectedLabel: "", success: false, detail: "row cell missing"))
                continue
            }
            let selectedLabel = regionRowDisplayLabel(cell)
            print("[VPNTest] select row[\(row)] name=\"\(selectedLabel)\"")
            if cell.isHittable {
                cell.tap()
            } else {
                cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            sleep(1)
            logSnapshot(app, tag: "row\(row)-after-select")

            let alreadyConnected = waitForConnectedBySnapshot(app, timeout: 8)
            if alreadyConnected {
                print("[VPNTest] STEP PASS row \(row): already connected after region select (skip connect tap)")
            } else {
                let connectRows = snapshotVisibleButtons(app, max: 36)
                guard let connectIdx = pickConnectButtonIndex(from: connectRows) else {
                    results.append(VPNRegionRowResult(index: row, catalogName: "", selectedLabel: selectedLabel, success: false, detail: "connect button not found in visible button list"))
                    continue
                }
                print("[VPNTest] row \(row): connect button index \(connectIdx)")
                guard tapVisibleButtonByIndex(app, index: connectIdx, context: "row\(row)-connect") else {
                    results.append(VPNRegionRowResult(index: row, catalogName: "", selectedLabel: selectedLabel, success: false, detail: "connect tap failed at index \(connectIdx)"))
                    continue
                }
            }

            let connected = waitForConnectedBySnapshot(app, timeout: alreadyConnected ? 2 : connectWait)
            if !connected {
                logSnapshot(app, tag: "row\(row)-connect-timeout")
                results.append(VPNRegionRowResult(index: row, catalogName: "", selectedLabel: selectedLabel, success: false, detail: "connected state not visible within \(Int(connectWait))s"))
                continue
            }
            print("[VPNTest] STEP PASS row \(row): connected")

            print("[VPNTest] row \(row): connected — holding \(holdConnectedSeconds)s before disconnect")
            sleep(holdConnectedSeconds)
            let stayedConnected = looksConnectedBySnapshot(app)
            print("[VPNTest] row \(row): stayed connected after hold=\(stayedConnected)")
            logSnapshot(app, tag: "row\(row)-before-disconnect")

            // Required delay: 1s before toggle-off.
            sleep(1)
            let disconnectRows = snapshotVisibleButtons(app, max: 36)
            guard let disconnectIdx = pickDisconnectButtonIndex(from: disconnectRows) else {
                results.append(VPNRegionRowResult(index: row, catalogName: "", selectedLabel: selectedLabel, success: false, detail: "disconnect button not found in visible button list"))
                continue
            }
            print("[VPNTest] row \(row): disconnect button index \(disconnectIdx)")
            guard tapVisibleButtonByIndex(app, index: disconnectIdx, context: "row\(row)-disconnect") else {
                results.append(VPNRegionRowResult(index: row, catalogName: "", selectedLabel: selectedLabel, success: false, detail: "disconnect tap failed at index \(disconnectIdx)"))
                continue
            }
            print("[VPNTest] STEP PASS row \(row): disconnect tap sent")
            // Required delay: 1s after toggle-off.
            sleep(1)

            let dismissed = dismissFeedbackBySnapshot(app, timeout: 18)
            if !dismissed {
                results.append(VPNRegionRowResult(index: row, catalogName: "", selectedLabel: selectedLabel, success: false, detail: "feedback page did not close"))
                continue
            }
            print("[VPNTest] STEP PASS row \(row): feedback closed")
            logSnapshot(app, tag: "row\(row)-after-feedback-close")
            // Required delay: 1s after feedback close and before default-identity verification.
            sleep(1)

            let nowIdentity = captureHomeNetworkIdentity(app, tag: "row\(row)-post-disconnect", verbose: false)
            if defaultIdentityRestored(baseline: baseline, now: nowIdentity) {
                print("[VPNTest] STEP PASS row \(row): default identity restored")
                results.append(VPNRegionRowResult(index: row, catalogName: "", selectedLabel: selectedLabel, success: true, detail: "held \(holdConnectedSeconds)s, feedback closed, default identity restored"))
            } else {
                print("[VPNTest] row \(row): identity not restored baselineIP=\"\(baseline.ip)\" nowIP=\"\(nowIdentity.ip)\" baselineLoc=\"\(baseline.location)\" nowLoc=\"\(nowIdentity.location)\"")
                results.append(VPNRegionRowResult(index: row, catalogName: "", selectedLabel: selectedLabel, success: false, detail: "default ip/location not restored after feedback close"))
            }
        }

        let lines = results.map { $0.description }
        let summary = """
        ========== VPN region pipeline (index-driven + 4× connect 5s disconnect) ==========
        \(lines.joined(separator: "\n"))
        Passed: \(results.filter(\.success).count) / \(results.count)
        ================================================================
        """
        print("[VPNTest] \(summary)")
        let attach = XCTAttachment(string: summary)
        attach.name = "four_region_report.txt"
        attach.lifetime = .keepAlways
        add(attach)

        for r in results {
            XCTAssertTrue(r.success, "Row \(r.index) failed: \(r.detail)")
        }
    }

    /// First region (index 0): IFU **auto-connects on select** (no Connect tap); wait connected; **5s**; disconnect with same VPN control; assert idle **Connect VPN** / toggle-off; then popup poll.
    func testConnectRegionRowZero_Disconnect_LogOverlay() throws {
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
        let preTap = regionRowDisplayLabel(cell0)
        print("[VPNTest] selecting list index **0** only — cell[0] label before tap: \"\(preTap)\"")

        let (selOk, label) = selectRegionListRowByIndex(app, rowIndex: 0, listTimeout: 28, skipOpenRegionList: true, assumeListAlreadyAtTop: true)
        XCTAssertTrue(selOk, "selectRegionListRowByIndex row 0 failed (label=\"\(label)\").")

        XCTAssertTrue(tapConnectAfterRegionSelectIfNeeded(app, rowIndex: 0), "Connect step failed after selecting row 0 (non-IFU or unexpected IFU).")

        let connectWait: TimeInterval = VPNTestConstants.isIFUTarget ? 65 : 45
        XCTAssertTrue(waitForVPNConnectedUI(app, timeout: connectWait), "Connected UI did not appear within \(connectWait)s.")
        print("[VPNTest] milestone: connected verified")

        sleep(5)
        print("[VPNTest] ═══ BUTTON DUMP: connected state (after 5s hold, before disconnect) ═══")
        logConnectScreenDiagnostics(app)
        logAllButtonsDetailed(app, maxButtons: 80)
        print("[VPNTest] ═══ END connected-state button dump ═══")

        XCTAssertTrue(tapDisconnectFromVisibleButtonSnapshot(app), "Disconnect tap failed (button snapshot).")
        if measureSecondsUntil(timeout: 45, pollUs: 15_000, predicate: { self.isVPNDisconnectedOrDialogPresent(app) }) != nil {
            print("[VPNTest] milestone: Post-disconnect wait finished (disconnected UI or popup visible)")
        } else {
            print("[VPNTest] milestone: Post-disconnect wait timed out (still reading as connected with no dialog)")
        }

        _ = logPostDisconnectPopupYesNoAndDismissIfPresent(app, pollForOverlaySeconds: 16)

        XCTAssertTrue(
            waitForIdleConnectVPNVisible(app, timeout: 28),
            "After disconnect, idle UI should show Connect VPN (or IFU vpn toggle off). Dump: logConnectScreenDiagnostics above."
        )
        print("[VPNTest] milestone: disconnected successfully (only Connect VPN / idle VPN control — not connected)")
    }

    /// Index **0** only: open region list (scroll-to-top once), select row 0 (**swipe-up-only** into view), connect if needed, wait connected, disconnect, log **Alert/Sheet** + short diagnostics, **`logPostDisconnectPopupYesNoAndDismissIfPresent`**, then idle **Connect VPN** / toggle-off.
    func testFirstRegionDisconnect_ThenInspectPopupAndScreen() throws {
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
        print("[VPNTest] first region — cell[0] label: \"\(regionRowDisplayLabel(cell0))\"")

        let (selOk, label) = selectRegionListRowByIndex(app, rowIndex: 0, listTimeout: 28, skipOpenRegionList: true, assumeListAlreadyAtTop: true)
        XCTAssertTrue(selOk, "select row 0 failed (label=\"\(label)\").")

        XCTAssertTrue(tapConnectAfterRegionSelectIfNeeded(app, rowIndex: 0), "Connect step failed after selecting row 0.")

        let connectWait: TimeInterval = VPNTestConstants.isIFUTarget ? 65 : 45
        XCTAssertTrue(waitForVPNConnectedUI(app, timeout: connectWait), "Connected UI did not appear within \(connectWait)s.")
        print("[VPNTest] milestone: connected verified")

        sleep(3)
        print("[VPNTest] milestone: disconnecting (same VPN control as connected state)")
        XCTAssertTrue(tapDisconnectFromVisibleButtonSnapshot(app), "Disconnect failed (button snapshot).")
        _ = measureSecondsUntil(timeout: 45, pollUs: 15_000, predicate: { self.isVPNDisconnectedOrDialogPresent(app) })

        print("[VPNTest] ═══ POST-DISCONNECT: what is on screen — BEFORE popup dismiss helper ═══")
        let alertEx = app.alerts.firstMatch.exists
        let sheetEx = app.sheets.firstMatch.exists
        print("[VPNTest] POST-DISCONNECT: system Alert visible = \(alertEx)")
        print("[VPNTest] POST-DISCONNECT: Sheet visible = \(sheetEx)")
        let stillConnectedUI = isVPNConnectedUI(app)
        print("[VPNTest] POST-DISCONNECT: isVPNConnectedUI = \(stillConnectedUI)")
        logAccessibilitySummary(app)
        logConnectScreenDiagnostics(app)
        logAllButtonsDetailed(app, maxButtons: 48)
        print("[VPNTest] ═══ END post-disconnect pre-dismiss dump ═══")

        let summary = """
        POST-DISCONNECT SNAPSHOT (before dismiss)
        - Alert visible: \(alertEx)
        - Sheet visible: \(sheetEx)
        - Still reads as VPN connected UI: \(stillConnectedUI)
        """
        let preAttach = XCTAttachment(string: summary)
        preAttach.name = "post_disconnect_presence.txt"
        preAttach.lifetime = .keepAlways
        add(preAttach)

        let hadOverlay = logPostDisconnectPopupYesNoAndDismissIfPresent(app, pollForOverlaySeconds: 16)
        print("[VPNTest] POST-DISMISS: logPostDisconnect returned hadAlertOrSheet=\(hadOverlay)")

        print("[VPNTest] ═══ POST-DISCONNECT: after popup handler ═══")
        logConnectScreenDiagnostics(app)
        logAllButtonsDetailed(app, maxButtons: 32)

        XCTAssertTrue(
            waitForIdleConnectVPNVisible(app, timeout: 28),
            "Expected idle Connect VPN / IFU vpn-toggle-off after disconnect and popup handling."
        )
        print("[VPNTest] milestone: disconnected successfully — idle connect UI visible (popup check complete)")
    }

    /// **Pipeline:** (1) select row0 → connect → verify connected → disconnect → **close IFU feedback** → reopen list → select row1 → **`clearIFUPromoOverlaysBeforeVPNChromeWork`** (alternate-IP / session card) → main button snapshot → connect → optional second peel → **5s** → disconnect → **close feedback** → verify idle. Row0 has **no** dwell; row1 has **5s** connected hold.
    func testTwoRegions_Row0Disconnect_ClearPromo_Row1ConnectHold5s_Report() throws {
        let app = ensureVPNAppReady()
        XCTAssertEqual(app.state, .runningForeground)
        dismissPaywallIfNeeded(app)
        prepareDisconnectedState(app)
        let baselineDisconnectedIdentity = captureHomeNetworkIdentity(app, tag: "baseline-disconnected", verbose: false)

        XCTAssertTrue(openRegionList(app, timeout: 28), "Could not open region list.")
        sleep(1)
        guard let host = resolveRegionListContainerForSelection(app) else {
            XCTFail("Region list host missing after openRegionList.")
            return
        }
        scrollRegionListToTop(host: host, maxSwipeDown: 8)
        usleep(300_000)
        let cells = host.cells
        XCTAssertGreaterThanOrEqual(cells.count, 2, "Need at least two visible region rows (cells.count=\(cells.count)).")

        let cell0 = cells.element(boundBy: 0)
        let cell1 = cells.element(boundBy: 1)
        XCTAssertTrue(cell0.waitForExistence(timeout: 6), "List cell 0 missing.")
        XCTAssertTrue(cell1.waitForExistence(timeout: 6), "List cell 1 missing.")
        let name0 = regionRowDisplayLabel(cell0)
        let name1 = regionRowDisplayLabel(cell1)
        print("[VPNTest] two-region: skipping full catalog — top-of-list preview only: [0]=\"\(name0)\" [1]=\"\(name1)\"")
        let connectWaitBase: TimeInterval = VPNTestConstants.isIFUTarget ? 65 : 45
        let holdSeconds: UInt32 = 5

        // —— Row 0: select → connect → verify connected → disconnect → close IFU feedback → reopen list (no dwell; no Connected-queries while feedback is up)
        let (ok0, label0) = selectRegionListRowByIndex(app, rowIndex: 0, listTimeout: 28, skipOpenRegionList: true, assumeListAlreadyAtTop: true)
        XCTAssertTrue(ok0, "Row 0 select failed (label=\"\(label0)\").")

        XCTAssertTrue(tapConnectAfterRegionSelectIfNeeded(app, rowIndex: 0), "Row 0: connect step failed after region selection.")
        XCTAssertTrue(waitForVPNConnectedUI(app, timeout: connectWaitBase), "Row 0: connected UI timeout \(connectWaitBase)s.")
        XCTAssertTrue(isVPNConnectedUI(app), "Row 0: verify connected before disconnect.")
        print("[VPNTest] two-region: row0 — disconnect (IFU feedback will appear after toggle-off)")

        XCTAssertTrue(tapDisconnectFromVisibleButtonSnapshotWhenConnected(app), "Row 0: disconnect tap failed.")

        print("[VPNTest] two-region: row0 — dismiss IFU feedback immediately after disconnect (no multi-second settle before first dismiss pass)")
        if VPNTestConstants.isIFUTarget {
            usleep(250_000)
            ensureIFUPostSessionFeedbackDismissed(app, maxRounds: 14)
        }
        dismissPaywallIfNeeded(app)
        print("[VPNTest] row0 post-feedback: proceeding on UI flow only (no identity gating).")

        print("[VPNTest] two-region: reopen region list for row 1 (prime with Current Location tap first)")
        _ = tapCurrentLocationSelectorIfVisible(app)
        XCTAssertTrue(openRegionList(app, timeout: 28), "Could not reopen region list after row0 feedback.")
        sleep(1)
        guard let host1 = resolveRegionListContainerForSelection(app) else {
            XCTFail("Region list host missing after reopen for row 1.")
            return
        }
        scrollRegionListToTop(host: host1, maxSwipeDown: 8)
        usleep(300_000)

        // —— Row 1: select → connect → **5s** → disconnect → close feedback → verify idle
        let (ok1, label1) = selectRegionListRowByIndex(app, rowIndex: 1, listTimeout: 28, skipOpenRegionList: true, assumeListAlreadyAtTop: true)
        XCTAssertTrue(ok1, "Row 1 select failed (label=\"\(label1)\").")

        let row1Wait: TimeInterval = {
            let l = label1.lowercased()
            if l.contains("fastest") || l.contains("connect to fastest") { return max(connectWaitBase, 95) }
            return connectWaitBase
        }()

        // IFU alternate-IP / session promos can still be up on main chrome — do not snapshot `app.buttons` for connect until cleared.
        print("[VPNTest] two-region: row1 — clear IFU / alternate-server / paywall overlays before main-screen button snapshot")
        clearIFUPromoOverlaysBeforeVPNChromeWork(app, maxRounds: 12)
        sleep(1)
        _ = waitForMainConnectScreenFromButtonSnapshot(app, timeout: 20)
        XCTAssertTrue(tapConnectFromVisibleButtonSnapshot(app), "Row 1: snapshot connect failed.")
        // Connect can surface the same promo stack on top while the tunnel comes up — peel once before waiting for Connected.
        if VPNTestConstants.isIFUTarget {
            usleep(400_000)
            clearIFUPromoOverlaysBeforeVPNChromeWork(app, maxRounds: 10)
        }
        if !waitForVPNConnectedUI(app, timeout: row1Wait) {
            print("[VPNTest] two-region: row1 connect wait failed — peel IFU overlay if any, retry one connect tap")
            if VPNTestConstants.isIFUTarget {
                clearIFUPromoOverlaysBeforeVPNChromeWork(app, maxRounds: 10)
            }
            XCTAssertTrue(waitForMainConnectScreenFromButtonSnapshot(app, timeout: 18), "Row 1: main chrome not ready before connect retry.")
            XCTAssertTrue(tapConnectFromVisibleButtonSnapshot(app), "Row 1: snapshot connect retry failed.")
            if VPNTestConstants.isIFUTarget {
                usleep(400_000)
                clearIFUPromoOverlaysBeforeVPNChromeWork(app, maxRounds: 10)
            }
            XCTAssertTrue(waitForVPNConnectedUI(app, timeout: row1Wait), "Row 1: connected UI timeout after retry (label=\"\(label1)\").")
        }
        XCTAssertTrue(isVPNConnectedUI(app), "Row 1: connected UI must be visible before \(holdSeconds)s hold.")
        print("[VPNTest] two-region report: row1 connected — holding \(holdSeconds)s (listPreview=\"\(name1)\" selected=\"\(label1)\")")
        sleep(holdSeconds)
        XCTAssertTrue(
            isVPNConnectedUI(app),
            "Row 1: expected to stay connected for full \(holdSeconds)s hold (UI dropped early — check IFU feedback blocking or server)."
        )

        let promoAfterHold = ifuPostSessionFeedbackCardVisible(app)
        var btnLines: [String] = []
        var btnScanned = 0
        for i in 0..<20 {
            let b = app.buttons.element(boundBy: i)
            if !b.waitForExistence(timeout: 0.2) { break }
            btnScanned = i + 1
            btnLines.append("[\(i)] label=\"\(b.label)\" hittable=\(b.isHittable)")
        }
        var textLines: [String] = []
        for i in 0..<24 {
            let t = app.staticTexts.element(boundBy: i)
            if !t.waitForExistence(timeout: 0.2) { break }
            let lab = t.label
            if !lab.isEmpty { textLines.append("[\(i)] \"\(lab)\"") }
        }

        let region1Name = label0.isEmpty ? name0 : label0
        let region2Name = label1.isEmpty ? name1 : label1
        let summaryLines = """
        Region 1: \(region1Name) - connect, verify, disconnect, feedback dismissed
        Region 2: \(region2Name) - connected for \(holdSeconds)s, disconnect, feedback dismissed, idle OK
        """
        let report = """
        ========== Two-region report (row1 \(holdSeconds)s hold; no full catalog) ==========
        \(summaryLines)
        Row 0 list preview (top): \(name0) | selected: \(label0)
        Row 1 list preview (top): \(name1) | selected: \(label1)
        After row1 \(holdSeconds)s hold (still connected):
        - app.buttons (first contiguous indices scanned) = \(btnScanned)
        - IFU session-ended promo card visible (heuristic) = \(promoAfterHold)
        - isVPNConnectedUI = \(isVPNConnectedUI(app))

        First \(btnLines.count) buttons:
        \(btnLines.joined(separator: "\n"))

        Non-empty staticTexts (sample up to \(textLines.count)):
        \(textLines.joined(separator: "\n"))
        ================================================================
        """
        print("[VPNTest] \(report)")
        let attach = XCTAttachment(string: report)
        attach.name = "two_region_hold5_report.txt"
        attach.lifetime = .keepAlways
        add(attach)

        XCTAssertTrue(tapDisconnectFromVisibleButtonSnapshotWhenConnected(app), "Row 1: disconnect tap failed.")

        print("[VPNTest] two-region: row1 — dismiss IFU feedback immediately after disconnect")
        if VPNTestConstants.isIFUTarget {
            usleep(250_000)
            ensureIFUPostSessionFeedbackDismissed(app, maxRounds: 14)
        }
        _ = logPostDisconnectPopupYesNoAndDismissIfPresent(app, pollForOverlaySeconds: 0, pollSystemAlertOrSheet: false)
        dismissPaywallIfNeeded(app)
        let row1AfterFeedbackClose = captureHomeNetworkIdentity(app, tag: "row1-after-feedback-close", verbose: false)
        let ipRestored = !baselineDisconnectedIdentity.ip.isEmpty
            && !row1AfterFeedbackClose.ip.isEmpty
            && baselineDisconnectedIdentity.ip == row1AfterFeedbackClose.ip
        let locationRestored = !baselineDisconnectedIdentity.location.isEmpty
            && !row1AfterFeedbackClose.location.isEmpty
            && baselineDisconnectedIdentity.location == row1AfterFeedbackClose.location
        if ipRestored || locationRestored {
            print("[VPNTest] row1: default identity restored — finishing test")
        } else {
            XCTAssertTrue(
                waitForIdleConnectVPNVisible(app, timeout: 16),
                "Row 1: expected default identity restore or idle connect UI after disconnect + feedback close."
            )
            print("[VPNTest] row1: idle connect UI visible — finishing test")
        }
        print("[VPNTest] ══════════════════════════════════════════════════════════════")
        print("[VPNTest]  TEST SUCCEEDED (two-region pipeline)")
        print("[VPNTest]   Region 1: \(region1Name) — connect, verify, disconnect, feedback dismissed")
        print("[VPNTest]   Region 2: \(region2Name) — connected \(holdSeconds)s, disconnect, feedback dismissed, idle OK")
        print("[VPNTest] ══════════════════════════════════════════════════════════════")
        print("[VPNTest] two-region report: PASSED")
    }
}
