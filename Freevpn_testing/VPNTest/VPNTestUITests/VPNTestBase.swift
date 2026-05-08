//
//  VPNTestBase.swift
//  VPNTestUITests
//
//  Base class for VPN tests; registers report observer.
//

import XCTest

class VPNTestBase: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        VPNTestReportObserver.registerIfNeeded()
    }

    /// Use when script has prompted "Launch App" and user opened the app from TestFlight.
    /// Activates the VPN app and waits for it to be in foreground (up to manualLaunchWaitTimeout);
    /// if still not running, launches it. Returns the app ready for interaction.
    func ensureVPNAppReady() -> XCUIApplication {
        let bundleId = VPNTestConstants.resolvedVPNAppBundleIdentifier
        print("[VPNTest] Target app bundle: \(bundleId)")
        let app = XCUIApplication(bundleIdentifier: bundleId)
        app.activate()
        let inForeground = app.wait(for: .runningForeground, timeout: VPNTestConstants.manualLaunchWaitTimeout)
        if !inForeground {
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: VPNTestConstants.defaultTimeout)
        }
        return app
    }

    /// Open the region list by tapping the visible region selector (e.g. "Fastest", "US East").
    /// Tries staticTexts and buttons; use longer waits for real device. Returns true if list appeared.
    @discardableResult
    func openRegionList(_ app: XCUIApplication, timeout: TimeInterval = 20) -> Bool {
        let regionSelectorLabels = VPNTestConstants.regionSelectorHintsOrdered
        let settleMs: UInt32 = VPNTestConstants.isIFUTarget ? 500_000 : 1_000_000
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for label in regionSelectorLabels {
                var el = app.staticTexts[label].firstMatch
                if el.exists, el.isHittable {
                    print("[VPNTest] openRegionList: tap staticText \"\(label)\"")
                    el.tap()
                    usleep(settleMs)
                    if waitForRegionListVisible(app, timeout: VPNTestConstants.isIFUTarget ? 6 : 8) { return true }
                }
                el = app.buttons[label].firstMatch
                if el.exists, el.isHittable {
                    print("[VPNTest] openRegionList: tap button \"\(label)\"")
                    el.tap()
                    usleep(settleMs)
                    if waitForRegionListVisible(app, timeout: VPNTestConstants.isIFUTarget ? 6 : 8) { return true }
                }
            }
            usleep(400_000)
        }
        return false
    }

    /// Region picker sheet is open: **`regionList`** id **or** a list that actually contains **Current Location**.  
    /// Does **not** use “largest table” fallback — idle home can have unrelated tables; feedback helpers must not hammer full **`resolveRegionListContainer`** scans.
    func isRegionListPickerSheetOpen(_ app: XCUIApplication) -> Bool {
        regionListHostByIdOrCurrentLocationAnchor(app, idWait: 0.45) != nil
    }

    /// Strict host only (id + **Current Location** anchor). Used for sheet detection and IFU feedback heuristics.
    private func regionListHostByIdOrCurrentLocationAnchor(_ app: XCUIApplication, idWait: TimeInterval) -> XCUIElement? {
        let id = VPNTestConstants.AccessibilityIds.regionList
        let tId = app.tables[id]
        if tId.waitForExistence(timeout: idWait), tId.cells.count > 0 { return tId }
        let cvId = app.collectionViews[id]
        if cvId.waitForExistence(timeout: idWait), cvId.cells.count > 0 { return cvId }
        let anchor = app.staticTexts["Current Location"].firstMatch
        let maxLists = 12
        if anchor.waitForExistence(timeout: 0.3) {
            for i in 0..<maxLists {
                let tbl = app.tables.element(boundBy: i)
                if !tbl.waitForExistence(timeout: 0.1) { break }
                if tbl.cells.count == 0 { continue }
                if tbl.staticTexts["Current Location"].firstMatch.waitForExistence(timeout: 0.18) { return tbl }
            }
            for i in 0..<maxLists {
                let cv = app.collectionViews.element(boundBy: i)
                if !cv.waitForExistence(timeout: 0.1) { break }
                if cv.cells.count == 0 { continue }
                if cv.staticTexts["Current Location"].firstMatch.waitForExistence(timeout: 0.18) { return cv }
            }
        }
        return nil
    }

    /// Finds scrollable region picker for **selection** / discovery: strict host first, then loose fallbacks when the sheet is open but anchor is scrolled away.
    private func regionListHostMatchingHeuristics(_ app: XCUIApplication, idWait: TimeInterval, allowCellCountFallback: Bool) -> XCUIElement? {
        if let strict = regionListHostByIdOrCurrentLocationAnchor(app, idWait: idWait) { return strict }
        guard allowCellCountFallback else { return nil }
        let maxLists = 14
        var best: XCUIElement?
        var bestCount = 0
        for i in 0..<maxLists {
            let tbl = app.tables.element(boundBy: i)
            if !tbl.waitForExistence(timeout: 0.1) { break }
            let n = tbl.cells.count
            if n > bestCount {
                bestCount = n
                best = tbl
            }
        }
        if bestCount >= 2, let b = best {
            print("[VPNTest] regionList host: fallback `tables[?]` most cells (\(bestCount))")
            return b
        }
        for i in 0..<maxLists {
            let cv = app.collectionViews.element(boundBy: i)
            if !cv.waitForExistence(timeout: 0.1) { break }
            let n = cv.cells.count
            if n > bestCount {
                bestCount = n
                best = cv
            }
        }
        if bestCount >= 2, let b = best {
            print("[VPNTest] regionList host: fallback `collectionViews[?]` most cells (\(bestCount))")
            return b
        }
        if app.tables.firstMatch.waitForExistence(timeout: 0.35), app.tables.firstMatch.cells.count > 0 { return app.tables.firstMatch }
        if app.collectionViews.firstMatch.waitForExistence(timeout: 0.35), app.collectionViews.firstMatch.cells.count > 0 { return app.collectionViews.firstMatch }
        if app.cells.firstMatch.waitForExistence(timeout: 0.35), app.cells.count > 0 { return app.cells.firstMatch }
        return nil
    }

    /// Wait until the region list (table with cells) is visible. Returns true when found.
    private func waitForRegionListVisible(_ app: XCUIApplication, timeout: TimeInterval = 8) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if regionListHostMatchingHeuristics(app, idWait: 0.5, allowCellCountFallback: true) != nil { return true }
            usleep(280_000)
        }
        return false
    }

    /// Table or collection hosting region rows for **taps** / scroll: strict match, then loose fallbacks.
    func resolveRegionListContainer(_ app: XCUIApplication) -> XCUIElement? {
        regionListHostMatchingHeuristics(app, idWait: 2.0, allowCellCountFallback: true)
    }

    /// Scroll list toward the top (best-effort; UITableView/UICollectionView). Fewer swipes than before to avoid long “scroll to top” phases.
    func scrollRegionListToTop(host: XCUIElement, maxSwipeDown: Int = 5) {
        for _ in 0..<maxSwipeDown {
            host.swipeDown(velocity: .fast)
            usleep(65_000)
        }
        usleep(280_000)
    }

    /// Bring `cell` on-screen using **only** `swipeUp` on `host`. Stops when (1) the cell is hittable, (2) **two** consecutive swipes leave the same frame (end of list), or (3) after at least one swipe, **two** consecutive loop starts still show the **same non-hittable rect** as the last pass — avoids XCTest hammering `Cell at {10, 180…}` while nothing changes; `regionRowDisplayLabel` runs next.
    func scrollCellIntoViewSwipeUpOnly(_ cell: XCUIElement, host: XCUIElement, maxSwipes: Int = 22) {
        var swipes = 0
        var noScrollProgressCount = 0
        var anchorWhenNotHittable: CGRect?
        var sameAnchorAtLoopStart = 0
        while swipes < maxSwipes {
            if cell.exists, cell.isHittable { return }

            if swipes > 0, cell.exists, !cell.isHittable, let anchor = anchorWhenNotHittable {
                if Self.regionCellFramesNearlyEqual(cell.frame, anchor) {
                    sameAnchorAtLoopStart += 1
                    if sameAnchorAtLoopStart >= 2 {
                        print("[VPNTest] scrollUp: same non-hittable cell frame after swipe(s); skip further swipes (read label next). y≈\(Int(cell.frame.minY))")
                        return
                    }
                } else {
                    sameAnchorAtLoopStart = 0
                }
            } else {
                sameAnchorAtLoopStart = 0
            }

            let frameBeforeSwipe: CGRect? = cell.exists ? cell.frame : nil
            host.swipeUp(velocity: .default)
            swipes += 1
            usleep(35_000)
            if cell.exists, cell.isHittable {
                anchorWhenNotHittable = nil
                return
            }
            if let before = frameBeforeSwipe, cell.exists {
                let after = cell.frame
                if Self.regionCellFramesNearlyEqual(before, after) {
                    noScrollProgressCount += 1
                    if noScrollProgressCount >= 2 { return }
                } else {
                    noScrollProgressCount = 0
                }
            } else {
                noScrollProgressCount = 0
            }

            if cell.exists, !cell.isHittable {
                anchorWhenNotHittable = cell.frame
            } else {
                anchorWhenNotHittable = nil
            }
        }
    }

    private static func regionCellFramesNearlyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.origin.x - b.origin.x) < 1.5 && abs(a.origin.y - b.origin.y) < 1.5
            && abs(a.size.width - b.size.width) < 1.5 && abs(a.size.height - b.size.height) < 1.5
    }

    /// Primary text for a region row (UITableViewCell often has empty `cell.label`; text lives in subviews).
    func regionRowDisplayLabel(_ cell: XCUIElement) -> String {
        guard cell.exists else { return "" }
        let trimmed = cell.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let maxT = min(cell.staticTexts.count, 20)
        for i in 0..<maxT {
            let t = cell.staticTexts.element(boundBy: i)
            guard t.exists else { continue }
            let l = t.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if !l.isEmpty { return l }
        }
        let maxB = min(cell.buttons.count, 12)
        for i in 0..<maxB {
            let b = cell.buttons.element(boundBy: i)
            guard b.exists else { continue }
            let l = b.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if l.isEmpty { continue }
            let low = l.lowercased()
            if low == "chevron" || low == "more" || low == "detail" { continue }
            return l
        }
        let maxO = min(cell.otherElements.count, 8)
        for i in 0..<maxO {
            let o = cell.otherElements.element(boundBy: i)
            guard o.exists else { continue }
            let l = o.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if !l.isEmpty { return l }
        }
        return ""
    }

    /// One screenful of titles (used when scroll-merge fallback is needed for lazy-loaded lists).
    func collectVisibleRegionCellLabels(from host: XCUIElement, maxPerFrame: Int = 48) -> [String] {
        var labels: [String] = []
        let n = min(host.cells.count, maxPerFrame)
        for i in 0..<n {
            let c = host.cells.element(boundBy: i)
            guard c.exists else { continue }
            let label = regionRowDisplayLabel(c)
            if !label.isEmpty {
                labels.append(label)
            }
        }
        return labels
    }

    /// Enumerate **every** row index `0 ..< cells.count` (IFU often reports the full region count, e.g. 91, before any scroll).
    /// Skips rows whose `regionRowDisplayLabel` is still empty (off-screen lazy cells — use fallback if many gaps).
    func enumerateAllRegionRowLabels(host: XCUIElement, maxCells: Int = 500) -> (reportedCount: Int, labelsInOrder: [String]) {
        guard host.exists else {
            print("[VPNTest] discover: region list host no longer exists")
            return (0, [])
        }
        let reported = host.cells.count
        let cap = min(reported, maxCells)
        print("[VPNTest] discover: cells.count = \(reported) (enumerating row indices 0..<\(cap); stop early if index not queryable)")
        var labelsInOrder: [String] = []
        labelsInOrder.reserveCapacity(cap)
        var miss = 0
        for i in 0..<cap {
            let cell = host.cells.element(boundBy: i)
            if !cell.exists {
                miss += 1
                if miss > 40 {
                    print("[VPNTest] discover: stopped at index \(i) — \(miss) consecutive missing cells (reported \(reported)).")
                    break
                }
                continue
            }
            miss = 0
            let text = regionRowDisplayLabel(cell)
            if !text.isEmpty {
                labelsInOrder.append(text)
            }
        }
        return (reported, labelsInOrder)
    }

    /// For each row index `0 ..< cells.count`, scroll **only upward** on `host` until that cell is hittable, then read its title. One pass top→bottom (no swipe-down recovery per row). Array length == `cells.count`.
    func discoverRegionsInOpenListPerIndexScroll(host: XCUIElement, maxCells: Int = 500, maxSwipesPerCell: Int = 22) -> [String] {
        guard host.exists else {
            print("[VPNTest] discover: per-index — host missing")
            return []
        }
        scrollRegionListToTop(host: host, maxSwipeDown: 5)
        usleep(220_000)
        let n = min(host.cells.count, maxCells)
        if n == 0 {
            print("[VPNTest] discover: per-index — cells.count is 0")
            return []
        }
        print("[VPNTest] discover: single-pass top→bottom (swipeUp only) — cells.count=\(n)")
        var byIndex = [String](repeating: "", count: n)
        for i in 0..<n {
            let cell = host.cells.element(boundBy: i)
            scrollCellIntoViewSwipeUpOnly(cell, host: host, maxSwipes: maxSwipesPerCell)
            usleep(35_000)
            byIndex[i] = regionRowDisplayLabel(cell)
        }
        let filled = byIndex.filter { !$0.isEmpty }.count
        print("[VPNTest] discover: single-pass done — \(filled)/\(n) non-empty titles.")
        // Per-index pass ends with the list scrolled toward the bottom; scroll back to top so index 0 is reachable for `selectRegionListRowByIndex(..., 0)`.
        scrollRegionListToTop(host: host, maxSwipeDown: 5)
        usleep(220_000)
        print("[VPNTest] discover: list scrolled back to top for selection / next steps.")
        return byIndex
    }

    /// Walk the open region list: **one entry per `cells.count` index** (lazy-safe). Falls back to label-merge scroll only if `cells.count` is 0.
    func discoverRegionsInOpenList(host: XCUIElement, maxScrollSteps: Int = 24) -> [String] {
        guard host.exists else { return [] }
        let n = host.cells.count
        if n > 0 {
            return discoverRegionsInOpenListPerIndexScroll(host: host, maxCells: 500, maxSwipesPerCell: 22)
        }
        print("[VPNTest] discover: cells.count 0 — scroll-merge fallback (unordered).")
        scrollRegionListToTop(host: host)
        usleep(400_000)
        var ordered: [String] = []
        var seen = Set<String>()
        var noNewRounds = 0
        for _ in 0..<maxScrollSteps {
            let before = seen.count
            for label in collectVisibleRegionCellLabels(from: host, maxPerFrame: 64) {
                if !label.isEmpty, !seen.contains(label) {
                    seen.insert(label)
                    ordered.append(label)
                }
            }
            if seen.count == before {
                noNewRounds += 1
            } else {
                noNewRounds = 0
            }
            if noNewRounds >= 4 { break }
            host.swipeUp(velocity: .default)
            usleep(280_000)
        }
        return ordered
    }

    /// Opens the region picker and returns distinct region names from the live list UI.
    @discardableResult
    func openRegionListAndDiscoverRegionNames(_ app: XCUIApplication, listOpenTimeout: TimeInterval = 25) -> [String] {
        guard openRegionList(app, timeout: listOpenTimeout) else {
            print("[VPNTest] discover: openRegionList failed")
            return []
        }
        sleep(1)
        guard let host = resolveRegionListContainer(app) else {
            print("[VPNTest] discover: no list host")
            return []
        }
        let names = discoverRegionsInOpenList(host: host, maxScrollSteps: 24)
        let nonEmpty = names.filter { !$0.isEmpty }.count
        print("[VPNTest] Discovered \(names.count) index(es) (\(nonEmpty) with readable titles):")
        for (i, name) in names.enumerated() {
            print("[VPNTest]   [\(i)] \(name.isEmpty ? "(no label)" : name)")
        }
        return names
    }

    /// Opens the region list, walks/scrolls the same way as discovery, prints **every index → name** for the test log (row mapping), then returns the ordered titles. Leaves the list open for immediate `selectRegionListRowByIndex(..., skipOpenRegionList: true)` on row 0.
    @discardableResult
    func captureRegionListCatalog(_ app: XCUIApplication, listOpenTimeout: TimeInterval = 25) -> [String] {
        for attempt in 1...2 {
            guard openRegionList(app, timeout: listOpenTimeout) else {
                print("[VPNTest] region catalog: openRegionList failed (attempt \(attempt))")
                if attempt == 2 { return [] }
                continue
            }
            sleep(attempt == 1 ? 1 : 2)
            guard let host = resolveRegionListContainer(app) else {
                print("[VPNTest] region catalog: no list host (attempt \(attempt))")
                logAccessibilitySummary(app)
                if attempt == 2 { return [] }
                continue
            }
            let reportedCells = host.cells.count
            print("[VPNTest] region catalog: attempt \(attempt) — host identifier=\"\(host.identifier)\" cells.count=\(reportedCells)")
            let names = discoverRegionsInOpenList(host: host, maxScrollSteps: 28)
            let readable = names.filter { !$0.isEmpty }.count
            print("[VPNTest] ========== Region list catalog (index → name) ==========")
            print("[VPNTest] cells.count (UIKit) = \(reportedCells); indices in array = \(names.count); readable titles = \(readable)")
            for (i, name) in names.enumerated() {
                print("[VPNTest]   catalog[\(i)] \(name.isEmpty ? "(no label)" : name)")
            }
            if reportedCells > 0, names.count != reportedCells {
                print("[VPNTest] region catalog: note — array count (\(names.count)) vs cells.count (\(reportedCells)).")
            }
            print("[VPNTest] =========================================================")
            if !names.isEmpty { return names }
            print("[VPNTest] region catalog: 0 readable titles — dumping accessibility summary, then retry if any.")
            logAccessibilitySummary(app)
        }
        return []
    }

    /// Prefer an explicit services table id; else the largest table/collection that is **not** `regionList`.
    func resolveServicesListHost(_ app: XCUIApplication) -> XCUIElement? {
        for sid in VPNTestConstants.AccessibilityIds.servicesListCandidates {
            let t = app.tables[sid].firstMatch
            if t.waitForExistence(timeout: 1), t.cells.count > 0 { return t }
            let cv = app.collectionViews[sid].firstMatch
            if cv.waitForExistence(timeout: 1), cv.cells.count > 0 { return cv }
        }
        let rid = VPNTestConstants.AccessibilityIds.regionList
        var best: XCUIElement?
        var bestCount = 0
        let tableCount = min(app.tables.count, 12)
        for i in 0..<tableCount {
            let el = app.tables.element(boundBy: i)
            guard el.waitForExistence(timeout: 0.5), el.exists else { continue }
            if el.identifier == rid { continue }
            let c = el.cells.count
            if c > bestCount { bestCount = c; best = el }
        }
        let cvCount = min(app.collectionViews.count, 8)
        for i in 0..<cvCount {
            let el = app.collectionViews.element(boundBy: i)
            guard el.waitForExistence(timeout: 0.5), el.exists else { continue }
            if el.identifier == rid { continue }
            let c = el.cells.count
            if c > bestCount { bestCount = c; best = el }
        }
        return best
    }

    /// Dismiss region picker or services-style full-screen list: nav **Back** / chevron, edge-swipe pop, **Done**, swipe-down.
    @discardableResult
    func dismissFullscreenListToMainVPNBestEffort(_ app: XCUIApplication, timeout: TimeInterval = 12) -> Bool {
        func listsGone() -> Bool {
            resolveRegionListContainer(app) == nil && resolveServicesListHost(app) == nil
        }
        func success() -> Bool {
            listsGone() && waitForMainConnectScreen(app, timeout: 4)
        }
        if listsGone() { return waitForMainConnectScreen(app, timeout: 3) }
        let nav = app.navigationBars.firstMatch
        if nav.waitForExistence(timeout: 2) {
            let labels = ["Back", "VPN", "Done", "Close", "Regions", "Cancel", "Select Region", "Regions list"]
            for lab in labels {
                let b = nav.buttons[lab].firstMatch
                if b.exists, b.isHittable {
                    print("[VPNTest] dismissList: navigationBar button \"\(lab)\"")
                    b.tap()
                    sleep(1)
                    if success() { return true }
                }
            }
            let nNav = min(nav.buttons.count, 6)
            for i in 0..<nNav {
                let btn = nav.buttons.element(boundBy: i)
                guard btn.waitForExistence(timeout: 0.5), btn.exists, btn.isHittable else { continue }
                print("[VPNTest] dismissList: navigationBar [\(i)] label=\"\(btn.label)\"")
                btn.tap()
                sleep(1)
                if success() { return true }
            }
        }
        for lab in ["Done", "Close", "Cancel"] {
            let b = app.buttons[lab].firstMatch
            if b.exists, b.isHittable {
                print("[VPNTest] dismissList: app.buttons \"\(lab)\"")
                b.tap()
                sleep(1)
                if success() { return true }
            }
        }
        // Interactive pop (leading-edge swipe) — common when there is no visible "Back" label.
        for _ in 0..<2 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.45))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.45))
            start.press(forDuration: 0.08, thenDragTo: end)
            sleep(1)
            if success() { return true }
        }
        for _ in 0..<4 {
            app.swipeDown(velocity: .fast)
            sleep(1)
            if success() { return true }
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if success() { return true }
            usleep(500_000)
        }
        return success()
    }

    /// Tap tab bar / buttons / static text until a non-region services-style list appears.
    @discardableResult
    func openServicesListBestEffort(_ app: XCUIApplication, timeout: TimeInterval = 22) -> Bool {
        let hints = VPNTestConstants.servicesEntryHintsOrdered
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for label in hints {
                let tab = app.tabBars.buttons[label].firstMatch
                if tab.waitForExistence(timeout: 0.5), tab.isHittable {
                    print("[VPNTest] openServicesList: tabBars.buttons \"\(label)\"")
                    tab.tap()
                    usleep(600_000)
                    if resolveServicesListHost(app) != nil { return true }
                }
                let st = app.staticTexts[label].firstMatch
                if st.exists, st.isHittable {
                    print("[VPNTest] openServicesList: staticTexts \"\(label)\"")
                    st.tap()
                    usleep(600_000)
                    if resolveServicesListHost(app) != nil { return true }
                }
                let bt = app.buttons[label].firstMatch
                if bt.exists, bt.isHittable {
                    print("[VPNTest] openServicesList: buttons \"\(label)\"")
                    bt.tap()
                    usleep(600_000)
                    if resolveServicesListHost(app) != nil { return true }
                }
            }
            usleep(350_000)
        }
        return false
    }

    /// With services list visible, scroll-merge row titles (same strategy as regions) and print.
    @discardableResult
    func captureServicesListCatalog(_ app: XCUIApplication) -> [String] {
        guard let host = resolveServicesListHost(app) else {
            print("[VPNTest] services catalog: no services list host")
            return []
        }
        let reported = host.cells.count
        let names = discoverRegionsInOpenList(host: host, maxScrollSteps: 28)
        print("[VPNTest] ========== Services list catalog (index → name) ==========")
        print("[VPNTest] cells.count (UIKit) = \(reported); rows with readable titles = \(names.count)")
        for (i, name) in names.enumerated() {
            print("[VPNTest]   service[\(i)] \(name)")
        }
        if reported > 0, names.count < reported {
            print("[VPNTest] services catalog: note — readable titles (\(names.count)) < cells.count (\(reported)).")
        }
        print("[VPNTest] =============================================================")
        return names
    }

    /// With region list open, scroll until a cell whose label contains `substring` (case-insensitive) is hittable, then tap.
    @discardableResult
    func selectRegionInOpenList(app: XCUIApplication, host: XCUIElement, labelContaining substring: String, maxSwipes: Int = 30) -> Bool {
        let needle = substring.lowercased()
        for _ in 0..<maxSwipes {
            let n = min(host.cells.count, 120)
            for i in 0..<n {
                let cell = host.cells.element(boundBy: i)
                guard cell.exists else { continue }
                if regionRowDisplayLabel(cell).lowercased().contains(needle) {
                    scrollCellIntoViewSwipeUpOnly(cell, host: host, maxSwipes: 20)
                    if cell.isHittable { cell.tap() } else {
                        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                    }
                    sleep(2)
                    return waitForMainConnectScreen(app, timeout: 15)
                }
            }
            host.swipeUp(velocity: .default)
            usleep(280_000)
        }
        return false
    }

    /// Scroll the list until `cell` is hittable (or max swipes), swiping on `host`.
    func scrollCellIntoView(_ cell: XCUIElement, host: XCUIElement, maxSwipes: Int = 24) {
        var swipes = 0
        while swipes < maxSwipes, cell.exists, !cell.isHittable {
            host.swipeUp(velocity: .default)
            swipes += 1
            usleep(250_000)
        }
        if !cell.isHittable, swipes >= maxSwipes / 2 {
            var back = 0
            while back < maxSwipes / 2, cell.exists, !cell.isHittable {
                host.swipeDown(velocity: .default)
                back += 1
                usleep(250_000)
            }
        }
    }

    /// IFU main-screen VPN control (image button): label like `vpn toggle off` when disconnected.
    func vpnToggleOffButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "label CONTAINS[c] %@", "vpn toggle"),
            NSPredicate(format: "label CONTAINS[c] %@", "off"),
        ])).firstMatch
    }

    /// IFU: label like `vpn toggle on` when connected.
    func vpnToggleOnButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "label CONTAINS[c] %@", "vpn toggle"),
            NSPredicate(format: "label CONTAINS[c] %@", "on"),
        ])).firstMatch
    }

    // MARK: - Button snapshot (no `app.buttons["Tag"]` multi-query; one linear pass over `element(boundBy:)`)

    private func snapshotIndexedButtons(_ app: XCUIApplication, max: Int = 80) -> [(Int, String)] {
        var out: [(Int, String)] = []
        for i in 0..<max {
            let b = app.buttons.element(boundBy: i)
            if !b.waitForExistence(timeout: 0.15) { break }
            out.append((i, b.label))
        }
        return out
    }

    private func mainScreenSignalsPresentInButtonLabels(_ labels: [String]) -> Bool {
        for lab in labels {
            let l = lab.lowercased()
            if l.contains("vpn toggle") { return true }
            if l.contains("connect vpn") { return true }
            if l.contains("connected"), !l.contains("disconnected") { return true }
        }
        return false
    }

    /// After region row tap: wait until **`app.buttons`** snapshot shows VPN main affordances (`vpn toggle`, `Connect VPN`, `Connected` in a label) — **no** `waitForMainConnectScreen` multi-query loop.
    @discardableResult
    func waitForMainConnectScreenFromButtonSnapshot(_ app: XCUIApplication, timeout: TimeInterval = 22) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var last: [(Int, String)] = []
        while Date() < deadline {
            let rows = snapshotIndexedButtons(app, max: 72)
            let labs = rows.map(\.1)
            if mainScreenSignalsPresentInButtonLabels(labs) {
                print("[VPNTest] main screen (button snapshot): ready — \(rows.count) row(s) in `app.buttons`:")
                for (i, lab) in rows {
                    print("[VPNTest]   [\(i)] \"\(lab)\"")
                }
                return true
            }
            last = rows
            usleep(320_000)
        }
        print("[VPNTest] main screen (button snapshot): timeout after \(timeout)s — last \(last.count) row(s):")
        for (i, lab) in last {
            print("[VPNTest]   [\(i)] \"\(lab)\"")
        }
        return false
    }

    /// Pick **one** `app.buttons[i]` from a fresh snapshot to connect — no `findVPNToggle` / multi-string queries.
    @discardableResult
    func tapConnectFromVisibleButtonSnapshot(_ app: XCUIApplication) -> Bool {
        var cleared = 0
        while cleared < 3 {
            guard dismissReviewOrRatingAlertIfPresent(app, timeout: 1.2) else { break }
            cleared += 1
        }
        let rows = snapshotIndexedButtons(app, max: 80)
        print("[VPNTest] connect snapshot: \(rows.count) `app.buttons` — choose ONE index from this list:")
        for (i, lab) in rows {
            print("[VPNTest]   [\(i)] \"\(lab)\"")
        }
        let low: (String) -> String = { $0.lowercased() }
        if let (i, lab) = rows.reversed().first(where: { low($0.1).contains("vpn toggle") && low($0.1).contains("off") }) {
            let b = app.buttons.element(boundBy: i)
            print("[VPNTest] connect snapshot: TAP [\(i)] \"\(lab)\" (vpn toggle + off)")
            tapButtonOrCenter(b, context: "connect-snapshot")
            return true
        }
        if let (i, lab) = rows.reversed().first(where: { low($0.1).contains("vpn toggle") }) {
            let b = app.buttons.element(boundBy: i)
            print("[VPNTest] connect snapshot: TAP [\(i)] \"\(lab)\" (vpn toggle)")
            tapButtonOrCenter(b, context: "connect-snapshot")
            return true
        }
        if let (i, lab) = rows.reversed().first(where: { low($0.1) == "connect vpn" || (low($0.1).contains("connect") && low($0.1).contains("vpn") && !low($0.1).contains("disconnect")) }) {
            let b = app.buttons.element(boundBy: i)
            print("[VPNTest] connect snapshot: TAP [\(i)] \"\(lab)\" (Connect-like)")
            tapButtonOrCenter(b, context: "connect-snapshot")
            return true
        }
        print("[VPNTest] connect snapshot: no tap candidate in snapshot")
        return false
    }

    /// Pick **one** `app.buttons[i]` from a fresh snapshot to disconnect — same idea as connect (IFU often one `vpn toggle`).
    @discardableResult
    func tapDisconnectFromVisibleButtonSnapshot(_ app: XCUIApplication) -> Bool {
        var cleared = 0
        while cleared < 3 {
            guard dismissReviewOrRatingAlertIfPresent(app, timeout: 1.2) else { break }
            cleared += 1
        }
        let rows = snapshotIndexedButtons(app, max: 80)
        print("[VPNTest] disconnect snapshot: \(rows.count) `app.buttons` — choose ONE index from this list:")
        for (i, lab) in rows {
            print("[VPNTest]   [\(i)] \"\(lab)\"")
        }
        let low: (String) -> String = { $0.lowercased() }
        if let (i, lab) = rows.reversed().first(where: { low($0.1).contains("disconnect") && low($0.1).contains("vpn") }) {
            let b = app.buttons.element(boundBy: i)
            print("[VPNTest] disconnect snapshot: TAP [\(i)] \"\(lab)\"")
            tapButtonOrCenter(b, context: "disconnect-snapshot")
            return true
        }
        if let (i, lab) = rows.reversed().first(where: { low($0.1).contains("vpn toggle") && low($0.1).contains("on") }) {
            let b = app.buttons.element(boundBy: i)
            print("[VPNTest] disconnect snapshot: TAP [\(i)] \"\(lab)\" (vpn toggle + on)")
            tapButtonOrCenter(b, context: "disconnect-snapshot")
            return true
        }
        if let (i, lab) = rows.reversed().first(where: { low($0.1).contains("vpn toggle") }) {
            let b = app.buttons.element(boundBy: i)
            print("[VPNTest] disconnect snapshot: TAP [\(i)] \"\(lab)\" (vpn toggle)")
            tapButtonOrCenter(b, context: "disconnect-snapshot")
            return true
        }
        print("[VPNTest] disconnect snapshot: no tap candidate in snapshot")
        return false
    }

    /// Calls **`tapDisconnectFromVisibleButtonSnapshot`** only while **`isVPNConnectedUI`** is true. After IFU disconnect the session-feedback card appears with **`vpn toggle off`** still visible — a second “disconnect” tap would hit the toggle again; skip when already disconnected.
    @discardableResult
    func tapDisconnectFromVisibleButtonSnapshotWhenConnected(_ app: XCUIApplication) -> Bool {
        if !isVPNConnectedUI(app) {
            print("[VPNTest] disconnect snapshot: skip tap — UI already reads as disconnected (IFU feedback / idle)")
            return true
        }
        return tapDisconnectFromVisibleButtonSnapshot(app)
    }

    /// True when main VPN screen shows connect affordance (list dismissed or connect visible).
    /// Uses short **`waitForExistence`** slices so a wedged UI does not block one `.exists` for the XCTest default (~120s) per iteration.
    func waitForMainConnectScreen(_ app: XCUIApplication, timeout: TimeInterval = 20) -> Bool {
        let connectId = VPNTestConstants.AccessibilityIds.connectButton
        let deadline = Date().addingTimeInterval(timeout)
        let slice: TimeInterval = 0.4
        while Date() < deadline {
            if app.buttons[connectId].firstMatch.waitForExistence(timeout: slice) { return true }
            if app.switches[connectId].firstMatch.waitForExistence(timeout: slice) { return true }
            if app.buttons["Connect VPN"].firstMatch.waitForExistence(timeout: slice) { return true }
            if app.staticTexts["Connect VPN"].firstMatch.waitForExistence(timeout: slice) { return true }
            if vpnToggleOffButton(app).waitForExistence(timeout: slice) { return true }
            if app.switches.count > 0, app.switches.firstMatch.waitForExistence(timeout: slice) { return true }
            usleep(120_000)
        }
        return false
    }

    /// After disconnect: **not** showing connected UI, and idle affordance is visible — **`Connect VPN`** (button or static text) and/or IFU **`vpn toggle` + off** (same control used to connect/disconnect).
    @discardableResult
    func waitForIdleConnectVPNVisible(_ app: XCUIApplication, timeout: TimeInterval = 30) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isVPNConnectedUI(app) {
                usleep(400_000)
                continue
            }
            let connectBtn = app.buttons["Connect VPN"].firstMatch
            let connectText = app.staticTexts["Connect VPN"].firstMatch
            let ifuIdle = vpnToggleOffButton(app)
            if connectBtn.exists || connectText.exists || ifuIdle.exists {
                print("[VPNTest] idle UI: Connect VPN button=\(connectBtn.exists) staticText=\(connectText.exists) ifuVpnToggleOff=\(ifuIdle.exists)")
                return true
            }
            usleep(350_000)
        }
        return false
    }

    /// Select the first real region row, scroll into view if needed, tap until main connect screen appears.
    /// Skips "Connect to Fastest" / Fastest-only promo row when present. Returns false if list missing or connect never appears.
    @discardableResult
    func selectFirstRegionInList(_ app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        guard let host = resolveRegionListContainer(app) else {
            print("[VPNTest] selectFirstRegionInList: no region table/collection found")
            return false
        }
        let cells = host.cells
        let count = cells.count
        guard count > 0 else { return false }

        var indexToTap = VPNTestConstants.regionSelectionIndex
        let firstCell = cells.element(boundBy: 0)
        let firstLabel = regionRowDisplayLabel(firstCell)
        if firstLabel.contains("Fastest") || firstLabel == VPNTestConstants.regionListSkipLabel {
            indexToTap = count > 1 ? 1 : 0
        } else {
            indexToTap = min(VPNTestConstants.regionSelectionIndex, count - 1)
        }

        let cell = cells.element(boundBy: indexToTap)
        guard cell.waitForExistence(timeout: min(timeout, 8)) else { return false }

        print("[VPNTest] Selecting region cell [\(indexToTap)] label=\"\(regionRowDisplayLabel(cell))\"")

        let overallDeadline = Date().addingTimeInterval(timeout)
        var attempt = 0
        while Date() < overallDeadline, attempt < 4 {
            attempt += 1
            scrollCellIntoViewSwipeUpOnly(cell, host: host, maxSwipes: 24)
            usleep(200_000)
            if cell.isHittable {
                cell.tap()
            } else {
                cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            sleep(2)
            if waitForMainConnectScreenFromButtonSnapshot(app, timeout: 12) {
                print("[VPNTest] Region selected; main screen visible (button snapshot) (attempt \(attempt))")
                return true
            }
            print("[VPNTest] Region tap did not reveal connect screen; retrying (attempt \(attempt))")
            host.swipeUp(velocity: .default)
            usleep(300_000)
        }

        logAccessibilitySummary(app)
        return false
    }

    /// XCTAttachment + temp PNG for milestone docs (home, list, connect idle, connected, after disconnect).
    func captureMilestoneScreenshot(app: XCUIApplication, name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let data = screenshot.pngRepresentation
        let safe = name.replacingOccurrences(of: "/", with: "_")
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("milestone_\(safe).png")
        try? data.write(to: url)
        print("[VPNTest] Milestone screenshot: \(url.path)")
    }

    /// Try to dismiss paywalls/overlays so the region list can appear. Call before waiting for region list.
    /// Taps common "Close", "Skip", "Maybe Later", etc. for up to 5s or 5 taps.
    func dismissPaywallIfNeeded(_ app: XCUIApplication) {
        let dismissLabels = ["Close", "Skip", "Maybe Later", "No thanks", "Not now", "No, Thanks", "Maybe Later", "X", "Dismiss", "Continue"]
        let deadline = Date().addingTimeInterval(5)
        var tapCount = 0
        let maxTaps = 5
        while Date() < deadline, tapCount < maxTaps {
            var tapped = false
            for label in dismissLabels {
                let btn = app.buttons[label].firstMatch
                if btn.exists && btn.isHittable {
                    btn.tap()
                    tapCount += 1
                    tapped = true
                    usleep(500_000) // 0.5s for UI to update
                    break
                }
            }
            if !tapped { break }
        }
    }

    /// Dismisses **system** “rate / review” alerts (e.g. *Enjoying our VPN? Leave a Review!*) that sit above the VPN chrome and break coordinate taps on `vpn toggle`.
    @discardableResult
    func dismissReviewOrRatingAlertIfPresent(_ app: XCUIApplication, timeout: TimeInterval = 2.5) -> Bool {
        let alert = app.alerts.firstMatch
        guard alert.waitForExistence(timeout: timeout), alert.exists else { return false }
        var blob = alert.label
        let n = min(alert.staticTexts.count, 8)
        for i in 0..<n {
            let t = alert.staticTexts.element(boundBy: i)
            if t.exists { blob += " " + t.label }
        }
        let low = blob.lowercased()
        guard low.contains("review") || low.contains("rating") || low.contains("enjoying") || low.contains("rate") else {
            return false
        }
        print("[VPNTest] review alert: dismissing — \"\(blob.prefix(120))\"")
        let prefer = ["Not Now", "No Thanks", "No thanks", "Maybe Later", "Maybe later", "Later", "Cancel", "Close", "Dismiss"]
        for lab in prefer {
            let b = alert.buttons[lab].firstMatch
            if b.waitForExistence(timeout: 0.35), b.isHittable {
                b.tap()
                sleep(1)
                return true
            }
        }
        let bc = alert.buttons.count
        if bc > 0 {
            let b = alert.buttons.element(boundBy: bc - 1)
            if b.exists, b.isHittable {
                print("[VPNTest] review alert: tap last button label=\"\(b.label)\"")
                b.tap()
                sleep(1)
                return true
            }
        }
        return false
    }

    /// After disconnect: optionally polls for system **Alert** / **Sheet**. Set **`pollSystemAlertOrSheet`** to **false** on IFU when only the in-app session-ended card matters (use **`dismissIFUPostSessionFeedbackOverlayBestEffort`** separately).
    @discardableResult
    func logPostDisconnectPopupYesNoAndDismissIfPresent(_ app: XCUIApplication, pollForOverlaySeconds: TimeInterval = 14, pollSystemAlertOrSheet: Bool = true) -> Bool {
        sleep(1)
        if !pollSystemAlertOrSheet {
            print("[VPNTest] post-disconnect: skipping system Alert/Sheet poll (IFU feedback-only path)")
            return false
        }
        let pollStarted = Date()
        let pollDeadline = pollStarted.addingTimeInterval(pollForOverlaySeconds)
        var wave = 0
        while Date() < pollDeadline {
            wave += 1
            let alert = app.alerts.firstMatch
            if alert.waitForExistence(timeout: 0.55) {
                print("[VPNTest] popup after disconnect: yes (Alert seen after \(String(format: "%.1f", Date().timeIntervalSince(pollStarted)))s)")
                print("[VPNTest] overlay kind: Alert")
                let btnCount = alert.buttons.count
                let printN = min(btnCount, 8)
                for i in 0..<printN {
                    let b = alert.buttons.element(boundBy: i)
                    guard b.exists else { break }
                    print("[VPNTest]   alert.buttons[\(i)] identifier=\"\(b.identifier)\" label=\"\(b.label)\" hittable=\(b.isHittable)")
                }
                if btnCount == 1, alert.buttons.element(boundBy: 0).exists {
                    let b = alert.buttons.element(boundBy: 0)
                    if b.isHittable {
                        print("[VPNTest] closing overlay: tap alert.buttons[0] label=\"\(b.label)\"")
                        b.tap()
                        print("[VPNTest] milestone: Popup close (alert.buttons[0] tapped)")
                    } else {
                        print("[VPNTest] milestone: Popup close NOT done (alert.buttons[0] not hittable)")
                    }
                } else if btnCount >= 2 {
                    let idx = btnCount - 1
                    let b = alert.buttons.element(boundBy: idx)
                    if b.exists, b.isHittable {
                        print("[VPNTest] closing overlay: tap alert.buttons[\(idx)] label=\"\(b.label)\"")
                        b.tap()
                        print("[VPNTest] milestone: Popup close (alert.buttons[\(idx)] tapped)")
                    } else {
                        print("[VPNTest] milestone: Popup close NOT done (alert dismiss button not hittable)")
                    }
                } else {
                    print("[VPNTest] milestone: Popup close NOT done (alert has no buttons)")
                }
                sleep(1)
                let still = app.alerts.firstMatch.exists
                print("[VPNTest] popup dismiss verify: alert still visible — \(still ? "yes" : "no")")
                return true
            }
            let sheet = app.sheets.firstMatch
            if sheet.waitForExistence(timeout: 0.45) {
                print("[VPNTest] popup after disconnect: yes (sheet)")
                print("[VPNTest] overlay kind: Sheet")
                let btnCount = sheet.buttons.count
                let printN = min(btnCount, 12)
                for i in 0..<printN {
                    let b = sheet.buttons.element(boundBy: i)
                    guard b.exists else { break }
                    print("[VPNTest]   sheet.buttons[\(i)] identifier=\"\(b.identifier)\" label=\"\(b.label)\" hittable=\(b.isHittable)")
                }
                if btnCount >= 1 {
                    let idx = btnCount - 1
                    let b = sheet.buttons.element(boundBy: idx)
                    if b.exists, b.isHittable {
                        print("[VPNTest] closing overlay: tap sheet.buttons[\(idx)] label=\"\(b.label)\"")
                        b.tap()
                        print("[VPNTest] milestone: Popup close (sheet.buttons[\(idx)] tapped)")
                    } else {
                        print("[VPNTest] milestone: Popup close NOT done (sheet dismiss button not hittable)")
                    }
                } else {
                    print("[VPNTest] milestone: Popup close NOT done (sheet has no buttons)")
                }
                sleep(1)
                let still = app.sheets.firstMatch.exists
                print("[VPNTest] popup dismiss verify: sheet still visible — \(still ? "yes" : "no")")
                return true
            }
            if wave == 1 || wave % 10 == 0 {
                let elapsed = Date().timeIntervalSince(pollStarted)
                print("[VPNTest] popup probe: no Alert/Sheet yet — polling… \(String(format: "%.1f", elapsed))s / \(String(format: "%.0f", pollForOverlaySeconds))s")
            }
            usleep(320_000)
        }
        print("[VPNTest] popup after disconnect: no (no Alert or Sheet within \(String(format: "%.0f", pollForOverlaySeconds))s)")
        let m = min(app.buttons.count, 12)
        if m > 0 {
            print("[VPNTest] no Alert or Sheet — first \(m) `app.buttons` (informational only, not tapped):")
            for i in 0..<m {
                let b = app.buttons.element(boundBy: i)
                guard b.exists else { break }
                print("[VPNTest]   app.buttons[\(i)] identifier=\"\(b.identifier)\" label=\"\(b.label)\"")
            }
        }
        print("[VPNTest] milestone: Popup close (nothing to dismiss — no Alert or Sheet)")
        return false
    }

    /// True when IFU-style **in-app** “session ended” feedback is on screen (not `UIAlertController`).
    func ifuPostSessionFeedbackCardVisible(_ app: XCUIApplication) -> Bool {
        let listOpen = isRegionListPickerSheetOpen(app)
        if app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "session ended")).firstMatch.exists { return true }
        if app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "How was it")).firstMatch.exists { return true }
        if app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "How was your")).firstMatch.exists { return true }
        if app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "alternate server")).firstMatch.exists { return true }
        if app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "alternate ip")).firstMatch.exists { return true }
        if app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "VPN session")).firstMatch.exists { return true }
        let thumbsUp = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Thumbs Up")).firstMatch
        if !listOpen, thumbsUp.exists, thumbsUp.isHittable, app.buttons.count > 12 { return true }
        if VPNTestConstants.isIFUTarget, !listOpen, app.buttons.count > 13 {
            let td = app.buttons["thumbsDown"]
            if td.exists { return true }
        }
        // Feedback card often shows **Alternate IP** as a CTA next to rating controls — do not tap it (opens a flow); presence with thumbsDown implies the session sheet is up.
        if !listOpen {
            let td = app.buttons["thumbsDown"].firstMatch
            let altIpCue = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "alternate ip")).firstMatch
            if td.waitForExistence(timeout: 0.35), altIpCue.waitForExistence(timeout: 0.35) {
                return true
            }
        }
        return false
    }

    /// One pass of taps/swipes that usually clears the IFU post-disconnect stack (runs even when **`ifuPostSessionFeedbackCardVisible`** is flaky).
    private func oneIFUPostSessionDismissSequence(_ app: XCUIApplication) {
        let b0 = app.buttons.element(boundBy: 0)
        if b0.exists, b0.isHittable, b0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("[VPNTest] IFU post-session: sequence — backdrop buttons[0]")
            tapButtonOrCenter(b0, context: "ifu-sequence-backdrop")
            return
        }
        let td = app.buttons["thumbsDown"]
        if td.exists, td.isHittable {
            print("[VPNTest] IFU post-session: sequence — thumbsDown")
            tapButtonOrCenter(td, context: "ifu-sequence-thumbsDown")
            return
        }
        let tu = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Thumbs Up")).firstMatch
        if tu.exists, tu.isHittable {
            print("[VPNTest] IFU post-session: sequence — Thumbs Up")
            tapButtonOrCenter(tu, context: "ifu-sequence-thumbsUp")
            return
        }
        for lab in ["Close", "Not now", "No thanks", "Dismiss", "Done", "OK"] {
            let b = app.buttons[lab].firstMatch
            if b.waitForExistence(timeout: 0.25), b.isHittable {
                print("[VPNTest] IFU post-session: sequence — \"\(lab)\"")
                tapButtonOrCenter(b, context: "ifu-sequence-\(lab)")
                return
            }
        }
        print("[VPNTest] IFU post-session: sequence — swipe down (do not tap Alternate IP / Try Alternate — those open flows)")
        app.swipeDown(velocity: .default)
    }

    /// Dismiss IFU **“VPN session ended”** feedback (backdrop / thumbs / Close / swipe). **Does not** tap Alternate IP or Try Alternate Server (those open flows). Runs **before** `logPostDisconnectPopupYesNoAndDismissIfPresent` inside `prepareUIForNextRegionSelectionAfterDisconnect`.
    @discardableResult
    func dismissIFUPostSessionFeedbackOverlayBestEffort(_ app: XCUIApplication, maxPasses: Int = 8) -> Bool {
        var didAnything = false
        for pass in 1...maxPasses {
            if !ifuPostSessionFeedbackCardVisible(app) {
                if didAnything {
                    print("[VPNTest] IFU post-session card: cleared after \(pass - 1) dismiss pass(es)")
                }
                return didAnything
            }
            print("[VPNTest] IFU post-session card: dismiss pass \(pass)/\(maxPasses)")
            didAnything = true
            var acted = false
            let b0 = app.buttons.element(boundBy: 0)
            if b0.exists, b0.isHittable, b0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("[VPNTest] IFU post-session card: tap backdrop buttons[0] (empty label)")
                tapButtonOrCenter(b0, context: "ifu-post-session-backdrop")
                acted = true
            }
            if !acted {
                let td = app.buttons["thumbsDown"]
                if td.exists, td.isHittable {
                    print("[VPNTest] IFU post-session card: tap thumbsDown")
                    tapButtonOrCenter(td, context: "ifu-post-session-thumbsDown")
                    acted = true
                }
            }
            if !acted {
                let tu = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Thumbs Up")).firstMatch
                if tu.exists, tu.isHittable {
                    print("[VPNTest] IFU post-session card: tap Thumbs Up")
                    tapButtonOrCenter(tu, context: "ifu-post-session-thumbsUp")
                    acted = true
                }
            }
            if !acted {
                for lab in ["Close", "Not now", "No thanks", "Dismiss", "Done", "OK"] {
                    let b = app.buttons[lab].firstMatch
                    if b.exists, b.isHittable {
                        print("[VPNTest] IFU post-session card: tap \"\(lab)\"")
                        tapButtonOrCenter(b, context: "ifu-post-session-\(lab)")
                        acted = true
                        break
                    }
                }
            }
            if !acted {
                print("[VPNTest] IFU post-session card: swipe down (fallback — never tap Alternate IP / Try Alternate Server)")
                app.swipeDown(velocity: .default)
            }
            sleep(1)
        }
        print("[VPNTest] IFU post-session card: still visible after \(maxPasses) passes — region list may not open")
        return didAnything
    }

    /// Re-runs dismiss passes until IFU feedback heuristics clear **or** `app.buttons` count drops back toward the lean main screen (~≤13). Uses **`oneIFUPostSessionDismissSequence`** so we still act when text labels don’t match **`ifuPostSessionFeedbackCardVisible`** yet.
    func ensureIFUPostSessionFeedbackDismissed(_ app: XCUIApplication, maxRounds: Int = 14) {
        if VPNTestConstants.isIFUTarget,
           !ifuPostSessionFeedbackCardVisible(app),
           !isRegionListPickerSheetOpen(app),
           !isVPNConnectedUI(app) {
            let s: TimeInterval = 0.35
            if app.buttons["Connect VPN"].firstMatch.waitForExistence(timeout: s)
                || app.staticTexts["Connect VPN"].firstMatch.waitForExistence(timeout: s)
                || vpnToggleOffButton(app).waitForExistence(timeout: s) {
                print("[VPNTest] IFU session card: ensure — skip rounds (already idle main, feedback gone, region sheet closed)")
                return
            }
        }
        for r in 1...maxRounds {
            let listOpen = isRegionListPickerSheetOpen(app)
            let heavyChrome = VPNTestConstants.isIFUTarget && !listOpen && app.buttons.count > 13
            let cardHeuristic = ifuPostSessionFeedbackCardVisible(app)
            if !cardHeuristic, !heavyChrome {
                if r > 1 { print("[VPNTest] IFU session card: ensure — cleared after \(r - 1) round(s) (buttons.count=\(app.buttons.count))") }
                return
            }
            print("[VPNTest] IFU session card: ensure round \(r)/\(maxRounds) (cardHeuristic=\(cardHeuristic) heavyChrome=\(heavyChrome) buttons.count=\(app.buttons.count))")
            if cardHeuristic {
                _ = dismissIFUPostSessionFeedbackOverlayBestEffort(app, maxPasses: 8)
            } else {
                oneIFUPostSessionDismissSequence(app)
            }
            sleep(1)
        }
        let sheetOpen = isRegionListPickerSheetOpen(app)
        if ifuPostSessionFeedbackCardVisible(app) || (VPNTestConstants.isIFUTarget && !sheetOpen && app.buttons.count > 13) {
            print("[VPNTest] IFU session card: ensure — WARNING may still be blocked after \(maxRounds) round(s) (buttons.count=\(app.buttons.count) regionSheetOpen=\(sheetOpen))")
        }
    }

    /// After first disconnect the IFU card can animate in **after** a second — wait, then squash feedback before list work.
    func waitAndDismissIFUPostDisconnectFeedback(_ app: XCUIApplication, settleSeconds: UInt32 = 3) {
        sleep(settleSeconds)
        ensureIFUPostSessionFeedbackDismissed(app, maxRounds: 14)
    }

    /// IFU **session-ended / feedback** (often lists **Alternate IP** as an option) must be **closed** (backdrop / thumbs / Close / swipe) — **never** tap Alternate IP or Try Alternate Server, which open flows. Then main chrome is ready for **`waitForMainConnectScreenFromButtonSnapshot`** / connect.
    func clearIFUPromoOverlaysBeforeVPNChromeWork(_ app: XCUIApplication, maxRounds: Int = 12) {
        dismissPaywallIfNeeded(app)
        var clearedReviews = 0
        while clearedReviews < 3 {
            guard dismissReviewOrRatingAlertIfPresent(app, timeout: 1.2) else { break }
            clearedReviews += 1
        }
        guard VPNTestConstants.isIFUTarget else { return }
        ensureIFUPostSessionFeedbackDismissed(app, maxRounds: maxRounds)
        dismissPaywallIfNeeded(app)
    }

    /// After a region disconnect: IFU session card → optional system Alert/Sheet poll → paywall → open region list. Pass **`pollSystemAlertOrSheet: false`** when IFU never shows iOS alerts here. **`ifuFeedbackSettleSeconds`**: brief wait before dismissing feedback (IFU card animates in after toggle-off).
    @discardableResult
    func prepareUIForNextRegionSelectionAfterDisconnect(_ app: XCUIApplication, listOpenTimeout: TimeInterval = 28, pollSystemAlertOrSheet: Bool = true, ifuFeedbackSettleSeconds: UInt32 = 2) -> Bool {
        if VPNTestConstants.isIFUTarget {
            waitAndDismissIFUPostDisconnectFeedback(app, settleSeconds: ifuFeedbackSettleSeconds)
        } else {
            _ = dismissIFUPostSessionFeedbackOverlayBestEffort(app)
            ensureIFUPostSessionFeedbackDismissed(app, maxRounds: 4)
        }
        let hadAlertOrSheet = logPostDisconnectPopupYesNoAndDismissIfPresent(app, pollForOverlaySeconds: 14, pollSystemAlertOrSheet: pollSystemAlertOrSheet)
        if !hadAlertOrSheet {
            dismissPaywallIfNeeded(app)
        }
        let rid = VPNTestConstants.AccessibilityIds.regionList
        if let host = resolveRegionListContainer(app), host.identifier == rid {
            ensureIFUPostSessionFeedbackDismissed(app, maxRounds: 6)
            return true
        }
        _ = dismissFullscreenListToMainVPNBestEffort(app, timeout: 10)
        if let host = resolveRegionListContainer(app), host.identifier == rid {
            ensureIFUPostSessionFeedbackDismissed(app, maxRounds: 6)
            return true
        }
        _ = waitForMainConnectScreen(app, timeout: 5)
        let opened = openRegionList(app, timeout: listOpenTimeout)
        if opened {
            ensureIFUPostSessionFeedbackDismissed(app, maxRounds: 6)
        }
        return opened
    }

    /// Banner + full button list (+ connect diagnostics). Call after each major UI action while stabilizing flows.
    func logTraceStep(_ title: String, _ app: XCUIApplication, includeDiagnostics: Bool = true, maxButtons: Int = 120) {
        print("\n[VPNTest] ╔════════════════════════════════════════════════════════════════════╗")
        print("[VPNTest] ║ TRACE: \(title)")
        print("[VPNTest] ╚════════════════════════════════════════════════════════════════════╝")
        logAllButtonsDetailed(app, maxButtons: maxButtons)
        if includeDiagnostics {
            logConnectScreenDiagnostics(app)
        }
    }

    /// Print every `app.buttons` entry (index, identifier, label, hittable). Use after region selection to see IFU controls (e.g. `vpn toggle off`).
    func logAllButtonsDetailed(_ app: XCUIApplication, maxButtons: Int = 120) {
        let total = app.buttons.count
        let n = min(total, maxButtons)
        print("[VPNTest] ═══ XCUIApplication.buttons dump (total.count=\(total), printing \(n)) ═══")
        for i in 0..<n {
            let b = app.buttons.element(boundBy: i)
            guard b.exists else {
                print("[VPNTest]   [\(i)] <missing>")
                continue
            }
            let id = b.identifier.replacingOccurrences(of: "\n", with: " ")
            let lab = b.label.replacingOccurrences(of: "\n", with: " ")
            print("[VPNTest]   [\(i)] identifier=\"\(id)\" label=\"\(lab)\" hittable=\(b.isHittable)")
        }
        if total > n {
            print("[VPNTest]   … \(total - n) more button(s) not printed (increase maxButtons).")
        }
        print("[VPNTest] ══════════════════════════════════════════════════════════════")
    }

    /// Log what the test sees for Connect/Disconnect: buttons, switches, and "connect"/"Status" text. Run before tapping Connect to see why the tap might fail.
    func logConnectScreenDiagnostics(_ app: XCUIApplication) {
        print("[VPNTest] ─── Connect screen diagnostics ───")
        let btnTotal = app.buttons.count
        print("[VPNTest] Buttons: \(btnTotal)")
        for i in 0..<min(btnTotal, 25) {
            let b = app.buttons.element(boundBy: i)
            guard b.exists else {
                print("[VPNTest]   [\(i)] <no element — count/hierarchy mismatch, stopping button dump>")
                break
            }
            print("[VPNTest]   [\(i)] id=\"\(b.identifier)\" label=\"\(b.label)\" hittable=\(b.isHittable)")
        }
        let swTotal = app.switches.count
        print("[VPNTest] Switches: \(swTotal)")
        for i in 0..<min(swTotal, 10) {
            let s = app.switches.element(boundBy: i)
            guard s.exists else {
                print("[VPNTest]   [\(i)] switch <missing>")
                break
            }
            print("[VPNTest]   [\(i)] id=\"\(s.identifier)\" label=\"\(s.label)\" value=\(s.value as? String ?? "?") hittable=\(s.isHittable)")
        }
        let connectLike = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "connect"))
        let connectLikeCount = min(connectLike.count, 10)
        print("[VPNTest] StaticTexts containing 'connect': \(connectLike.count)")
        for i in 0..<connectLikeCount {
            let t = connectLike.element(boundBy: i)
            guard t.exists else { break }
            print("[VPNTest]   [\(i)] label=\"\(t.label)\" hittable=\(t.isHittable)")
        }
        if app.staticTexts["Status"].firstMatch.exists {
            let status = app.staticTexts["Status"].firstMatch
            print("[VPNTest] 'Status' text exists, hittable=\(status.isHittable)")
        }
        print("[VPNTest] ─────────────────────────────────")
    }

    /// Print a short summary of the app's accessibility tree (for debugging when region list or Connect/Disconnect isn't found).
    func logAccessibilitySummary(_ app: XCUIApplication) {
        let tables = app.tables.count
        let collections = app.collectionViews.count
        let scrolls = app.scrollViews.count
        let buttons = app.buttons.count
        let staticTexts = app.staticTexts.count
        let cells = app.cells.count
        let otherCount = app.otherElements.count
        print("[VPNTest] Accessibility summary — tables: \(tables), collectionViews: \(collections), scrollViews: \(scrolls), cells: \(cells), buttons: \(buttons), staticTexts: \(staticTexts), otherElements: \(otherCount)")
        let buttonSample = min(20, buttons)
        if buttonSample > 0 {
            print("[VPNTest] Buttons (id / label):")
            for i in 0..<buttonSample {
                let b = app.buttons.element(boundBy: i)
                guard b.exists else { break }
                let id = b.identifier
                let label = b.label
                print("[VPNTest]   [\(i)] id=\"\(id)\" label=\"\(label)\" hittable=\(b.isHittable)")
            }
        }
        let textSample = min(20, staticTexts)
        if textSample > 0 {
            var labels: [String] = []
            for i in 0..<textSample {
                labels.append(app.staticTexts.element(boundBy: i).label)
            }
            print("[VPNTest] First \(textSample) staticText labels: \(labels)")
        }
        if cells > 0 {
            for i in 0..<min(5, cells) {
                let c = app.cells.element(boundBy: i)
                print("[VPNTest] app.cells[\(i)] label: \"\(c.label)\"")
            }
        }
    }

    /// Find the Connect/Disconnect control. For connect: prefer "Connect VPN" button; for disconnect use switch beside "Connected".
    func findVPNToggle(_ app: XCUIApplication, forDisconnect: Bool, requireHittable: Bool = true, timeout: TimeInterval = 8) -> XCUIElement? {
        let id = VPNTestConstants.AccessibilityIds.connectButton
        let waitPerTry = min(5.0, max(2.0, timeout / 3))
        if forDisconnect {
            let vpnOn = vpnToggleOnButton(app)
            if vpnOn.waitForExistence(timeout: waitPerTry), (!requireHittable || vpnOn.isHittable) { return vpnOn }
            let switchById = app.switches[id].firstMatch
            if switchById.waitForExistence(timeout: waitPerTry), (!requireHittable || switchById.isHittable) { return switchById }
            if app.switches.count > 0, app.switches.firstMatch.waitForExistence(timeout: 1), (!requireHittable || app.switches.firstMatch.isHittable) { return app.switches.firstMatch }
            return nil
        }
        // Connect: prefer button / "Connect VPN" so we don't tap the wrong control
        let vpnOff = vpnToggleOffButton(app)
        if vpnOff.waitForExistence(timeout: 2), (!requireHittable || vpnOff.isHittable) { return vpnOff }
        let btnById = app.buttons[id].firstMatch
        if btnById.waitForExistence(timeout: waitPerTry), (!requireHittable || btnById.isHittable) { return btnById }
        let anyWithId = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", id)).firstMatch
        if anyWithId.waitForExistence(timeout: waitPerTry), (!requireHittable || anyWithId.isHittable) { return anyWithId }
        for connectLabel in ["Connect VPN", "Tap to Connect", "Tap to Connect VPN", "Connect"] {
            let b = app.buttons[connectLabel].firstMatch
            if b.waitForExistence(timeout: 1), (!requireHittable || b.isHittable) { return b }
            let s = app.staticTexts[connectLabel].firstMatch
            if s.waitForExistence(timeout: 1), (!requireHittable || s.isHittable) { return s }
        }
        let anyConnect = app.descendants(matching: .any).containing(NSPredicate(format: "label CONTAINS[c] %@", "connect")).firstMatch
        if anyConnect.waitForExistence(timeout: 1), (!requireHittable || anyConnect.isHittable) { return anyConnect }
        if app.switches.count > 0, app.switches.firstMatch.waitForExistence(timeout: 1), (!requireHittable || app.switches.firstMatch.isHittable) { return app.switches.firstMatch }
        return nil
    }

    /// Call after giving the app 2–3s post-connect so the UI has turned green. Takes a fresh snapshot (re-queries the app),
    /// finds the "Connected" area (green), then taps the green switch/button beside it to disconnect.
    @discardableResult
    func tapDisconnectSwitchWhenConnectedVisible(_ app: XCUIApplication, timeout: TimeInterval = 15) -> Bool {
        guard app.staticTexts["Connected"].firstMatch.waitForExistence(timeout: timeout) else { return false }
        let id = VPNTestConstants.AccessibilityIds.connectButton
        var sw = app.switches[id].firstMatch
        if !sw.waitForExistence(timeout: 1) || !sw.isHittable {
            sw = app.switches.firstMatch
        }
        guard sw.waitForExistence(timeout: 2), sw.isHittable else { return false }
        sw.tap()
        return true
    }

    /// After a disconnect tap, the tunnel may be down but **Connected** text can still exist behind a system alert. Treat alert/sheet as “past connected” for idle waits.
    func isVPNDisconnectedOrDialogPresent(_ app: XCUIApplication) -> Bool {
        if app.alerts.firstMatch.waitForExistence(timeout: 0.35) { return true }
        if app.sheets.firstMatch.waitForExistence(timeout: 0.35) { return true }
        return !isVPNConnectedUI(app)
    }

    /// Bounded existence so XCTest does not hang on `.exists` / hierarchy rebuild (can exceed 30s and fail the test run).
    private func boundedElementExists(_ element: XCUIElement, timeout: TimeInterval = 0.4) -> Bool {
        element.waitForExistence(timeout: timeout)
    }

    /// True when the UI looks VPN-connected: exact status labels, ON switch, or disconnect affordance.
    /// Avoids matching "Disconnected" via a naive "connected" substring check.
    func isVPNConnectedUI(_ app: XCUIApplication) -> Bool {
        let connectId = VPNTestConstants.AccessibilityIds.connectButton
        let slice: TimeInterval = 0.4
        if boundedElementExists(app.staticTexts["Connected"].firstMatch, timeout: slice) { return true }
        if boundedElementExists(app.buttons["Connected"].firstMatch, timeout: slice) { return true }
        for exact in ["VPN Connected", "Protected", "Secure connection"] {
            if boundedElementExists(app.staticTexts[exact].firstMatch, timeout: slice) { return true }
        }
        let swId = app.switches[connectId].firstMatch
        if boundedElementExists(swId, timeout: slice), (swId.value as? String) == "1" { return true }
        let s0 = app.switches.firstMatch
        if boundedElementExists(s0, timeout: slice), (s0.value as? String) == "1" { return true }
        if boundedElementExists(app.buttons["Disconnect VPN"].firstMatch, timeout: slice) { return true }
        if boundedElementExists(app.staticTexts["Disconnect VPN"].firstMatch, timeout: slice) { return true }
        if boundedElementExists(vpnToggleOnButton(app), timeout: slice) { return true }
        return false
    }

    /// Poll until connected UI appears or timeout.
    @discardableResult
    func waitForVPNConnectedUI(_ app: XCUIApplication, timeout: TimeInterval = 45) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var lastFeedbackDismiss = Date.distantPast
        while Date() < deadline {
            if isVPNConnectedUI(app) {
                print("[VPNTest] milestone: Connected showing on screen")
                return true
            }
            if VPNTestConstants.isIFUTarget,
               Date().timeIntervalSince(lastFeedbackDismiss) >= 2.0,
               ifuPostSessionFeedbackCardVisible(app) {
                print("[VPNTest] IFU feedback visible while waiting for Connected — dismiss sheet (no Alternate-IP tap), then re-check")
                ensureIFUPostSessionFeedbackDismissed(app, maxRounds: 6)
                lastFeedbackDismiss = Date()
                continue
            }
            usleep(300_000)
        }
        return false
    }

    private func tapButtonOrCenter(_ el: XCUIElement, context: String) {
        guard el.exists else {
            print("[VPNTest] \(context): skip tap — element does not exist")
            return
        }
        if el.isHittable {
            el.tap()
            return
        }
        print("[VPNTest] \(context): not hittable — coordinate tap center")
        guard el.exists else { return }
        el.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// IFU connected: **`firstMatch` for `vpn toggle` is often wrong** (promo rows). Enumerate matches, log each, then tap best: label contains **on**, else **off**, else last match (coordinate tap if needed).
    @discardableResult
    func tapIFUVPNDisconnectByScanningVpnToggleButtons(_ app: XCUIApplication) -> Bool {
        let q = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "vpn toggle"))
        let raw = q.count
        let n = min(raw, 20)
        if n == 0 {
            print("[VPNTest] IFU disconnect scan: 0 buttons matching label CONTAINS 'vpn toggle' (query.count=\(raw))")
            return false
        }
        print("[VPNTest] IFU disconnect scan: \(raw) button(s) match 'vpn toggle'; listing \(n)")
        for i in 0..<n {
            let b = q.element(boundBy: i)
            guard b.exists else { continue }
            print("[VPNTest]   vpn-toggle[\(i)] label=\"\(b.label)\" hittable=\(b.isHittable)")
        }
        let labLower = { (s: String) -> String in s.lowercased() }
        for i in (0..<n).reversed() {
            let b = q.element(boundBy: i)
            guard b.exists else { continue }
            if labLower(b.label).contains("on") {
                print("[VPNTest] IFU disconnect: chosen vpn-toggle[\(i)] (label contains 'on')")
                tapButtonOrCenter(b, context: "IFU vpn-toggle[\(i)]")
                return true
            }
        }
        for i in (0..<n).reversed() {
            let b = q.element(boundBy: i)
            guard b.exists else { continue }
            if labLower(b.label).contains("off") {
                print("[VPNTest] IFU disconnect: chosen vpn-toggle[\(i)] (label contains 'off'; IFU may keep off label while connected)")
                tapButtonOrCenter(b, context: "IFU vpn-toggle[\(i)]")
                return true
            }
        }
        for i in (0..<n).reversed() {
            let b = q.element(boundBy: i)
            guard b.exists else { continue }
            print("[VPNTest] IFU disconnect: chosen vpn-toggle[\(i)] (fallback last existing match)")
            tapButtonOrCenter(b, context: "IFU vpn-toggle[\(i)]")
            return true
        }
        return false
    }

    /// Disconnect: explicit **Disconnect VPN** / **Disconnect**, then IFU **vpn-toggle** scan (not `firstMatch`), then switches / `findVPNToggle`.
    @discardableResult
    func tapVPNDisconnectBestEffort(_ app: XCUIApplication, timeout: TimeInterval = 15) -> Bool {
        func disconnectConfirmed() -> Bool {
            if isVPNDisconnectedOrDialogPresent(app) {
                if app.alerts.firstMatch.exists || app.sheets.firstMatch.exists {
                    print("[VPNTest] milestone: Disconnected button successful (dialog visible; tunnel treated as disconnected for automation)")
                } else {
                    print("[VPNTest] milestone: Disconnected button successful (connected UI cleared)")
                }
                return true
            }
            return false
        }
        guard isVPNConnectedUI(app) else {
            print("[VPNTest] Disconnect: not in connected UI — skipping disconnect taps")
            return true
        }
        for title in ["Disconnect VPN", "Disconnect"] {
            let b = app.buttons[title].firstMatch
            if b.waitForExistence(timeout: 2), b.exists {
                print("[VPNTest] Disconnect: tapping app.buttons[\"\(title)\"]")
                tapButtonOrCenter(b, context: "Disconnect \"\(title)\"")
                sleep(2)
                if disconnectConfirmed() { return true }
            }
        }
        if VPNTestConstants.isIFUTarget {
            if tapIFUVPNDisconnectByScanningVpnToggleButtons(app) {
                sleep(2)
                if disconnectConfirmed() { return true }
            }
        } else {
            let anyVpn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "vpn toggle")).firstMatch
            if anyVpn.waitForExistence(timeout: 4), anyVpn.exists {
                print("[VPNTest] Disconnect: tap generic vpn-toggle (label=\"\(anyVpn.label)\")")
                tapButtonOrCenter(anyVpn, context: "vpn-toggle firstMatch")
                sleep(2)
                if disconnectConfirmed() { return true }
            }
        }
        let onBtn = vpnToggleOnButton(app)
        if onBtn.waitForExistence(timeout: 3), onBtn.exists {
            print("[VPNTest] Disconnect: tap vpn-toggle-on predicate (label=\"\(onBtn.label)\")")
            tapButtonOrCenter(onBtn, context: "vpn-toggle-on")
            sleep(2)
            if disconnectConfirmed() { return true }
        }
        if tapDisconnectSwitchWhenConnectedVisible(app, timeout: timeout) {
            sleep(2)
            if disconnectConfirmed() { return true }
            print("[VPNTest] milestone: Disconnected button successful (disconnect switch tap sent)")
            return true
        }
        let connectId = VPNTestConstants.AccessibilityIds.connectButton
        let sw = app.switches[connectId].firstMatch
        if sw.waitForExistence(timeout: 3), sw.isHittable, (sw.value as? String) == "1" {
            sw.tap()
            sleep(1)
            if disconnectConfirmed() { return true }
        }
        if app.switches.count > 0 {
            let s = app.switches.firstMatch
            if s.waitForExistence(timeout: 2), s.isHittable, (s.value as? String) == "1" {
                s.tap()
                sleep(1)
                if disconnectConfirmed() { return true }
            }
        }
        if tapVPNToggle(app, forDisconnect: true, timeout: timeout) {
            print("[VPNTest] Disconnect: tapVPNToggle disconnect path executed")
            sleep(2)
            if disconnectConfirmed() { return true }
        }
        sleep(1)
        if app.alerts.firstMatch.waitForExistence(timeout: 4) {
            print("[VPNTest] milestone: Disconnected button successful (alert appeared after disconnect attempts)")
            return true
        }
        if app.sheets.firstMatch.waitForExistence(timeout: 2) {
            print("[VPNTest] milestone: Disconnected button successful (sheet appeared after disconnect attempts)")
            return true
        }
        print("[VPNTest] milestone: Disconnected button NOT confirmed (connected UI still present, no alert/sheet)")
        return false
    }

    /// Tap the VPN Connect/Disconnect toggle. Uses findVPNToggle; if normal tap fails, tries coordinate-based tap.
    @discardableResult
    func tapVPNToggle(_ app: XCUIApplication, forDisconnect: Bool, timeout: TimeInterval = 10) -> Bool {
        guard let el = findVPNToggle(app, forDisconnect: forDisconnect, requireHittable: false, timeout: timeout), el.exists else { return false }
        let label = el.label
        if forDisconnect {
            print("[VPNTest] Disconnect: tapping (id=\(el.identifier), label=\"\(label)\")")
        } else {
            print("[VPNTest] Connect: tapping (id=\(el.identifier), label=\"\(label)\")")
        }
        if el.isHittable {
            el.tap()
            return true
        }
        el.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return true
    }

    /// Poll every `pollUs` microseconds until `predicate()` is true. Returns elapsed seconds from **this call’s start**, or nil if `timeout` hit.
    func measureSecondsUntil(
        timeout: TimeInterval,
        pollUs: useconds_t = 5_000,
        predicate: () -> Bool
    ) -> TimeInterval? {
        let start = CFAbsoluteTimeGetCurrent()
        let deadline = start + timeout
        while CFAbsoluteTimeGetCurrent() < deadline {
            if predicate() {
                return CFAbsoluteTimeGetCurrent() - start
            }
            usleep(pollUs)
        }
        return nil
    }

    /// Best-effort: leave app disconnected so connect timing starts from a clean UI.
    func prepareDisconnectedState(_ app: XCUIApplication) {
        if isVPNConnectedUI(app) {
            _ = tapVPNDisconnectBestEffort(app, timeout: 20)
            _ = measureSecondsUntil(timeout: 22, pollUs: 10_000) { self.isVPNDisconnectedOrDialogPresent(app) }
        }
        sleep(1)
    }

    /// IFU **row 0**: skip Connect (auto-connect). **Any other case**: one linear **`app.buttons`** snapshot → **one** tap (`tapConnectFromVisibleButtonSnapshot`) — no `findVPNToggle` / `tapIFUVPNConnectQuick` multi-query.
    @discardableResult
    func tapConnectAfterRegionSelectIfNeeded(_ app: XCUIApplication, rowIndex: Int) -> Bool {
        if VPNTestConstants.isIFUTarget, rowIndex == 0 {
            print("[VPNTest] IFU row \(rowIndex): skip explicit Connect tap (expect auto-connect after select)")
            return true
        }
        sleep(1)
        print("[VPNTest] row \(rowIndex): connect via **button snapshot** only (no multi-tag `buttons[\"…\"]` search)")
        return tapConnectFromVisibleButtonSnapshot(app)
    }

    /// IFU fast path: tap `vpn toggle off` (or any `vpn toggle`) to connect — skips long `findVPNToggle` search when possible.
    @discardableResult
    func tapIFUVPNConnectQuick(_ app: XCUIApplication) -> Bool {
        if isVPNConnectedUI(app) {
            print("[VPNTest] milestone: Connect VPN successful (already showing connected UI)")
            return true
        }
        let off = vpnToggleOffButton(app)
        if off.waitForExistence(timeout: 3), off.isHittable {
            print("[VPNTest] IFU connect: vpnToggleOffButton (\(off.label))")
            off.tap()
            print("[VPNTest] milestone: Connect VPN successful (vpn toggle tapped)")
            return true
        }
        let any = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "vpn toggle")).firstMatch
        if any.waitForExistence(timeout: 2), any.isHittable {
            print("[VPNTest] IFU connect: first 'vpn toggle' button (\(any.label))")
            any.tap()
            print("[VPNTest] milestone: Connect VPN successful (vpn toggle tapped)")
            return true
        }
        let ok = tapVPNToggle(app, forDisconnect: false, timeout: 12)
        if ok { print("[VPNTest] milestone: Connect VPN successful (Connect VPN control tapped)") }
        return ok
    }

    /// Open region list, tap row `rowIndex`, return success + row title from accessibility.
    /// Set `skipOpenRegionList` when the list is already open (e.g. right after `captureRegionListCatalog`).
    /// Set **`assumeListAlreadyAtTop`** when the caller already scrolled the list to the top (avoids a second scroll + re-query of row 0).
    @discardableResult
    func selectRegionListRowByIndex(_ app: XCUIApplication, rowIndex: Int, listTimeout: TimeInterval = 18, skipOpenRegionList: Bool = false, assumeListAlreadyAtTop: Bool = false) -> (ok: Bool, label: String) {
        if !skipOpenRegionList {
            guard openRegionList(app, timeout: listTimeout) else {
                print("[VPNTest] selectRegionListRowByIndex: openRegionList failed")
                return (false, "")
            }
        } else if resolveRegionListContainer(app) == nil {
            guard openRegionList(app, timeout: listTimeout) else {
                print("[VPNTest] selectRegionListRowByIndex: skipOpen set but list not visible; reopen failed")
                return (false, "")
            }
        }
        usleep(400_000)
        guard let host = resolveRegionListContainer(app) else {
            print("[VPNTest] selectRegionListRowByIndex: no list host")
            return (false, "")
        }
        if assumeListAlreadyAtTop {
            print("[VPNTest] selectRegionListRowByIndex: skipping scroll-to-top (caller already aligned list) before row \(rowIndex)")
        } else {
            scrollRegionListToTop(host: host, maxSwipeDown: 8)
            usleep(240_000)
            print("[VPNTest] selectRegionListRowByIndex: scrolled list to top before row \(rowIndex)")
        }
        let cells = host.cells
        guard rowIndex < cells.count else {
            print("[VPNTest] selectRegionListRowByIndex: row \(rowIndex) >= cells.count \(cells.count)")
            return (false, "")
        }
        let cell = cells.element(boundBy: rowIndex)
        guard cell.waitForExistence(timeout: 8) else { return (false, "") }
        let label = regionRowDisplayLabel(cell)
        print("[VPNTest] selectRegionListRowByIndex: tapping row \(rowIndex) name=\"\(label)\" (scroll into view: swipeUp only — no swipe-down recovery)")
        scrollCellIntoViewSwipeUpOnly(cell, host: host, maxSwipes: 22)
        if cell.isHittable {
            cell.tap()
        } else {
            cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        sleep(1)
        let ok = waitForMainConnectScreenFromButtonSnapshot(app, timeout: 22)
        if !ok {
            print("[VPNTest] selectRegionListRowByIndex: main screen not ready (button snapshot) after row \(rowIndex)")
        }
        return (ok, label)
    }
}
