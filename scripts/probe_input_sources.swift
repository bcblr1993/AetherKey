import Foundation
import Carbon

let prefix = "com.aethernative.inputmethod.AetherKey"
func string(_ source: TISInputSource, _ key: CFString) -> String {
    guard let p = TISGetInputSourceProperty(source, key) else { return "" }
    return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
}
func flag(_ source: TISInputSource, _ key: CFString) -> Bool {
    guard let p = TISGetInputSourceProperty(source, key) else { return false }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(p).takeUnretainedValue())
}
let sources = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] ?? []
if CommandLine.arguments.contains("--disable-aetherkey") {
    for s in sources where string(s, kTISPropertyInputSourceID) == prefix || string(s, kTISPropertyInputSourceID) == prefix + ".Hans" {
        print("disable", string(s, kTISPropertyInputSourceID), TISDisableInputSource(s))
    }
}
let refreshed = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] ?? []
let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
let report: [String: Any] = [
    "current": current.map { string($0, kTISPropertyInputSourceID) } ?? "",
    "aetherKeySources": refreshed.filter { string($0, kTISPropertyInputSourceID).hasPrefix(prefix) }.map { s -> [String: Any] in
        ["id": string(s, kTISPropertyInputSourceID), "name": string(s, kTISPropertyLocalizedName), "enabled": flag(s, kTISPropertyInputSourceIsEnabled), "selectable": flag(s, kTISPropertyInputSourceIsSelectCapable)]
    }
]
print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
