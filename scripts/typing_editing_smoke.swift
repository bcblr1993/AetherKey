import AppKit
import Carbon
import CoreGraphics

// Run in the dedicated QA VM only, with user-authorized CGEvent access.
// Focus TextEdit on this script's test document first. Every keystroke checks focus.
func abort(_ message: String) -> Never { print("ABORT:", message); exit(2) }
let args = CommandLine.arguments
let action = args.count > 1 ? args[1] : "status"
if action == "activate" {
    guard let editor = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first else { abort("TextEdit is not running") }
    editor.activate(options: [.activateAllWindows])
    exit(0)
}
guard CGPreflightPostEventAccess() else { abort("CGEvent access unavailable") }
let filter = [kTISPropertyInputSourceID as String: "com.aethernative.inputmethod.AetherKey.Hans"] as CFDictionary
guard let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
      let source = sources.first else { abort("Input source missing") }
if action == "select" {
    // Reconnect the host's IMK session after replacing/restarting the test app.
    let asciiFilter = [kTISPropertyInputSourceID as String: "com.apple.keylayout.ABC"] as CFDictionary
    if let list = TISCreateInputSourceList(asciiFilter, true)?.takeRetainedValue() as? [TISInputSource], let ascii = list.first {
        _ = TISSelectInputSource(ascii)
        Thread.sleep(forTimeInterval: 0.2)
    }
    guard TISSelectInputSource(source) == noErr else { abort("Cannot select AetherKey") }
    print("AetherKey selected"); exit(0)
}
func key(_ code: CGKeyCode, _ flags: CGEventFlags = []) {
    guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.TextEdit" else {
        abort("TextEdit lost focus; aborting before sending a key")
    }
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        event.flags = flags
        event.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.015)
    }
    Thread.sleep(forTimeInterval: 0.08)
}
let codes: [Character: CGKeyCode] = ["a":0,"b":11,"c":8,"d":2,"e":14,"f":3,"g":5,"h":4,"i":34,"j":38,"k":40,"l":37,"m":46,"n":45,"o":31,"p":35,"q":12,"r":15,"s":1,"t":17,"u":32,"v":9,"w":13,"x":7,"y":16,"z":6,"'":39,";":41]
func type(_ text: String) { for c in text { key(codes[c]!) } }
switch action {
case "type": type(args[2])
case "key": key(CGKeyCode(args[2])!)
case "pin": key(35, [.maskControl, .maskAlternate])
case "unpin": key(32, [.maskControl, .maskAlternate])
case "forget": key(51, [.maskControl, .maskAlternate])
case "edit":
    type("niha"); key(123); type("o"); key(117); key(123); type("a")
case "syllable":
    type("ni'hao"); key(123, .maskAlternate); key(51, .maskAlternate)
case "commit": key(49); key(36); key(1, .maskCommand)
case "expand": key(48, .maskAlternate)
case "follow": type("nihao"); key(49); type("shijie")
case "save": key(1, .maskCommand)
case "escape": key(53)
default: abort("Unknown action")
}
print("completed", action)
