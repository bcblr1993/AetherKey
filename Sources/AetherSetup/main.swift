import AppKit
import SwiftUI

final class SetupDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !InstallationManager.shared.isInstalling }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        InstallationManager.shared.isInstalling ? .terminateCancel : .terminateNow
    }
}

let app = NSApplication.shared
let delegate = SetupDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
let mainMenu = NSMenu()
let applicationItem = NSMenuItem()
let applicationMenu = NSMenu(title: "AetherKey")
applicationMenu.addItem(withTitle: "退出安装向导", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
applicationItem.submenu = applicationMenu
mainMenu.addItem(applicationItem)
let editItem = NSMenuItem()
let editMenu = NSMenu(title: "编辑")
for (title, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
    editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
}
editItem.submenu = editMenu
mainMenu.addItem(editItem)
app.mainMenu = mainMenu
let previewIndex = CommandLine.arguments.firstIndex(of: "--preview-step")
let previewStep = previewIndex.flatMap { index in
    index + 1 < CommandLine.arguments.count ? Int(CommandLine.arguments[index + 1]) : nil
}
if previewStep != nil, CommandLine.arguments.contains("--light") {
    app.appearance = NSAppearance(named: .aqua)
}
let manager = previewStep.map { InstallationManager(previewStep: $0) } ?? .shared
let host = NSHostingView(rootView: SetupWizardView(installer: manager))
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
    styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
window.title = "AetherKey · 安装与设置"
window.titleVisibility = .hidden
window.titlebarAppearsTransparent = true
window.isMovableByWindowBackground = true
window.delegate = delegate
window.contentView = host
window.center()
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
// Isolated visual review, without touching installed input methods or system settings.
if let flag = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > flag + 1, manager.isPreview {
    let path = CommandLine.arguments[flag + 1]
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        host.layoutSubtreeIfNeeded()
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
        app.terminate(nil)
    }
}
app.run()
