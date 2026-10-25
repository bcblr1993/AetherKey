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
        buffer.hasPrefix("v") && (compositionScheme == .full || buffer.dropFirst().first?.isNumber == true)
    }
    private var buffer: String = ""
    private var compositionCursor: Int = 0
    private var originalFullBuffer: String = ""
    private var partialComposedText: String = ""
    private var inputMode: InputMode = .chinese
    private var allCandidates: [Candidate] = []
    private var candidateViewMode: CandidateViewMode = AetherSettings.shared.defaultViewMode
    private var currentPage: Int = 1
    private var pageSize: Int {
        return candidateViewMode == .scroll ? 14 : 7
    }
    private var selectedIndexInPage: Int = 0
    private weak var activeClient: AnyObject? = nil
    
    // Tracking context & Shift single-tap
    private var shiftPressTime: TimeInterval = 0
    private var shiftSoleModifier: Bool = false
    private var lastCommittedChar: Character? = nil
    private var compositionContext = ""
    private var committedContext = ""
    private var committedContextEnd: Int?
    private var lastCompositionCaretRect: NSRect?
    
    // MARK: - IMK Lifecycle
    public override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        self.activeClient = inputClient as AnyObject?
    }

    public override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        self.activeClient = sender as AnyObject?
        if AetherSettings.shared.isAutoEnglishInTerminalEnabled,
           let textInput = sender as? IMKTextInput,
           let bundleId = textInput.bundleIdentifier(),
           ContextDetector.shared.isTerminalApp(bundleIdentifier: bundleId) {
            inputMode = .english
        }
    }

    public override func deactivateServer(_ sender: Any!) {
        committedContext = ""
        committedContextEnd = nil
        if !buffer.isEmpty {
            resetComposition(client: sender)
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
        
        let statsItem = NSMenuItem(
            title: "AetherKey \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.4") · 53.3万词库 (已习得 \(UserLexicon.shared.learnedEntryCount) 词)",
            action: nil,
            keyEquivalent: ""
        )
        statsItem.isEnabled = false
        menu.addItem(statsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let modeTitle = (inputMode == .chinese) ? "当前模式：中文 (单击 Shift 切换)" : "当前模式：英文 EN (单击 Shift 切换)"
        let modeItem = NSMenuItem(title: modeTitle, action: #selector(menuToggleInputMode), keyEquivalent: "")
        modeItem.target = self
        menu.addItem(modeItem)
        
        let viewTitle = (candidateViewMode == .scroll) ? "候选视图：卷轴模式 (⌥Tab 切换)" : "候选视图：翻页模式 (⌥Tab 切换)"
        let viewItem = NSMenuItem(title: viewTitle, action: #selector(menuToggleViewMode), keyEquivalent: "")
        viewItem.target = self
        menu.addItem(viewItem)
        
        for scheme in PinyinScheme.allCases {
            let action: Selector
            switch scheme {
            case .full: action = #selector(menuSelectFull)
            case .flypy: action = #selector(menuSelectFlypy)
            case .microsoft: action = #selector(menuSelectMicrosoft)
            }
            let item = NSMenuItem(title: "拼音方案：\(scheme.title)", action: action, keyEquivalent: "")
            item.target = self
            item.state = settings.pinyinScheme == scheme ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        
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

    @objc private func menuSelectFull() { selectScheme(.full) }
    @objc private func menuSelectFlypy() { selectScheme(.flypy) }
    @objc private func menuSelectMicrosoft() { selectScheme(.microsoft) }

    private func selectScheme(_ scheme: PinyinScheme) {
        // Existing marked text keeps its original layout until committed or cancelled.
        AetherSettings.shared.pinyinScheme = scheme
    }

    @objc private func menuCheckForUpdates() {
        MainActor.assumeIsolated { UpdateController.shared.checkForUpdates() }
    }

    @objc private func menuToggleInputMode() {
        inputMode = (inputMode == .chinese ? .english : .chinese)
        if !buffer.isEmpty {
            commitRaw(client: activeClient)
        }
    }

    @objc private func menuToggleViewMode() {
        toggleViewMode(client: activeClient)
    }

    @objc private func menuTogglePangu() {
        AetherSettings.shared.isPanguSpacingEnabled.toggle()
    }

    @objc private func menuTogglePunctuation() {
        AetherSettings.shared.isSmartPunctuationEnabled.toggle()
    }

    @objc private func menuToggleEnglishPunctuation() {
        AetherSettings.shared.isEnglishPunctuationEnabled.toggle()
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
        
        // 1. Shift key tap detection for instantaneous Chinese / English toggle
        if event.type == .flagsChanged {
            handleFlagsChanged(event: event, client: sender)
            return false // Allow OS to receive flag changes
        }
        
        // Only intercept keyDown events
        guard event.type == .keyDown else {
            return false
        }
        
        // Shift key held while other key pressed -> clear sole modifier flag
        if shiftSoleModifier {
            shiftSoleModifier = false
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
            if !event.isARepeat { AetherSettings.shared.isEnglishPunctuationEnabled.toggle() }
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
        
        // If in English mode and buffer is empty, instant pass-through
        if inputMode == .english && buffer.isEmpty {
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
            case 123:
                compositionCursor = flags.contains(.option) ? previousSyllableBoundary() : max(0, compositionCursor - 1)
                updateClientMarkedText(client: sender); renderPanel(client: sender)
                return true
            case 124:
                compositionCursor = flags.contains(.option) ? nextSyllableBoundary() : min(buffer.count, compositionCursor + 1)
                updateClientMarkedText(client: sender); renderPanel(client: sender)
                return true
                
            // Page Previous: '-' (without Shift, outside v-mode) or PageUp (116)
            case 27 where !flags.contains(.shift) && !isCalculatorComposition, 116:
                flipPage(delta: -1, client: sender)
                return true
                
            // Page Next: '=' (without Shift, outside v-mode) or PageDown (121)
            case 24 where !flags.contains(.shift) && !isCalculatorComposition, 121:
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
        
        // Intercept characters for composition insertion and punctuation
        guard let characters = event.characters, !characters.isEmpty else {
            return false
        }
        
        // 3. State Machine: Buffer is Empty
        if buffer.isEmpty {
            if let firstChar = characters.first, firstChar.isASCII && firstChar.isLetter {
                // Uppercase ASCII letters (Shift+Letter or CapsLock) pass through directly in Chinese mode
                if firstChar.isUppercase {
                    let formatted = AetherSettings.shared.isPanguSpacingEnabled
                        ? PanguSpacing.shared.formatCommitText(preceding: lastCommittedChar, committing: characters)
                        : characters
                    commitDirect(text: formatted, client: sender)
                    return true
                }
                
                // Lowercase 'a'...'z' or 'v' -> Begin composition
                insertComposition(characters.lowercased())
                originalFullBuffer = buffer
                partialComposedText = ""
                updateCandidates(client: sender)
                return true
            }
            
            // Check Smart Punctuation in Chinese mode
            if inputMode == .chinese,
               let firstChar = characters.first,
               SmartPunctuation.shared.isPunctuation(firstChar) {
                let converted = AetherSettings.shared.usesChinesePunctuation
                    ? SmartPunctuation.shared.convert(char: firstChar, precedingChar: lastCommittedChar)
                    : String(firstChar)
                commitDirect(text: converted, client: sender)
                return true
            }
            
            // Record raw digit or ASCII character for contextual decimal/Pangu tracking
            if let firstChar = characters.first, firstChar.isNumber {
                lastCommittedChar = firstChar
            }
            
            // Unhandled pass-through
            return false
        }
        
        // Numeric selection keys 1 - 9
        if let char = characters.first, char.isNumber, let digit = char.wholeNumberValue, digit >= 1 && digit <= 9 {
            // In v-mode, digits are part of the mathematical/RMB expression!
            if isCalculatorComposition || buffer == "v" {
                insertComposition(String(char))
                updateCandidates(client: sender)
                return true
            }
            
            let pageCandidates = candidatesForCurrentPage()
            let targetIdx = digit - 1
            if targetIdx < pageCandidates.count {
                commitCandidate(pageCandidates[targetIdx], client: sender)
                return true
            }
        }
        
        // If in v-mode and '0' is typed
        if isCalculatorComposition || buffer == "v", let char = characters.first, char == "0" {
            insertComposition(String(char))
            updateCandidates(client: sender)
            return true
        }
        
        // Character appending: letters, digits in v-mode, math operators, or apostrophe
        if let firstChar = characters.first {
            if (firstChar == ";" && compositionScheme == .microsoft && acceptsMicrosoftFinal) || firstChar.isLetter || firstChar == "'" || (isCalculatorComposition && "+-*/.()^%".contains(firstChar)) {
                let toAppend = isCalculatorComposition ? characters : characters.lowercased()
                insertComposition(toAppend)
                if partialComposedText.isEmpty {
                    originalFullBuffer = buffer
                }
                updateCandidates(client: sender)
                return true
            }
            
            // Punctuation typed during composition: commit candidate first, then punctuation
            if SmartPunctuation.shared.isPunctuation(firstChar) {
                commitCurrentSelection(client: sender)
                let converted = AetherSettings.shared.usesChinesePunctuation
                    ? SmartPunctuation.shared.convert(char: firstChar, precedingChar: lastCommittedChar)
                    : String(firstChar)
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
        
        if inputMode == .english && buffer.isEmpty {
            return false
        }
        
        var handled = false
        for char in string {
            let lowerChar = Character(char.lowercased())
            if buffer.isEmpty {
                if char.isASCII && char.isLetter {
                    if char.isUppercase {
                        let formatted = AetherSettings.shared.isPanguSpacingEnabled
                            ? PanguSpacing.shared.formatCommitText(preceding: lastCommittedChar, committing: String(char))
                            : String(char)
                        commitDirect(text: formatted, client: sender)
                        handled = true
                    } else {
                        insertComposition(String(lowerChar))
                        originalFullBuffer = buffer
                        partialComposedText = ""
                        updateCandidates(client: sender)
                        handled = true
                    }
                } else if inputMode == .chinese && SmartPunctuation.shared.isPunctuation(char) {
                    let converted = AetherSettings.shared.usesChinesePunctuation
                        ? SmartPunctuation.shared.convert(char: char, precedingChar: lastCommittedChar)
                        : String(char)
                    commitDirect(text: converted, client: sender)
                    handled = true
                }
            } else {
                if char == " " {
                    commitCurrentSelection(client: sender)
                    handled = true
                } else if char == "\n" || char == "\r" {
                    commitRaw(client: sender)
                    handled = true
                } else if (isCalculatorComposition || buffer == "v") && (char.isNumber || "+-*/.()^%".contains(char)) {
                    insertComposition(String(char))
                    updateCandidates(client: sender)
                    handled = true
                } else if let digit = char.wholeNumberValue, digit >= 1 && digit <= 9 {
                    let pageCandidates = candidatesForCurrentPage()
                    let targetIdx = digit - 1
                    if targetIdx < pageCandidates.count {
                        commitCandidate(pageCandidates[targetIdx], client: sender)
                        handled = true
                    }
                } else if (char == ";" && compositionScheme == .microsoft && acceptsMicrosoftFinal) || lowerChar.isLetter || lowerChar == "'" {
                    insertComposition(String(isCalculatorComposition ? char : lowerChar))
                    if partialComposedText.isEmpty {
                        originalFullBuffer = buffer
                    }
                    updateCandidates(client: sender)
                    handled = true
                } else if SmartPunctuation.shared.isPunctuation(char) {
                    commitCurrentSelection(client: sender)
                    let converted = AetherSettings.shared.usesChinesePunctuation
                        ? SmartPunctuation.shared.convert(char: char, precedingChar: lastCommittedChar)
                        : String(char)
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
        buffer.replaceSubrange(start..<end, with: text)
        compositionCursor = range.lowerBound + text.count
        // Rebuild the full reading after an edit, including already selected prefixes.
        if partialComposedText.isEmpty {
            originalFullBuffer = buffer
        } else {
            let consumedLength = max(0, originalFullBuffer.count - (buffer.count - text.count + range.count))
            originalFullBuffer = String(originalFullBuffer.prefix(consumedLength)) + buffer
        }
    }

    private func insertComposition(_ text: String) {
        if buffer.isEmpty {
            compositionScheme = AetherSettings.shared.pinyinScheme
            compositionContext = precedingContext(client: activeClient)
            committedContext = compositionContext
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

    private var acceptsMicrosoftFinal: Bool {
        let prefix = String(buffer.prefix(compositionCursor))
        return (prefix.split(separator: "'", omittingEmptySubsequences: false).last?.count ?? 0) % 2 == 1
    }

    private var compositionBoundaries: [Int] {
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
        switch action {
        case .pin: UserLexicon.shared.setPinned(candidate.text, for: reading, pinned: true)
        case .unpin: UserLexicon.shared.setPinned(candidate.text, for: reading, pinned: false)
        case .forget: UserLexicon.shared.forget(candidate.text, for: reading)
        }
        updateCandidates(client: client)
    }

    // MARK: - Shift Single-Tap Toggle
    private func handleFlagsChanged(event: NSEvent, client: Any?) {
        let isShiftPressed = event.modifierFlags.contains(.shift)
        let otherModifiers = event.modifierFlags.intersection([.command, .control, .option])
        
        if isShiftPressed && otherModifiers.isEmpty {
            shiftPressTime = CACurrentMediaTime()
            shiftSoleModifier = true
        } else if !isShiftPressed && shiftSoleModifier {
            let duration = CACurrentMediaTime() - shiftPressTime
            if duration > 0.02 && duration < 0.40 {
                // Smoothly toggle input mode
                inputMode = (inputMode == .chinese ? .english : .chinese)
                if !buffer.isEmpty {
                    commitRaw(client: client)
                }
            }
            shiftSoleModifier = false
            shiftPressTime = 0
        }
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
        
        if isPartial {
            // Partial selection in a multi-syllable input (e.g. picking "今天" from "jintiantianqi"):
            // Accumulate partial composed text and keep remaining pinyin in buffer!
            let consumedPinyin = candidateReading(candidate)
            UserLexicon.shared.recordCommit(pinyin: consumedPinyin, word: candidate.text)
            
            let formattedPart = AetherSettings.shared.isPanguSpacingEnabled
                ? PanguSpacing.shared.formatCommitText(preceding: lastCommittedChar, committing: candidate.text)
                : candidate.text
            commitDirect(text: formattedPart, client: targetClient)
            
            compositionContext = PinyinContext.suffix(compositionContext + candidate.text)
            partialComposedText += candidate.text
            buffer = String(buffer.dropFirst(consumed))
            compositionCursor = buffer.count
            updateCandidates(client: targetClient)
            return
        }
        
        // Full buffer commit
        let fullPinyin = candidateReading(candidate)
        if !isCalculatorComposition && candidate.comment != "英" && !candidate.isEmoji {
            UserLexicon.shared.recordCommit(pinyin: fullPinyin, word: candidate.text)
            if !partialComposedText.isEmpty && !originalFullBuffer.isEmpty {
                // Also learn the complete multi-part phrase the user assembled!
                UserLexicon.shared.recordCommit(pinyin: DoublePinyin.reading(originalFullBuffer, scheme: compositionScheme), word: partialComposedText + candidate.text)
            }
        }
        
        let formattedText = AetherSettings.shared.isPanguSpacingEnabled
            ? PanguSpacing.shared.formatCommitText(preceding: lastCommittedChar, committing: candidate.text)
            : candidate.text
        
        commitDirect(text: formattedText, client: targetClient)
        clearState()
    }

    private func commitRaw(client: Any?) {
        let rawText = buffer
        let targetClient = resolveClient(client)
        let formattedText = AetherSettings.shared.isPanguSpacingEnabled
            ? PanguSpacing.shared.formatCommitText(preceding: lastCommittedChar, committing: rawText)
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
        let text = buffer
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
        lastCompositionCaretRect = nil
        compositionContext = ""
        buffer = ""
        compositionCursor = 0
        originalFullBuffer = ""
        partialComposedText = ""
        allCandidates.removeAll()
        currentPage = 1
        selectedIndexInPage = 0
        
        if Thread.isMainThread {
            MainActor.assumeIsolated { CandidatePanelHolder.shared.dismiss() }
        } else {
            Task { @MainActor in CandidatePanelHolder.shared.dismiss() }
        }
    }

    // MARK: - Caret Positioning & Panel Rendering
    private func renderPanel(client: Any?) {
        guard !buffer.isEmpty else {
            clearState()
            return
        }
        
        var caretRect = NSRect.zero
        if let textInput = resolveClient(client) as? IMKTextInput {
            // Restore the original IMK insertion-point query. In Electron hosts this
            // returns a live line rectangle while firstRect can return garbage values.
            _ = textInput.attributes(forCharacterIndex: 0, lineHeightRectangle: &caretRect)
            if !CandidateCaretGeometry.isUsable(caretRect) {
                let marked = textInput.markedRange()
                let selected = textInput.selectedRange()
                let location = marked.location != NSNotFound ? NSMaxRange(marked) : selected.location
                if location != NSNotFound {
                    caretRect = textInput.firstRect(
                        forCharacterRange: NSRange(location: location, length: 0), actualRange: nil
                    )
                }
            }
        }
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
                "firstEnd": NSStringFromRect(caretRect), "firstStart": NSStringFromRect(start),
                "attributesZero": NSStringFromRect(attributesZero), "attributesEnd": NSStringFromRect(attributesEnd)
            ])
        }
        if !CandidateCaretGeometry.isUsable(caretRect) {
            // Reuse the visible composition anchor during transient host layout updates.
            caretRect = lastCompositionCaretRect ?? NSRect(
                x: NSEvent.mouseLocation.x, y: NSEvent.mouseLocation.y, width: 0, height: 22
            )
        } else {
            lastCompositionCaretRect = caretRect
        }

        let curCandidates = candidatesForCurrentPage()
        let curBuffer = buffer
        let curDisplayPinyin = (inputMode == .vMode) ? curBuffer : (compositionScheme == .full ? PinyinEngine.shared.formatSegmentedPinyin(rawInput: curBuffer) : DoublePinyin.reading(curBuffer, scheme: compositionScheme))
        let curMode = inputMode
        let curViewMode = candidateViewMode
        let curSel = selectedIndexInPage
        let curPage = currentPage
        let curTotal = totalPages
        
        let applyState = { @MainActor [weak self] in
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
                return UserLexicon.shared.isPinned(candidate.text, for: self.candidateReading(candidate))
            }
            panel.state.onToggleViewMode = {
                self?.toggleViewMode(client: self?.activeClient)
            }
            panel.state.onPageDelta = { delta in
                self?.flipPage(delta: delta, client: self?.activeClient)
            }
            panel.show(caretRect: caretRect)
        }
        
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                applyState()
            }
        } else {
            Task { @MainActor in
                applyState()
            }
        }
    }
}
