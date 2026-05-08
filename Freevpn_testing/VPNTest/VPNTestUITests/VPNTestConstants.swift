//
//  VPNTestConstants.swift
//  VPNTestUITests
//
//  Constants and configuration for VPN app UI testing.
//
//  IFU app (client/iOS/Dash/Targets/IFU):
//  - Region list: RegionSelectorTableVC.regionsListTableView (IFU.storyboard id P9i-b1-Fqt).
//    Set accessibilityIdentifier = "regionList" in RegionSelectorTableVC.m viewDidLoad → test uses AccessibilityIds.regionList.
//  - Connect button: VPN2VC.btnConnectVPN (outlet to storyboard id wpI-MF-ayL). Image-only in storyboard; set
//    accessibilityLabel = "Connect VPN" and accessibilityIdentifier = "connectButton" in VPN2VC.m → test uses AccessibilityIds.connectButton or button "Connect VPN".
//  - Cell reuse: regionsTableCell; cell label shows region name (e.g. "United States East", "Fastest").
//
//  Bundle IDs (actproxy iOS Dash — source lives under your actproxy/client tree; this repo only runs tests):
//  - IFU (Free VPN US, TestFlight): org.freevpn.vpn.us
//  - IDV:                          com.actmobile.dashvpn
//

import Foundation

enum VPNTestConstants {
    /// Bundle identifier of the VPN app under test (the app you open from TestFlight).
    /// IFU (Free VPN US) = org.freevpn.vpn.us | IDV = com.actmobile.dashvpn
    static let vpnAppBundleIdentifier = "org.freevpn.vpn.us"

    /// Short-name → bundle id for Dash-family apps (common VPN2 / regionList / connectButton ids; skins differ).
    /// Override any time: `VPNTEST_BUNDLE_ID=com.my.bundle xcodebuild test …` takes precedence.
    /// Or: `VPNTEST_APP=ifu` …
    private static let vpnAppBundleByAlias: [String: String] = [
        "ifu": "org.freevpn.vpn.us",
        "idv": "com.actmobile.dashvpn",
        "dashvpn": "com.actmobile.dashvpn",
        // Add your other TestFlight / debug bundle IDs when you wire them:
        // "brand3": "com.example.vpn3",
    ]

    /// Active target for `XCUIApplication(bundleIdentifier:)`.
    static var resolvedVPNAppBundleIdentifier: String {
        let env = ProcessInfo.processInfo.environment
        if let full = env["VPNTEST_BUNDLE_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines), !full.isEmpty {
            return full
        }
        if let key = env["VPNTEST_APP"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           let bid = vpnAppBundleByAlias[key], !bid.isEmpty {
            return bid
        }
        return vpnAppBundleIdentifier
    }

    /// IFU (Free VPN US) bundle — used for faster region-bar hints and vpn-toggle-only connect path.
    static let ifuBundleIdentifier = "org.freevpn.vpn.us"

    static var isIFUTarget: Bool {
        resolvedVPNAppBundleIdentifier == ifuBundleIdentifier
    }

    /// On IFU, try these home **region bar** labels first (connected home often shows **US East** / etc.; list itself anchors on **Current Location** in `resolveRegionListContainer`).
    static let ifuRegionSelectorQuickHints: [String] = ["Current Location", "US East", "Fastest", "US West", "Europe", "Asia"]

    /// Tappable home-screen region selector labels (IFU + variants). Extend per SKU after inspecting UI.
    static let regionSelectorHints: [String] = [
        "Current Location", "US East", "Fastest", "US West", "Europe", "Asia",
        "United States East", "United States", "Auto", "Best location", "Fastest server",
    ]

    /// `openRegionList` uses this: IFU prepends `ifuRegionSelectorQuickHints` (deduped), others use `regionSelectorHints` only.
    static var regionSelectorHintsOrdered: [String] {
        if !isIFUTarget { return regionSelectorHints }
        var seen = Set<String>()
        var out: [String] = []
        for h in ifuRegionSelectorQuickHints + regionSelectorHints {
            let k = h.lowercased()
            if seen.contains(k) { continue }
            seen.insert(k)
            out.append(h)
        }
        return out
    }

    /// Launch stability test configuration
    static let launchStabilityIterations = 20
    static let launchStabilityDurationSeconds: UInt32 = 60

    /// Region connection test configuration
    static let regionConnectionRegionCount = 5
    static let regionConnectionRoundsPerRegion = 50
    static let regionConnectionDurationSeconds: UInt32 = 60

    /// Accessibility identifiers - update to match your VPN app's UI.
    /// Use Xcode Accessibility Inspector or app source to find actual identifiers.
    enum AccessibilityIds {
        /// Main table/list showing regions
        static let regionList = "regionList"
        /// Cell identifier for region rows (table view cells)
        static let regionCell = "regionCell"
        /// Connect / Disconnect control (button or green toggle switch next to "Connected")
        static let connectButton = "connectButton"
        /// Region icon image (within each cell)
        static let regionIcon = "regionIcon"
        /// Optional: header or title for region list
        static let regionListTitle = "regionListTitle"
        /// IFU / Dash: optional table id for the Services screen (set in app if known). Tests also scan non-`regionList` tables.
        static let servicesListCandidates = ["servicesList", "serviceList", "servicesTable", "serviceTable"]
    }

    /// Tries to open the in-app Services / Apps / Streaming list (tab bar, button, or static text).
    static let servicesEntryHints: [String] = [
        "Services", "Service", "Apps", "Streaming", "Browse", "Add-ons", "Addons", "Features", "More",
    ]

    /// IFU: try common tab labels first, then the rest.
    static var servicesEntryHintsOrdered: [String] {
        if !isIFUTarget { return servicesEntryHints }
        var seen = Set<String>()
        var out: [String] = []
        for h in ["Services", "Service", "Apps", "Streaming", "Browse"] + servicesEntryHints {
            let k = h.lowercased()
            if seen.contains(k) { continue }
            seen.insert(k)
            out.append(h)
        }
        return out
    }

    /// Labels for "Fastest" region (try in order; update to match your app)
    static let fastestRegionLabels = ["Fastest", "fastest", "Automatic", "Auto", "Best"]

    /// Connect button: try these labels if no accessibility id (IFU, IDV, etc.)
    static let connectButtonLabels = ["Connect", "Tap to Connect", "Tap to Connect VPN", "Connect VPN"]

    /// Timeouts
    static let defaultTimeout: TimeInterval = 15
    static let elementWaitTimeout: TimeInterval = 10
    /// When using "Launch App" prompt: max time to wait for user to open app from TestFlight
    static let manualLaunchWaitTimeout: TimeInterval = 90
    /// Max time to wait for region list to appear (fail fast if app is on paywall or wrong screen)
    static let waitForRegionListAfterLaunch: TimeInterval = 15

    /// Region index to select: 0 = first row in list, 1 = second row (use when first is "Connect to Fastest").
    static let regionSelectionIndex = 0

    /// Label at top of region list to skip (do not tap this — tap the region at regionSelectionIndex instead).
    static let regionListSkipLabel = "Connect to Fastest"

    /// Max time to wait for the Connect/Disconnect button to show "Disconnect" or "Connected" after connect.
    static let waitForDisconnectStateTimeout: TimeInterval = 20

    /// Hard cap while polling for connected / disconnected UI (seconds).
    static let transitionMeasureHardTimeout: TimeInterval = 60

    /// After Connect tap: connected UI must appear within this many seconds (default 1). Relax: `VPNTEST_CONNECT_UI_THRESHOLD_SEC=5`.
    static var uiThresholdConnectTransitionSeconds: TimeInterval {
        thresholdFromEnv(key: "VPNTEST_CONNECT_UI_THRESHOLD_SEC", default: 1.0)
    }

    /// After Disconnect tap: disconnected UI must appear within this many seconds (default 1). Relax: `VPNTEST_DISCONNECT_UI_THRESHOLD_SEC=5`.
    static var uiThresholdDisconnectTransitionSeconds: TimeInterval {
        thresholdFromEnv(key: "VPNTEST_DISCONNECT_UI_THRESHOLD_SEC", default: 1.0)
    }

    private static func thresholdFromEnv(key: String, default def: TimeInterval) -> TimeInterval {
        guard let s = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              let v = Double(s), v > 0 else { return def }
        return v
    }
}
