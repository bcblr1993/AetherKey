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
    let kConnectionName = (Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String) ?? "\(bundleID)_1_Connection"

    server = IMKServer(name: kConnectionName, bundleIdentifier: bundleID)

    let delegate = AppDelegate()
    appDelegate = delegate
    app.delegate = delegate
}

app.run()

