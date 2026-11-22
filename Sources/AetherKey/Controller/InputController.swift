import AppKit
import InputMethodKit

/// Global shared candidate panel instance
@MainActor
public enum CandidatePanelHolder {
    public static let shared = CandidatePanel()
}

/// AetherKey Input Controller conforming to macOS IMKServer specifications.
/// Designed for Apple Silicon with zero-blocking synchronous event handling,
/// DP sentence composition, partial prefix commit, Pangu spacing, smart punctuation,
/// Shift toggle, and AetherNative Liquid Glass visual aesthetics.
@objc(AetherInputController)
public final class AetherInputController: IMKInputController, @unchecked Sendable {
    
    // MARK: - State Management
    private var compositionScheme: PinyinScheme = .full
    private var isCalculatorComposition: Bool {
        compositionScheme != .wubi86 && buffer.hasPrefix("v") && (compositionScheme == .full || buffer.dropFirst().first?.isNumber == true)
    }
    private var buffer: String = ""
    private var rawBuffer: String = ""
    private var compositionCursor: Int = 0
    private var originalFullBuffer: String = ""
    private var partialComposedText: String = ""
    private var inputMode: InputMode = .chinese
    private var allCandidates: [Candidate] = []
    private var candidateViewMode: CandidateViewMode = AetherSettings.shared.defaultViewMode
    private var currentPage: Int = 1
    private var pageSize: Int {
        let base = AetherSettings.shared.candidatePageSize
        if AetherSettings.shared.candidateLayoutOrientation == .vertical { return base }
        return candidateViewMode == .scroll ? base * 2 : base
    }
    private var selectedIndexInPage: Int = 0
    private weak var activeClient: AnyObject? = nil
    private var menuTargetBundleIdentifier: String? = nil
    
    // Tracking context & Shift single-tap
    private var shiftPressTime: TimeInterval = 0
    private var shiftSoleModifier: Bool = false
    private var shiftDisqualifiedUntilAllReleased: Bool = false
    private var lastCommittedChar: Character? = nil
    private var compositionPrecedingChar: Character? = nil
    private var lastLearnedCommits: [(pinyin: String, word: String)] = []
    private var lastCommitWasSmartPunctuation: Bool = false
    private var compositionContext = ""
    private var committedContext = ""
    private var committedContextEnd: Int?
    private var lastCompositionCaretRect: NSRect?
    private var compositionGeneration: Int = 0

    private static let manualModeLock = NSLock()
    nonisolated(unsafe) private static var manualModeOverrides: [String: InputMode] = [:]
    
    // MARK: - IMK Lifecycle
    public override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: server == nil ? nil : inputClient)
        self.activeClient = inputClient as AnyObject?
    }

    public override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        self.activeClient = sender as AnyObject?
        shiftPressTime = 0
        shiftSoleModifier = false
        shiftDisqualifiedUntilAllReleased = false
        if let overridden = Self.savedManualMode(for: sender) {
            inputMode = overridden
        } else {
            let bundleId = (sender as? IMKTextInput)?.bundleIdentifier()
            inputMode = ContextDetector.shared.resolvedDefaultMode(for: bundleId, settings: AetherSettings.shared)
        }
    }

    public override func deactivateServer(_ sender: Any!) {
        shiftPressTime = 0
        shiftSoleModifier = false
        shiftDisqualifiedUntilAllReleased = false
        committedContext = ""
        committedContextEnd = nil
        lastCommittedChar = nil
        compositionPrecedingChar = nil
        lastLearnedCommits.removeAll()
        lastCommitWasSmartPunctuation = false
        SmartPunctuation.shared.resetState()
        if !buffer.isEmpty {
            resetComposition(client: sender)
        } else if inputMode == .vMode {
            inputMode = .chinese
        }
        super.deactivateServer(sender)
    }

    public override func commitComposition(_ sender: Any!) {
        if !buffer.isEmpty {
            commitCurrentSelection(client: sender)
        }
        super.commitComposition(sender)
    }

    public override func menu() -> NSMenu! {
        let menu = NSMenu(title: "AetherKey")
        let settings = AetherSettings.shared
        
        let dictionaryTitle = settings.pinyinScheme == .wubi86
            ? "五笔 86 · \(WubiEngine.shared.entryCount.formatted()) 条编码"
            : "\(PinyinLexicon.entryCount.formatted()) 条拼音词库"
        let statsItem = NSMenuItem(
            title: "AetherKey \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.11") · \(dictionaryTitle) (已习得 \(UserLexicon.shared.learnedEntryCount) 词)",
            action: nil,
            keyEquivalent: ""
        )
        statsItem.isEnabled = false
        menu.addItem(statsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let modeTitle: String
        switch inputMode {
        case .chinese:
            modeTitle = "当前模式：中文 (单击 Shift 切换)"
        case .english:
            modeTitle = "当前模式：英文 EN (单击 Shift 切换)"
        case .vMode:
            modeTitle = "当前模式：v 宏模式 (单击 Shift 切换)"
        }
        let modeItem = NSMenuItem(title: modeTitle, action: #selector(menuToggleInputMode), keyEquivalent: "")
        modeItem.target = self
        menu.addItem(modeItem)

        if let bundleId = currentClientBundleIdentifier(from: activeClient) {
            menuTargetBundleIdentifier = bundleId
            let currentRule = settings.appDefaultMode(for: bundleId)
            let ruleLabel = currentRule?.title ?? "跟随全局"
            let appRuleRootItem = NSMenuItem(title: "此应用默认模式：\(ruleLabel)", action: nil, keyEquivalent: "")
            let appRuleSubmenu = NSMenu(title: "此应用默认模式")

            let globalItem = NSMenuItem(title: "跟随全局", action: #selector(menuSetAppDefaultGlobal), keyEquivalent: "")
            globalItem.target = self
            globalItem.state = currentRule == nil ? .on : .off
            appRuleSubmenu.addItem(globalItem)

            let englishItem = NSMenuItem(title: "默认英文", action: #selector(menuSetAppDefaultEnglish), keyEquivalent: "")
            englishItem.target = self
            englishItem.state = currentRule == .english ? .on : .off
            appRuleSubmenu.addItem(englishItem)

            let chineseItem = NSMenuItem(title: "默认中文", action: #selector(menuSetAppDefaultChinese), keyEquivalent: "")
            chineseItem.target = self
            chineseItem.state = currentRule == .chinese ? .on : .off
            appRuleSubmenu.addItem(chineseItem)

            appRuleRootItem.submenu = appRuleSubmenu
            menu.addItem(appRuleRootItem)
        } else {
            menuTargetBundleIdentifier = nil
        }

        let schemeRootItem = NSMenuItem(title: "输入方案：\(settings.pinyinScheme.title)", action: nil, keyEquivalent: "")
        let schemeSubmenu = NSMenu(title: "输入方案")
        for scheme in PinyinScheme.allCases {
            let action: Selector
            switch scheme {
            case .full: action = #selector(menuSelectFull)
            case .flypy: action = #selector(menuSelectFlypy)
            case .microsoft: action = #selector(menuSelectMicrosoft)
            case .zrm: action = #selector(menuSelectZrm)
            case .sogou: action = #selector(menuSelectSogou)
            case .wubi86: action = #selector(menuSelectWubi86)
            }
            let item = NSMenuItem(title: scheme.title, action: action, keyEquivalent: "")
            item.target = self
            item.state = settings.pinyinScheme == scheme ? .on : .off
            schemeSubmenu.addItem(item)
        }
        schemeRootItem.submenu = schemeSubmenu
        menu.addItem(schemeRootItem)
        
        let viewTitle = (candidateViewMode == .scroll) ? "候选视图：卷轴模式 (⌥Tab 切换)" : "候选视图：翻页模式 (⌥Tab 切换)"
        let viewItem = NSMenuItem(title: viewTitle, action: #selector(menuToggleViewMode), keyEquivalent: "")
        viewItem.target = self
        menu.addItem(viewItem)

        let orientationItem = NSMenuItem(title: "候选竖排布局", action: #selector(menuToggleLayoutOrientation), keyEquivalent: "")
        orientationItem.target = self
        orientationItem.state = settings.candidateLayoutOrientation == .vertical ? .on : .off
        menu.addItem(orientationItem)

        menu.addItem(NSMenuItem.separator())

        let traditionalItem = NSMenuItem(title: "输出繁体中文", action: #selector(menuToggleTraditional), keyEquivalent: "f")
        traditionalItem.keyEquivalentModifierMask = [.control, .shift]
        traditionalItem.target = self
        traditionalItem.state = settings.isTraditionalChineseEnabled ? .on : .off
        menu.addItem(traditionalItem)
        
        let panguItem = NSMenuItem(title: "盘古之白自动空格", action: #selector(menuTogglePangu), keyEquivalent: "")
        panguItem.target = self
        panguItem.state = settings.isPanguSpacingEnabled ? .on : .off
        menu.addItem(panguItem)
        
        let punctItem = NSMenuItem(title: "智能中文标点与配对引号", action: #selector(menuTogglePunctuation), keyEquivalent: "")
        punctItem.target = self
        punctItem.state = settings.isSmartPunctuationEnabled ? .on : .off
        menu.addItem(punctItem)
        
        let englishPunctItem = NSMenuItem(title: "中文使用英文标点", action: #selector(menuToggleEnglishPunctuation), keyEquivalent: ".")
        englishPunctItem.keyEquivalentModifierMask = [.control]
        englishPunctItem.target = self
        englishPunctItem.state = settings.isEnglishPunctuationEnabled ? .on : .off
        menu.addItem(englishPunctItem)

        let fuzzyItem = NSMenuItem(title: "模糊音智能纠错", action: #selector(menuToggleFuzzy), keyEquivalent: "")
        fuzzyItem.target = self
        fuzzyItem.isEnabled = settings.pinyinScheme != .wubi86
        fuzzyItem.state = settings.isFuzzyPinyinEnabled ? .on : .off
        menu.addItem(fuzzyItem)
        
        let termItem = NSMenuItem(title: "终端与 IDE 自动英文模式", action: #selector(menuToggleTerminalAutoEnglish), keyEquivalent: "")
        termItem.target = self
        termItem.state = settings.isAutoEnglishInTerminalEnabled ? .on : .off
        menu.addItem(termItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let prefsItem = NSMenuItem(title: "AetherKey 偏好设置与词库中心...", action: #selector(menuOpenPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)
        
        let updateItem = NSMenuItem(title: "检查更新…", action: #selector(menuCheckForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        return menu
    }

    @objc private func menuSelectWubi86() { selectScheme(.wubi86) }

    @objc private func menuSelectFull() { selectScheme(.full) }
    @objc private func menuSelectFlypy() { selectScheme(.flypy) }
    @objc private func menuSelectMicrosoft() { selectScheme(.microsoft) }
    @objc private func menuSelectZrm() { selectScheme(.zrm) }
    @objc private func menuSelectSogou() { selectScheme(.sogou) }

    private func selectScheme(_ scheme: PinyinScheme) {
        // Existing marked text keeps its original layout until committed or cancelled.
        AetherSettings.shared.pinyinScheme = scheme
    }

    @objc private func menuCheckForUpdates() {
        MainActor.assumeIsolated { UpdateController.shared.checkForUpdates() }
    }

    @objc private func menuToggleInputMode() {
        toggleInputMode(client: activeClient, showHUD: true)
    }

    @objc private func menuToggleViewMode() {
        toggleViewMode(client: activeClient)
    }

    @objc private func menuToggleLayoutOrientation() {
        let current = AetherSettings.shared.candidateLayoutOrientation
        AetherSettings.shared.candidateLayoutOrientation = (current == .vertical ? .horizontal : .vertical)
        if !buffer.isEmpty {
            currentPage = 1
            selectedIndexInPage = 0
            renderPanel(client: activeClient)
        }
    }

    @objc private func menuToggleTraditional() {
        AetherSettings.shared.isTraditionalChineseEnabled.toggle()
        showScriptHUD(client: activeClient)
        if !buffer.isEmpty {
            updateCandidates(client: activeClient)
        }
    }

    @objc private func menuSetAppDefaultGlobal() {
        applyAppDefaultMode(nil)
    }

    @objc private func menuSetAppDefaultEnglish() {
        applyAppDefaultMode(.english)
    }

    @objc private func menuSetAppDefaultChinese() {
        applyAppDefaultMode(.chinese)
    }

    private func currentClientBundleIdentifier(from client: Any?) -> String? {
        guard let raw = (client as? IMKTextInput)?.bundleIdentifier()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return raw
    }

    private func applyAppDefaultMode(_ mode: AppDefaultInputMode?) {
        let targetClient = resolveClient(activeClient)
        guard let bundleId = currentClientBundleIdentifier(from: targetClient) ?? menuTargetBundleIdentifier else { return }
        AetherSettings.shared.setAppDefaultMode(mode, for: bundleId)
        Self.clearManualMode(for: targetClient, bundleIdentifier: bundleId)

        let resolved = ContextDetector.shared.resolvedDefaultMode(for: bundleId, settings: AetherSettings.shared)
        if inputMode != resolved {
            if !buffer.isEmpty && (resolved == .english || inputMode == .vMode) {
                commitRaw(client: targetClient)
            }
            inputMode = resolved
        }
    }

    @objc private func menuTogglePangu() {
        AetherSettings.shared.isPanguSpacingEnabled.toggle()
    }

    @objc private func menuTogglePunctuation() {
        AetherSettings.shared.isSmartPunctuationEnabled.toggle()
    }

    @objc private func menuToggleEnglishPunctuation() {
        AetherSettings.shared.isEnglishPunctuationEnabled.toggle()
        showPunctuationHUD(client: activeClient)
    }

    @objc private func menuToggleFuzzy() {
        AetherSettings.shared.isFuzzyPinyinEnabled.toggle()
    }

    @objc private func menuToggleTerminalAutoEnglish() {
        AetherSettings.shared.isAutoEnglishInTerminalEnabled.toggle()
    }

    @objc private func menuOpenPreferences() {
        Task { @MainActor in
            PreferencesWindowController.shared.showWindow()
        }
    }

    public override func recognizedEvents(_ sender: Any!) -> Int {
        return Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue)
    }

    // MARK: - Synchronous Event Interception
    public override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event else { return false }
        self.activeClient = sender as AnyObject?
        
        synchronizeManualMode(client: sender)

        // 1. Shift key tap detection for instantaneous Chinese / English toggle
        if event.type == .flagsChanged {
            handleFlagsChanged(event: event, client: sender)
            return false // Allow OS to receive flag changes
        }
        
        // Only intercept keyDown events
        guard event.type == .keyDown else {
            return false
        }
        
        // Shift or other key held while keyDown pressed -> disqualify pending Shift single-tap
        if shiftSoleModifier || event.modifierFlags.contains(.shift) {
            shiftSoleModifier = false
            shiftDisqualifiedUntilAllReleased = event.modifierFlags.contains(.shift)
        }
        
        // Candidate management never commits the composition or reaches the host app.
        if !buffer.isEmpty, flagsForManagement(event) {
            switch event.keyCode {
            case 35: manageSelectedCandidate(.pin, client: sender); return true
            case 32: manageSelectedCandidate(.unpin, client: sender); return true
            case 51: manageSelectedCandidate(.forget, client: sender); return true
            default: break
            }
        }

        // Consume only Ctrl + period before generic shortcut pass-through. Do not
        // commit raw pinyin, move its caret, or rebuild the candidate panel.
        if event.keyCode == 47,
           event.modifierFlags.intersection([.command, .control, .option, .shift]) == [.control] {
            if !event.isARepeat {
                AetherSettings.shared.isEnglishPunctuationEnabled.toggle()
                showPunctuationHUD(client: sender)
            }
            return true
        }

        // Consume Ctrl + Shift + F for Simplified/Traditional toggle while preserving any active composition.
        if event.keyCode == 3,
           event.modifierFlags.intersection([.command, .control, .option, .shift]) == [.control, .shift] {
            if !event.isARepeat {
                AetherSettings.shared.isTraditionalChineseEnabled.toggle()
                showScriptHUD(client: sender)
                if !buffer.isEmpty {
                    updateCandidates(client: sender)
                }
            }
            return true
        }

        // Pass through Command / Control keyboard shortcuts instantly
        let flags = event.modifierFlags
        if flags.contains(.command) || flags.contains(.control) {
            if !buffer.isEmpty {
                commitRaw(client: sender)
            }
            return false
        }
        
        // If in English mode and buffer is empty, instant pass-through while syncing context
        if inputMode == .english && buffer.isEmpty {
            syncPassThroughContext(from: event)
            return false
        }
        
        let keyCode = event.keyCode
        
        // 2. State Machine: Buffer is Non-Empty (Composition in progress)
        // Handle editing and navigation keys by keyCode even if characters string is empty or private-use
        if !buffer.isEmpty {
            switch keyCode {
            // Backspace / Delete
            case 51:
                let start = flags.contains(.option) ? previousSyllableBoundary() : max(0, compositionCursor - 1)
                guard start < compositionCursor else { return true }
                replaceComposition(start..<compositionCursor, with: "")
                if buffer.isEmpty {
                    resetComposition(client: sender)
                } else {
                    updateCandidates(client: sender)
                }
                return true
                
            // Forward Delete, Home and End edit the marked pinyin, not the document.
            case 117:
                if compositionCursor < buffer.count {
                    replaceComposition(compositionCursor..<(compositionCursor + 1), with: "")
                    updateCandidates(client: sender)
                }
                return true
            case 115:
                compositionCursor = 0
                updateClientMarkedText(client: sender); renderPanel(client: sender)
                return true
            case 119:
                compositionCursor = buffer.count
                updateClientMarkedText(client: sender); renderPanel(client: sender)
                return true
            // Escape
            case 53:
                resetComposition(client: sender)
                return true
                
            // Enter / Return -> Commit raw buffer as typed
            case 36, 76:
                commitRaw(client: sender)
                return true
                
            // Space -> Commit currently highlighted candidate
            case 49:
                commitCurrentSelection(client: sender)
                return true
                
            // Up Arrow
            case 126:
                moveSelection(delta: -1, client: sender)
                return true
                
            // Down Arrow
            case 125:
                moveSelection(delta: 1, client: sender)
                return true
                
            // Left Arrow / Right Arrow
            case 123 where AetherSettings.shared.isFourArrowSelectionEnabled && !flags.contains(.option):
                moveSelection(delta: -1, client: sender)
                return true
            case 124 where AetherSettings.shared.isFourArrowSelectionEnabled && !flags.contains(.option):
                moveSelection(delta: 1, client: sender)
                return true
            case 123:
                compositionCursor = flags.contains(.option) ? previousSyllableBoundary() : max(0, compositionCursor - 1)
                updateClientMarkedText(client: sender); renderPanel(client: sender)
                return true
            case 124:
                compositionCursor = flags.contains(.option) ? nextSyllableBoundary() : min(buffer.count, compositionCursor + 1)
                updateClientMarkedText(client: sender); renderPanel(client: sender)
                return true
                
            // Page Previous: '-' (27) or '[' (33) (without Shift, outside v-mode) or PageUp (116)
            case 27 where !flags.contains(.shift) && !isCalculatorComposition,
                 33 where !flags.contains(.shift) && !isCalculatorComposition,
                 116:
                flipPage(delta: -1, client: sender)
                return true
                
            // Page Next: '=' (24) or ']' (30) (without Shift, outside v-mode) or PageDown (121)
            case 24 where !flags.contains(.shift) && !isCalculatorComposition,
                 30 where !flags.contains(.shift) && !isCalculatorComposition,
                 121:
                flipPage(delta: 1, client: sender)
                return true
                
            // Tab key (48): Sogou-style 卷轴 / 翻页模式切换 与 候选词流转
            case 48:
                if flags.contains(.option) {
                    // Option + Tab: Toggle between 卷轴 (scroll) and 翻页 (paging) modes
                    toggleViewMode(client: sender)
                    return true
                } else if flags.contains(.shift) {
                    // Shift + Tab: Move selection backwards
                    moveSelection(delta: -1, client: sender)
                    return true
                } else {
                    // Tab: Navigate selection forward
                    moveSelection(delta: 1, client: sender)
                    return true
                }
                
            default:
                break
            }
        }
        
        // 3. State Machine: Buffer is Empty
        if buffer.isEmpty {
            if keyCode == 51 && flags.intersection([.command, .control, .option]).isEmpty {
                for entry in lastLearnedCommits {
                    UserLexicon.shared.rollbackCommit(pinyin: entry.pinyin, word: entry.word)
                }
                lastLearnedCommits.removeAll()
                if lastCommitWasSmartPunctuation {
                    SmartPunctuation.shared.rollbackLastQuoteIfNeeded()
                    lastCommitWasSmartPunctuation = false
                }
                lastCommittedChar = nil
                if !committedContext.isEmpty {
                    committedContext.removeLast()
                }
                return false
            }
            if [123, 124, 125, 126, 115, 119, 116, 121, 36, 76].contains(keyCode) {
                lastLearnedCommits.removeAll()
                lastCommitWasSmartPunctuation = false
                lastCommittedChar = nil
                return false
            }
        }

        // Intercept characters for composition insertion and punctuation
        guard let characters = event.characters, !characters.isEmpty else {
            return false
        }
        
        if buffer.isEmpty {
            if let firstChar = characters.first, firstChar.isASCII && firstChar.isLetter {
                // Uppercase ASCII letters (Shift+Letter or CapsLock) pass through directly in Chinese mode
                if firstChar.isUppercase {
                    let preceding = effectivePrecedingChar(client: sender)
                    let formatted = AetherSettings.shared.isPanguSpacingEnabled
                        ? PanguSpacing.shared.formatCommitText(preceding: preceding, committing: characters)
                        : characters
                    lastLearnedCommits.removeAll()
                    lastCommitWasSmartPunctuation = false
                    commitDirect(text: formatted, client: sender)
                    return true
                }
                
                // Lowercase 'a'...'z' or 'v' -> Begin composition
                insertComposition(characters.lowercased(), client: sender)
                originalFullBuffer = buffer
                partialComposedText = ""
                updateCandidates(client: sender)
                return true
            }
            
            // Check Smart Punctuation in Chinese mode
            if inputMode == .chinese,
               let firstChar = characters.first,
               SmartPunctuation.shared.isPunctuation(firstChar) {
                let preceding = effectivePrecedingChar(client: sender)
                let converted = AetherSettings.shared.usesChinesePunctuation
                    ? SmartPunctuation.shared.convert(char: firstChar, precedingChar: preceding)
                    : String(firstChar)
                lastLearnedCommits.removeAll()
                lastCommitWasSmartPunctuation = AetherSettings.shared.usesChinesePunctuation
                commitDirect(text: converted, client: sender)
                return true
            }
            
            // Record raw space, digit, or visible ASCII character for contextual decimal/Pangu tracking
            syncPassThroughContext(from: event)
            
            // Unhandled pass-through
            return false
        }
        
        // Numeric selection keys 1 - 9
        if let char = characters.first, char.isNumber, let digit = char.wholeNumberValue, digit >= 1 && digit <= 9 {
            let isMacroKeyword = VModeCalculator.isMacroKeywordMode(buffer)
            // In v-mode math/RMB expressions, digits are part of the expression;
            // in macro keyword mode (e.g. vdate, vnow, varrow), 1-9 select candidates directly.
            if (isCalculatorComposition || (buffer == "v" && compositionScheme != .wubi86)) && !isMacroKeyword {
                insertComposition(String(char), client: sender)
                updateCandidates(client: sender)
                return true
            }
            
            let pageCandidates = candidatesForCurrentPage()
            let targetIdx = digit - 1
            if targetIdx < pageCandidates.count {
                commitCandidate(pageCandidates[targetIdx], client: sender)
                return true
            }
            if isMacroKeyword {
                return true
            }
        }
        
        // If in v-mode and '0' is typed
        if (isCalculatorComposition || (buffer == "v" && compositionScheme != .wubi86)),
           let char = characters.first, char == "0" {
            if !VModeCalculator.isMacroKeywordMode(buffer) {
                insertComposition(String(char), client: sender)
                updateCandidates(client: sender)
            }
            return true
        }
        
        // Character appending: letters (preserving original case in rawBuffer), digits in v-mode, math operators, or apostrophe
        if let firstChar = characters.first {
            if (firstChar == ";" && schemeUsesSemicolonFinal && acceptsSemicolonFinal)
                || firstChar.isLetter
                || (firstChar == "'" && (compositionScheme != .wubi86 || buffer.hasPrefix("z")))
                || (isCalculatorComposition && !VModeCalculator.isMacroKeywordMode(buffer) && "+-*/.()^%".contains(firstChar)) {
                appendCode(characters, client: sender)
                if partialComposedText.isEmpty {
                    originalFullBuffer = buffer
                }
                updateCandidates(client: sender)
                return true
            }
            
            // Punctuation typed during composition: commit candidate first, then punctuation
            if SmartPunctuation.shared.isPunctuation(firstChar) {
                commitCurrentSelection(client: sender)
                let preceding = effectivePrecedingChar(client: sender)
                let converted = AetherSettings.shared.usesChinesePunctuation
                    ? SmartPunctuation.shared.convert(char: firstChar, precedingChar: preceding)
                    : String(firstChar)
                lastCommitWasSmartPunctuation = AetherSettings.shared.usesChinesePunctuation
                commitDirect(text: converted, client: sender)
                return true
            }
        }
        
        return false
    }

    // MARK: - Text Stream Fallback for Standard Text Fields
    public override func inputText(_ string: String!, client sender: Any!) -> Bool {
        guard let string = string, !string.isEmpty else { return false }
        self.activeClient = sender as AnyObject?
        synchronizeManualMode(client: sender)
        
        if inputMode == .english && buffer.isEmpty {
            if let last = string.last, !string.unicodeScalars.allSatisfy(CharacterSet.controlCharacters.contains) {
                lastLearnedCommits.removeAll()
                lastCommitWasSmartPunctuation = false
                lastCommittedChar = last
            }
            return false
        }
        
        var handled = false
        for char in string {
            let lowerChar = Character(char.lowercased())
            if buffer.isEmpty {
                if char.isASCII && char.isLetter {
                    if char.isUppercase {
                        let preceding = effectivePrecedingChar(client: sender)
                        let formatted = AetherSettings.shared.isPanguSpacingEnabled
                            ? PanguSpacing.shared.formatCommitText(preceding: preceding, committing: String(char))
                            : String(char)
                        lastLearnedCommits.removeAll()
                        lastCommitWasSmartPunctuation = false
                        commitDirect(text: formatted, client: sender)
                        handled = true
                    } else {
                        insertComposition(String(lowerChar), client: sender)
                        originalFullBuffer = buffer
                        partialComposedText = ""
                        updateCandidates(client: sender)
                        handled = true
                    }
                } else if inputMode == .chinese && SmartPunctuation.shared.isPunctuation(char) {
                    let preceding = effectivePrecedingChar(client: sender)
                    let converted = AetherSettings.shared.usesChinesePunctuation
                        ? SmartPunctuation.shared.convert(char: char, precedingChar: preceding)
                        : String(char)
                    lastLearnedCommits.removeAll()
                    lastCommitWasSmartPunctuation = AetherSettings.shared.usesChinesePunctuation
                    commitDirect(text: converted, client: sender)
                    handled = true
                } else if !char.unicodeScalars.allSatisfy(CharacterSet.controlCharacters.contains) {
                    lastLearnedCommits.removeAll()
                    lastCommitWasSmartPunctuation = false
                    lastCommittedChar = char
                }
            } else {
                if char == " " {
                    commitCurrentSelection(client: sender)
                    handled = true
                } else if char == "\n" || char == "\r" {
                    commitRaw(client: sender)
                    handled = true
                } else if (isCalculatorComposition || (buffer == "v" && compositionScheme != .wubi86))
                            && !VModeCalculator.isMacroKeywordMode(buffer)
                            && (char.isNumber || "+-*/.()^%".contains(char)) {
                    insertComposition(String(char), client: sender)
                    updateCandidates(client: sender)
                    handled = true
                } else if let digit = char.wholeNumberValue, digit >= 1 && digit <= 9 {
                    let pageCandidates = candidatesForCurrentPage()
                    let targetIdx = digit - 1
                    if targetIdx < pageCandidates.count {
                        commitCandidate(pageCandidates[targetIdx], client: sender)
                        handled = true
                    } else if VModeCalculator.isMacroKeywordMode(buffer) {
                        handled = true
                    }
                } else if VModeCalculator.isMacroKeywordMode(buffer) && char.isNumber {
                    handled = true
                } else if (char == ";" && schemeUsesSemicolonFinal && acceptsSemicolonFinal) || lowerChar.isLetter || (lowerChar == "'" && (compositionScheme != .wubi86 || buffer.hasPrefix("z"))) {
                    appendCode(String(char), client: sender)
                    if partialComposedText.isEmpty {
                        originalFullBuffer = buffer
                    }
                    updateCandidates(client: sender)
                    handled = true
                } else if SmartPunctuation.shared.isPunctuation(char) {
                    commitCurrentSelection(client: sender)
                    let preceding = effectivePrecedingChar(client: sender)
                    let converted = AetherSettings.shared.usesChinesePunctuation
                        ? SmartPunctuation.shared.convert(char: char, precedingChar: preceding)
                        : String(char)
                    lastCommitWasSmartPunctuation = AetherSettings.shared.usesChinesePunctuation
                    commitDirect(text: converted, client: sender)
                    handled = true
                }
            }
        }
        return handled
    }

    private func replaceComposition(_ range: Range<Int>, with text: String) {
        let start = buffer.index(buffer.startIndex, offsetBy: range.lowerBound)
        let end = buffer.index(buffer.startIndex, offsetBy: range.upperBound)
        let rawStart = rawBuffer.index(rawBuffer.startIndex, offsetBy: range.lowerBound)
        let rawEnd = rawBuffer.index(rawBuffer.startIndex, offsetBy: range.upperBound)
        rawBuffer.replaceSubrange(rawStart..<rawEnd, with: text)

        let lowered = text.lowercased()
        let keepCase = isCalculatorComposition || (buffer.isEmpty && lowered.hasPrefix("v"))
        let normalized = (keepCase || lowered.count != text.count) ? text : lowered
        buffer.replaceSubrange(start..<end, with: normalized)
        compositionCursor = range.lowerBound + normalized.count
        // Rebuild the full reading after an edit, including already selected prefixes.
        if partialComposedText.isEmpty {
            originalFullBuffer = buffer
        } else {
            let consumedLength = max(0, originalFullBuffer.count - (buffer.count - normalized.count + range.count))
            originalFullBuffer = String(originalFullBuffer.prefix(consumedLength)) + buffer
        }
    }

    private func appendCode(_ text: String, client: Any?) {
        if compositionScheme == .wubi86 {
            let lower = text.lowercased()
            guard lower.allSatisfy({ ($0 >= "a" && $0 <= "z") || ($0 == "'" && buffer.hasPrefix("z")) }) else { return }
            if !buffer.hasPrefix("z"), buffer.count == 4 {
                // Editing a full code is allowed after deleting a letter. At the end,
                // the fifth root commits the highlighted word and starts a new code.
                guard compositionCursor == buffer.count,
                      let selected = candidatesForCurrentPage().dropFirst(selectedIndexInPage).first,
                      selected.comment != "英" else { return }
                commitCurrentSelection(client: client)
            }
        }
        insertComposition(text, client: client)
    }

    private func insertComposition(_ text: String, client: Any? = nil) {
        if buffer.isEmpty {
            let resolved = resolveClient(client)
            compositionGeneration += 1
            compositionScheme = AetherSettings.shared.pinyinScheme
            candidateViewMode = AetherSettings.shared.defaultViewMode
            compositionContext = precedingContext(client: resolved)
            committedContext = compositionContext
            compositionPrecedingChar = effectivePrecedingChar(client: resolved)
            lastCompositionCaretRect = queryHostCaretRect(client: resolved)
            onMainActor { CandidatePanelHolder.shared.resetAnchor() }
        }
        replaceComposition(compositionCursor..<compositionCursor, with: text)
    }

    private func precedingContext(client: Any?) -> String {
        guard let textInput = resolveClient(client) as? IMKTextInput else { return "" }
        let selection = textInput.selectedRange()
        guard selection.location != NSNotFound, selection.location > 0, selection.length == 0 else { return "" }
        // Ask for a small UTF-16 window. A host may decline this request.
        let start = max(0, selection.location - 24)
        if let text = textInput.attributedSubstring(from: NSRange(location: start, length: selection.location - start))?.string {
            return PinyinContext.suffix(text)
        }
        return committedContextEnd == selection.location ? PinyinContext.suffix(committedContext) : ""
    }

    private var schemeUsesSemicolonFinal: Bool {
        compositionScheme == .microsoft || compositionScheme == .sogou
    }

    private var acceptsSemicolonFinal: Bool {
        let prefix = String(buffer.prefix(compositionCursor))
        return (prefix.split(separator: "'", omittingEmptySubsequences: false).last?.count ?? 0) % 2 == 1
    }

    private var compositionBoundaries: [Int] {
        if compositionScheme == .wubi86 { return Array(1...max(1, buffer.count)) }
        if compositionScheme == .full || isCalculatorComposition {
            return PinyinEngine.shared.segmentTokens(rawInput: buffer).map(\.rawEndOffset)
        }
        return DoublePinyin.tokens(buffer, scheme: compositionScheme)?.map(\.rawEnd) ?? [buffer.count]
    }

    private func previousSyllableBoundary() -> Int {
        let boundaries = [0] + compositionBoundaries
        return boundaries.last(where: { $0 < compositionCursor }) ?? 0
    }

    private func nextSyllableBoundary() -> Int {
        compositionBoundaries
            .first(where: { $0 > compositionCursor }) ?? buffer.count
    }

    private func flagsForManagement(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection([.command, .control, .option, .shift]) == [.control, .option]
    }

    private func candidateReading(_ candidate: Candidate) -> String {
        candidate.pinyin ?? String(buffer.prefix(candidate.consumedInputLength > 0 ? candidate.consumedInputLength : buffer.count))
    }

    private func manageSelectedCandidate(_ action: CandidateAction, client: Any?) {
        let candidates = candidatesForCurrentPage()
        guard candidates.indices.contains(selectedIndexInPage) else { return }
        manageCandidate(candidates[selectedIndexInPage], action: action, client: client)
    }

    private func manageCandidate(_ candidate: Candidate, action: CandidateAction, client: Any?) {
        guard !isCalculatorComposition, !candidate.isEmoji, candidate.comment != "英" else { return }
        let reading = candidateReading(candidate)
        let targetWord = candidate.canonicalText
        switch action {
        case .pin: UserLexicon.shared.setPinned(targetWord, for: reading, pinned: true)
        case .unpin: UserLexicon.shared.setPinned(targetWord, for: reading, pinned: false)
        case .forget: UserLexicon.shared.forget(targetWord, for: reading)
        }
        updateCandidates(client: client)
    }

    // MARK: - Shift Single-Tap Toggle & Status HUD
    private func handleFlagsChanged(event: NSEvent, client: Any?) {
        let relevant = event.modifierFlags.intersection([.shift, .command, .control, .option, .capsLock])
        if relevant == [.shift] {
            if !shiftDisqualifiedUntilAllReleased && !shiftSoleModifier {
                shiftPressTime = CACurrentMediaTime()
                shiftSoleModifier = true
            }
        } else if relevant.isEmpty {
            let duration = CACurrentMediaTime() - shiftPressTime
            var clickedDuringShift = false
            if event.timestamp > 0 {
                let elapsed = duration + 0.03
                let leftAgo = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)
                let rightAgo = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .rightMouseDown)
                clickedDuringShift = leftAgo < elapsed || rightAgo < elapsed
            }
            if shiftSoleModifier && !shiftDisqualifiedUntilAllReleased && !clickedDuringShift
                && duration > 0.02 && duration < 0.35 {
                toggleInputMode(client: client, showHUD: true)
            }
            shiftSoleModifier = false
            shiftDisqualifiedUntilAllReleased = false
            shiftPressTime = 0
        } else {
            shiftSoleModifier = false
            shiftDisqualifiedUntilAllReleased = true
            shiftPressTime = 0
        }
    }

    private func toggleInputMode(client: Any?, showHUD: Bool) {
        let targetClient = resolveClient(client)
        synchronizeManualMode(client: targetClient)
        inputMode = (inputMode == .chinese ? .english : .chinese)
        Self.saveManualMode(inputMode, for: targetClient)
        if !buffer.isEmpty {
            commitRaw(client: targetClient)
        }
        if showHUD {
            let anchor = queryHostCaretRect(client: targetClient)
            let level = (targetClient as? IMKTextInput)?.windowLevel()
            let badge = inputMode == .chinese ? "中" : "EN"
            let title = inputMode == .chinese ? "中文输入" : "英文模式"
            let isAccent = inputMode == .chinese
            onMainActor {
                StatusHUDHolder.shared.show(badge: badge, title: title, isAccent: isAccent, anchorRect: anchor, clientWindowLevel: level)
            }
        }
    }

    private func showPunctuationHUD(client: Any?) {
        let targetClient = resolveClient(client)
        let anchor = queryHostCaretRect(client: targetClient)
        let level = (targetClient as? IMKTextInput)?.windowLevel()
        let isEnglishPunct = AetherSettings.shared.isEnglishPunctuationEnabled
        let badge = isEnglishPunct ? "." : "。"
        let title = isEnglishPunct ? "英文标点" : "中文标点"
        onMainActor {
            StatusHUDHolder.shared.show(badge: badge, title: title, isAccent: !isEnglishPunct, anchorRect: anchor, clientWindowLevel: level)
        }
    }

    private func showScriptHUD(client: Any?) {
        let targetClient = resolveClient(client)
        let anchor = queryHostCaretRect(client: targetClient)
        let level = (targetClient as? IMKTextInput)?.windowLevel()
        let isTraditional = AetherSettings.shared.isTraditionalChineseEnabled
        let badge = isTraditional ? "繁" : "简"
        let title = isTraditional ? "繁体中文" : "简体中文"
        onMainActor {
            StatusHUDHolder.shared.show(badge: badge, title: title, isAccent: true, anchorRect: anchor, clientWindowLevel: level)
        }
    }

    private func onMainActor(_ block: @MainActor @escaping @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { block() }
        } else {
            Task { @MainActor in block() }
        }
    }

    // Hosts can reuse an already-active controller or deliver input without
    // activateServer. Read the application's latest explicit choice at entry.
    // Preserve an in-progress composition (including calculator mode).
    private func synchronizeManualMode(client: Any?) {
        guard buffer.isEmpty, let mode = Self.savedManualMode(for: client) else { return }
        inputMode = mode
    }

    private static func clientIdentifier(for client: Any?) -> String? {
        guard let textInput = client as? IMKTextInput else { return nil }
        // Input sessions can be recreated when a host rebuilds or refocuses its
        // editor. Keep the user's explicit mode choice for the application,
        // rather than resetting to Chinese for each new session identifier.
        if let bundle = textInput.bundleIdentifier(), !bundle.isEmpty {
            return "app:\(bundle)"
        }
        if let unique = textInput.uniqueClientIdentifierString(), !unique.isEmpty {
            return "client:\(unique)"
        }
        return nil
    }

    private static func savedManualMode(for client: Any?) -> InputMode? {
        guard let id = clientIdentifier(for: client) else { return nil }
        manualModeLock.lock()
        defer { manualModeLock.unlock() }
        return manualModeOverrides[id]
    }

    private static func saveManualMode(_ mode: InputMode, for client: Any?) {
        guard let id = clientIdentifier(for: client) else { return }
        manualModeLock.lock()
        manualModeOverrides[id] = mode
        manualModeLock.unlock()
    }

    private static func clearManualMode(for client: Any?, bundleIdentifier: String? = nil) {
        manualModeLock.lock()
        defer { manualModeLock.unlock() }
        if let id = clientIdentifier(for: client) {
            manualModeOverrides.removeValue(forKey: id)
        }
        if let bundle = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !bundle.isEmpty {
            manualModeOverrides.removeValue(forKey: "app:\(bundle)")
        }
    }

    private func syncPassThroughContext(from event: NSEvent) {
        let keyCode = event.keyCode
        if [51, 117, 123, 124, 125, 126, 115, 119, 116, 121, 36, 76].contains(keyCode) {
            lastLearnedCommits.removeAll()
            lastCommitWasSmartPunctuation = false
            lastCommittedChar = nil
            return
        }
        guard let chars = event.characters, !chars.isEmpty,
              !chars.unicodeScalars.allSatisfy(CharacterSet.controlCharacters.contains),
              let last = chars.last else { return }
        if let scalar = last.unicodeScalars.first, (0xF700...0xF8FF).contains(scalar.value) {
            return
        }
        lastLearnedCommits.removeAll()
        lastCommitWasSmartPunctuation = false
        lastCommittedChar = last
    }

    private func effectivePrecedingChar(client: Any?) -> Character? {
        if let textInput = resolveClient(client) as? IMKTextInput {
            let selection = textInput.selectedRange()
            if selection.location == 0 {
                if textInput.attributedSubstring(from: NSRange(location: 0, length: 0)) != nil {
                    return nil
                }
            } else if selection.location != NSNotFound && selection.location > 0 {
                let len = min(2, selection.location)
                let start = selection.location - len
                if let preceding = textInput.attributedSubstring(from: NSRange(location: start, length: len))?.string {
                    return preceding.last
                }
                if let knownEnd = committedContextEnd, selection.location != knownEnd {
                    return nil
                }
            }
        }
        return lastCommittedChar
    }

    private func queryHostCaretRect(client: Any?) -> NSRect? {
        guard let textInput = resolveClient(client) as? IMKTextInput else { return nil }
        var caretRect = NSRect.zero
        _ = textInput.attributes(forCharacterIndex: 0, lineHeightRectangle: &caretRect)
        if !CandidateCaretGeometry.isUsable(caretRect) {
            let marked = textInput.markedRange()
            let selected = textInput.selectedRange()
            let location = marked.location != NSNotFound ? marked.location : selected.location
            if location != NSNotFound {
                caretRect = textInput.firstRect(
                    forCharacterRange: NSRange(location: location, length: 0), actualRange: nil
                )
            }
        }
        return CandidateCaretGeometry.isUsable(caretRect) ? caretRect : nil
    }

    private static func displayPinyinWithCursor(
        rawBuffer: String,
        formatted: String,
        cursorOffset: Int,
        scheme: PinyinScheme,
        isVMode: Bool
    ) -> String {
        guard cursorOffset < rawBuffer.count else { return formatted }
        if isVMode || scheme == .wubi86 {
            let clamped = max(0, min(cursorOffset, formatted.count))
            let idx = formatted.index(formatted.startIndex, offsetBy: clamped)
            return String(formatted[..<idx]) + "▏" + String(formatted[idx...])
        }
        if scheme == .full {
            if cursorOffset == 0 { return "▏" + formatted }
            let rawPrefix = String(rawBuffer.prefix(cursorOffset))
            let nonAposTarget = rawPrefix.filter { $0 != "'" }.count
            var nonAposSeen = 0
            var splitIndex = formatted.startIndex
            while splitIndex < formatted.endIndex && nonAposSeen < nonAposTarget {
                if formatted[splitIndex] != "'" {
                    nonAposSeen += 1
                }
                splitIndex = formatted.index(after: splitIndex)
            }
            if rawPrefix.last == "'", splitIndex < formatted.endIndex, formatted[splitIndex] == "'" {
                splitIndex = formatted.index(after: splitIndex)
            }
            return String(formatted[..<splitIndex]) + "▏" + String(formatted[splitIndex...])
        }
        let clamped = max(0, min(cursorOffset, rawBuffer.count))
        let idx = rawBuffer.index(rawBuffer.startIndex, offsetBy: clamped)
        return String(rawBuffer[..<idx]) + "▏" + String(rawBuffer[idx...])
    }

    // MARK: - Candidate Engine & Pagination
    private func updateCandidates(client: Any?) {
        guard !buffer.isEmpty else {
            resetComposition(client: client)
            return
        }
        
        if isCalculatorComposition && buffer.count > 1 {
            inputMode = .vMode
            allCandidates = VModeCalculator.shared.candidates(for: buffer)
            if allCandidates.isEmpty {
                allCandidates = [Candidate(text: buffer, comment: "v模式")]
            }
        } else {
            if inputMode == .vMode {
                inputMode = .chinese
            }
            allCandidates = DoublePinyin.query(buffer, scheme: compositionScheme, precedingText: compositionContext)
        }

        if rawBuffer != buffer {
            let preservedRaw = rawBuffer
            allCandidates = allCandidates.map { candidate in
                guard candidate.comment == "英" else { return candidate }
                return Candidate(
                    id: candidate.id,
                    text: preservedRaw,
                    comment: candidate.comment,
                    pinyin: candidate.pinyin,
                    isVMode: candidate.isVMode,
                    isEmoji: candidate.isEmoji,
                    consumedInputLength: candidate.consumedInputLength,
                    rawText: candidate.rawText
                )
            }
        }

        if !isCalculatorComposition && AetherSettings.shared.isTraditionalChineseEnabled {
            allCandidates = ChineseScriptConverter.shared.convertCandidates(allCandidates, toTraditional: true)
        }
        
        currentPage = 1
        selectedIndexInPage = 0
        
        updateClientMarkedText(client: client)
        renderPanel(client: client)
    }

    private func candidatesForCurrentPage() -> [Candidate] {
        guard !allCandidates.isEmpty else { return [] }
        let startIndex = (currentPage - 1) * pageSize
        let endIndex = min(startIndex + pageSize, allCandidates.count)
        guard startIndex < endIndex else { return [] }
        return Array(allCandidates[startIndex..<endIndex])
    }

    private var totalPages: Int {
        guard !allCandidates.isEmpty else { return 1 }
        return max(1, Int(ceil(Double(allCandidates.count) / Double(pageSize))))
    }

    private func moveSelection(delta: Int, client: Any?) {
        let pageCandidates = candidatesForCurrentPage()
        guard !pageCandidates.isEmpty else { return }
        
        var newIdx = selectedIndexInPage + delta
        if newIdx < 0 {
            if currentPage > 1 {
                currentPage -= 1
                selectedIndexInPage = candidatesForCurrentPage().count - 1
            } else {
                newIdx = 0
            }
        } else if newIdx >= pageCandidates.count {
            if currentPage < totalPages {
                currentPage += 1
                selectedIndexInPage = 0
            } else {
                newIdx = pageCandidates.count - 1
            }
        } else {
            selectedIndexInPage = newIdx
        }
        renderPanel(client: client)
    }

    public func toggleViewMode(client: Any? = nil) {
        candidateViewMode = (candidateViewMode == .paging ? .scroll : .paging)
        AetherSettings.shared.defaultViewMode = candidateViewMode
        currentPage = 1
        selectedIndexInPage = 0
        renderPanel(client: client ?? activeClient)
    }

    private func flipPage(delta: Int, client: Any?) {
        let newPage = currentPage + delta
        if newPage >= 1 && newPage <= totalPages {
            currentPage = newPage
            selectedIndexInPage = 0
            renderPanel(client: client ?? activeClient)
        }
    }

    // MARK: - Committing Text with Pangu Spacing & Partial Selection Support
    private func commitCurrentSelection(client: Any?) {
        let pageCandidates = candidatesForCurrentPage()
        guard !pageCandidates.isEmpty else {
            commitRaw(client: client)
            return
        }
        let selectedCandidate = pageCandidates[min(selectedIndexInPage, pageCandidates.count - 1)]
        commitCandidate(selectedCandidate, client: client)
    }

    private func resolveClient(_ client: Any?) -> Any? {
        if let c = client { return c }
        return activeClient
    }

    private func commitCandidate(_ candidate: Candidate, client: Any?) {
        let targetClient = resolveClient(client)
        let consumed = candidate.consumedInputLength
        let isPartial = (consumed > 0 && consumed < buffer.count && !isCalculatorComposition)
        let canonicalWord = candidate.canonicalText
        
        if isPartial {
            // Partial selection in a multi-syllable input (e.g. picking "今天" from "jintiantianqi"):
            // Accumulate partial composed text and keep remaining pinyin in buffer!
            let consumedPinyin = candidateReading(candidate)
            UserLexicon.shared.recordCommit(pinyin: consumedPinyin, word: canonicalWord)
            lastLearnedCommits = [(pinyin: consumedPinyin, word: canonicalWord)]
            lastCommitWasSmartPunctuation = false
            
            let formattedPart = AetherSettings.shared.isPanguSpacingEnabled
                ? PanguSpacing.shared.formatCommitText(preceding: compositionPrecedingChar, committing: candidate.text)
                : candidate.text
            commitDirect(text: formattedPart, client: targetClient)
            
            compositionContext = PinyinContext.suffix(compositionContext + canonicalWord)
            compositionPrecedingChar = formattedPart.last ?? candidate.text.last
            partialComposedText += canonicalWord
            buffer = String(buffer.dropFirst(consumed))
            rawBuffer = String(rawBuffer.dropFirst(min(consumed, rawBuffer.count)))
            compositionCursor = buffer.count
            compositionGeneration += 1
            lastCompositionCaretRect = queryHostCaretRect(client: targetClient)
            onMainActor { CandidatePanelHolder.shared.resetAnchor() }
            updateCandidates(client: targetClient)
            return
        }
        
        // Full buffer commit
        let fullPinyin = candidateReading(candidate)
        lastLearnedCommits.removeAll()
        lastCommitWasSmartPunctuation = false
        if !isCalculatorComposition && candidate.comment != "英" && !candidate.isEmoji {
            UserLexicon.shared.recordCommit(pinyin: fullPinyin, word: canonicalWord)
            lastLearnedCommits.append((pinyin: fullPinyin, word: canonicalWord))
            if !partialComposedText.isEmpty && !originalFullBuffer.isEmpty {
                // Also learn the complete multi-part phrase the user assembled!
                let assembledReading = DoublePinyin.reading(originalFullBuffer, scheme: compositionScheme)
                let assembledWord = partialComposedText + canonicalWord
                UserLexicon.shared.recordCommit(pinyin: assembledReading, word: assembledWord)
                lastLearnedCommits.append((pinyin: assembledReading, word: assembledWord))
            }
        }
        
        let formattedText = AetherSettings.shared.isPanguSpacingEnabled
            ? PanguSpacing.shared.formatCommitText(preceding: compositionPrecedingChar, committing: candidate.text)
            : candidate.text
        
        commitDirect(text: formattedText, client: targetClient)
        clearState()
    }

    private func commitRaw(client: Any?) {
        let rawText = rawBuffer
        let targetClient = resolveClient(client)
        let formattedText = AetherSettings.shared.isPanguSpacingEnabled
            ? PanguSpacing.shared.formatCommitText(preceding: compositionPrecedingChar, committing: rawText)
            : rawText
        commitDirect(text: formattedText, client: targetClient)
        clearState()
    }

    private func commitDirect(text: String, client: Any?, clearMarked: Bool = true) {
        guard let textInput = resolveClient(client) as? IMKTextInput else { return }
        if clearMarked && !buffer.isEmpty {
            textInput.setMarkedText(
                "",
                selectionRange: NSRange(location: 0, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
        }
        textInput.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        lastCommittedChar = text.last
        committedContext = String((committedContext + text).suffix(24))
        let selection = textInput.selectedRange()
        committedContextEnd = selection.location != NSNotFound && selection.location > 0 && selection.length == 0
            ? selection.location : nil
    }

    private func updateClientMarkedText(client: Any?) {
        guard let textInput = resolveClient(client) as? IMKTextInput else { return }
        let text = rawBuffer
        textInput.setMarkedText(
            text,
            selectionRange: NSRange(location: String(text.prefix(compositionCursor)).utf16.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    public func resetComposition(client: Any?) {
        if let textInput = resolveClient(client) as? IMKTextInput {
            textInput.setMarkedText(
                "",
                selectionRange: NSRange(location: 0, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
        }
        cancelComposition()
        clearState()
    }

    private func clearState() {
        compositionGeneration += 1
        lastCompositionCaretRect = nil
        compositionPrecedingChar = nil
        compositionContext = ""
        buffer = ""
        rawBuffer = ""
        compositionCursor = 0
        originalFullBuffer = ""
        partialComposedText = ""
        allCandidates.removeAll()
        currentPage = 1
        selectedIndexInPage = 0
        if inputMode == .vMode {
            inputMode = .chinese
        }
        
        onMainActor { CandidatePanelHolder.shared.dismiss() }
    }

    // MARK: - Caret Positioning & Panel Rendering
    private func renderPanel(client: Any?) {
        guard !buffer.isEmpty else {
            clearState()
            return
        }
        
        let liveCaret = queryHostCaretRect(client: client)
        if CandidateGeometryDiagnostics.enabled, let textInput = resolveClient(client) as? IMKTextInput {
            let marked = textInput.markedRange()
            let selected = textInput.selectedRange()
            var attributesZero = NSRect.zero
            _ = textInput.attributes(forCharacterIndex: 0, lineHeightRectangle: &attributesZero)
            var attributesEnd = NSRect.zero
            let location = marked.location != NSNotFound ? NSMaxRange(marked) : selected.location
            if location != NSNotFound {
                _ = textInput.attributes(forCharacterIndex: location, lineHeightRectangle: &attributesEnd)
            }
            let start = marked.location != NSNotFound ? textInput.firstRect(
                forCharacterRange: NSRange(location: marked.location, length: 0), actualRange: nil
            ) : .zero
            CandidateGeometryDiagnostics.record([
                "stage": "client", "bundle": textInput.bundleIdentifier() ?? "unknown",
                "marked": NSStringFromRange(marked), "selected": NSStringFromRange(selected),
                "firstEnd": NSStringFromRect(liveCaret ?? .zero), "firstStart": NSStringFromRect(start),
                "attributesZero": NSStringFromRect(attributesZero), "attributesEnd": NSStringFromRect(attributesEnd)
            ])
        }

        let caretRect: NSRect
        let usedMouseFallback: Bool
        if let anchor = lastCompositionCaretRect {
            if let liveCaret, abs(liveCaret.minY - anchor.minY) >= max(12, anchor.height * 0.6) {
                lastCompositionCaretRect = liveCaret
                caretRect = liveCaret
            } else {
                caretRect = anchor
            }
            usedMouseFallback = false
        } else if let liveCaret {
            lastCompositionCaretRect = liveCaret
            caretRect = liveCaret
            usedMouseFallback = false
        } else {
            caretRect = NSRect(
                x: NSEvent.mouseLocation.x, y: NSEvent.mouseLocation.y, width: 0, height: 22
            )
            usedMouseFallback = true
        }

        let curCandidates = candidatesForCurrentPage()
        let curBuffer = buffer
        let curRawBuffer = rawBuffer
        let baseDisplayPinyin = (inputMode == .vMode)
            ? curRawBuffer
            : (compositionScheme == .full
                ? PinyinEngine.shared.formatSegmentedPinyin(rawInput: curBuffer)
                : DoublePinyin.reading(curBuffer, scheme: compositionScheme))
        let curDisplayPinyin = Self.displayPinyinWithCursor(
            rawBuffer: curBuffer,
            formatted: baseDisplayPinyin,
            cursorOffset: compositionCursor,
            scheme: compositionScheme,
            isVMode: inputMode == .vMode
        )
        let curMode = inputMode
        let curViewMode = candidateViewMode
        let curSel = selectedIndexInPage
        let curPage = currentPage
        let curTotal = totalPages
        let clientWindowLevel = (resolveClient(client) as? IMKTextInput)?.windowLevel()
        
        onMainActor { [weak self] in
            let panel = CandidatePanelHolder.shared
            panel.state.inputString = curBuffer
            panel.state.displayPinyin = curDisplayPinyin
            panel.state.mode = curMode
            panel.state.viewMode = curViewMode
            panel.state.candidates = curCandidates
            panel.state.selectedIndex = curSel
            panel.state.currentPage = curPage
            panel.state.totalPages = curTotal
            panel.state.onSelectCandidate = { idx in
                guard let self = self else { return }
                let pageCands = self.candidatesForCurrentPage()
                if idx >= 0 && idx < pageCands.count {
                    self.commitCandidate(pageCands[idx], client: self.activeClient)
                }
            }
            panel.state.onCandidateAction = { index, action in
                guard let self else { return }
                let candidates = self.candidatesForCurrentPage()
                guard candidates.indices.contains(index) else { return }
                self.manageCandidate(candidates[index], action: action, client: self.activeClient)
            }
            panel.state.isCandidatePinned = { index in
                guard let self else { return false }
                let candidates = self.candidatesForCurrentPage()
                guard candidates.indices.contains(index) else { return false }
                let candidate = candidates[index]
                return UserLexicon.shared.isPinned(candidate.canonicalText, for: self.candidateReading(candidate))
            }
            panel.state.onToggleViewMode = {
                self?.toggleViewMode(client: self?.activeClient)
            }
            panel.state.onPageDelta = { delta in
                self?.flipPage(delta: delta, client: self?.activeClient)
            }
            panel.show(caretRect: caretRect, clientWindowLevel: clientWindowLevel)
        }

        if usedMouseFallback {
            let expectedGeneration = compositionGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                guard let self, !self.buffer.isEmpty, self.compositionGeneration == expectedGeneration,
                      self.lastCompositionCaretRect == nil,
                      let resolvedCaret = self.queryHostCaretRect(client: self.activeClient) else { return }
                self.lastCompositionCaretRect = resolvedCaret
                let level = (self.resolveClient(self.activeClient) as? IMKTextInput)?.windowLevel()
                MainActor.assumeIsolated {
                    CandidatePanelHolder.shared.resetAnchor()
                    CandidatePanelHolder.shared.show(caretRect: resolvedCaret, clientWindowLevel: level)
                }
            }
        }
    }
}
