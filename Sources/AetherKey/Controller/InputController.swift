import AppKit
import InputMethodKit

/// Global shared candidate panel instance
@MainActor
public enum CandidatePanelHolder {
    public static let shared = CandidatePanel()
}

/// AetherKey Input Controller conforming to macOS IMKServer specifications.
/// Designed for Apple Silicon with zero-blocking synchronous event handling,
/// Pangu spacing, smart punctuation, Shift toggle, and AetherNative visual aesthetics.
@objc(AetherInputController)
public final class AetherInputController: IMKInputController {
    
    // MARK: - State Management
    private var buffer: String = ""
    private var inputMode: InputMode = .chinese
    private var allCandidates: [Candidate] = []
    private var currentPage: Int = 1
    private let pageSize: Int = 5
    private var selectedIndexInPage: Int = 0
    
    // Tracking context & Shift single-tap
    private var shiftPressTime: TimeInterval = 0
    private var shiftSoleModifier: Bool = false
    private var lastCommittedChar: Character? = nil
    
    // MARK: - IMK Lifecycle
    public override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
    }

    public override func recognizedEvents(_ sender: Any!) -> Int {
        return Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue)
    }

    // MARK: - Synchronous Event Interception
    public override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event else { return false }
        
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
        
        // Pass through Command / Control keyboard shortcuts instantly
        let flags = event.modifierFlags
        if flags.contains(.command) || flags.contains(.control) {
            if !buffer.isEmpty {
                commitRaw(client: sender)
            }
            return false
        }
        
        // Context Awareness: Check if frontmost app is Terminal or code editor
        let bundleID = (sender as? IMKTextInput)?.bundleIdentifier()
        if ContextDetector.shared.shouldDefaultToEnglish(bundleIdentifier: bundleID) && buffer.isEmpty {
            return false
        }
        
        // If in English mode and buffer is empty, instant pass-through
        if inputMode == .english && buffer.isEmpty {
            return false
        }
        
        // Intercept characters
        guard let characters = event.characters, !characters.isEmpty else {
            return false
        }
        
        let keyCode = event.keyCode
        
        // 2. State Machine: Buffer is Empty
        if buffer.isEmpty {
            // First character is 'a'...'z' or 'v' -> Begin composition
            if let firstChar = characters.first, (firstChar.isLetter || firstChar == "v") && firstChar.isASCII {
                buffer.append(characters)
                updateCandidates(client: sender)
                return true
            }
            
            // Check Smart Punctuation in Chinese mode
            if inputMode == .chinese, let firstChar = characters.first, SmartPunctuation.shared.isPunctuation(firstChar) {
                let converted = SmartPunctuation.shared.convert(char: firstChar, precedingChar: lastCommittedChar)
                commitDirect(text: converted, client: sender)
                return true
            }
            
            // Unhandled pass-through
            return false
        }
        
        // 3. State Machine: Buffer is Non-Empty (Composition in progress)
        switch keyCode {
        // Backspace / Delete
        case 51:
            buffer.removeLast()
            if buffer.isEmpty {
                resetComposition(client: sender)
            } else {
                updateCandidates(client: sender)
            }
            return true
            
        // Escape
        case 53:
            resetComposition(client: sender)
            return true
            
        // Enter / Return -> Commit raw buffer as typed
        case 36:
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
            moveSelection(delta: -1, client: sender)
            return true
        case 124:
            moveSelection(delta: 1, client: sender)
            return true
            
        // Page Previous: '-', '[', PageUp (116)
        case 27, 33, 116:
            flipPage(delta: -1, client: sender)
            return true
            
        // Page Next: '=', ']', PageDown (121)
        case 24, 30, 121:
            flipPage(delta: 1, client: sender)
            return true
            
        default:
            break
        }
        
        // Numeric selection keys 1 - 9
        if let char = characters.first, char.isNumber, let digit = char.wholeNumberValue, digit >= 1 && digit <= 9 {
            let pageCandidates = candidatesForCurrentPage()
            let targetIdx = digit - 1
            if targetIdx < pageCandidates.count {
                commitCandidate(pageCandidates[targetIdx], client: sender)
                return true
            }
        }
        
        // Character appending: letters, digits in v-mode, math operators, or apostrophe
        if let firstChar = characters.first {
            if firstChar.isLetter || firstChar == "'" || (buffer.hasPrefix("v") && "+-*/.()^".contains(firstChar)) {
                buffer.append(characters)
                updateCandidates(client: sender)
                return true
            }
            
            // Punctuation typed during composition: commit candidate first, then punctuation
            if SmartPunctuation.shared.isPunctuation(firstChar) {
                commitCurrentSelection(client: sender)
                let converted = SmartPunctuation.shared.convert(char: firstChar, precedingChar: lastCommittedChar)
                commitDirect(text: converted, client: sender)
                return true
            }
        }
        
        return false
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
            if duration > 0.04 && duration < 0.38 {
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
        
        if buffer.hasPrefix("v") && buffer.count > 1 {
            inputMode = .vMode
            allCandidates = VModeCalculator.shared.candidates(for: buffer)
            if allCandidates.isEmpty {
                allCandidates = [Candidate(text: buffer, comment: "v模式")]
            }
        } else {
            if inputMode == .vMode {
                inputMode = .chinese
            }
            allCandidates = PinyinEngine.shared.query(rawInput: buffer)
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

    private func flipPage(delta: Int, client: Any?) {
        let newPage = currentPage + delta
        if newPage >= 1 && newPage <= totalPages {
            currentPage = newPage
            selectedIndexInPage = 0
            renderPanel(client: client)
        }
    }

    // MARK: - Committing Text with Pangu Spacing
    private func commitCurrentSelection(client: Any?) {
        let pageCandidates = candidatesForCurrentPage()
        guard !pageCandidates.isEmpty else {
            commitRaw(client: client)
            return
        }
        let selectedCandidate = pageCandidates[min(selectedIndexInPage, pageCandidates.count - 1)]
        commitCandidate(selectedCandidate, client: client)
    }

    private func commitCandidate(_ candidate: Candidate, client: Any?) {
        // Automatic Pangu Spacing applied between Chinese, English and numbers
        let formattedText = PanguSpacing.shared.formatCommitText(
            preceding: lastCommittedChar,
            committing: candidate.text
        )
        
        commitDirect(text: formattedText, client: client)
        clearState()
    }

    private func commitRaw(client: Any?) {
        let rawText = buffer
        commitDirect(text: rawText, client: client)
        clearState()
    }

    private func commitDirect(text: String, client: Any?) {
        guard let textInput = client as? IMKTextInput else { return }
        textInput.insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        lastCommittedChar = text.last
    }

    private func updateClientMarkedText(client: Any?) {
        guard let textInput = client as? IMKTextInput else { return }
        let text = buffer
        textInput.setMarkedText(
            text,
            selectionRange: NSRange(location: text.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
    }

    public func resetComposition(client: Any?) {
        if let textInput = client as? IMKTextInput {
            textInput.setMarkedText(
                "",
                selectionRange: NSRange(location: 0, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
            )
        }
        cancelComposition()
        clearState()
    }

    private func clearState() {
        buffer = ""
        allCandidates.removeAll()
        currentPage = 1
        selectedIndexInPage = 0
        
        Task { @MainActor in
            CandidatePanelHolder.shared.dismiss()
        }
    }

    // MARK: - Caret Positioning & Panel Rendering
    private func renderPanel(client: Any?) {
        guard !buffer.isEmpty else {
            clearState()
            return
        }
        
        var caretRect = NSRect.zero
        if let textInput = client as? IMKTextInput {
            _ = textInput.attributes(forCharacterIndex: 0, lineHeightRectangle: &caretRect)
        }
        
        if caretRect == .zero || caretRect.origin == .zero {
            let mouse = NSEvent.mouseLocation
            caretRect = NSRect(x: mouse.x, y: mouse.y, width: 0, height: 22)
        }
        
        let curCandidates = candidatesForCurrentPage()
        let curBuffer = buffer
        let curMode = inputMode
        let curSel = selectedIndexInPage
        let curPage = currentPage
        let curTotal = totalPages
        
        Task { @MainActor in
            let panel = CandidatePanelHolder.shared
            panel.state.inputString = curBuffer
            panel.state.mode = curMode
            panel.state.candidates = curCandidates
            panel.state.selectedIndex = curSel
            panel.state.currentPage = curPage
            panel.state.totalPages = curTotal
            panel.show(caretRect: caretRect)
        }
    }
}
