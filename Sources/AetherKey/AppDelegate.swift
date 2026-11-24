import AppKit
import ApplicationServices
import Carbon
import Combine
import InputMethodKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private let didRefreshBundleOnLaunch: Bool

    public init(didRefreshBundleOnLaunch: Bool = false) {
        self.didRefreshBundleOnLaunch = didRefreshBundleOnLaunch
        super.init()
    }
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Pre-warm the 530k+ lexicon, language model, English mix, U-mode chaizi & Wubi table in background
        DispatchQueue.global(qos: .userInitiated).async {
            PinyinEngine.shared.preload()
            LanguageModel.shared.preload()
            EnglishMixEngine.shared.preload()
            UModeChaiziEngine.shared.preload()
            _ = WubiEngine.shared.entryCount
        }
        invalidateIntlFileCacheModificationPasteboard()
        LoginItemController.shared.start()
        UpdateController.shared.start()
        setupClipboardMonitoring()
        if AetherSettings.shared.isAutoSyncEnabled {
            DispatchQueue.global(qos: .utility).async {
                _ = try? LexiconSyncManager.shared.syncNow()
            }
        }
        setupStatusMenu()
        updateStatusItemVisibility()
        if didRefreshBundleOnLaunch {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                _ = await InputMethodRegistrar.registerAndCycleEnable(
                    bundleURL: Bundle.main.bundleURL,
                    forceCycleEnable: true,
                    selectAfterEnable: true
                )
                self?.updateStatusItemVisibility()
            }
        }
        AetherSettings.shared.$isAlwaysShowMenuBarIconEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItemVisibility()
            }
            .store(in: &cancellables)
        
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
    
    /// Hides the standalone status item when AetherKey is already enabled in the system Input Menu
    /// (unless the user opts to keep the shortcut icon visible), avoiding duplicate menu bar icons.
    private func updateStatusItemVisibility() {
        let isEnabled = InputMethodRegistrar.isAetherKeyEnabled()
        statusItem?.isVisible = !isEnabled || AetherSettings.shared.isAlwaysShowMenuBarIconEnabled
    }
    
    /// Clears CarbonCore's in-memory `AppleIntlFileCacheModificationDatePasteboard` so sandboxed
    /// extensions like `KeyboardSettings.appex` immediately detect `~/Library/Input Methods/AetherKey.app`.
    private func invalidateIntlFileCacheModificationPasteboard() {
        InputMethodRegistrar.invalidateIntlFileCache()
        TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
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
            button.toolTip = "AetherKey \(UpdateController.version)"
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
        
        let titleItem = NSMenuItem(title: "AetherKey \(UpdateController.version) (AetherNative)", action: nil, keyEquivalent: "")
        titleItem.image = makeMenuBarIcon(size: 15)
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        let dictionaryTitle = settings.pinyinScheme == .wubi86
            ? "五笔 86 · \(WubiEngine.shared.entryCount.formatted()) 条编码"
            : "内置 \(PinyinLexicon.entryCount.formatted()) 条拼音词库"
        let statsItem = NSMenuItem(
            title: "\(dictionaryTitle) · 已习得 \(UserLexicon.shared.learnedEntryCount) 词",
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

        let toolboxItem = NSMenuItem(title: "快捷工具箱（常用语/剪贴板/符号）…", action: #selector(openToolbox), keyEquivalent: "")
        toolboxItem.target = self
        menu.addItem(toolboxItem)

        let syncItem = NSMenuItem(title: "立即同步词库与常用语", action: #selector(syncLexiconNow), keyEquivalent: "")
        syncItem.target = self
        menu.addItem(syncItem)

        let refreshMenuItem = NSMenuItem(title: "刷新系统输入法菜单", action: #selector(refreshSystemInputMenu), keyEquivalent: "")
        refreshMenuItem.target = self
        menu.addItem(refreshMenuItem)

        let updateItem = NSMenuItem(title: "检查更新…", action: #selector(UpdateController.checkForUpdates), keyEquivalent: "")
        updateItem.target = UpdateController.shared
        menu.addItem(updateItem)
        
        menu.addItem(NSMenuItem.separator())

        let schemeRootItem = NSMenuItem(title: "输入方案：\(settings.pinyinScheme.title)", action: nil, keyEquivalent: "")
        let schemeSubmenu = NSMenu(title: "输入方案")
        for scheme in PinyinScheme.allCases {
            let item = NSMenuItem(title: scheme.title, action: #selector(selectScheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = scheme.rawValue
            item.state = settings.pinyinScheme == scheme ? .on : .off
            schemeSubmenu.addItem(item)
        }
        schemeRootItem.submenu = schemeSubmenu
        menu.addItem(schemeRootItem)

        let traditionalItem = NSMenuItem(title: "输出繁体中文", action: #selector(toggleTraditional), keyEquivalent: "f")
        traditionalItem.keyEquivalentModifierMask = [.control, .shift]
        traditionalItem.target = self
        traditionalItem.state = settings.isTraditionalChineseEnabled ? .on : .off
        menu.addItem(traditionalItem)
        
        let panguItem = NSMenuItem(title: "盘古之白自动空格", action: #selector(togglePangu), keyEquivalent: "")
        panguItem.target = self
        panguItem.state = settings.isPanguSpacingEnabled ? .on : .off
        menu.addItem(panguItem)
        
        let punctItem = NSMenuItem(title: "智能中文标点与配对引号", action: #selector(togglePunctuation), keyEquivalent: "")
        punctItem.target = self
        punctItem.state = settings.isSmartPunctuationEnabled ? .on : .off
        menu.addItem(punctItem)
        
        let englishPunctItem = NSMenuItem(title: "中文使用英文标点", action: #selector(toggleEnglishPunctuation), keyEquivalent: ".")
        englishPunctItem.keyEquivalentModifierMask = [.control]
        englishPunctItem.target = self
        englishPunctItem.state = settings.isEnglishPunctuationEnabled ? .on : .off
        menu.addItem(englishPunctItem)

        let fuzzyItem = NSMenuItem(title: "模糊音智能纠错", action: #selector(toggleFuzzy), keyEquivalent: "")
        fuzzyItem.target = self
        fuzzyItem.isEnabled = settings.pinyinScheme != .wubi86
        fuzzyItem.state = settings.isFuzzyPinyinEnabled ? .on : .off
        menu.addItem(fuzzyItem)

        let terminalAutoEnglishItem = NSMenuItem(title: "终端与编辑器默认英文", action: #selector(toggleAutoEnglishInTerminal), keyEquivalent: "")
        terminalAutoEnglishItem.target = self
        terminalAutoEnglishItem.state = settings.isAutoEnglishInTerminalEnabled ? .on : .off
        menu.addItem(terminalAutoEnglishItem)

        let orientationItem = NSMenuItem(title: "候选竖排布局", action: #selector(toggleLayoutOrientation), keyEquivalent: "")
        orientationItem.target = self
        orientationItem.state = (settings.candidateLayoutOrientation == .vertical) ? .on : .off
        menu.addItem(orientationItem)
        
        let scrollItem = NSMenuItem(title: "默认使用卷轴展开模式", action: #selector(toggleDefaultViewMode), keyEquivalent: "")
        scrollItem.target = self
        scrollItem.state = (settings.defaultViewMode == .scroll) ? .on : .off
        menu.addItem(scrollItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "退出 AetherKey", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    @objc private func activateAndSwitchInputMethod() {
        Task { @MainActor [weak self] in
            _ = await InputMethodRegistrar.registerAndCycleEnable(
                bundleURL: Bundle.main.bundleURL,
                forceCycleEnable: false,
                selectAfterEnable: true
            )
            self?.updateStatusItemVisibility()
        }
    }

    @objc private func refreshSystemInputMenu() {
        Task { @MainActor [weak self] in
            let ok = await InputMethodRegistrar.refreshSystemAndReenable(
                bundleURL: Bundle.main.bundleURL,
                selectAfterRefresh: true
            )
            self?.updateStatusItemVisibility()
            StatusHUDHolder.shared.show(
                badge: ok ? "刷新" : "提醒",
                title: ok ? "系统输入法菜单已刷新" : "已刷新，若仍未显示请在键盘设置中重新添加",
                isAccent: ok,
                anchorRect: nil
            )
        }
    }
    
    private func setupClipboardMonitoring() {
        if AetherSettings.shared.isClipboardHistoryEnabled {
            ClipboardHistoryStore.shared.startMonitoring()
        }
        AetherSettings.shared.$isClipboardHistoryEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { enabled in
                if enabled {
                    ClipboardHistoryStore.shared.startMonitoring()
                } else {
                    ClipboardHistoryStore.shared.stopMonitoring()
                }
            }
            .store(in: &cancellables)
    }

    @objc private func openPreferences() {
        PreferencesWindowController.shared.showWindow()
    }

    @objc private func openToolbox() {
        AetherInputController.presentToolbox()
    }

    @objc private func syncLexiconNow() {
        DispatchQueue.global(qos: .utility).async {
            do {
                _ = try LexiconSyncManager.shared.syncNow()
                Task { @MainActor in
                    StatusHUDHolder.shared.show(badge: "同步", title: "词库与常用语已同步", isAccent: true, anchorRect: nil)
                }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor in
                    StatusHUDHolder.shared.show(badge: "失败", title: message, isAccent: false, anchorRect: nil)
                }
            }
        }
    }
    
    @objc private func selectScheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let scheme = PinyinScheme(rawValue: raw) else { return }
        AetherSettings.shared.pinyinScheme = scheme
    }

    @objc private func toggleTraditional() {
        AetherSettings.shared.isTraditionalChineseEnabled.toggle()
    }

    @objc private func togglePangu() {
        AetherSettings.shared.isPanguSpacingEnabled.toggle()
    }
    
    @objc private func togglePunctuation() {
        AetherSettings.shared.isSmartPunctuationEnabled.toggle()
    }
    
    @objc private func toggleEnglishPunctuation() {
        AetherSettings.shared.isEnglishPunctuationEnabled.toggle()
    }

    @objc private func toggleFuzzy() {
        AetherSettings.shared.isFuzzyPinyinEnabled.toggle()
    }

    @objc private func toggleAutoEnglishInTerminal() {
        AetherSettings.shared.isAutoEnglishInTerminalEnabled.toggle()
    }

    @objc private func toggleLayoutOrientation() {
        let cur = AetherSettings.shared.candidateLayoutOrientation
        AetherSettings.shared.candidateLayoutOrientation = (cur == .vertical ? .horizontal : .vertical)
    }
    
    @objc private func toggleDefaultViewMode() {
        let cur = AetherSettings.shared.defaultViewMode
        AetherSettings.shared.defaultViewMode = (cur == .paging ? .scroll : .paging)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
