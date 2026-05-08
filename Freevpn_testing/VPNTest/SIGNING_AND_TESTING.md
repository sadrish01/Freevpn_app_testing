# Why You See Signing Errors & How to Test on USB Device

## What the errors mean

When you run `./run_tests.sh --quick-connect` (or any test), **two things** get built and **installed on your USB iPhone**:

1. **VPNTestHost** (bundle: `com.example.VPNTestHost`) – a small host app
2. **VPNTestUITests** (bundle: `com.example.VPNTestUITests.xctrunner`) – the test runner that drives the UI

Your **TestFlight app** is **not** built or signed by this project. It stays as-is on the device. The test runner **attaches to** one app by its **bundle ID** and sends taps (Connect, Disconnect, etc.). Which app it uses is set in `VPNTestConstants.swift` → `vpnAppBundleIdentifier`. If you open **IFU** (Free VPN US) from TestFlight, that app’s bundle ID is **`org.freevpn.vpn.us`**. If the constant was **`com.actmobile.dashvpn`** (IDV), the test would activate/launch **IDV** instead of your open IFU app. So the constant must match the app you’re testing (IFU = `org.freevpn.vpn.us`, IDV = `com.actmobile.dashvpn`).

The errors you see mean:

| Error | Meaning |
|-------|--------|
| **No profiles for 'com.example.VPNTestHost'** | Xcode could not find (or create) a provisioning profile to install the **test host app** on your device. |
| **No profiles for 'com.example.VPNTestUITests.xctrunner'** | Same for the **test runner** that runs on the device. |
| **Unable to log in with account 'actmobile@actmobile.com'. Login details rejected** | The Apple ID used for signing (actmobile@actmobile.com) could not be used: wrong password, 2FA not completed, session expired, or account restricted. |

So: **testing on the USB device is blocked because the test host + test runner cannot be signed and installed.** The TestFlight app itself does not need to be re-signed.

---

## How to fix it (so tests run on USB device)

You need **one** Apple Developer account that can install apps on your iPhone:

1. **Open** `VPNTest.xcodeproj` in Xcode.
2. **Select the project** (blue icon) → **Signing & Capabilities** for:
   - **VPNTestHost**
   - **VPNTestUITests**
3. **Team:**
   - If **actmobile@actmobile.com** is correct: in Xcode go to **Xcode → Settings → Accounts**, select that account, and **sign in again** (or fix password/2FA). Then ensure that team is selected for both targets.
   - If you prefer to use **your personal Apple ID**: choose your **Personal Team** (or your company team) for both VPNTestHost and VPNTestUITests. Enable **Automatically manage signing**.
4. **Connect your iPhone via USB**, unlock it, tap **Trust** if asked.
5. Run again:
   ```bash
   ./run_tests.sh --quick-connect
   ```
6. When the script says **“Open the VPN app on your iPhone”**, open the app from **TestFlight** (or home screen), then press Enter. The test will run on the **USB device** and drive the TestFlight app.

No simulator is involved; the script is set up for **USB device only**.

---

## XCUITest vs Appium (what you have vs “Appium trigger”)

- **What you have now:** **XCUITest** – the script runs `xcodebuild test`, which builds the test runner, installs it on the device, and runs your Swift tests. You launch the TestFlight app when the script asks, then tests run on the USB device.
- **Appium:** A separate stack (Appium server + client in Python/JS/etc. + WebDriverAgent on the device). Appium can also drive an app already installed (e.g. from TestFlight) by **bundle ID**, without building the app. But the **driver** (e.g. WebDriverAgent) still must be **built and signed** and installed on the device once; you can get similar “no profiles” / “login rejected” errors for that driver until signing is fixed.

So:

- **“Test on USB device when I launch app through TestFlight”** – you can do that with the **current XCUITest setup** once signing is fixed: run the script, open the app from TestFlight when prompted, tests run on the USB device.
- **“Appium to trigger testing”** – that would mean adding an Appium-based flow (separate from this Xcode project). The TestFlight app would still be the app under test; the “trigger” would be your Appium test script starting a session with that bundle ID on the USB device. You’d still need to sign and install the iOS driver (e.g. WebDriverAgent) once.

If you want to stick with the current script and USB-only testing, fixing signing as above is enough. If you want to move to Appium, the next step is to set up Appium + WebDriverAgent (or equivalent) and point it at your TestFlight app’s bundle ID on the USB device.
