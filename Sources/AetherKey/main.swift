import AppKit
import InputMethodKit

let app = NSApplication.shared

let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
                ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil ||
                NSClassFromString("XCTestCase") != nil

// Retain globally to prevent ARC deallocation
var server: IMKServer?
var appDelegate: AppDelegate?

if !isTesting {
    let bundleID = Bundle.main.bundleIdentifier ?? "com.aethernative.inputmethod.AetherKey"
    let bundleURL = Bundle.main.bundleURL
    var didRefreshBundleOnLaunch = false
    if InputMethodRegistrar.isInstalledInputMethodPath(bundleURL),
       let fingerprint = InputMethodRegistrar.bundleFingerprint(at: bundleURL),
       InputMethodRegistrar.shouldRefreshForBundleChange(
           currentFingerprint: fingerprint,
           lastRecordedFingerprint: InputMethodRegistrar.lastRecordedFingerprint()
       ) {
        InputMethodRegistrar.recordRegisteredFingerprint(fingerprint)
        InputMethodRegistrar.prepareFreshSystemAgentsSynchronously(bundleURL: bundleURL)
        didRefreshBundleOnLaunch = true
    }

    let kConnectionName = (Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String) ?? "\(bundleID)_Connection"

    server = IMKServer(name: kConnectionName, bundleIdentifier: bundleID)

    let delegate = AppDelegate(didRefreshBundleOnLaunch: didRefreshBundleOnLaunch)
    appDelegate = delegate
    app.delegate = delegate
}

app.run()

