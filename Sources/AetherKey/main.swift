import AppKit
import InputMethodKit

let kConnectionName = "AetherKey_1_Connection"

guard let bundleID = Bundle.main.bundleIdentifier else {
    fatalError("Missing bundle identifier in Info.plist")
}

// Initialize IMKServer matching connection name in Info.plist
let server = IMKServer(name: kConnectionName, bundleIdentifier: bundleID)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
