import Foundation
import Testing
import AppKit
import SwiftUI
import InputMethodKit

@testable import AetherKey

// MARK: - Mock Text Input Client for Headless Verification
final class MockTextInputClient: NSObject, IMKTextInput, @unchecked Sendable {
    var insertedText: String = ""
    var markedText: String = ""
    var markedSelection: NSRange = NSRange(location: 0, length: 0)
    var lastReplacementRange: NSRange = NSRange(location: NSNotFound, length: NSNotFound)
    var attributesCaretRect: NSRect?
    var lastFirstRectRange: NSRange?
    var caretRect: NSRect = NSRect(x: 200, y: 500, width: 0, height: 22)
    
    func insertText(_ string: Any!, replacementRange: NSRange) {
        if let str = string as? String {
            insertedText += str
        }
        self.lastReplacementRange = replacementRange
    }
    
    func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
        if let str = string as? String {
            markedText = str
        }
        self.markedSelection = selectionRange
        self.lastReplacementRange = replacementRange
    }
    
    func selectedRange() -> NSRange {
        return NSRange(location: 0, length: 0)
    }
    
    func markedRange() -> NSRange {
        return NSRange(location: 0, length: markedText.count)
    }
    
    func attributedSubstring(from range: NSRange) -> NSAttributedString? {
        return nil
    }
    
    func length() -> Int {
        return insertedText.count
    }
    
    func characterIndex(for point: NSPoint, tracking: IMKLocationToOffsetMappingMode, inMarkedRange: UnsafeMutablePointer<ObjCBool>?) -> Int {
        return 0
    }
    
    func attributes(forCharacterIndex index: Int, lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>?) -> [AnyHashable : Any]? {
        lineRect?.pointee = attributesCaretRect ?? caretRect
        return [:]
    }
    
    func validAttributesForMarkedText() -> [Any]? {
        return nil
    }
    
    func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String?) {}
    func selectMode(_ modeIdentifier: String?) {}
    func supportsUnicode() -> Bool { return true }
    func bundleIdentifier() -> String? { return "com.apple.Notes" }
    func windowLevel() -> CGWindowLevel { return 0 }
    func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { return true }
    func uniqueClientIdentifierString() -> String? { return "mock-notes-client" }
    func string(from range: NSRange, actualRange: NSRangePointer?) -> String? { return nil }
    func firstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer?) -> NSRect {
        lastFirstRectRange = aRange
        return caretRect
    }
    
    func reset() {
        insertedText = ""
        markedText = ""
        lastReplacementRange = NSRange(location: NSNotFound, length: NSNotFound)
    }
}

// Helper to simulate key events with exact keyCodes and modifiers
func makeKeyEvent(char: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
    return NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifiers,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: char,
        charactersIgnoringModifiers: char,
        isARepeat: false,
        keyCode: keyCode
    )!
}

@Suite("AetherKey Core Engine & Mainstream IME Full-Coverage Test Suite")
struct AetherKeyEngineTests {
    @Test("Every bundled Unihan reading remains reachable as an exact syllable candidate")
    func testCompleteCharacterCoverage() throws {
        let engine = PinyinEngine(userLexicon: UserLexicon(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")))
        let url = try #require(Bundle.main.url(forResource: "characters", withExtension: "json"))
        let rows = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
        #expect(rows.count == 426)
        #expect(Set(rows.values.flatMap { $0.unicodeScalars.map(\.value) }).count == 44_359)
        for (syllable, characters) in rows {
            let candidates = engine.query(rawInput: syllable)
            let reachable = Set(candidates.map(\.text))
            let missing = characters.map(String.init).filter { !reachable.contains($0) }
            #expect(missing.isEmpty, "Missing characters for \(syllable): \(missing)")
            #expect(Set(candidates.map(\.text)).count == candidates.count)
        }
        for (syllable, character) in [("jing", "璟"), ("yi", "逸"), ("yu", "彧"),
                                      ("zhe", "喆"), ("da", "龘"), ("ou", "𠙶")] {
            #expect(engine.query(rawInput: syllable).contains { $0.text == character })
        }
        #expect(engine.query(rawInput: "jingyi").contains {
            $0.text == "璟" && $0.consumedInputLength == 4
        })
        #expect(engine.query(rawInput: "chenjingyi").contains {
            $0.text == "陈" && $0.consumedInputLength == 4
        })
    }

    @Test("Rare name characters can be selected through real controller pagination and partial commits")
    @MainActor
    func testRareNamePartialSelection() throws {
        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        for character in "chenjingyi" {
            _ = controller.handle(makeKeyEvent(char: String(character), keyCode: 0), client: client)
        }
        let panel = CandidatePanelHolder.shared
        for word in ["陈", "璟", "逸"] {
            var selected = false
            let pages = panel.state.totalPages
            for _ in 0..<pages {
                if let index = panel.state.candidates.firstIndex(where: { $0.text == word }) {
                    if index < 9 {
                        _ = controller.handle(makeKeyEvent(char: String(index + 1), keyCode: 18), client: client)
                    } else {
                        panel.state.onSelectCandidate?(index)
                    }
                    selected = true
                    break
                }
                _ = controller.handle(makeKeyEvent(char: "=", keyCode: 24), client: client)
            }
            #expect(selected, "Character missing from every candidate page: \(word)")
            guard selected else { controller.resetComposition(client: client); return }
        }
        #expect(client.insertedText == "陈璟逸")
        #expect(client.markedText.isEmpty)
    }

    @Test("Apple-observed phrase order interleaves text and emoji without losing alternatives")
    func testAppleStyleCandidateRanking() {
        for input in ["woaini", "wo'ai'ni"] {
            let result = PinyinEngine.shared.query(rawInput: input)
            #expect(Array(result.prefix(4).map(\.text)) == ["我爱你", "🤟", "我爱妳", "😘"])
            #expect(result.prefix(7).filter(\.isEmoji).count <= 2)
            #expect(result.filter { $0.text == "我爱妳" }.count == 1)
            #expect(result.filter(\.isEmoji).allSatisfy { $0.consumedInputLength == input.count })
            let emoji = Set(result.filter(\.isEmoji).map(\.text))
            #expect(Set(EmojiLexicon.matches(for: input).map(\.text)).isSubset(of: emoji))
        }
        // General policy applies to all keywords, not just the phrase above.
        for input in ["aixin", "zhongguo", "kaixin", "hua"] {
            let result = PinyinEngine.shared.query(rawInput: input)
            #expect(result.first?.isEmoji == false)
            #expect(result.prefix(7).filter(\.isEmoji).count <= 2)
            #expect(result.contains { !$0.isEmoji && $0.consumedInputLength < input.count } || input == "hua")
        }
        let country = PinyinEngine.shared.query(rawInput: "zhongguo")
        #expect(country.dropFirst().first?.text == "🇨🇳")
        #expect(!country.prefix(7).contains { $0.text == "🐉" })
        #expect(country.contains { $0.text == "🐉" })
        // Learning and partial-candidate input lengths survive the merge.
        let learned = Candidate(text: "自定义", consumedInputLength: 6)
        let partial = Candidate(text: "我", consumedInputLength: 2)
        let result = CandidateRanking.merge(text: [learned, partial], input: "woaini")
        #expect(result.first == learned)
        #expect(result.contains(partial))
        #expect(CandidateRanking.merge(text: [partial], input: "zzzz") == [partial])
    }

    @Test("Emoji keywords use native Unicode and preserve normal text candidates")
    func testEmojiKeywords() {
        for (pinyin, emoji) in [("meigui", "🌹"), ("mei'gui", "🌹"),
                                 (" MEIGUI ", "🌹"), ("meiguo", "🇺🇸"),
                                 ("aixin", "❤️"), ("dianzan", "👍"),
                                 ("kafei", "☕"), ("shengrikuaile", "🎂")] {
            let candidates = PinyinEngine.shared.query(rawInput: pinyin)
            let match = candidates.first { $0.text == emoji }
            #expect(match?.isEmoji == true)
            #expect(match?.consumedInputLength == pinyin.trimmingCharacters(in: .whitespacesAndNewlines).count)
            #expect(candidates.filter { $0.text == emoji }.count == 1)
            #expect(candidates.first?.isEmoji == false)
        }
        let rose = PinyinEngine.shared.query(rawInput: "meigui")
        #expect(rose.first?.text == "玫瑰")
        #expect(rose.dropFirst().first?.text == "🌹")
        #expect(EmojiLexicon.matches(for: "meiguizhenpiaoliang").allSatisfy { $0.text != "🌹" })
        #expect(EmojiLexicon.matches(for: "meig").isEmpty)
        #expect(EmojiLexicon.matches(for: "").isEmpty)
        #expect(PinyinEngine.shared.query(rawInput: "nihao").first?.text == "你好")
    }

    @Test("Every installed Apple Chinese emoji name and replacement remains reachable")
    func testAllAppleEmojiNames() throws {
        let root = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/CoreEmoji.framework/Resources/zh_CN.lproj")
        let namesURL = root.appendingPathComponent("AppleName.strings")
        // This audit intentionally fails on this Mac if the system data cannot be read.
        let data = try Data(contentsOf: namesURL)
        let names = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        #expect(names.count > 1800)
        func canonical(_ text: String) -> String {
            String(text.split(separator: "@", maxSplits: 1)[0]).replacingOccurrences(of: "\u{FE0F}", with: "")
        }
        for (emoji, name) in names {
            let key = EmojiLexicon.pinyinKey(name)
            #expect(EmojiLexicon.matches(for: key).contains { canonical($0.text) == canonical(emoji) }, "Missing Apple name: \(name) \(emoji)")
        }
        let replacementData = try Data(contentsOf: root.appendingPathComponent("FindReplaceReranking.plist"))
        let replacements = try #require(PropertyListSerialization.propertyList(from: replacementData, format: nil) as? [String: [String]])
        for (keyword, emojis) in replacements {
            for emoji in emojis where emoji.count == 1 && emoji.unicodeScalars.contains(where: { $0.value > 127 && $0.properties.isEmoji }) {
                #expect(EmojiLexicon.matches(for: EmojiLexicon.pinyinKey(keyword)).contains { canonical($0.text) == canonical(emoji) })
            }
        }
        #expect(EmojiLexicon.loadSystemEntries(directory: URL(fileURLWithPath: "/nonexistent-aetherkey-emoji")).isEmpty)
    }

    @Test("All bundled emoji sequences including skin tones, families and flags are searchable")
    func testFullEmojiCoverage() throws {
        let url = try #require(Bundle(for: PinyinEngine.self).url(forResource: "emoji", withExtension: "json"))
        let entries = try JSONDecoder().decode([String: [EmojiLexicon.Entry]].self, from: Data(contentsOf: url))
        var unique = Set<String>()
        for (key, expected) in entries {
            let matches = Set(EmojiLexicon.matches(for: key).map { $0.text.replacingOccurrences(of: "\u{FE0F}", with: "") })
            for entry in expected {
                unique.insert(entry.text)
                #expect(matches.contains(entry.text.replacingOccurrences(of: "\u{FE0F}", with: "")))
            }
        }
        #expect(unique.count >= 3900)
    }

    @Test("Emoji numeric selection commits the full Unicode sequence and clears composition")
    @MainActor
    func testEmojiCommit() {
        for (input, expected) in [("meigui", "🌹"), ("meiguo", "🇺🇸"), ("aixin", "❤️")] {
            let client = MockTextInputClient()
            let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
            for char in input {
                _ = controller.handle(makeKeyEvent(char: String(char), keyCode: 0), client: client)
            }
            _ = controller.handle(makeKeyEvent(char: "2", keyCode: 19), client: client)
            #expect(client.insertedText == expected)
            #expect(client.markedText.isEmpty)
            #expect(!UserLexicon.shared.preferredWords(for: input).contains(expected))
        }
    }
    
    // MARK: - 1. Mainstream Key State Machine Tests
    @Test("Scenario 1: Space Bar commits first candidate and resets composition")
    @MainActor
    func testSpaceBarCommit() {
        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        
        // Type "nihao"
        for (char, code) in [("n", 45), ("i", 34), ("h", 4), ("a", 0), ("o", 31)] as [(String, UInt16)] {
            let event = makeKeyEvent(char: char, keyCode: code)
            let handled = controller.handle(event, client: client)
            #expect(handled == true)
        }
        #expect(client.markedText == "nihao")
        
        // Press Space (keyCode 49)
        let spaceEvent = makeKeyEvent(char: " ", keyCode: 49)
        let spaceHandled = controller.handle(spaceEvent, client: client)
        #expect(spaceHandled == true)
        
        // Space should commit "你好"
        #expect(client.insertedText == "你好")
        #expect(client.lastReplacementRange == NSRange(location: NSNotFound, length: 0))
    }
    
    @Test("Scenario 2: Return / Enter commits raw buffer without pinyin conversion")
    @MainActor
    func testReturnKeyRawCommit() {
        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        
        // Type "swift"
        for (char, code) in [("s", 1), ("w", 13), ("i", 34), ("f", 3), ("t", 17)] as [(String, UInt16)] {
            _ = controller.handle(makeKeyEvent(char: char, keyCode: code), client: client)
        }
        #expect(client.markedText == "swift")
        
        // Press Enter (keyCode 36)
        let enterEvent = makeKeyEvent(char: "\r", keyCode: 36)
        let handled = controller.handle(enterEvent, client: client)
        #expect(handled == true)
        
        // Should insert raw text "swift"
        #expect(client.insertedText == "swift")
    }
    
    @Test("Scenario 3: Numeric Keys 1-9 select corresponding candidate on current page")
    @MainActor
    func testNumericKeySelection() {
        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        
        // Type "zhong"
        for (char, code) in [("z", 6), ("h", 4), ("o", 31), ("n", 45), ("g", 5)] as [(String, UInt16)] {
            _ = controller.handle(makeKeyEvent(char: char, keyCode: code), client: client)
        }
        
        // Press '2' (keyCode 19)
        let key2 = makeKeyEvent(char: "2", keyCode: 19)
        let handled = controller.handle(key2, client: client)
        #expect(handled == true)
        #expect(!client.insertedText.isEmpty)
    }
    
    @Test("Scenario 4: Backspace deletes composition buffer character by character")
    @MainActor
    func testBackspaceHandling() {
        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        
        // Type "zh"
        _ = controller.handle(makeKeyEvent(char: "z", keyCode: 6), client: client)
        _ = controller.handle(makeKeyEvent(char: "h", keyCode: 4), client: client)
        #expect(client.markedText == "zh")
        
        // Delete once
        let backspace1 = makeKeyEvent(char: "\u{8}", keyCode: 51)
        let h1 = controller.handle(backspace1, client: client)
        #expect(h1 == true)
        #expect(client.markedText == "z")
        
        // Delete again -> buffer empty -> composition reset
        let h2 = controller.handle(backspace1, client: client)
        #expect(h2 == true)
        #expect(client.markedText == "")
    }
    
    @Test("Scenario 5: Escape cancels composition immediately")
    @MainActor
    func testEscapeCancellation() {
        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        
        _ = controller.handle(makeKeyEvent(char: "z", keyCode: 6), client: client)
        _ = controller.handle(makeKeyEvent(char: "w", keyCode: 13), client: client)
        #expect(client.markedText == "zw")
        
        // Escape (keyCode 53)
        let escEvent = makeKeyEvent(char: "\u{1B}", keyCode: 53)
        let handled = controller.handle(escEvent, client: client)
        #expect(handled == true)
        #expect(client.markedText == "")
        #expect(client.insertedText == "")
    }
    
    @Test("Scenario 6: Arrow keys and Page keys navigate candidates and flip pages")
    @MainActor
    func testNavigationAndPaging() {
        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        
        // Type "a"
        _ = controller.handle(makeKeyEvent(char: "a", keyCode: 0), client: client)
        
        // Down Arrow (keyCode 125) moves selection
        let downArrow = makeKeyEvent(char: "", keyCode: 125)
        #expect(controller.handle(downArrow, client: client) == true)
        
        // Up Arrow (keyCode 126) moves back
        let upArrow = makeKeyEvent(char: "", keyCode: 126)
        #expect(controller.handle(upArrow, client: client) == true)
        
        // Page Next: '=' (keyCode 24)
        let pageNext = makeKeyEvent(char: "=", keyCode: 24)
        #expect(controller.handle(pageNext, client: client) == true)
        
        // Page Prev: '-' (keyCode 27)
        let pagePrev = makeKeyEvent(char: "-", keyCode: 27)
        #expect(controller.handle(pagePrev, client: client) == true)
    }
    
    @Test("Scenario 7: Shortcut pass-through allows Cmd+C, Cmd+V, and Ctrl combinations")
    @MainActor
    func testShortcutPassThrough() {
        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        
        // Cmd+C should return false (pass through to OS)
        let cmdC = makeKeyEvent(char: "c", keyCode: 8, modifiers: [.command])
        #expect(controller.handle(cmdC, client: client) == false)
        
        // Ctrl+C should return false
        let ctrlC = makeKeyEvent(char: "c", keyCode: 8, modifiers: [.control])
        #expect(controller.handle(ctrlC, client: client) == false)
    }

    // MARK: - 2. Pinyin Segmentation & Lexicon Engine Tests
    @Test("Scenario 8: Pinyin Engine matches exact words, long sentences, and abbreviations")
    func testPinyinSegmentationAndLexicon() {
        let engine = PinyinEngine.shared
        
        // Exact multi-syllables
        let zhongwen = engine.query(rawInput: "zhongwen")
        #expect(zhongwen.contains(where: { $0.text == "中文" }))
        
        let nihao = engine.query(rawInput: "nihao")
        #expect(nihao.contains(where: { $0.text == "你好" }))
        
        let tiananmen = engine.query(rawInput: "tiananmen")
        #expect(tiananmen.contains(where: { $0.text == "天安门" }))
        
        // Apostrophe segmentation: xi'an -> 西安 vs xian -> 先
        let xianApos = engine.query(rawInput: "xi'an")
        #expect(xianApos.contains(where: { $0.text == "西安" }))
        
        let fanganApos = engine.query(rawInput: "fang'an")
        #expect(fanganApos.contains(where: { $0.text == "方案" }))
        
        // Shengmu abbreviations (简拼)
        #expect(engine.query(rawInput: "zg").contains(where: { $0.text == "中国" }))
        #expect(engine.query(rawInput: "bj").contains(where: { $0.text == "北京" }))
        #expect(engine.query(rawInput: "sh").contains(where: { $0.text == "上海" }))
        #expect(engine.query(rawInput: "gz").contains(where: { $0.text == "广州" }))
        #expect(engine.query(rawInput: "sz").contains(where: { $0.text == "深圳" }))
        #expect(engine.query(rawInput: "srf").contains(where: { $0.text == "输入法" }))
        #expect(engine.query(rawInput: "wyy").contains(where: { $0.text == "网易云" }))
        #expect(engine.query(rawInput: "rmb").contains(where: { $0.text == "人民币" }))
        #expect(engine.query(rawInput: "kfz").contains(where: { $0.text == "开发者" }))
        #expect(engine.query(rawInput: "czxt").contains(where: { $0.text == "操作系统" }))
        
        // Single characters covering all initial sounds
        #expect(engine.query(rawInput: "wo").contains(where: { $0.text == "我" }))
        #expect(engine.query(rawInput: "de").contains(where: { $0.text == "的" }))
        #expect(engine.query(rawInput: "shi").contains(where: { $0.text == "是" }))
        #expect(engine.query(rawInput: "ren").contains(where: { $0.text == "人" }))
    }

    // MARK: - 3. Pangu Spacing Tests
    @Test("Scenario 9: Pangu Spacing automatically adds spacing between CJK and English/digits")
    func testPanguSpacingFull() {
        let pangu = PanguSpacing.shared
        
        #expect(pangu.spacing("使用Swift开发") == "使用 Swift 开发")
        #expect(pangu.spacing("AetherKey输入法") == "AetherKey 输入法")
        #expect(pangu.spacing("第1版本发布") == "第 1 版本发布")
        #expect(pangu.spacing("100个候选词") == "100 个候选词")
        #expect(pangu.spacing("Liquid Glass Aesthetics") == "Liquid Glass Aesthetics")
        
        // Contextual space prepending
        #expect(pangu.shouldPrependSpace(preceding: "S", committing: "苹果") == true)
        #expect(pangu.shouldPrependSpace(preceding: "你", committing: "Apple") == true)
        #expect(pangu.shouldPrependSpace(preceding: "好", committing: "世界") == false)
    }

    // MARK: - 4. Smart Punctuation & Decimal Retention Tests
    @Test("Scenario 10: Smart Punctuation converts symbols, pairs quotes, and preserves decimals")
    func testSmartPunctuationFull() {
        let punct = SmartPunctuation.shared
        
        // Standard conversions (aligned with Sogou Pinyin symbolset2.plist jian-ban)
        #expect(punct.convert(char: ",", precedingChar: nil) == "，")
        #expect(punct.convert(char: ".", precedingChar: nil) == "。")
        #expect(punct.convert(char: "?", precedingChar: nil) == "？")
        #expect(punct.convert(char: "!", precedingChar: nil) == "！")
        #expect(punct.convert(char: "/", precedingChar: nil) == "、")
        #expect(punct.convert(char: "\\", precedingChar: nil) == "、")
        #expect(punct.convert(char: "(", precedingChar: nil) == "（")
        #expect(punct.convert(char: ")", precedingChar: nil) == "）")
        
        // Decimal point preservation
        #expect(punct.convert(char: ".", precedingChar: "3") == ".")
        #expect(punct.convert(char: ".", precedingChar: "0") == ".")
        #expect(punct.convert(char: ".", precedingChar: "a") == "。")
        
        // Time & ratio colons
        #expect(punct.convert(char: ":", precedingChar: "1") == ":")
        #expect(punct.convert(char: ":", precedingChar: "字") == "：")
    }

    // MARK: - 5. V-Mode Calculator & Financial RMB Tests
    @Test("Scenario 11: V-Mode evaluates math, RMB currency formatting, and date macros")
    func testVModeCalculatorFull() {
        let vCalc = VModeCalculator.shared
        
        // Math arithmetic
        let addMult = vCalc.candidates(for: "v1+2*3")
        #expect(addMult.first?.text == "7")
        
        let power = vCalc.candidates(for: "v2^8")
        #expect(power.first?.text == "256")
        
        let division = vCalc.candidates(for: "v10/4")
        #expect(division.first?.text == "2.5")
        
        let parens = vCalc.candidates(for: "v(10+20)/3")
        #expect(parens.first?.text == "10")
        
        // RMB Capitalization
        let rmbThousand = vCalc.convertToRMB(amount: 1000)
        #expect(rmbThousand == "壹仟元整")
        
        let rmbCents = vCalc.candidates(for: "v128.5")
        #expect(rmbCents.contains(where: { $0.text.contains("壹佰贰拾捌元伍角整") }))
        
        // Date macros
        let dateCand = vCalc.candidates(for: "vdate")
        #expect(dateCand.first?.text.contains("年") == true)
        
        let weekCand = vCalc.candidates(for: "vweek")
        #expect(weekCand.contains(where: { $0.text.contains("星期") }))
    }

    // MARK: - 6. Candidate Panel Non-Activating Window Specs
    @Test("Scenario 12: Candidate Panel Non-Activating Window Specs and Level")
    @MainActor
    func testCandidatePanelSpecsFull() {
        let panel = CandidatePanel()
        
        #expect(panel.canBecomeKey == false)
        #expect(panel.canBecomeMain == false)
        #expect(panel.isFloatingPanel == true)
        #expect(panel.level == .popUpMenu)
        #expect(panel.isOpaque == false)
        // The native window shadow gives the borderless material panel depth.
        #expect(panel.hasShadow == true)
    }

    @Test("Candidate popup keeps its side and anchor through layout changes near the screen edge")
    func testCandidatePlacementStability() {
        let screen = NSRect(x: 0, y: 0, width: 1200, height: 800)
        let caret = NSRect(x: 990, y: 105, width: 0, height: 22)
        var placement = CandidatePanelPlacement()
        let compact = placement.frame(caret: caret, size: NSSize(width: 572, height: 80.5), screen: screen)
        #expect(compact.minY > caret.maxY)
        let expanded = placement.frame(caret: caret,
            size: NSSize(width: 572, height: 118.5), screen: screen)
        #expect(expanded.origin == compact.origin)
        #expect(expanded.maxX <= screen.maxX - 8)
        #expect(expanded.maxY <= screen.maxY - 8)
        let compactAgain = placement.frame(caret: caret, size: compact.size, screen: screen)
        #expect(compactAgain == compact)
        let movedCaret = NSRect(x: 700, y: 500, width: 0, height: 22)
        let moved = placement.frame(caret: movedCaret, size: compact.size, screen: screen)
        #expect(moved.maxY < movedCaret.minY)
        #expect(moved.minX == min(movedCaret.minX, screen.maxX - moved.width - 8))
    }

    @Test("Input method queries the moving insertion end of marked text")
    @MainActor
    func testCandidateCaretQueryFollowsMarkedText() {
        let client = MockTextInputClient()
        client.attributesCaretRect = .zero
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        _ = controller.handle(makeKeyEvent(char: "n", keyCode: 45), client: client)
        #expect(client.lastFirstRectRange == NSRange(location: 1, length: 0))
        _ = controller.handle(makeKeyEvent(char: "i", keyCode: 34), client: client)
        #expect(client.lastFirstRectRange == NSRange(location: 2, length: 0))
        controller.resetComposition(client: client)
    }

    @Test("Reject invalid host caret placeholders while accepting real insertion rectangles")
    func testCandidateCaretGeometryValidation() {
        let denormal = 1.6080749353408704e-314
        #expect(!CandidateCaretGeometry.isUsable(NSRect(x: denormal, y: 0, width: denormal, height: denormal)))
        #expect(!CandidateCaretGeometry.isUsable(.zero))
        #expect(!CandidateCaretGeometry.isUsable(NSRect(x: CGFloat.nan, y: 10, width: 1, height: 16)))
        #expect(CandidateCaretGeometry.isUsable(NSRect(x: 550, y: 86, width: 1, height: 16)))
        #expect(CandidateCaretGeometry.isUsable(NSRect(x: -300, y: -200, width: 0, height: 22)))
        #expect(CandidateCaretGeometry.isUsable(NSRect(x: 0, y: 0, width: 0, height: 22)))
    }

    @Test("Candidate popup follows ordinary horizontal caret movement instead of locking its origin")
    func testCandidatePanelFollowsCaret() {
        let screen = NSRect(x: 0, y: 0, width: 1600, height: 900)
        let caret = NSRect(x: 200, y: 500, width: 0, height: 22)
        let size = NSSize(width: 572, height: 80.5)
        var placement = CandidatePanelPlacement()
        let first = placement.frame(caret: caret, size: size, screen: screen)
        for advance in [8.0, 16.0, 24.0, 40.0, 80.0] {
            let moved = placement.frame(caret: caret.offsetBy(dx: advance, dy: 0), size: size, screen: screen)
            #expect(abs(moved.minX - first.minX - CGFloat(advance)) < 0.01)
            #expect(moved.minY == first.minY)
        }
        let wrapped = placement.frame(caret: caret.offsetBy(dx: -60, dy: -24), size: size, screen: screen)
        #expect(wrapped.minX == caret.minX - 60)
        #expect(wrapped.maxY == caret.minY - 24 - 7)
    }

    @Test("Candidate surface fits short content, grows for phrases, and bounds overflow")
    @MainActor
    func testAdaptiveCandidateSurface() {
        let cases: [[Candidate]] = [
            [Candidate(text: "你")],
            ["你", "泥", "拟", "逆", "倪", "匿", "呢"].map { Candidate(text: $0) },
            ["你好世界", "输入法", "候选词", "跟随光标", "自然输入", "中文", "排版"].map { Candidate(text: $0) },
            [Candidate(text: String(repeating: "很长的候选词", count: 30), comment: "注释")]
        ]
        var widths: [CGFloat] = []
        for candidates in cases {
            let width = CandidatePanelMetrics.contentWidth(candidates: candidates, viewMode: .paging,
                pinyin: "ni", mode: .chinese, currentPage: 1, totalPages: 2)
            widths.append(width)
            let view = CandidateListView(inputString: "ni", mode: .chinese, candidates: candidates,
                selectedIndex: 0, currentPage: 1, totalPages: 2)
            let host = NSHostingView(rootView: view)
            let fitting = host.fittingSize
            #expect(abs(fitting.width - width - CandidatePanelMetrics.outerPadding * 2) < 1)
            #expect(abs(fitting.height - CandidatePanelMetrics.height(for: .paging)) < 1)
        }
        #expect(widths[0] < widths[1])
        #expect(widths[1] < widths[2])
        #expect(widths[3] == 640)
        #expect(widths[1] < 400)
    }

    @Test("Candidate popup remains measured and visible during typing and rapid dismiss/reopen")
    @MainActor
    func testCandidatePanelPresentationContinuity() async throws {
        let panel = CandidatePanel()
        panel.state.candidates = [Candidate(text: "你")]
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let caret = NSRect(x: screen.midX, y: screen.midY, width: 0, height: 22)
        panel.show(caretRect: caret)
        let initial = panel.frame
        panel.state.candidates = ["你好世界", "输入法", "候选词", "跟随光标", "自然输入", "中文", "排版"].map { Candidate(text: $0) }
        panel.show(caretRect: caret)
        #expect(panel.frame.width > initial.width)
        #expect(panel.frame.minX == initial.minX)
        #expect(panel.frame.maxY == initial.maxY)
        let wideFrame = panel.frame
        panel.state.viewMode = .scroll
        panel.show(caretRect: caret)
        #expect(panel.frame.width <= wideFrame.width)
        #expect(panel.frame.maxY == initial.maxY)
        panel.dismiss()
        panel.show(caretRect: caret)
        try await Task.sleep(for: .milliseconds(220))
        #expect(panel.state.isVisible)
        #expect(panel.isVisible)
        #expect(panel.alphaValue > 0.99)
        panel.dismiss()
        try await Task.sleep(for: .milliseconds(160))
        #expect(!panel.isVisible)
    }

    // MARK: - 7. Context Detector Tests
    @Test("Scenario 13: Context Detector identifies terminal and editor applications")
    func testContextDetectorFull() {
        let detector = ContextDetector.shared
        
        #expect(detector.isTerminalApp(bundleIdentifier: "com.apple.Terminal") == true)
        #expect(detector.isTerminalApp(bundleIdentifier: "com.googlecode.iterm2") == true)
        #expect(detector.isTerminalApp(bundleIdentifier: "net.kovidgoyal.kitty") == true)
        #expect(detector.isTerminalApp(bundleIdentifier: "com.microsoft.VSCode") == true)
        
        #expect(detector.isTerminalApp(bundleIdentifier: "com.apple.Notes") == false)
        #expect(detector.isTerminalApp(bundleIdentifier: "com.apple.Safari") == false)
        #expect(detector.isTerminalApp(bundleIdentifier: "com.apple.TextEdit") == false)
    }

    // MARK: - 8. IMK Bundle Metadata & Simplified Chinese Categorization
    @Test("Scenario 14: IMK Bundle Metadata & Simplified Chinese Language Categorization")
    func testBundleMetadataClassification() {
        let currentFile = URL(fileURLWithPath: #filePath)
        let projectRoot = currentFile.deletingLastPathComponent().deletingLastPathComponent()
        let plistURL = projectRoot.appendingPathComponent("Resources/Info.plist")
        guard let plistData = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            Issue.record("Failed to read Resources/Info.plist at \(plistURL.path)")
            return
        }
        
        // 1. Language region & Top-level TISIntendedLanguage
        #expect(plist["CFBundleDevelopmentRegion"] as? String == "zh-Hans")
        #expect(plist["TISIntendedLanguage"] as? String == "zh-Hans")
        #expect(plist["InputMethodConnectionName"] as? String == "com.aethernative.inputmethod.AetherKey_1_Connection")
        #expect(plist["InputMethodServerControllerClass"] as? String == "AetherInputController")
        
        // 2. Character Repertoire must be Hans (Simplified Chinese)
        let repertoires = plist["tsInputMethodCharacterRepertoireKey"] as? [String]
        #expect(repertoires?.contains("Hans") == true)
        
        // 3. ComponentInputModeDict
        guard let modeDict = plist["ComponentInputModeDict"] as? [String: Any],
              let modeList = modeDict["tsInputModeListKey"] as? [String: Any],
              let hansMode = modeList["com.aethernative.inputmethod.AetherKey.Hans"] as? [String: Any] else {
            Issue.record("Missing input modes in ComponentInputModeDict")
            return
        }
        
        #expect(hansMode["TISIntendedLanguage"] as? String == "zh-Hans")
        #expect(hansMode["TISInputSourceID"] as? String == "com.aethernative.inputmethod.AetherKey.Hans")
        #expect(hansMode["tsInputModeScriptKey"] as? String == "smSimpChinese")
        
        // 4. Visible Modes Array
        let visibleModes = modeDict["tsVisibleInputModeOrderedArrayKey"] as? [String]
        #expect(visibleModes?.contains("com.aethernative.inputmethod.AetherKey.Hans") == true)
        
        // 5. Localization files exist
        let zhHansURL = projectRoot.appendingPathComponent("Resources/zh-Hans.lproj/InfoPlist.strings")
        let zhCNURL = projectRoot.appendingPathComponent("Resources/zh_CN.lproj/InfoPlist.strings")
        #expect(FileManager.default.fileExists(atPath: zhHansURL.path))
        #expect(FileManager.default.fileExists(atPath: zhCNURL.path))
        
        let zhHansContent = (try? String(contentsOf: zhHansURL, encoding: .utf8)) ?? ""
        #expect(zhHansContent.contains("com.aethernative.inputmethod.AetherKey.Hans"))
        #expect(zhHansContent.contains("AetherKey 拼音"))
    }

    // MARK: - 9. Real-World User Typing Scenarios
    @Test("Scenario 15: Real-world Chinese typing (zhansan -> 张三, mosheng -> 陌生, chifan -> 吃饭)")
    @MainActor
    func testRealWorldTypingScenarios() {
        let engine = PinyinEngine.shared
        
        // 1. "zhansan" must have 张三 as #1 candidate
        let zhansanCandidates = engine.query(rawInput: "zhansan")
        #expect(!zhansanCandidates.isEmpty)
        #expect(zhansanCandidates.first?.text == "张三")
        
        // 2. "mosheng" must have 陌生 as #1 candidate
        let moshengCandidates = engine.query(rawInput: "mosheng")
        #expect(!moshengCandidates.isEmpty)
        #expect(moshengCandidates.first?.text == "陌生")
        
        // 3. "chifan" must have 吃饭 as #1 candidate
        let chifanCandidates = engine.query(rawInput: "chifan")
        #expect(!chifanCandidates.isEmpty)
        #expect(chifanCandidates.first?.text == "吃饭")
        
        // 4. "shuijiao" must contain 睡觉
        let shuijiaoCandidates = engine.query(rawInput: "shuijiao")
        #expect(shuijiaoCandidates.contains(where: { $0.text == "睡觉" }))
        
        // 5. Full typing interaction: typing "zhansan" + Space commits "张三"
        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        
        for (char, code) in [("z", 6), ("h", 4), ("a", 0), ("n", 45), ("s", 1), ("a", 0), ("n", 45)] as [(String, UInt16)] {
            _ = controller.handle(makeKeyEvent(char: char, keyCode: code), client: client)
        }
        #expect(client.markedText == "zhansan")
        
        // Press Space
        _ = controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client)
        #expect(client.insertedText == "张三")
    }

    // MARK: - 10. Sogou-style Dual Presentation Modes: Paging vs Scroll (卷轴 vs 翻页)
    @Test("Scenario 16: Sogou dual presentation mode toggle (Option+Tab) and candidate carousel flow")
    @MainActor
    func testDualPresentationModes() {
        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        
        // Type "zhongguo"
        for (char, code) in [("z", 6), ("h", 4), ("o", 31), ("n", 45), ("g", 5), ("g", 5), ("u", 32), ("o", 31)] as [(String, UInt16)] {
            _ = controller.handle(makeKeyEvent(char: char, keyCode: code), client: client)
        }
        #expect(client.markedText == "zhongguo")
        
        // Default mode is .paging (翻页模式)
        let panel = CandidatePanelHolder.shared
        #expect(panel.state.viewMode == .paging)
        #expect(panel.state.candidates.count <= 7)
        
        // Press Option + Tab to toggle to .scroll (卷轴模式)
        let optTab = makeKeyEvent(char: "\t", keyCode: 48, modifiers: [.option])
        let handledToggle = controller.handle(optTab, client: client)
        #expect(handledToggle == true)
        #expect(panel.state.viewMode == .scroll)
        
        // In scroll mode, pageSize expands to 14 multi-candidate panoramic layout
        #expect(panel.state.candidates.count > 0)
        
        // Tab key navigates candidate forward in scroll carousel
        let tab = makeKeyEvent(char: "\t", keyCode: 48)
        let handledTab = controller.handle(tab, client: client)
        #expect(handledTab == true)
        #expect(panel.state.selectedIndex == 1)
        
        // Press Option + Tab again to toggle back to .paging (翻页模式)
        _ = controller.handle(optTab, client: client)
        #expect(panel.state.viewMode == .paging)
        
        // Clean up composition
        _ = controller.handle(makeKeyEvent(char: "\u{1B}", keyCode: 53), client: client)
        #expect(client.markedText == "")
    }

    // MARK: - 11. DP Sentence Composition & Incremental Prefix Typing
    @Test("Scenario 17: DP Sentence Composition, Incremental Partial Pinyin, and Rich Jianpin")
    func testSentenceCompositionAndIncrementalPinyin() {
        let engine = PinyinEngine.shared
        
        // 1. Multi-word DP Sentence Composition
        let woxiangchifan = engine.query(rawInput: "woxiangchifan")
        #expect(woxiangchifan.first?.text == "我想吃饭")
        
        let jintianSentence = engine.query(rawInput: "jintiantianqizenmeyang")
        #expect(jintianSentence.first?.text == "今天天气怎么样")
        
        let nihaoshijie = engine.query(rawInput: "nihaoshijie")
        #expect(nihaoshijie.first?.text == "你好世界")
        
        // 2. Incremental / Partial Pinyin (Chinese candidates never vanish mid-keystroke)
        let partialN = engine.query(rawInput: "n")
        #expect(partialN.contains(where: { $0.text == "你" }))
        
        let partialZh = engine.query(rawInput: "zh")
        #expect(partialZh.contains(where: { $0.text == "这" || $0.text == "中" }))
        
        let partialNih = engine.query(rawInput: "nih")
        #expect(partialNih.first?.text == "你好")
        
        let partialZhongg = engine.query(rawInput: "zhongg")
        #expect(partialZhongg.first?.text == "中国")
        
        // 3. Expanded Jianpin (声母简拼)
        #expect(engine.query(rawInput: "nh").first?.text == "你好")
        #expect(engine.query(rawInput: "wx").first?.text == "微信")
        #expect(engine.query(rawInput: "zfb").first?.text == "支付宝")
        #expect(engine.query(rawInput: "rgzn").first?.text == "人工智能")
        #expect(engine.query(rawInput: "wsm").first?.text == "为什么")
        #expect(engine.query(rawInput: "zmy").first?.text == "怎么样")
        #expect(engine.query(rawInput: "mwt").first?.text == "没问题")
        #expect(engine.query(rawInput: "bzd").first?.text == "不知道")
        #expect(engine.query(rawInput: "ytbl").first?.text == "液态玻璃")
        
        // 4. Segmented Pinyin Formatting
        #expect(engine.formatSegmentedPinyin(rawInput: "nihao") == "ni'hao")
        #expect(engine.formatSegmentedPinyin(rawInput: "jintiantianqi") == "jin'tian'tian'qi")
    }

    // MARK: - 12. Partial Prefix Selection & User Lexicon Learning
    @Test("Scenario 18: Partial prefix selection in long sentences & dynamic UserLexicon learning")
    @MainActor
    func testPartialSelectionAndUserLexicon() {
        AetherSettings.shared.resetToDefaults()
        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        
        // Type "jintiantianqi" (4 syllables: 今天天气)
        for char in "jintiantianqi" {
            _ = controller.handle(makeKeyEvent(char: String(char), keyCode: 0), client: client)
        }
        #expect(client.markedText == "jintiantianqi")
        
        // Verify candidate #1 is full sentence "今天天气" and prefix candidate "今天" is present
        let cands = PinyinEngine.shared.query(rawInput: "jintiantianqi")
        #expect(cands.first?.text == "今天天气")
        let prefixIdx = cands.firstIndex(where: { $0.text == "今天" && $0.consumedInputLength == 7 })
        #expect(prefixIdx != nil)
        
        // If user selects prefix candidate "今天" (e.g. pressing key for that index),
        // it commits "今天" and leaves "tianqi" in the composition buffer!
        if let idx = prefixIdx, idx < 7 {
            let keyDigit = String(idx + 1)
            _ = controller.handle(makeKeyEvent(char: keyDigit, keyCode: 19), client: client)
            #expect(client.insertedText == "今天")
            #expect(client.markedText == "tianqi")
            
            // Now press Space to commit the remaining "天气"
            _ = controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client)
            #expect(client.insertedText == "今天天气")
            #expect(client.markedText == "")
        }
        
        // Test custom phrase in UserLexicon
        UserLexicon.shared.addCustomPhrase(pinyin: "aktest", phrase: "灵键极速输入法")
        let customQuery = PinyinEngine.shared.query(rawInput: "aktest")
        #expect(customQuery.first?.text == "灵键极速输入法")
        UserLexicon.shared.removeCustomPhrase(pinyin: "aktest", phrase: "灵键极速输入法")
    }

    // MARK: - 13. Stateful Quote Pairing & Uppercase Pass-Through & V-Mode Controller Flow
    @Test("Scenario 19: Stateful quote pairing (“” / ‘’), uppercase pass-through, and V-Mode controller flow")
    @MainActor
    func testQuotePairingAndVModeController() {
        AetherSettings.shared.resetToDefaults()
        let punct = SmartPunctuation.shared
        punct.resetState()
        
        // 1. Double quotes alternate “ and ”
        #expect(punct.convert(char: "\"", precedingChar: nil) == "“")
        #expect(punct.convert(char: "\"", precedingChar: nil) == "”")
        #expect(punct.convert(char: "\"", precedingChar: nil) == "“")
        #expect(punct.convert(char: "\"", precedingChar: nil) == "”")
        
        // 2. Single quotes alternate ‘ and ’
        #expect(punct.convert(char: "'", precedingChar: nil) == "‘")
        #expect(punct.convert(char: "'", precedingChar: nil) == "’")
        
        // 3. Em-dash and Sogou-style alternating corner brackets (「『 / 」』)
        #expect(punct.convert(char: "_", precedingChar: nil) == "——")
        #expect(punct.convert(char: "{", precedingChar: nil) == "「")
        #expect(punct.convert(char: "}", precedingChar: nil) == "」")
        #expect(punct.convert(char: "{", precedingChar: nil) == "『")
        #expect(punct.convert(char: "}", precedingChar: nil) == "』")
        #expect(PinyinEngine.shared.query(rawInput: "zhognguo").first?.text == "中国")
        
        // 4. V-Mode end-to-end typing in AetherInputController (digits 1-9 append to expression instead of selecting candidate)
        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        for char in "v1+2*3" {
            _ = controller.handle(makeKeyEvent(char: String(char), keyCode: 0), client: client)
        }
        #expect(client.markedText == "v1+2*3")
        _ = controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client)
        #expect(client.insertedText == "7")
        
        // 5. Uppercase letter direct pass-through when buffer is empty
        client.reset()
        _ = controller.handle(makeKeyEvent(char: "A", keyCode: 0, modifiers: [.shift]), client: client)
        #expect(client.insertedText == "A")
        #expect(client.markedText == "")
    }
}


@Suite("Composition editing and persistent candidate preferences", .serialized)
struct CompositionEditingTests {
    @Test @MainActor
    func editsMiddleAndPreservesCandidates() {
        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        _ = controller.inputText("niha", client: client)
        _ = controller.handle(makeKeyEvent(char: "", keyCode: 123), client: client)
        #expect(client.markedSelection.location == 3)
        _ = controller.inputText("o", client: client)
        #expect(client.markedText == "nihoa")
        #expect(client.markedSelection.location == 4)
        _ = controller.handle(makeKeyEvent(char: "", keyCode: 117), client: client)
        #expect(client.markedText == "niho")
        _ = controller.handle(makeKeyEvent(char: "", keyCode: 123), client: client)
        _ = controller.inputText("a", client: client)
        #expect(client.markedText == "nihao")
        #expect(client.markedSelection.location == 4)
        _ = controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client)
        #expect(client.insertedText == "你好")
    }

    @Test @MainActor
    func syllableMovementAndDeletion() {
        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        _ = controller.inputText("ni'hao", client: client)
        _ = controller.handle(makeKeyEvent(char: "", keyCode: 123, modifiers: [.option]), client: client)
        #expect(client.markedSelection.location == 3)
        _ = controller.handle(makeKeyEvent(char: "", keyCode: 51, modifiers: [.option]), client: client)
        #expect(client.markedText == "hao")
        #expect(client.markedSelection.location == 0)
        _ = controller.handle(makeKeyEvent(char: "", keyCode: 51), client: client)
        #expect(client.markedText == "hao")
        _ = controller.handle(makeKeyEvent(char: "", keyCode: 119), client: client)
        #expect(client.markedSelection.location == 3)
        _ = controller.handle(makeKeyEvent(char: "", keyCode: 115), client: client)
        #expect(client.markedSelection.location == 0)
        _ = controller.handle(makeKeyEvent(char: "", keyCode: 124, modifiers: [.option]), client: client)
        #expect(client.markedSelection.location == 3)
        controller.resetComposition(client: client)
    }

    @Test @MainActor
    func editingAfterPartialSelectionKeepsFullReading() throws {
        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        _ = controller.inputText("jintiantianqi", client: client)
        let candidates = PinyinEngine.shared.query(rawInput: "jintiantianqi")
        let index = try #require(candidates.firstIndex { $0.text == "今天" && $0.consumedInputLength == 7 })
        for _ in 0..<(index / 7) { _ = controller.handle(makeKeyEvent(char: "=", keyCode: 24), client: client) }
        _ = controller.handle(makeKeyEvent(char: String(index % 7 + 1), keyCode: 18), client: client)
        #expect(client.insertedText == "今天" && client.markedText == "tianqi")
        _ = controller.handle(makeKeyEvent(char: "", keyCode: 123), client: client)
        _ = controller.inputText("a", client: client)
        _ = controller.handle(makeKeyEvent(char: "", keyCode: 51), client: client)
        #expect(client.markedText == "tianqi")
        _ = controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client)
        #expect(client.insertedText == "今天天气")
        #expect(UserLexicon.shared.preferredWords(for: "jintiantianqi").contains("今天天气"))
    }

    @Test
    func preferencesMigrateAndPersistInMutationOrder() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"frequencyTable":{"nihao":{"你好":3}},"customPhrases":{},"totalCommittedCharsCount":6}"#.utf8).write(to: url)
        let lexicon = UserLexicon(storageURL: url)
        #expect(lexicon.totalCommittedCharacters == 6)
        #expect(lexicon.preferredWords(for: "nihao").contains("你好"))
        for _ in 0..<30 {
            lexicon.setPinned("拟好", for: "ni'hao", pinned: true)
            lexicon.setPinned("拟好", for: "nihao", pinned: false)
        }
        lexicon.setPinned("拟好", for: "nihao", pinned: true)
        lexicon.forget("你好", for: "nihao")
        lexicon.flushPendingWrites()
        let loaded = UserLexicon(storageURL: url)
        #expect(loaded.isPinned("拟好", for: "nihao"))
        #expect(loaded.isForgotten("你好", for: "ni'hao"))
        #expect(!loaded.isForgotten("你好", for: "nh"))
        let engine = PinyinEngine(userLexicon: loaded)
        #expect(engine.query(rawInput: "nihao").first?.text == "拟好")
        #expect(!engine.query(rawInput: "nihao").contains { $0.text == "你好" })
        loaded.setPinned("你好", for: "nihao", pinned: true)
        #expect(!loaded.isForgotten("你好", for: "nihao"))
        loaded.flushPendingWrites()
    }

    @Test
    func sentencesRetainAlternativesAndLearnLocalNames() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let lexicon = UserLexicon(storageURL: url)
        let engine = PinyinEngine(userLexicon: lexicon)
        let baseline = engine.query(rawInput: "jing'yishangban").prefix(5).map(\.text)
        lexicon.addCustomPhrase(pinyin: "jingyi", phrase: "璟逸")
        let learned = engine.query(rawInput: "jing'yishangban").prefix(5).map(\.text)
        #expect(learned.first == "璟逸上班")
        #expect(learned.contains { $0 != "璟逸上班" && $0.count == 4 })
        #expect(baseline.first != learned.first)
        lexicon.forget("璟逸", for: "jingyi")
        #expect(!engine.query(rawInput: "jing'yishangban").prefix(5).contains { $0.text.hasPrefix("璟逸") })
        lexicon.flushPendingWrites()
    }

    @Test
    func sentenceAlternativesAvoidArbitrarySingleCharacterHomophones() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let engine = PinyinEngine(userLexicon: UserLexicon(storageURL: url))
        let candidates = engine.query(rawInput: "woxiangchifan").prefix(7).map(\.text)
        #expect(candidates.first == "我想吃饭")
        #expect(!candidates.contains("我向吃饭"))
        #expect(!candidates.contains("我像吃饭"))
        #expect(!candidates.contains("我想吃反"))
        #expect(!candidates.contains("我相持饭"))
        #expect(!candidates.contains("我相斥饭"))
    }

    @Test
    func pinnedPrefixDoesNotDisplaceACompletePhrase() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let lexicon = UserLexicon(storageURL: url)
        lexicon.setPinned("你", for: "ni", pinned: true)
        let engine = PinyinEngine(userLexicon: lexicon)
        #expect(engine.query(rawInput: "ni").first?.text == "你")
        #expect(engine.query(rawInput: "nihao").first?.text == "你好")
        lexicon.forget("你", for: "ni")
        #expect(engine.query(rawInput: "nihao").first?.text == "你好")
        #expect(!engine.query(rawInput: "nihao").contains { $0.text == "你" })
        lexicon.flushPendingWrites()
    }

    @Test @MainActor
    func managementShortcutsKeepCompositionAndCursor() {
        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        let key = "ceshizhiding"
        let word = "专用回归词"
        let lexicon = UserLexicon.shared
        lexicon.addCustomPhrase(pinyin: key, phrase: word)
        defer {
            lexicon.setPinned(word, for: key, pinned: true)
            lexicon.setPinned(word, for: key, pinned: false)
            lexicon.removeCustomPhrase(pinyin: key, phrase: word)
        }
        _ = controller.inputText(key, client: client)
        _ = controller.handle(makeKeyEvent(char: "", keyCode: 123), client: client)
        let location = client.markedSelection.location
        #expect(controller.handle(makeKeyEvent(char: "p", keyCode: 35, modifiers: [.control, .option]), client: client))
        #expect(lexicon.isPinned(word, for: key))
        #expect(client.markedText == key && client.markedSelection.location == location)
        #expect(client.insertedText.isEmpty)
        _ = controller.handle(makeKeyEvent(char: "u", keyCode: 32, modifiers: [.control, .option]), client: client)
        #expect(!lexicon.isPinned(word, for: key))
        _ = controller.handle(makeKeyEvent(char: "", keyCode: 51, modifiers: [.control, .option]), client: client)
        #expect(lexicon.isForgotten(word, for: key))
        #expect(!PinyinEngine.shared.query(rawInput: key).contains { $0.text == word })
        #expect(client.markedText == key && client.insertedText.isEmpty)
        controller.resetComposition(client: client)
    }
}

extension CompositionEditingTests {
    @Test @MainActor
    func doublePinyinLayoutsAndExactOffsets() {
        #expect(DoublePinyin.reading("nihc", scheme: .flypy) == "ni'hao")
        #expect(DoublePinyin.reading("nihk", scheme: .microsoft) == "ni'hao")
        #expect(DoublePinyin.reading("vsgo", scheme: .flypy) == "zhong'guo")
        #expect(DoublePinyin.reading("vsgo", scheme: .microsoft) == "zhong'guo")
        #expect(DoublePinyin.reading("jbtm", scheme: .flypy) == "jin'tian")
        #expect(DoublePinyin.reading("jntm", scheme: .microsoft) == "jin'tian")
        #expect(DoublePinyin.reading("p;", scheme: .microsoft) == "ping")
        for (code, reading) in [("aa", "a"), ("ai", "ai"), ("an", "an"), ("ah", "ang"), ("ao", "ao"), ("ee", "e"), ("en", "en"), ("eg", "eng"), ("er", "er"), ("oo", "o"), ("ou", "ou")] {
            #expect(DoublePinyin.reading(code, scheme: .flypy) == reading)
        }
        for (code, reading) in [("oa", "a"), ("ol", "ai"), ("oj", "an"), ("oh", "ang"), ("ok", "ao"), ("oe", "e"), ("of", "en"), ("og", "eng"), ("or", "er"), ("oo", "o"), ("ob", "ou")] {
            #expect(DoublePinyin.reading(code, scheme: .microsoft) == reading)
        }
        #expect(DoublePinyin.reading("ni'hc", scheme: .flypy) == "ni'hao")
        #expect(DoublePinyin.tokens("ni'hc", scheme: .flypy)?.map(\.rawEnd) == [3, 5])
        #expect(DoublePinyin.tokens("nb;", scheme: .flypy) == nil)
        #expect(DoublePinyin.query("vsgo", scheme: .flypy).contains { $0.text == "中国" && $0.consumedInputLength == 4 })
        let candidates = DoublePinyin.query("jbtmtmqi", scheme: .flypy)
        #expect(candidates.contains { $0.text == "今天" && $0.consumedInputLength == 4 })
        #expect(DoublePinyin.query("ni", scheme: .full).first?.text == PinyinEngine.shared.query(rawInput: "ni").first?.text)
    }

    @Test @MainActor
    func doublePinyinSyllableCoverageAndSharedPreferences() {
        for scheme in [PinyinScheme.flypy, .microsoft] {
            for syllable in PinyinLexicon.syllablesChars.keys.sorted() {
                for code in DoublePinyin.codes(for: syllable, scheme: scheme) {
                    let readings = DoublePinyin.tokens(code, scheme: scheme)?.first?.readings ?? []
                    #expect(readings.contains(syllable), "\(scheme): \(syllable) -> \(code) -> \(readings)")
                }
            }
        }
        let reading = "nihao"; let word = "双拼偏好验证词"
        UserLexicon.shared.addCustomPhrase(pinyin: reading, phrase: word)
        defer { UserLexicon.shared.removeCustomPhrase(pinyin: reading, phrase: word) }
        UserLexicon.shared.setPinned(word, for: reading, pinned: true)
        #expect(DoublePinyin.query("nihc", scheme: .flypy).first?.text == word)
        #expect(DoublePinyin.query("nihk", scheme: .microsoft).first?.text == word)
        UserLexicon.shared.forget(word, for: reading)
        #expect(!DoublePinyin.query("nihc", scheme: .flypy).contains { $0.text == word })
        #expect(!DoublePinyin.query("nihk", scheme: .microsoft).contains { $0.text == word })
    }

    @Test @MainActor
    func doublePinyinControllerCommitEditAndCalculator() {
        let settings = AetherSettings.shared
        let original = settings.pinyinScheme
        defer { settings.pinyinScheme = original }
        for scheme in [PinyinScheme.flypy, .microsoft] {
            settings.pinyinScheme = scheme
            let client = MockTextInputClient()
            let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
            _ = controller.inputText(scheme == .flypy ? "nihc" : "nihk", client: client)
            #expect(client.markedText == (scheme == .flypy ? "nihc" : "nihk"))
            _ = controller.handle(makeKeyEvent(char: "", keyCode: 123, modifiers: [.option]), client: client)
            #expect(client.markedSelection.location == 2)
            _ = controller.handle(makeKeyEvent(char: "", keyCode: 117), client: client)
            _ = controller.inputText("h", client: client)
            _ = controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client)
            #expect(client.insertedText == "你好")
            _ = controller.inputText("vsgo", client: client)
            _ = controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client)
            #expect(client.insertedText.hasSuffix("中国"))
            _ = controller.inputText("v1+2", client: client)
            _ = controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client)
            #expect(client.insertedText.hasSuffix("3"))
        }
    }

    @Test @MainActor
    func microsoftSemicolonAndPartialCommit() throws {
        let settings = AetherSettings.shared; let original = settings.pinyinScheme
        defer { settings.pinyinScheme = original }
        settings.pinyinScheme = .microsoft
        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        _ = controller.handle(makeKeyEvent(char: "p", keyCode: 35), client: client)
        _ = controller.handle(makeKeyEvent(char: ";", keyCode: 41), client: client)
        #expect(client.markedText == "p;")
        #expect(client.insertedText.isEmpty)
        _ = controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client)
        #expect(!client.insertedText.isEmpty)
        controller.resetComposition(client: client); client.reset()
        settings.pinyinScheme = .flypy
        _ = controller.inputText("jbtmtmqi", client: client)
        let index = try #require(DoublePinyin.query("jbtmtmqi", scheme: .flypy).firstIndex { $0.text == "今天" })
        #expect(index < 7)
        _ = controller.handle(makeKeyEvent(char: String(index + 1), keyCode: 18), client: client)
        #expect(client.insertedText == "今天")
        #expect(client.markedText == "tmqi")
        _ = controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client)
        #expect(client.insertedText == "今天天气")
    }
}
