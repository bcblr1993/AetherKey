import AppKit
import InputMethodKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusMenu()
    }
    
    private func setupStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = "⟡"
            button.toolTip = "AetherKey - Apple Silicon 原生极速输入法"
        }
        
        let menu = NSMenu()
        let titleItem = NSMenuItem(title: "AetherKey 1.0 (AetherNative)", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let modeItem = NSMenuItem(title: "设计哲学: Liquid Glass 科技美学", action: nil, keyEquivalent: "")
        modeItem.isEnabled = false
        menu.addItem(modeItem)
        
        let panguItem = NSMenuItem(title: "排版引擎: 盘古空格 & 智能标点", action: nil, keyEquivalent: "")
        panguItem.isEnabled = false
        menu.addItem(panguItem)
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "退出 AetherKey", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
