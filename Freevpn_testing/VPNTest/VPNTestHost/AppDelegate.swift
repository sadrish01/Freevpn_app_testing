//
//  AppDelegate.swift
//  VPNTestHost
//
//  Minimal host app for UI test target. Tests launch the VPN app by bundle ID.
//

import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UIViewController()
        window?.backgroundColor = .systemBackground
        window?.makeKeyAndVisible()
        return true
    }
}
