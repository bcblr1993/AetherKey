import AppKit
import SwiftUI

let app = NSApplication.shared
let window = NSWindow(
    contentRect: NSRect(x: 100, y: 100, width: 760, height: 680),
    styleMask: [.titled, .closable, .miniaturizable, .resizable],
    backing: .buffered,
    defer: false
)
window.title = "AetherKey 安装与设置向导"
window.center()
window.contentView = NSHostingView(rootView: SetupWizardView())
window.makeKeyAndOrderFront(nil)
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
