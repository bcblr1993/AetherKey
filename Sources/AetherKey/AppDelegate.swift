import AppKit
import ApplicationServices
import Carbon
import InputMethodKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Pre-warm the 530k+ lexicon in background for zero first-keystroke latency
        DispatchQueue.global(qos: .userInitiated).async {
            PinyinEngine.shared.preload()
        }
        invalidateIntlFileCacheModificationPasteboard()
        setupStatusMenu()
        updateStatusItemVisibility()
        
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleInputSourcesChanged),
            name: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleInputSourcesChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
    }
    
    @objc private func handleInputSourcesChanged(_ notification: Notification) {
        updateStatusItemVisibility()
    }
    
    /// Hides the standalone status item when AetherKey is already enabled in the system Input Menu,
    /// avoiding duplicate menu bar icons alongside macOS's native TextInputMenuAgent.
    private func updateStatusItemVisibility() {
        let filter = [kTISPropertyInputSourceID as String: "com.aethernative.inputmethod.AetherKey.Hans"] as CFDictionary
        var isEnabled = false
        if let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
           let source = list.first,
           let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) {
            isEnabled = CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue())
        }
        statusItem?.isVisible = !isEnabled
    }
    
    /// Clears CarbonCore's in-memory `AppleIntlFileCacheModificationDatePasteboard` so sandboxed
    /// extensions like `KeyboardSettings.appex` immediately detect `~/Library/Input Methods/AetherKey.app`.
    private func invalidateIntlFileCacheModificationPasteboard() {
        var pb: Pasteboard?
        if PasteboardCreate("AppleIntlFileCacheModificationDatePasteboard" as CFString, &pb) == noErr, let pb = pb {
            PasteboardClear(pb)
            PasteboardSynchronize(pb)
        }
        let bundleURL = Bundle.main.bundleURL as CFURL
        TISRegisterInputSource(bundleURL)
    }
    
    /// Use the same brand geometry as the system input-source resource.
    private func makeMenuBarIcon(size: CGFloat = 16) -> NSImage {
        AetherMenuBarIcon.image(size: size)
    }

    private func setupStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = ""
            button.image = makeMenuBarIcon(size: 16)
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.toolTip = "AetherKey 1.0 - Apple Silicon 原生极速输入法"
        }
        
        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
        rebuildMenu(menu)
    }
    
    public func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }
    
    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = AetherSettings.shared
        
        let titleItem = NSMenuItem(title: "AetherKey 1.0 正式版 (AetherNative)", action: nil, keyEquivalent: "")
        titleItem.image = makeMenuBarIcon(size: 15)
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        let statsItem = NSMenuItem(
            title: "内置 53.3 万词库 · 已习得 \(UserLexicon.shared.learnedEntryCount) 词",
            action: nil,
            keyEquivalent: ""
        )
        statsItem.isEnabled = false
        menu.addItem(statsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let switchItem = NSMenuItem(title: "⚡️ 激活并切换至 AetherKey 拼音", action: #selector(activateAndSwitchInputMethod), keyEquivalent: "")
        switchItem.target = self
        menu.addItem(switchItem)
        
        let prefsItem = NSMenuItem(title: "偏好设置与词库中心...", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let panguItem = NSMenuItem(title: "盘古之白自动空格", action: #selector(togglePangu), keyEquivalent: "")
        panguItem.target = self
        panguItem.state = settings.isPanguSpacingEnabled ? .on : .off
        menu.addItem(panguItem)
        
        let punctItem = NSMenuItem(title: "智能中文标点与配对引号", action: #selector(togglePunctuation), keyEquivalent: "")
        punctItem.target = self
        punctItem.state = settings.isSmartPunctuationEnabled ? .on : .off
        menu.addItem(punctItem)
        
        let fuzzyItem = NSMenuItem(title: "模糊音智能纠错", action: #selector(toggleFuzzy), keyEquivalent: "")
        fuzzyItem.target = self
        fuzzyItem.state = settings.isFuzzyPinyinEnabled ? .on : .off
        menu.addItem(fuzzyItem)
        
        let scrollItem = NSMenuItem(title: "默认使用卷轴展开模式 (14词)", action: #selector(toggleDefaultViewMode), keyEquivalent: "")
        scrollItem.target = self
        scrollItem.state = (settings.defaultViewMode == .scroll) ? .on : .off
        menu.addItem(scrollItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "退出 AetherKey", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    @objc private func activateAndSwitchInputMethod() {
        invalidateIntlFileCacheModificationPasteboard()
        
        guard let listRef = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] else {
            return
        }
        var parentSource: TISInputSource?
        var hansSource: TISInputSource?
        for source in listRef {
            if let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
                let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
                if id == "com.aethernative.inputmethod.AetherKey" {
                    parentSource = source
                } else if id == "com.aethernative.inputmethod.AetherKey.Hans" {
                    hansSource = source
                }
            }
        }
        if let parent = parentSource {
            var parentEnabled = false
            if let enabledPtr = TISGetInputSourceProperty(parent, kTISPropertyInputSourceIsEnabled) {
                parentEnabled = CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(enabledPtr).takeUnretainedValue())
            }
            if !parentEnabled {
                _ = TISEnableInputSource(parent)
                return
            }
        }
        if let hans = hansSource {
            _ = TISSelectInputSource(hans)
        }
    }
    
    @objc private func openPreferences() {
        PreferencesWindowController.shared.showWindow()
    }
    
    @objc private func togglePangu() {
        AetherSettings.shared.isPanguSpacingEnabled.toggle()
    }
    
    @objc private func togglePunctuation() {
        AetherSettings.shared.isSmartPunctuationEnabled.toggle()
    }
    
    @objc private func toggleFuzzy() {
        AetherSettings.shared.isFuzzyPinyinEnabled.toggle()
    }
    
    @objc private func toggleDefaultViewMode() {
        let cur = AetherSettings.shared.defaultViewMode
        AetherSettings.shared.defaultViewMode = (cur == .paging ? .scroll : .paging)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
