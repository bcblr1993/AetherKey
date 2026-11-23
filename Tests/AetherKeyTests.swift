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
    var contextText: String?
    var canReadSurroundingText = true
    var attributesCaretRect: NSRect?
    var lastFirstRectRange: NSRange?
    var caretRect: NSRect = NSRect(x: 200, y: 500, width: 0, height: 22)
    
    func insertText(_ string: Any!, replacementRange: NSRange) {
        if let str = string as? String {
            insertedText += str
            if contextText != nil { contextText! += str }
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
        return NSRange(location: (contextText ?? "" as String).utf16.count, length: 0)
    }
    
    func markedRange() -> NSRange {
        return NSRange(location: 0, length: markedText.count)
    }
    
    func attributedSubstring(from range: NSRange) -> NSAttributedString? {
        guard canReadSurroundingText, let text = contextText,
              range.location >= 0, range.location <= text.utf16.count,
              range.length <= text.utf16.count - range.location else { return nil }
        return NSAttributedString(string: (text as NSString).substring(with: range))
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
    var mockBundleIdentifier: String? = "com.apple.Notes"
    var mockWindowLevel: CGWindowLevel = 0
    var mockUniqueID: String? = "mock-notes-client"
    func bundleIdentifier() -> String? { return mockBundleIdentifier }
    func windowLevel() -> CGWindowLevel { return mockWindowLevel }
    func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { return true }
    func uniqueClientIdentifierString() -> String? { return mockUniqueID }
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

func makeFlagsEvent(modifiers: NSEvent.ModifierFlags, keyCode: UInt16 = 56, timestamp: TimeInterval = 0) -> NSEvent {
    return NSEvent.keyEvent(
        with: .flagsChanged,
        location: .zero,
        modifierFlags: modifiers,
        timestamp: timestamp,
        windowNumber: 0,
        context: nil,
        characters: "",
        charactersIgnoringModifiers: "",
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

    @Test("Input method anchors at the start of marked text instead of chasing its moving end")
    @MainActor
    func testCandidateCaretQueryFollowsMarkedText() {
        let client = MockTextInputClient()
        client.attributesCaretRect = .zero
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        _ = controller.handle(makeKeyEvent(char: "n", keyCode: 45), client: client)
        #expect(client.lastFirstRectRange == NSRange(location: 0, length: 0))
        _ = controller.handle(makeKeyEvent(char: "i", keyCode: 34), client: client)
        #expect(client.lastFirstRectRange == NSRange(location: 0, length: 0))
        controller.resetComposition(client: client)
    }

    @Test("Reject invalid host caret placeholders while accepting real insertion rectangles")
    func testCandidateCaretGeometryValidation() {
        let denormal = 1.6080749353408704e-314
        #expect(!CandidateCaretGeometry.isUsable(NSRect(x: denormal, y: 0, width: denormal, height: denormal)))
        #expect(!CandidateCaretGeometry.isUsable(.zero))
        #expect(!CandidateCaretGeometry.isUsable(NSRect(x: 0, y: 0, width: 0, height: 22)))
        #expect(!CandidateCaretGeometry.isUsable(NSRect(x: CGFloat.nan, y: 10, width: 1, height: 16)))
        #expect(CandidateCaretGeometry.isUsable(NSRect(x: 550, y: 86, width: 1, height: 16)))
        #expect(CandidateCaretGeometry.isUsable(NSRect(x: -300, y: -200, width: 0, height: 22)))
        #expect(CandidateCaretGeometry.isUsable(NSRect(x: 0, y: 500, width: 0, height: 22)))
    }

    @Test("Candidate popup locks its origin on the same line and re-anchors only on line wraps")
    func testCandidatePanelFollowsCaret() {
        let screen = NSRect(x: 0, y: 0, width: 1600, height: 900)
        let caret = NSRect(x: 200, y: 500, width: 0, height: 22)
        let size = NSSize(width: 572, height: 80.5)
        var placement = CandidatePanelPlacement()
        let first = placement.frame(caret: caret, size: size, screen: screen)
        for (advance, dy) in [(8.0, 0.0), (16.0, 2.0), (24.0, -3.0), (40.0, 4.0), (80.0, 0.0)] {
            let locked = placement.frame(caret: caret.offsetBy(dx: advance, dy: dy), size: size, screen: screen)
            #expect(locked.origin == first.origin)
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
    @Test("Manual mode reaches existing and unactivated host controllers")
    @MainActor
    func manualModeSynchronizesWithoutActivation() async throws {
        let client = MockTextInputClient()
        client.mockBundleIdentifier = "test.idea.\(UUID().uuidString)"
        let first = AetherInputController(server: nil, delegate: nil, client: client)!
        let existing = AetherInputController(server: nil, delegate: nil, client: client)!
        first.activateServer(client)
        existing.activateServer(client)
        _ = first.handle(makeFlagsEvent(modifiers: [.shift]), client: client)
        try await Task.sleep(for: .milliseconds(35))
        _ = first.handle(makeFlagsEvent(modifiers: []), client: client)
        #expect(!existing.handle(makeKeyEvent(char: "a", keyCode: 0), client: client))
        existing.resetComposition(client: client)
        let fresh = AetherInputController(server: nil, delegate: nil, client: client)!
        #expect(!fresh.inputText("a", client: client))
        fresh.resetComposition(client: client)
        // A stale controller must toggle the shared English choice back to Chinese.
        _ = fresh.handle(makeFlagsEvent(modifiers: [.shift]), client: client)
        try await Task.sleep(for: .milliseconds(35))
        _ = fresh.handle(makeFlagsEvent(modifiers: []), client: client)
        #expect(first.handle(makeKeyEvent(char: "a", keyCode: 0), client: client))
        first.resetComposition(client: client)
    }

    @Test("Manual English survives replacement input sessions and remains isolated by application")
    @MainActor
    func manualModeSurvivesReplacementSession() async throws {
        let appID = "test.gemini.\(UUID().uuidString)"
        let first = MockTextInputClient()
        first.mockBundleIdentifier = appID
        first.mockUniqueID = "first-session"
        let controller = AetherInputController(server: nil, delegate: nil, client: first)!
        controller.activateServer(first)
        _ = controller.handle(makeFlagsEvent(modifiers: [.shift]), client: first)
        try await Task.sleep(for: .milliseconds(35))
        _ = controller.handle(makeFlagsEvent(modifiers: []), client: first)
        #expect(!controller.handle(makeKeyEvent(char: "a", keyCode: 0), client: first))
        controller.deactivateServer(first)

        let replacement = MockTextInputClient()
        replacement.mockBundleIdentifier = appID
        replacement.mockUniqueID = "replacement-session"
        let next = AetherInputController(server: nil, delegate: nil, client: replacement)!
        next.activateServer(replacement)
        #expect(!next.handle(makeKeyEvent(char: "a", keyCode: 0), client: replacement))
        next.resetComposition(client: replacement)

        let other = MockTextInputClient()
        other.mockBundleIdentifier = "test.other.\(UUID().uuidString)"
        other.mockUniqueID = first.mockUniqueID
        next.activateServer(other)
        #expect(next.handle(makeKeyEvent(char: "a", keyCode: 0), client: other))
        next.resetComposition(client: other)
    }

    @Test @MainActor
    func exactSyllablesOutrankAmbiguousAndFuzzyPhrases() {
        let engine = PinyinEngine(userLexicon: UserLexicon(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        for (input, first, ambiguous) in [("jian", "见", "积案"), ("jiang", "将", "激昂"), ("xian", "现", "西安")] {
            let rows = engine.query(rawInput: input).map(\.text)
            #expect(rows.first == first)
            #expect(rows.firstIndex(of: first)! < rows.firstIndex(of: ambiguous)!)
        }
        #expect(engine.query(rawInput: "xi'an").first?.text == "西安")
        #expect(engine.query(rawInput: "jian").contains { $0.text == "键" })
    }

    @Test @MainActor
    func dictionaryContextWorksAcrossWordsAndPolyphonicReadings() {
        let engine = PinyinEngine(userLexicon: UserLexicon(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let cases = [("快捷", "jian", "键"), ("一", "jian", "件"), ("看", "jian", "见"),
                     ("文", "jian", "件"), ("时", "jian", "间"), ("人", "min", "民"),
                     ("安", "quan", "全"), ("回", "jia", "家"), ("银", "hang", "行"),
                     ("输入", "fa", "法"), ("编", "ji", "辑"), ("专", "jia", "家")]
        for (context, input, expected) in cases {
            #expect(engine.query(rawInput: input, precedingText: context).first?.text == expected, "\(context) + \(input)")
        }
        #expect(engine.query(rawInput: "jian", precedingText: "快捷，").first?.text == "见")
        #expect(engine.query(rawInput: "jian", precedingText: "快捷 ").first?.text == "见")
    }

    @Test @MainActor
    func contextHonorsExplicitPreferencesAndForgetting() {
        let store = UserLexicon(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let engine = PinyinEngine(userLexicon: store)
        store.recordCommit(pinyin: "jian", word: "件")
        #expect(engine.query(rawInput: "jian", precedingText: "快捷").first?.text == "键")
        store.setPinned("件", for: "jian", pinned: true)
        #expect(engine.query(rawInput: "jian", precedingText: "快捷").first?.text == "件")
        store.setPinned("件", for: "jian", pinned: false)
        store.forget("键", for: "jian")
        #expect(!engine.query(rawInput: "jian", precedingText: "快捷").contains { $0.text == "键" })
        store.addCustomPhrase(pinyin: "jian", phrase: "自定义")
        #expect(engine.query(rawInput: "jian", precedingText: "快捷").first?.text == "自定义")
        store.addCustomPhrase(pinyin: "jian", phrase: "键")
        store.setPinned("件", for: "jian", pinned: true)
        #expect(engine.query(rawInput: "jian", precedingText: "快捷").first?.text == "件")
    }

    @Test @MainActor
    func controllerReadsActualCaretContextAndDiscardsStaleContext() {
        let settings = AetherSettings.shared; let previous = settings.pinyinScheme
        defer { settings.pinyinScheme = previous }; settings.pinyinScheme = .full
        let client = MockTextInputClient(); client.contextText = "快捷"
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        _ = controller.inputText("jian", client: client)
        #expect(CandidatePanelHolder.shared.state.candidates.first?.text == "键")
        _ = controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client)
        #expect(client.insertedText == "键")
        client.contextText = "文"
        _ = controller.inputText("jian", client: client)
        #expect(CandidatePanelHolder.shared.state.candidates.first?.text == "件")
        controller.resetComposition(client: client)
        client.contextText = "快捷，"
        let withoutContext = PinyinEngine.shared.query(rawInput: "jian").prefix(7).map(\.text)
        _ = controller.inputText("jian", client: client)
        #expect(CandidatePanelHolder.shared.state.candidates.map(\.text) == withoutContext)
        controller.resetComposition(client: client)
    }

    @Test @MainActor
    func fallbackContextRequiresUnchangedCaretAndSupportsBothDoublePinyinSchemes() {
        let settings = AetherSettings.shared; let previous = settings.pinyinScheme
        defer { settings.pinyinScheme = previous }
        settings.pinyinScheme = .full
        let client = MockTextInputClient(); client.contextText = ""; client.canReadSurroundingText = false
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        _ = controller.inputText("tian", client: client)
        _ = controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client)
        _ = controller.inputText("qi", client: client)
        #expect(CandidatePanelHolder.shared.state.candidates.first?.text == "气")
        controller.resetComposition(client: client)
        client.contextText = "其他位置"
        _ = controller.inputText("qi", client: client)
        #expect(CandidatePanelHolder.shared.state.candidates.first?.text != "气")
        controller.resetComposition(client: client)
        for scheme in [PinyinScheme.flypy, .microsoft] {
            #expect(DoublePinyin.query("jm", scheme: scheme, precedingText: "快捷").first?.text == "键")
        }
    }

    @Test @MainActor
    func englishPunctuationPreferenceDefaultsPersistsAndResets() throws {
        let name = "AetherKey.PunctuationTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AetherSettings(defaults: defaults)
        #expect(!settings.isEnglishPunctuationEnabled)
        #expect(settings.usesChinesePunctuation)
        settings.isEnglishPunctuationEnabled = true
        #expect(AetherSettings(defaults: defaults).isEnglishPunctuationEnabled)
        #expect(!settings.usesChinesePunctuation)
        settings.resetToDefaults()
        #expect(!AetherSettings(defaults: defaults).isEnglishPunctuationEnabled)
    }

    @Test @MainActor
    func punctuationShortcutPreservesCompositionAndUsesSelectedStyle() {
        let settings = AetherSettings.shared
        let previous = settings.isEnglishPunctuationEnabled
        let smart = settings.isSmartPunctuationEnabled
        let scheme = settings.pinyinScheme
        defer {
            settings.isEnglishPunctuationEnabled = previous
            settings.isSmartPunctuationEnabled = smart
            settings.pinyinScheme = scheme
        }
        settings.pinyinScheme = .full
        settings.isSmartPunctuationEnabled = true
        settings.isEnglishPunctuationEnabled = false
        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        _ = controller.inputText("nihao", client: client)
        _ = controller.handle(makeKeyEvent(char: "", keyCode: 123), client: client)
        let caret = client.markedSelection
        let candidates = CandidatePanelHolder.shared.state.candidates.map(\.text)
        #expect(controller.handle(makeKeyEvent(char: ".", keyCode: 47, modifiers: [.control]), client: client))
        #expect(settings.isEnglishPunctuationEnabled)
        #expect(client.insertedText.isEmpty)
        #expect(client.markedText == "nihao")
        #expect(client.markedSelection == caret)
        #expect(CandidatePanelHolder.shared.state.candidates.map(\.text) == candidates)
        #expect(controller.handle(makeKeyEvent(char: ",", keyCode: 43), client: client))
        #expect(client.insertedText == "你好,")
        #expect(controller.handle(makeKeyEvent(char: ".", keyCode: 47, modifiers: [.control]), client: client))
        #expect(!settings.isEnglishPunctuationEnabled)
        #expect(controller.handle(makeKeyEvent(char: ".", keyCode: 47), client: client))
        #expect(client.insertedText == "你好,。")
        #expect(controller.inputText("!", client: client))
        #expect(client.insertedText == "你好,。！")
    }

    @Test @MainActor
    func asciiPunctuationCoversBothInputPathsAndMicrosoftSemicolon() {
        let settings = AetherSettings.shared
        let previous = settings.isEnglishPunctuationEnabled
        let scheme = settings.pinyinScheme
        defer { settings.isEnglishPunctuationEnabled = previous; settings.pinyinScheme = scheme }
        settings.isEnglishPunctuationEnabled = true
        settings.pinyinScheme = .microsoft
        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        #expect(controller.inputText("p;", client: client))
        #expect(client.markedText == "p;")
        #expect(controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client))
        #expect(client.insertedText == "平")
        #expect(controller.inputText(",.!?:;[]{}\"\"", client: client))
        #expect(client.insertedText == "平,.!?:;[]{}\"\"")
        #expect(controller.handle(makeKeyEvent(char: "/", keyCode: 44), client: client))
        #expect(client.insertedText.hasSuffix("/"))
        for modifiers: NSEvent.ModifierFlags in [[.control, .shift], [.control, .option], [.command]] {
            #expect(!controller.handle(makeKeyEvent(char: ".", keyCode: 47, modifiers: modifiers), client: client))
            #expect(settings.isEnglishPunctuationEnabled)
        }
    }

    @Test @MainActor
    func fourArrowPreferencePersistsAndResets() throws {
        let name = "AetherKey.ArrowTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AetherSettings(defaults: defaults)
        #expect(!settings.isFourArrowSelectionEnabled)
        settings.isFourArrowSelectionEnabled = true
        #expect(AetherSettings(defaults: defaults).isFourArrowSelectionEnabled)
        settings.resetToDefaults()
        #expect(!AetherSettings(defaults: defaults).isFourArrowSelectionEnabled)
    }

    @Test @MainActor
    func fourArrowsSelectWhileOptionRetainsEditing() {
        let settings = AetherSettings.shared
        let previous = settings.isFourArrowSelectionEnabled
        defer { settings.isFourArrowSelectionEnabled = previous }
        settings.isFourArrowSelectionEnabled = true
        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        _ = controller.inputText("nihao", client: client)
        for code: UInt16 in [124, 125, 123, 126] {
            #expect(controller.handle(makeKeyEvent(char: "", keyCode: code), client: client))
            #expect(client.markedText == "nihao")
            #expect(client.markedSelection.location == 5)
        }
        #expect(CandidatePanelHolder.shared.state.selectedIndex == 0)
        _ = controller.handle(makeKeyEvent(char: "", keyCode: 124), client: client)
        #expect(CandidatePanelHolder.shared.state.selectedIndex == 1)
        _ = controller.handle(makeKeyEvent(char: "", keyCode: 123, modifiers: [.option]), client: client)
        #expect(client.markedSelection.location == 2)
        _ = controller.inputText("a", client: client)
        #expect(client.markedText == "niahao")
        _ = controller.handle(makeKeyEvent(char: "", keyCode: 51), client: client)
        #expect(client.markedText == "nihao")
        _ = controller.handle(makeKeyEvent(char: "", keyCode: 124, modifiers: [.option]), client: client)
        #expect(client.markedSelection.location == 5)
        settings.isFourArrowSelectionEnabled = false
        _ = controller.handle(makeKeyEvent(char: "", keyCode: 123), client: client)
        #expect(client.markedSelection.location == 4)
        controller.resetComposition(client: client)
    }

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

extension CompositionEditingTests {
    @Test @MainActor
    func wubiTableCoverageAndStableExactOrdering() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let engine = WubiEngine(userLexicon: UserLexicon(storageURL: path))
        #expect(engine.entryCount > 130_000)
        #expect(engine.characterCount > 20_000)
        for (code, text) in [("g", "一"), ("v", "发"), ("wq", "你"), ("vbg", "好"), ("khlg", "中国"), ("yghg", "证")] {
            #expect(engine.query(code).first?.text == text)
        }
        #expect(engine.code(for: "你好") == "wqvb")
        #expect(engine.code(for: "中国") == "khlg")
        #expect(engine.query("znihao").contains { $0.text == "你好" && $0.comment == "wqvb" && $0.consumedInputLength == 6 })
        #expect(engine.query("z").last?.comment == "英")
        #expect(engine.query("vvvvv").count == 1)
        #expect(engine.query("wq").contains { $0.comment?.hasPrefix("wq") == true })
        // Every exact row, including zero-frequency rare characters, stays reachable.
        let url = try #require(Bundle.main.url(forResource: "wubi86.dict", withExtension: "yaml", subdirectory: "Wubi86"))
        let source = try String(contentsOf: url, encoding: .utf8)
        let table = try #require(source.components(separatedBy: "...\n").last)
        var expected: [String: Set<String>] = [:]
        for line in table.split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t")
            guard fields.count >= 3, (1...4).contains(fields[1].count), fields[1].allSatisfy({ $0 >= "a" && $0 <= "y" }) else { continue }
            expected[String(fields[1]), default: []].insert(String(fields[0]))
        }
        for (code, words) in expected {
            #expect(words.isSubset(of: Set(engine.query(code).map(\.text))), "Exact code lost words: \(code)")
        }
    }

    @Test @MainActor
    func wubiPersonalDictionaryDoesNotPollutePinyin() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let lexicon = UserLexicon(storageURL: path)
        defer { lexicon.flushPendingWrites(); try? FileManager.default.removeItem(at: path) }
        let engine = WubiEngine(userLexicon: lexicon)
        let key = WubiEngine.learningKey("g")
        lexicon.addCustomPhrase(pinyin: key, phrase: "五笔专用短语")
        #expect(engine.query("g").first?.text == "五笔专用短语")
        #expect(!lexicon.preferredWords(for: "g").contains("五笔专用短语"))
        lexicon.setPinned("一", for: key, pinned: true)
        #expect(engine.query("g").first?.text == "一")
        lexicon.forget("一", for: key)
        #expect(!engine.query("g").contains { $0.text == "一" })
        #expect(!lexicon.isForgotten("一", for: "g"))
    }

    @Test @MainActor
    func wubiControllerFifthCodeAndPunctuation() {
        let settings = AetherSettings.shared; let original = settings.pinyinScheme
        defer { settings.pinyinScheme = original }
        settings.pinyinScheme = .wubi86
        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        // Exercise both IMK event entry points. Fifth code must start the next word.
        for char in "wqiy" { _ = controller.handle(makeKeyEvent(char: String(char), keyCode: 0), client: client) }
        #expect(client.insertedText.isEmpty && client.markedText == "wqiy")
        _ = controller.inputText("vb", client: client)
        #expect(client.insertedText == "你" && client.markedText == "vb")
        _ = controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client)
        #expect(client.insertedText == "你好")
        _ = controller.inputText("khlg", client: client)
        _ = controller.handle(makeKeyEvent(char: ".", keyCode: 47), client: client)
        #expect(client.insertedText.hasSuffix("中国。"))
        _ = controller.inputText("v", client: client)
        _ = controller.handle(makeKeyEvent(char: "1", keyCode: 18), client: client)
        #expect(client.markedText.isEmpty && client.insertedText.hasSuffix("发"))
        _ = controller.inputText("znihao", client: client)
        #expect(client.markedText == "znihao")
        _ = controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client)
        #expect(client.insertedText.hasSuffix("你好"))
    }

    @Test @MainActor
    func wubiEditingFrozenSchemeSelectionAndInvalidCodes() {
        let settings = AetherSettings.shared
        let oldScheme = settings.pinyinScheme; let oldArrows = settings.isFourArrowSelectionEnabled
        defer { settings.pinyinScheme = oldScheme; settings.isFourArrowSelectionEnabled = oldArrows }
        settings.pinyinScheme = .wubi86; settings.isFourArrowSelectionEnabled = true
        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: nil)!
        _ = controller.inputText("khlg", client: client)
        _ = controller.handle(makeKeyEvent(char: "", keyCode: 123, modifiers: [.option]), client: client)
        #expect(client.markedSelection.location == 3)
        _ = controller.handle(makeKeyEvent(char: "", keyCode: 117), client: client)
        _ = controller.inputText("g", client: client)
        #expect(client.markedText == "khlg" && client.insertedText.isEmpty)
        settings.pinyinScheme = .full
        _ = controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client)
        #expect(client.insertedText == "中国")
        _ = controller.inputText("nihao", client: client)
        _ = controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client)
        #expect(client.insertedText.hasSuffix("你好"))
        settings.pinyinScheme = .wubi86
        _ = controller.inputText("yghg", client: client)
        _ = controller.handle(makeKeyEvent(char: "", keyCode: 124), client: client)
        let selected = CandidatePanelHolder.shared.state.selectedIndex
        #expect(selected == 1)
        _ = controller.inputText("g", client: client)
        #expect(client.insertedText.hasSuffix("証") && client.markedText == "g")
        controller.resetComposition(client: client)
        _ = controller.inputText("vvvzz", client: client)
        #expect(client.markedText == "vvvz")
        _ = controller.handle(makeKeyEvent(char: "", keyCode: 53), client: client)
        #expect(client.markedText.isEmpty)
    }

    @Test @MainActor
    func wubiSettingsRoundTripAndDefaultCompatibility() {
        let name = "AetherKey.WubiTest." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(AetherSettings(defaults: defaults).pinyinScheme == .full)
        AetherSettings(defaults: defaults).pinyinScheme = .wubi86
        #expect(AetherSettings(defaults: defaults).pinyinScheme == .wubi86)
        #expect(DoublePinyin.codes(for: "ni", scheme: .wubi86).isEmpty)
        #expect(DoublePinyin.tokens("wq", scheme: .wubi86) == nil)
    }

    @Test
    func lexiconImportExportFullBackupAndTextFormats() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let sourceURL = dir.appendingPathComponent("source.json")
        let source = UserLexicon(storageURL: sourceURL)
        source.recordCommit(pinyin: "hangzhou", word: "杭州")
        source.recordCommit(pinyin: "hangzhou", word: "杭州")
        source.addCustomPhrase(pinyin: "gongsi", phrase: "灵键科技有限公司")
        source.addCustomPhrase(pinyin: "wubi86:gggg", phrase: "五笔短语测试")
        source.setPinned("杭州", for: "hangzhou", pinned: true)
        source.forget("航州", for: "hangzhou")
        source.flushPendingWrites()

        // 1. Full JSON backup export & replace import
        let backupURL = dir.appendingPathComponent("backup.json")
        try source.export(to: backupURL)

        let targetURL = dir.appendingPathComponent("target.json")
        let target = UserLexicon(storageURL: targetURL)
        target.addCustomPhrase(pinyin: "jiuci", phrase: "将被覆盖的旧词")
        let replaceSummary = try target.importFile(from: backupURL, mode: .replace)
        #expect(replaceSummary.mode == .replace)
        #expect(replaceSummary.customPhraseCount == 2)
        #expect(replaceSummary.pinnedWordCount == 1)
        #expect(replaceSummary.forgottenWordCount == 1)
        #expect(target.preferredWords(for: "gongsi").first == "灵键科技有限公司")
        #expect(target.preferredWords(for: "wubi86:gggg").first == "五笔短语测试")
        #expect(!target.preferredWords(for: "jiuci").contains("将被覆盖的旧词"))
        #expect(target.isPinned("杭州", for: "hangzhou"))
        #expect(target.isForgotten("航州", for: "hangzhou"))
        #expect(target.totalCommittedCharacters == 4)

        // 2. Plain text TSV export & merge import (including Rime-style "phrase\tpinyin\tweight" lines)
        let txtURL = dir.appendingPathComponent("phrases.txt")
        try source.export(to: txtURL)
        let rimeStyleText = """
        # Rime dict header
        ---
        name: custom_places
        ...
        西湖文化广场\txi hu wen hua guang chang\t200
        binjiang\t滨江高新
        wubi86:wqvb\t你好五笔
        """
        let rimeURL = dir.appendingPathComponent("rime_custom.txt")
        try Data(rimeStyleText.utf8).write(to: rimeURL)

        let mergeSummary = try target.importFile(from: rimeURL, mode: .merge)
        #expect(mergeSummary.mode == .merge)
        #expect(mergeSummary.customPhraseCount == 3)
        #expect(target.preferredWords(for: "xihuwenhuaguangchang").first == "西湖文化广场")
        #expect(target.preferredWords(for: "binjiang").contains("滨江高新"))
        #expect(target.preferredWords(for: "wubi86:wqvb").first == "你好五笔")
        // Existing custom phrases remain intact after merge
        #expect(target.preferredWords(for: "gongsi").first == "灵键科技有限公司")

        // 3. Reject empty and invalid inputs
        #expect(throws: UserLexicon.LexiconTransferError.emptyInput) {
            try target.importData(Data(), mode: .merge)
        }
        #expect(throws: UserLexicon.LexiconTransferError.invalidFormat) {
            try target.importData(Data("{invalid-json".utf8), mode: .merge)
        }
        target.flushPendingWrites()
    }

    @Test @MainActor
    func commonPlaceNamesAcrossFullDoubleJianpinAndWubi() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let engine = PinyinEngine(userLexicon: UserLexicon(storageURL: tempURL))

        // 1. Full pinyin top-1 verification for major cities, provinces, districts, tech hubs, and transport hubs
        let top1Cases: [(String, String)] = [
            ("beijing", "北京"), ("beijingshi", "北京市"),
            ("shanghai", "上海"), ("shanghaishi", "上海市"),
            ("guangzhou", "广州"), ("shenzhen", "深圳"),
            ("hangzhou", "杭州"), ("hangzhoushi", "杭州市"),
            ("qingdao", "青岛"), ("qingdaoshi", "青岛市"),
            ("jinan", "济南"), ("jinanshi", "济南市"),
            ("changzhou", "常州"), ("changzhoushi", "常州市"),
            ("taiyuan", "太原"), ("taiyuanshi", "太原市"),
            ("fuzhou", "福州"), ("xiamen", "厦门"),
            ("suzhou", "苏州"), ("wuxi", "无锡"), ("ningbo", "宁波"), ("wenzhou", "温州"),
            ("zhejiangsheng", "浙江省"), ("jiangsusheng", "江苏省"), ("guangdongsheng", "广东省"),
            ("xinjiangweiwuerzizhiqu", "新疆维吾尔自治区"),
            ("xihuqu", "西湖区"), ("binjiangqu", "滨江区"), ("yuhangqu", "余杭区"), ("pudongxinqu", "浦东新区"),
            ("nanshanqu", "南山区"), ("futianqu", "福田区"), ("chaoyangqu", "朝阳区"), ("haidianqu", "海淀区"),
            ("weilaikejicheng", "未来科技城"), ("zhongguancun", "中关村"), ("lujiazui", "陆家嘴"),
            ("qianhai", "前海"), ("yuehaijiedao", "粤海街道"), ("shenzhenwan", "深圳湾"), ("huaqiangbei", "华强北"),
            ("dawanqu", "大湾区"), ("yuegangaodawanqu", "粤港澳大湾区"), ("changsanjiao", "长三角"),
            ("hangzhoudongzhan", "杭州东站"), ("shanghaihongqiao", "上海虹桥"), ("daxingjichang", "大兴机场"),
            ("xi'an", "西安"), ("ji'an", "吉安"), ("lu'an", "六安")
        ]
        for (input, expected) in top1Cases {
            let first = engine.query(rawInput: input).first?.text
            #expect(first == expected, "Expected \(expected) at #1 for \(input), got \(String(describing: first))")
        }

        // 2. Sentence composition with place names
        #expect(engine.query(rawInput: "woquqingdao").first?.text == "我去青岛")
        #expect(engine.query(rawInput: "wozaihangzhoudongzhan").first?.text == "我在杭州东站")

        // 3. Jianpin abbreviations for places
        for (abbr, place) in [("qd", "青岛"), ("jn", "济南"), ("nb", "宁波"), ("wlkjc", "未来科技城"), ("dwq", "大湾区"), ("hzdz", "杭州东站")] {
            #expect(engine.query(rawInput: abbr).contains { $0.text == place }, "Missing \(place) for abbreviation \(abbr)")
        }

        // 4. Double pinyin & Wubi 86 support for modern place names
        #expect(DoublePinyin.query("qkdc", scheme: .flypy).first?.text == "青岛")
        #expect(DoublePinyin.query("q;dk", scheme: .microsoft).first?.text == "青岛")

        let wubi = WubiEngine(userLexicon: UserLexicon(storageURL: tempURL))
        let wlkjcCode = try #require(wubi.code(for: "未来科技城"))
        #expect(wubi.query(wlkjcCode).contains { $0.text == "未来科技城" })
        #expect(wubi.query("zweilaikejicheng").contains { $0.text == "未来科技城" && $0.comment == wlkjcCode })
    }

    @Test @MainActor
    func typoCorrectionAndSentenceIntegrityPreventGarbageComposition() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let engine = PinyinEngine(userLexicon: UserLexicon(storageURL: tempURL))

        // 1. Common transposition & double-tap typos must rank the intended word at #1 and never synthesize isolated-consonant garbage
        let typoCases: [(input: String, expectedTop: String, forbiddenGarbage: String)] = [
            ("houmina", "后面", "后米娜"),
            ("shijain", "时间", "时间爱你"),
            ("baozhneg", "保证", "保证呢个"),
            ("xinag", "想", "西那个"),
            ("shemme", "什么", "社么么"),
            ("xingnegn", "性能", "新哽鞥"),
            ("rangnni", "让你", "然哽你"),
            ("woshnme", "我什么", "我是能么")
        ]
        for item in typoCases {
            let results = engine.query(rawInput: item.input)
            #expect(results.first?.text == item.expectedTop, "Expected \(item.expectedTop) at #1 for typo \(item.input), got \(String(describing: results.first?.text))")
            #expect(!results.contains { $0.text == item.forbiddenGarbage }, "Forbidden garbage \(item.forbiddenGarbage) appeared for \(item.input)")
        }

        // Trailing redundant nasal typo "gongzuong" offers "工作" and never synthesizes "工作哽"
        let gongzuong = engine.query(rawInput: "gongzuong")
        #expect(gongzuong.contains { $0.text == "工作" })
        #expect(!gongzuong.contains { $0.text == "工作哽" })

        // 2. Random consonant mashing must not synthesize long nonsense Chinese sentences
        for mash in ["dfgjfdlgkjfdklgjdfjgdfklgdf", "nihaogfdjgkldfgjkldfgfd", "nfjgfdlkjgdfklgjdfklgjdfklg"] {
            let candidates = engine.query(rawInput: mash)
            #expect(!candidates.contains { $0.comment != "英" && $0.text.count >= 6 }, "Mash \(mash) should not synthesize long Chinese sentence")
        }
    }

    @Test @MainActor
    func userLexiconHygieneBackspaceUndoAndPinnedForgottenManagement() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let lexicon = UserLexicon(storageURL: tempURL)
        let engine = PinyinEngine(userLexicon: lexicon)

        // 1. Single-letter ordinary frequency learning must not hijack initial-prefix default ranking
        lexicon.recordCommit(pinyin: "w", word: "握")
        lexicon.recordCommit(pinyin: "c", word: "瓷")
        #expect(engine.query(rawInput: "w").first?.text == "我")
        #expect(engine.query(rawInput: "c").first?.text == "此")

        // Explicit pin on single letter still works
        lexicon.setPinned("握", for: "w", pinned: true)
        #expect(engine.query(rawInput: "w").first?.text == "握")
        lexicon.setPinned("握", for: "w", pinned: false)
        #expect(lexicon.allPinnedWords().isEmpty)

        // 2. Reject overlong / consonant-mash garbage from polluting frequencyTable
        lexicon.recordCommit(pinyin: "dfgjfdlgkjfdklgjdfjgdfklgdf", word: "的法国机法的了国可机法的可了国机的法机国的法可了国的法")
        #expect(lexicon.selectionCount("的法国机法的了国可机法的可了国机的法机国的法可了国的法", for: "dfgjfdlgkjfdklgjdfjgdfklgdf") == 0)

        // 3. Pinned and forgotten word enumeration & unforget cleanup
        lexicon.setPinned("常州", for: "changzhou", pinned: true)
        lexicon.forget("长洲", for: "changzhou")
        #expect(lexicon.allPinnedWords().contains { $0.pinyin == "changzhou" && $0.word == "常州" })
        #expect(lexicon.allForgottenWords().contains { $0.pinyin == "changzhou" && $0.word == "长洲" })
        lexicon.unforget("长洲", for: "changzhou")
        #expect(!lexicon.isForgotten("长洲", for: "changzhou"))
        #expect(lexicon.allForgottenWords().isEmpty)

        // 4. Backspace immediately after committing a word rolls back the learned frequency increment
        let beforeCount = UserLexicon.shared.selectionCount("测试", for: "ceshi")
        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: client)!
        _ = controller.inputText("ceshi", client: client)
        _ = controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client)
        #expect(UserLexicon.shared.selectionCount("测试", for: "ceshi") == beforeCount + 1)
        // User immediately presses Backspace when buffer is empty to delete the mistaken commit
        let passThrough = controller.handle(makeKeyEvent(char: "\u{7F}", keyCode: 51), client: client)
        #expect(passThrough == false)
        #expect(UserLexicon.shared.selectionCount("测试", for: "ceshi") == beforeCount)
    }

    @Test @MainActor
    func bracketPagingContextualPanguQuoteResetAndDoublePinyinJianpin() {
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        defer { settings.resetToDefaults() }

        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: client)!

        // 1. '[' (keyCode 33) and ']' (keyCode 30) flip pages during composition instead of committing punctuation
        _ = controller.inputText("shi", client: client)
        #expect(CandidatePanelHolder.shared.state.currentPage == 1)
        let nextHandled = controller.handle(makeKeyEvent(char: "]", keyCode: 30), client: client)
        #expect(nextHandled == true)
        #expect(CandidatePanelHolder.shared.state.currentPage == 2)
        #expect(client.insertedText.isEmpty)
        let prevHandled = controller.handle(makeKeyEvent(char: "[", keyCode: 33), client: client)
        #expect(prevHandled == true)
        #expect(CandidatePanelHolder.shared.state.currentPage == 1)
        controller.resetComposition(client: client)

        // 2. Contextual Pangu spacing: deleting committed Chinese text before typing uppercase ASCII must not prepend a space
        _ = controller.inputText("ni", client: client)
        _ = controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client)
        #expect(client.insertedText == "你")
        // Simulate user deleting "你" with Backspace
        client.insertedText = ""
        _ = controller.handle(makeKeyEvent(char: "\u{7F}", keyCode: 51), client: client)
        _ = controller.handle(makeKeyEvent(char: "A", keyCode: 0, modifiers: [.shift]), client: client)
        #expect(client.insertedText == "A")

        // 3. SmartPunctuation quote pairing rolls back when immediately backspaced and resets on deactivateServer
        SmartPunctuation.shared.resetState()
        client.insertedText = ""
        _ = controller.handle(makeKeyEvent(char: "\"", keyCode: 39), client: client)
        #expect(client.insertedText == "“")
        // Immediately backspace the opening quote -> next quote should still be opening "“"
        client.insertedText = ""
        _ = controller.handle(makeKeyEvent(char: "\u{7F}", keyCode: 51), client: client)
        _ = controller.handle(makeKeyEvent(char: "\"", keyCode: 39), client: client)
        #expect(client.insertedText == "“")
        // Deactivating server also resets open quote state
        controller.deactivateServer(client)
        client.insertedText = ""
        _ = controller.handle(makeKeyEvent(char: "\"", keyCode: 39), client: client)
        #expect(client.insertedText == "“")

        // 4. DoublePinyin falls back to commonAbbreviations when input is a known abbreviation (e.g. "srf", "zgc")
        #expect(DoublePinyin.query("srf", scheme: .flypy).contains { $0.text == "输入法" })
        #expect(DoublePinyin.query("zgc", scheme: .microsoft).contains { $0.text == "中关村" })
    }

    @Test("Panel keeps monotonic width within a session, re-anchors on partial commit, elevates level, and displays edit cursor")
    @MainActor
    func panelStabilityReanchorLevelAndEditCursor() {
        let panel = CandidatePanel()
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let rightEdgeCaret = NSRect(x: screen.maxX - 80, y: screen.midY, width: 0, height: 22)
        panel.state.candidates = ["你好世界", "输入法", "候选词", "跟随光标", "自然输入", "中文", "排版"].map { Candidate(text: $0) }
        panel.show(caretRect: rightEdgeCaret, clientWindowLevel: Int32(NSWindow.Level.popUpMenu.rawValue) + 5)
        let wideFrame = panel.frame
        #expect(panel.level.rawValue > NSWindow.Level.popUpMenu.rawValue)

        // Turning to a shorter page must not shrink the panel width or cause the left edge to bounce right.
        panel.state.candidates = [Candidate(text: "一"), Candidate(text: "二")]
        panel.show(caretRect: rightEdgeCaret)
        #expect(panel.frame.width == wideFrame.width)
        #expect(panel.frame.minX == wideFrame.minX)

        // Switching view mode recalculates width for the new layout.
        panel.state.viewMode = .scroll
        panel.show(caretRect: rightEdgeCaret)
        #expect(panel.frame.width <= wideFrame.width)
        panel.dismiss()

        // Controller anchors at initial caret, shows cursor bar during mid-buffer edit, and re-anchors after partial commit.
        let settings = AetherSettings.shared
        let prevScheme = settings.pinyinScheme
        defer { settings.pinyinScheme = prevScheme }
        settings.pinyinScheme = .full
        let client = MockTextInputClient()
        client.caretRect = NSRect(x: 220, y: 500, width: 0, height: 22)
        let controller = AetherInputController(server: nil, delegate: nil, client: client)!
        _ = controller.inputText("nihao", client: client)
        let startOrigin = CandidatePanelHolder.shared.frame.origin
        client.caretRect = NSRect(x: 245, y: 500, width: 0, height: 22)
        _ = controller.handle(makeKeyEvent(char: "", keyCode: 123), client: client)
        #expect(CandidatePanelHolder.shared.state.displayPinyin.contains("▏"))
        #expect(CandidatePanelHolder.shared.frame.origin == startOrigin)
        controller.resetComposition(client: client)

        client.caretRect = NSRect(x: 220, y: 500, width: 0, height: 22)
        _ = controller.inputText("jintiantianqi", client: client)
        let prefixIdx = CandidatePanelHolder.shared.state.candidates.firstIndex { $0.text == "今天" }
        if let idx = prefixIdx, idx < 7 {
            client.caretRect = NSRect(x: 265, y: 500, width: 0, height: 22)
            _ = controller.handle(makeKeyEvent(char: String(idx + 1), keyCode: 18), client: client)
            #expect(CandidatePanelHolder.shared.frame.minX == 265)
        }
        controller.resetComposition(client: client)
    }

    @Test("V-mode RMB capitalization handles rounding carry safely without crashing and inserts financial zeroes")
    func vModeRmbRoundingAndFinancialZeroes() {
        let calc = VModeCalculator.shared
        #expect(calc.convertToRMB(amount: 1.999) == "贰元整")
        #expect(calc.convertToRMB(amount: 9.996) == "壹拾元整")
        #expect(calc.convertToRMB(amount: 0.009) == "零元壹分")
        #expect(calc.candidates(for: "v1.999").contains { $0.text == "贰元整" })
        #expect(calc.convertToRMB(amount: 100_100) == "壹拾万零壹佰元整")
        #expect(calc.convertToRMB(amount: 101_000) == "壹拾万壹仟元整")
        #expect(calc.convertToRMB(amount: 100_000_001) == "壹亿零壹元整")
        #expect(calc.convertToRMB(amount: 100_010_000) == "壹亿零壹万元整")
    }

    @Test("Engine supports lue/nue equivalence, weighted Jianpin, mixed initials, syllable fuzzy, and normal Gengyan learning")
    func lueNueJianpinSyllableFuzzyAndLexiconHygiene() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let lexicon = UserLexicon(storageURL: tempURL)
        let engine = PinyinEngine(userLexicon: lexicon)

        // 1. lue/lve and nue/nve equivalence without polluting er/nver words
        #expect(engine.query(rawInput: "zhanlue").first?.text == "战略")
        #expect(engine.query(rawInput: "zhanlve").first?.text == "战略")
        #expect(engine.query(rawInput: "hulue").first?.text == "忽略")
        #expect(engine.query(rawInput: "celue").first?.text == "策略")
        #expect(engine.query(rawInput: "gonglue").first?.text == "攻略")
        #expect(engine.query(rawInput: "nuedai").first?.text == "虐待")
        #expect(engine.query(rawInput: "nue").first?.text == "虐")
        #expect(engine.query(rawInput: "fuluer").first?.text == "附录二")
        #expect(engine.query(rawInput: "nuerhachi").first?.text == "努尔哈赤")
        #expect(engine.query(rawInput: "banver").first?.text == "把女儿")

        // 2. Corpus-weighted Jianpin & mixed initial+syllable matching
        for (input, expected) in [
            ("jsj", "计算机"), ("pyq", "朋友圈"), ("hlw", "互联网"), ("sfz", "身份证"),
            ("sjk", "数据库"), ("fwq", "服务器"), ("dxs", "大学生"),
            ("pyquan", "朋友圈"), ("jsji", "计算机"), ("hlwang", "互联网"),
            ("sfzheng", "身份证"), ("jttianqi", "今天天气")
        ] {
            #expect(engine.query(rawInput: input).contains { $0.text == expected }, "Missing \(expected) for \(input)")
        }
        #expect(engine.query(rawInput: "yjs").contains { $0.text == "研究生" || $0.text == "研究所" })
        #expect(engine.query(rawInput: "gwy").contains { $0.text == "公务员" || $0.text == "国务院" })

        // 3. Syllable-level fuzzy expansion handles multi-nasal phrases (e.g. fangjian -> 房间 / 方江)
        let settings = AetherSettings.shared
        let oldFuzzy = settings.isFuzzyPinyinEnabled
        defer { settings.isFuzzyPinyinEnabled = oldFuzzy }
        settings.isFuzzyPinyinEnabled = true
        #expect(engine.query(rawInput: "fangan").first?.text == "方案")
        #expect(engine.query(rawInput: "fangjian").contains { $0.text == "房间" })

        // 4. Normal dictionary phrases with "哽" (e.g. 哽咽) can be learned while garbage compositions remain blocked
        lexicon.recordCommit(pinyin: "gengye", word: "哽咽")
        lexicon.recordCommit(pinyin: "gongzuong", word: "工作哽")
        #expect(lexicon.selectionCount("哽咽", for: "gengye") == 1)
        #expect(lexicon.selectionCount("工作哽", for: "gongzuong") == 0)
    }

    @Test("Controller preserves mixed-case raw English, syncs space/caret context, guards Shift+Cmd, shows HUD, and remembers VS Code manual mode")
    @MainActor
    func mixedCaseSpaceSyncShiftGuardHUDAndVSCodeMode() async throws {
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        defer { settings.resetToDefaults() }

        // 1. Mixed-case English preserved on Return & "英" candidate while empty-buffer uppercase still passes through
        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: client)!
        _ = controller.handle(makeKeyEvent(char: "i", keyCode: 34), client: client)
        _ = controller.handle(makeKeyEvent(char: "P", keyCode: 35, modifiers: [.shift]), client: client)
        for c in "hone" { _ = controller.handle(makeKeyEvent(char: String(c), keyCode: 0), client: client) }
        #expect(client.markedText == "iPhone")
        #expect(CandidatePanelHolder.shared.state.candidates.last?.text == "iPhone")
        _ = controller.handle(makeKeyEvent(char: "\r", keyCode: 36), client: client)
        #expect(client.insertedText == "iPhone")

        client.reset()
        _ = controller.handle(makeKeyEvent(char: "A", keyCode: 0, modifiers: [.shift]), client: client)
        #expect(client.insertedText == "A")

        // 2. Manual Space and moved caret reset Pangu / decimal context
        controller.deactivateServer(client)
        controller.activateServer(client)
        client.reset()
        _ = controller.inputText("nihao", client: client)
        _ = controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client)
        _ = controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client)
        _ = controller.handle(makeKeyEvent(char: "A", keyCode: 0, modifiers: [.shift]), client: client)
        #expect(client.insertedText == "你好A")

        client.reset()
        _ = controller.handle(makeKeyEvent(char: "3", keyCode: 20), client: client)
        _ = controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client)
        _ = controller.handle(makeKeyEvent(char: ".", keyCode: 47), client: client)
        #expect(client.insertedText == "。")

        client.reset()
        client.contextText = ""
        _ = controller.inputText("ni", client: client)
        _ = controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client)
        client.contextText = "" // Caret moved to document start
        _ = controller.handle(makeKeyEvent(char: "A", keyCode: 0, modifiers: [.shift]), client: client)
        #expect(client.insertedText.hasSuffix("A") && !client.insertedText.hasSuffix(" A"))

        // 3. Shift single tap toggles mode and fires StatusHUD, while Shift+Command combo does not toggle
        let vsClient = MockTextInputClient()
        vsClient.mockBundleIdentifier = "com.microsoft.VSCode"
        vsClient.mockUniqueID = "vscode-session-\(UUID().uuidString)"
        controller.activateServer(vsClient)
        // Defaults to English in VS Code -> short Shift tap switches to Chinese
        let hudBefore = StatusHUDHolder.shared.state.showCount
        _ = controller.handle(makeFlagsEvent(modifiers: [.shift]), client: vsClient)
        try await Task.sleep(for: .milliseconds(35))
        _ = controller.handle(makeFlagsEvent(modifiers: []), client: vsClient)
        #expect(StatusHUDHolder.shared.state.showCount == hudBefore + 1)
        #expect(StatusHUDHolder.shared.state.badge == "中")

        // Reactivating VS Code keeps user's manual Chinese choice instead of resetting to English
        controller.activateServer(client)
        controller.activateServer(vsClient)
        #expect(controller.handle(makeKeyEvent(char: "n", keyCode: 45), client: vsClient) == true)
        controller.resetComposition(client: vsClient)

        // Pressing Shift + Command (e.g. Cmd+Shift+4) and releasing Command first must NOT toggle back to English
        let hudCountBeforeCombo = StatusHUDHolder.shared.state.showCount
        _ = controller.handle(makeFlagsEvent(modifiers: [.shift]), client: vsClient)
        _ = controller.handle(makeFlagsEvent(modifiers: [.shift, .command]), client: vsClient)
        try await Task.sleep(for: .milliseconds(35))
        _ = controller.handle(makeFlagsEvent(modifiers: [.shift]), client: vsClient)
        _ = controller.handle(makeFlagsEvent(modifiers: []), client: vsClient)
        #expect(StatusHUDHolder.shared.state.showCount == hudCountBeforeCombo)
        #expect(controller.handle(makeKeyEvent(char: "n", keyCode: 45), client: vsClient) == true)
        controller.resetComposition(client: vsClient)
    }
}

extension CompositionEditingTests {
    private static func digitKeyCode(for digit: Int) -> UInt16 {
        switch digit {
        case 1: return 18
        case 2: return 19
        case 3: return 20
        case 4: return 21
        case 5: return 23
        case 6: return 22
        case 7: return 26
        case 8: return 28
        case 9: return 25
        default: return 18
        }
    }

    // MARK: - 1.1.0 Wave 3 Tests: Pangu Spacing Fixes & CJK Extensions
    @Test("Pangu spacing preserves CJK punctuation while spacing CJK extension B-H ideographs")
    func panguSpacingPunctuationFixAndExtensionIdeographs() {
        let pangu = PanguSpacing.shared

        #expect(pangu.spacing("《AetherKey》") == "《AetherKey》")
        #expect(pangu.spacing("你好。Hello") == "你好。Hello")
        #expect(pangu.spacing("Mac、iPad") == "Mac、iPad")
        #expect(pangu.spacing("「Swift」") == "「Swift」")
        #expect(pangu.spacing("【测试】123") == "【测试】123")
        #expect(pangu.spacing("『Aether』123") == "『Aether』123")

        // Extension B+ / G-H ideographs (0x20000...0x323AF) receive half-width spacing around ASCII
        #expect(pangu.spacing("𠙶Test") == "𠙶 Test")
        #expect(pangu.spacing("Test𠙶") == "Test 𠙶")
        #expect(pangu.spacing("测试𠙶123") == "测试𠙶 123")
        #expect(pangu.spacing("𰻞Swift") == "𰻞 Swift")

        #expect(pangu.shouldPrependSpace(preceding: "。", committing: "Hello") == false)
        #expect(pangu.shouldPrependSpace(preceding: "》", committing: "Swift") == false)
        #expect(pangu.shouldPrependSpace(preceding: "、", committing: "iPad") == false)
        #expect(pangu.shouldPrependSpace(preceding: "𠙶", committing: "Test") == true)
        #expect(pangu.formatCommitText(preceding: "T", committing: "𠙶") == " 𠙶")
        #expect(pangu.formatCommitText(preceding: "」", committing: "Swift") == "Swift")
    }

    // MARK: - 1.1.0 Wave 3 Tests: V-Mode Macros, Chinese Numerals, State Reset & Macro Digit Selection
    @Test("V-Mode calculator supports new macros, Chinese numerals, and boundary integers")
    func vModeMacrosAndChineseNumerals() {
        let vCalc = VModeCalculator.shared

        #expect(VModeCalculator.isMacroKeywordMode("vdate"))
        #expect(VModeCalculator.isMacroKeywordMode("vnow"))
        #expect(VModeCalculator.isMacroKeywordMode("vuuid"))
        #expect(!VModeCalculator.isMacroKeywordMode("v"))
        #expect(!VModeCalculator.isMacroKeywordMode("v1+2"))
        #expect(!VModeCalculator.isMacroKeywordMode("v123"))

        for macro in ["vnow", "vdt", "vdatetime"] {
            let items = vCalc.candidates(for: macro)
            #expect(items.count == 3)
            #expect(items[0].text.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"#, options: .regularExpression) != nil)
            #expect(items[1].text.contains("年") && items[1].text.contains("月") && items[1].text.contains("日"))
            #expect(items[2].text.contains("T"))
        }
        // Regression guard: vdate continues to match date rather than vdt
        let vdateItems = vCalc.candidates(for: "vdate")
        #expect(vdateItems.count == 2)
        #expect(vdateItems[0].text.contains("年"))
        #expect(vdateItems[1].text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil)

        let tsItems = vCalc.candidates(for: "vts")
        #expect(tsItems.count == 2)
        let sec = Int64(tsItems[0].text)
        let ms = Int64(tsItems[1].text)
        #expect(sec != nil && sec! >= 1_700_000_000)
        #expect(ms != nil && abs(ms! / 1000 - (sec ?? 0)) <= 1)

        let uuidItems = vCalc.candidates(for: "vuuid")
        #expect(uuidItems.count == 2)
        #expect(UUID(uuidString: uuidItems[0].text) != nil && uuidItems[0].text == uuidItems[0].text.lowercased())
        #expect(UUID(uuidString: uuidItems[1].text) != nil && uuidItems[1].text == uuidItems[1].text.uppercased())
        #expect(uuidItems[0].text.uppercased() == uuidItems[1].text)

        let arrowTexts = Set(vCalc.candidates(for: "varrow").map(\.text))
        #expect(arrowTexts.isSuperset(of: ["→", "←", "↔", "⇒"]))

        let mathTexts = Set(vCalc.candidates(for: "vmath").map(\.text))
        #expect(mathTexts.isSuperset(of: ["×", "÷", "≈", "≠", "≤", "≥"]))

        let greekTexts = Set(vCalc.candidates(for: "vgreek").map(\.text))
        #expect(greekTexts.isSuperset(of: ["α", "β", "π", "Ω"]))

        let symbolTexts = Set(vCalc.candidates(for: "vfh").map(\.text))
        #expect(symbolTexts.isSuperset(of: ["✓", "✗", "⌘", "⌥", "⇧", "⌃"]))

        let v123Items = vCalc.candidates(for: "v123")
        #expect(v123Items.contains { $0.text == "一百二十三" && $0.comment == "中文数字" })
        #expect(v123Items.contains { $0.text == "壹佰贰拾叁元整" })
        #expect(vCalc.candidates(for: "v1+2*3").first?.text == "7")

        let boundaries: [(Int64, String)] = [
            (0, "零"),
            (10, "十"),
            (15, "十五"),
            (105, "一百零五"),
            (10_010, "一万零一十"),
            (100_000_001, "一亿零一")
        ]
        for (value, expected) in boundaries {
            #expect(vCalc.convertToChineseNumeral(integer: value) == expected)
        }
    }

    @Test("V-Mode resets inputMode on commit or Escape and supports digit selection for macro keywords")
    @MainActor
    func vModeStateResetAndMacroDigitSelectionInController() async throws {
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        SmartPunctuation.shared.resetState()
        defer {
            settings.resetToDefaults()
            SmartPunctuation.shared.resetState()
        }

        // 1. Space commit resets .vMode -> .chinese so punctuation and Shift toggle work immediately
        let client1 = MockTextInputClient()
        client1.mockBundleIdentifier = "test.vmode.space.\(UUID().uuidString)"
        let controller1 = AetherInputController(server: nil, delegate: nil, client: client1)!
        controller1.activateServer(client1)
        for c in "v1+2" {
            #expect(controller1.handle(makeKeyEvent(char: String(c), keyCode: 0), client: client1))
        }
        #expect(client1.markedText == "v1+2")
        #expect(controller1.handle(makeKeyEvent(char: " ", keyCode: 49), client: client1))
        #expect(client1.insertedText == "3" && client1.markedText.isEmpty)

        #expect(controller1.handle(makeKeyEvent(char: ",", keyCode: 43), client: client1))
        #expect(controller1.handle(makeKeyEvent(char: ".", keyCode: 47), client: client1))
        #expect(client1.insertedText == "3，。")

        _ = controller1.handle(makeFlagsEvent(modifiers: [.shift]), client: client1)
        try await Task.sleep(for: .milliseconds(35))
        _ = controller1.handle(makeFlagsEvent(modifiers: []), client: client1)
        #expect(StatusHUDHolder.shared.state.badge == "EN")
        #expect(!controller1.handle(makeKeyEvent(char: "a", keyCode: 0), client: client1))
        controller1.resetComposition(client: client1)

        // 2. Escape cancellation also resets .vMode -> .chinese
        let client2 = MockTextInputClient()
        client2.mockBundleIdentifier = "test.vmode.esc.\(UUID().uuidString)"
        let controller2 = AetherInputController(server: nil, delegate: nil, client: client2)!
        controller2.activateServer(client2)
        for c in "v1+2" {
            #expect(controller2.handle(makeKeyEvent(char: String(c), keyCode: 0), client: client2))
        }
        #expect(controller2.handle(makeKeyEvent(char: "\u{1B}", keyCode: 53), client: client2))
        #expect(client2.markedText.isEmpty && client2.insertedText.isEmpty)

        #expect(controller2.handle(makeKeyEvent(char: ",", keyCode: 43), client: client2))
        #expect(controller2.handle(makeKeyEvent(char: ".", keyCode: 47), client: client2))
        #expect(client2.insertedText == "，。")

        _ = controller2.handle(makeFlagsEvent(modifiers: [.shift]), client: client2)
        try await Task.sleep(for: .milliseconds(35))
        _ = controller2.handle(makeFlagsEvent(modifiers: []), client: client2)
        #expect(StatusHUDHolder.shared.state.badge == "EN")
        #expect(!controller2.handle(makeKeyEvent(char: "a", keyCode: 0), client: client2))
        controller2.resetComposition(client: client2)

        // 3. Macro keyword mode selects candidate on digit 2 instead of appending "vdate2",
        //    while math expression mode keeps appending digits to "v1+2".
        let client3 = MockTextInputClient()
        client3.mockBundleIdentifier = "test.vmode.macro.\(UUID().uuidString)"
        let controller3 = AetherInputController(server: nil, delegate: nil, client: client3)!
        controller3.activateServer(client3)

        for c in "vdate" {
            #expect(controller3.handle(makeKeyEvent(char: String(c), keyCode: 0), client: client3))
        }
        #expect(client3.markedText == "vdate")
        #expect(controller3.handle(makeKeyEvent(char: "2", keyCode: 19), client: client3))
        #expect(client3.markedText.isEmpty)
        #expect(client3.insertedText != "vdate2")
        #expect(client3.insertedText.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil)

        client3.reset()
        #expect(controller3.inputText("vdate2", client: client3))
        #expect(client3.markedText.isEmpty)
        #expect(client3.insertedText.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil)

        client3.reset()
        for c in "v1+2" {
            #expect(controller3.handle(makeKeyEvent(char: String(c), keyCode: 0), client: client3))
        }
        #expect(client3.markedText == "v1+2")
        #expect(controller3.handle(makeKeyEvent(char: " ", keyCode: 49), client: client3))
        #expect(client3.insertedText == "3")
    }

    // MARK: - 1.1.0 Wave 3 Tests: Mixed-Case Raw English Numeric Selection
    @Test("Mixed-case raw English candidate retains original casing on numeric key selection")
    @MainActor
    func mixedCaseEnglishCandidateNumericSelection() throws {
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        defer { settings.resetToDefaults() }

        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: client)!
        defer { controller.resetComposition(client: client) }

        // 1. Type "iPhone" via handle(_:client:), find "英" candidate, and commit via numeric key 1-9
        _ = controller.handle(makeKeyEvent(char: "i", keyCode: 34), client: client)
        _ = controller.handle(makeKeyEvent(char: "P", keyCode: 35, modifiers: [.shift]), client: client)
        for c in "hone" {
            _ = controller.handle(makeKeyEvent(char: String(c), keyCode: 0), client: client)
        }
        #expect(client.markedText == "iPhone")

        let panel = CandidatePanelHolder.shared
        var foundIndex: Int?
        for _ in 0..<panel.state.totalPages {
            if let idx = panel.state.candidates.firstIndex(where: { $0.comment == "英" && $0.text == "iPhone" }) {
                foundIndex = idx
                break
            }
            _ = controller.handle(makeKeyEvent(char: "=", keyCode: 24), client: client)
        }
        let digitIdx = try #require(foundIndex)
        #expect(digitIdx < 9)
        #expect(controller.handle(makeKeyEvent(char: String(digitIdx + 1), keyCode: Self.digitKeyCode(for: digitIdx + 1)), client: client))
        #expect(client.insertedText == "iPhone")
        #expect(client.markedText.isEmpty)

        // 2. Also verify a mixed-case buffer with preceding Chinese candidates ("niHao") at a non-first slot
        client.reset()
        #expect(controller.inputText("niHao", client: client))
        #expect(client.markedText == "niHao")
        var mixedFoundIndex: Int?
        for _ in 0..<panel.state.totalPages {
            if let idx = panel.state.candidates.firstIndex(where: { $0.comment == "英" && $0.text == "niHao" }) {
                mixedFoundIndex = idx
                break
            }
            _ = controller.handle(makeKeyEvent(char: "=", keyCode: 24), client: client)
        }
        let mixedDigitIdx = try #require(mixedFoundIndex)
        #expect(mixedDigitIdx < 9)
        #expect(controller.handle(makeKeyEvent(char: String(mixedDigitIdx + 1), keyCode: Self.digitKeyCode(for: mixedDigitIdx + 1)), client: client))
        #expect(client.insertedText == "niHao")
        #expect(client.markedText.isEmpty)
    }

    // MARK: - 1.1.0 Wave 3 Tests: Simplified <-> Traditional Chinese Conversion
    @Test("ChineseScriptConverter handles one-to-many overrides and preserves non-Chinese candidates")
    func chineseScriptConverterPairsAndCandidates() {
        let converter = ChineseScriptConverter.shared
        let pairs: [(String, String)] = [
            ("头发", "頭髮"), ("发现", "發現"), ("皇后", "皇后"), ("后面", "後面"),
            ("干净", "乾淨"), ("干部", "幹部"), ("饼干", "餅乾"), ("里面", "裡面"),
            ("公里", "公里"), ("面条", "麵條"), ("手表", "手錶"), ("回复", "回覆"),
            ("恢复", "恢復"), ("复习", "複習"), ("反复", "反覆"), ("台风", "颱風")
        ]
        for (simplified, traditional) in pairs {
            #expect(converter.toTraditional(simplified) == traditional, "Conversion mismatch for \(simplified)")
        }
        #expect(converter.toTraditional("Swift回复123") == "Swift回覆123")
        #expect(converter.toTraditional("AetherKey") == "AetherKey")
        #expect(converter.toTraditional("") == "")

        let inputs: [Candidate] = [
            Candidate(text: "头发", consumedInputLength: 5),
            Candidate(text: "頭髮", consumedInputLength: 5),
            Candidate(text: "🌹", isEmoji: true, consumedInputLength: 5),
            Candidate(text: "toufa", comment: "英", consumedInputLength: 5),
            Candidate(text: "壹佰元整", isVMode: true)
        ]
        #expect(converter.convertCandidates(inputs, toTraditional: false).map(\.text) == inputs.map(\.text))

        let converted = converter.convertCandidates(inputs, toTraditional: true)
        #expect(converted.map(\.text) == ["頭髮", "🌹", "toufa", "壹佰元整"])
        #expect(converted.first?.canonicalText == "头发")
        #expect(converted.first?.rawText == "头发")
    }

    @Test("Ctrl+Shift+F toggles Traditional mode in place with unified lexicon across Full, Double Pinyin, and Wubi 86")
    @MainActor
    func traditionalModeShortcutUnifiedLexiconAndSchemes() throws {
        let settings = AetherSettings.shared
        let lexicon = UserLexicon.shared
        settings.resetToDefaults()

        var commitsToRollback: [(String, String)] = []
        var pinsToRemove: [(String, String)] = []
        var forgetsToRemove: [(String, String)] = []
        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: client)!

        defer {
            controller.resetComposition(client: client)
            for (reading, word) in pinsToRemove {
                lexicon.setPinned(word, for: reading, pinned: false)
            }
            for (reading, word) in forgetsToRemove {
                lexicon.unforget(word, for: reading)
            }
            for (reading, word) in commitsToRollback {
                lexicon.rollbackCommit(pinyin: reading, word: word)
            }
            settings.resetToDefaults()
        }

        // 1. Type "toufa", press Ctrl+Shift+F in-place -> pre-edit intact, HUD fires, candidate turns "頭髮"
        let beforeToufaCount = lexicon.selectionCount("头发", for: "toufa")
        #expect(controller.inputText("toufa", client: client))
        #expect(client.markedText == "toufa")
        let panel = CandidatePanelHolder.shared
        #expect(panel.state.candidates.first?.text == "头发")

        let hudBefore = StatusHUDHolder.shared.state.showCount
        #expect(controller.handle(makeKeyEvent(char: "f", keyCode: 3, modifiers: [.control, .shift]), client: client))
        #expect(settings.isTraditionalChineseEnabled)
        #expect(client.markedText == "toufa")
        #expect(client.insertedText.isEmpty)
        #expect(StatusHUDHolder.shared.state.showCount == hudBefore + 1)
        #expect(StatusHUDHolder.shared.state.badge == "繁")
        #expect(panel.state.isTraditional)
        #expect(panel.state.candidates.first?.text == "頭髮")

        #expect(controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client))
        #expect(client.insertedText == "頭髮")
        #expect(client.markedText.isEmpty)
        commitsToRollback.append(("toufa", "头发"))
        #expect(lexicon.selectionCount("头发", for: "toufa") == beforeToufaCount + 1)
        #expect(lexicon.selectionCount("頭髮", for: "toufa") == 0)

        // 2. Pin with Ctrl+Opt+P & commit in Traditional mode -> canonical Simplified key & word in UserLexicon, works in Simplified too
        client.reset()
        #expect(controller.inputText("huifu", client: client))
        let huifuIdx = try #require(panel.state.candidates.firstIndex { $0.text == "恢復" })
        for _ in 0..<huifuIdx {
            _ = controller.handle(makeKeyEvent(char: "", keyCode: 125), client: client)
        }
        #expect(controller.handle(makeKeyEvent(char: "p", keyCode: 35, modifiers: [.control, .option]), client: client))
        pinsToRemove.append(("huifu", "恢复"))
        #expect(lexicon.isPinned("恢复", for: "huifu"))
        #expect(!lexicon.isPinned("恢復", for: "huifu"))
        #expect(panel.state.candidates.first?.text == "恢復")

        #expect(controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client))
        #expect(client.insertedText == "恢復")
        commitsToRollback.append(("huifu", "恢复"))
        #expect(lexicon.preferredWords(for: "huifu").first == "恢复")
        #expect(!lexicon.preferredWords(for: "huifu").contains("恢復"))
        #expect(!lexicon.allPinnedWords().contains { $0.word == "恢復" })

        // Switch back to Simplified via Ctrl+Shift+F -> cross-script pin still ranks "恢复" first
        #expect(controller.handle(makeKeyEvent(char: "f", keyCode: 3, modifiers: [.control, .shift]), client: client))
        #expect(!settings.isTraditionalChineseEnabled)
        #expect(StatusHUDHolder.shared.state.badge == "简")
        client.reset()
        #expect(controller.inputText("huifu", client: client))
        #expect(panel.state.candidates.first?.text == "恢复")

        // Unpin "恢复", switch back to Traditional, and forget "回覆" -> stored canonically as "回复"
        #expect(controller.handle(makeKeyEvent(char: "u", keyCode: 32, modifiers: [.control, .option]), client: client))
        #expect(!lexicon.isPinned("恢复", for: "huifu"))
        #expect(controller.handle(makeKeyEvent(char: "f", keyCode: 3, modifiers: [.control, .shift]), client: client))
        let replyIdx = try #require(panel.state.candidates.firstIndex { $0.text == "回覆" })
        for _ in 0..<replyIdx {
            _ = controller.handle(makeKeyEvent(char: "", keyCode: 125), client: client)
        }
        #expect(controller.handle(makeKeyEvent(char: "", keyCode: 51, modifiers: [.control, .option]), client: client))
        forgetsToRemove.append(("huifu", "回复"))
        #expect(lexicon.isForgotten("回复", for: "huifu"))
        #expect(!lexicon.isForgotten("回覆", for: "huifu"))
        #expect(!lexicon.allForgottenWords().contains { $0.word == "回覆" })
        #expect(!panel.state.candidates.contains { $0.text == "回覆" })
        #expect(controller.handle(makeKeyEvent(char: "f", keyCode: 3, modifiers: [.control, .shift]), client: client))
        #expect(!panel.state.candidates.contains { $0.text == "回复" })
        controller.resetComposition(client: client)

        // 3. Double Pinyin (.flypy) & Wubi 86 output Traditional while preserving "英", Emoji, and V-Mode
        settings.isTraditionalChineseEnabled = true
        settings.pinyinScheme = .flypy
        client.reset()
        #expect(controller.inputText("vsgo", client: client))
        #expect(panel.state.candidates.first?.text == "中國")
        #expect(controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client))
        #expect(client.insertedText == "中國")
        commitsToRollback.append(("zhongguo", "中国"))

        settings.pinyinScheme = .wubi86
        client.reset()
        #expect(controller.inputText("khlg", client: client))
        #expect(panel.state.candidates.first?.text == "中國")
        #expect(panel.state.candidates.contains { $0.comment == "英" && $0.text == "khlg" })
        #expect(controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client))
        #expect(client.insertedText == "中國")
        commitsToRollback.append(("wubi86:khlg", "中国"))

        settings.pinyinScheme = .full
        client.reset()
        #expect(controller.inputText("meigui", client: client))
        #expect(panel.state.candidates.contains { $0.isEmoji && $0.text == "🌹" })
        controller.resetComposition(client: client)

        controller.deactivateServer(client)
        controller.activateServer(client)
        client.reset()
        #expect(controller.inputText("v128.5", client: client))
        #expect(panel.state.candidates.contains { $0.text.contains("壹佰贰拾捌元伍角整") })
        #expect(controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client))
        #expect(client.insertedText == "128.5")
    }

    // MARK: - 1.1.0 Wave 3 Tests: Granular Fuzzy Pinyin Rules
    @Test("FuzzyPinyinRules defaults, persistence, reset, and granular engine expansion")
    @MainActor
    func fuzzyPinyinRulesAndEngineBehavior() throws {
        // 1. Isolated UserDefaults persistence & reset
        let suiteName = "AetherKey.FuzzyRules." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let isolatedSettings = AetherSettings(defaults: defaults)
        // AetherKey 2.0.0: fuzzy pinyin is OFF by default.
        #expect(isolatedSettings.isFuzzyPinyinEnabled == false)
        #expect(isolatedSettings.fuzzyPinyinRules == .defaultRules)
        for expectedOn in [FuzzyPinyinRules.zhZ, .chC, .shS, .anAng, .enEng, .inIng, .ianIang, .uanUang] {
            #expect(isolatedSettings.fuzzyPinyinRules.contains(expectedOn))
        }
        for expectedOff in [FuzzyPinyinRules.lN, .fH, .rL] {
            #expect(!isolatedSettings.fuzzyPinyinRules.contains(expectedOff))
        }
        #expect(FuzzyPinyinRules.ruleMetadata.count == 11)

        isolatedSettings.fuzzyPinyinRules = [.lN, .fH]
        #expect(AetherSettings(defaults: defaults).fuzzyPinyinRules == [.lN, .fH])
        isolatedSettings.resetToDefaults()
        #expect(AetherSettings(defaults: defaults).fuzzyPinyinRules == .defaultRules)

        // 2. Engine fuzzy query behavior driven by AetherSettings.shared.fuzzyPinyinRules
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        defer { settings.resetToDefaults() }
        #expect(settings.isFuzzyPinyinEnabled == false)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let engine = PinyinEngine(userLexicon: UserLexicon(storageURL: tempURL))

        // 2.0.0 default: with fuzzy pinyin disabled, no fuzzy expansion happens at all.
        #expect(!engine.query(rawInput: "gongsi").prefix(4).contains { $0.text == "公示" })
        #expect(!engine.query(rawInput: "fangan").contains { $0.text == "返港" })

        // Explicitly enable fuzzy pinyin to exercise the granular rules.
        settings.isFuzzyPinyinEnabled = true

        // Default rules: l<->n, f<->h, r<->l are disabled; an<->ang is enabled
        #expect(!engine.query(rawInput: "lan").contains { $0.text == "南" })
        #expect(!engine.query(rawInput: "re").contains { $0.text == "乐" })
        #expect(engine.query(rawInput: "fangan").contains { $0.text == "返港" })

        // Enable .lN -> lan hits "南"
        settings.fuzzyPinyinRules.insert(.lN)
        #expect(engine.query(rawInput: "lan").contains { $0.text == "南" })

        // Enable .fH -> single-syllable top-4 fuzzy chars (fu->"护", hu->"服") and multi-syllable words (fuzhao->"护照", hujian->"福建")
        settings.fuzzyPinyinRules.insert(.fH)
        #expect(engine.query(rawInput: "fu").contains { $0.text == "护" })
        #expect(engine.query(rawInput: "hu").contains { $0.text == "服" })
        #expect(engine.query(rawInput: "fuzhao").contains { $0.text == "护照" })
        #expect(engine.query(rawInput: "hujian").contains { $0.text == "福建" })

        // Enable .rL -> re hits "乐" and luren hits "如人"
        settings.fuzzyPinyinRules.insert(.rL)
        #expect(engine.query(rawInput: "re").contains { $0.text == "乐" })
        #expect(engine.query(rawInput: "luren").contains { $0.text == "如人" })

        // Disable .anAng -> fangan no longer expands via an<->ang
        settings.fuzzyPinyinRules.remove(.anAng)
        #expect(!engine.query(rawInput: "fangan").contains { $0.text == "返港" })
    }

    // MARK: - 1.1.0 Wave 3 Tests: ZRM & Sogou Double Pinyin + Keymaps
    @Test("ZRM and Sogou Double Pinyin round-trip all mapped syllables and expose complete keymaps")
    @MainActor
    func zrmAndSogouDoublePinyinAndKeymaps() {
        for scheme in [PinyinScheme.zrm, .sogou] {
            var coveredCount = 0
            for syllable in PinyinLexicon.syllablesChars.keys.sorted() {
                let codes = DoublePinyin.codes(for: syllable, scheme: scheme)
                if !codes.isEmpty { coveredCount += 1 }
                for code in codes {
                    let readings = DoublePinyin.tokens(code, scheme: scheme)?.first?.readings ?? []
                    #expect(readings.contains(syllable), "\(scheme): \(syllable) -> \(code) -> \(readings)")
                }
            }
            #expect(coveredCount >= 422)
        }

        // ZRM specific encodings
        #expect(DoublePinyin.query("nihk", scheme: .zrm).contains { $0.text == "你好" })
        #expect(DoublePinyin.query("vsgo", scheme: .zrm).contains { $0.text == "中国" })
        #expect(DoublePinyin.query("py", scheme: .zrm).contains { $0.text == "平" })
        #expect(DoublePinyin.query("nv", scheme: .zrm).contains { $0.text == "女" })
        #expect(DoublePinyin.query("aa", scheme: .zrm).contains { $0.text == "啊" })
        #expect(DoublePinyin.reading("ah", scheme: .zrm) == "ang")
        #expect(DoublePinyin.query("ah", scheme: .zrm).contains { $0.text == "昂" })

        // Sogou specific encodings
        #expect(DoublePinyin.query("nihk", scheme: .sogou).contains { $0.text == "你好" })
        #expect(DoublePinyin.query("vsgo", scheme: .sogou).contains { $0.text == "中国" })
        #expect(DoublePinyin.query("p;", scheme: .sogou).contains { $0.text == "平" })
        #expect(DoublePinyin.query("ny", scheme: .sogou).contains { $0.text == "女" })
        #expect(DoublePinyin.query("oa", scheme: .sogou).contains { $0.text == "啊" })
        #expect(DoublePinyin.reading("oh", scheme: .sogou) == "ang")
        #expect(DoublePinyin.query("oh", scheme: .sogou).contains { $0.text == "昂" })

        // Keymap rows verification
        let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init))
        for scheme in [PinyinScheme.flypy, .microsoft, .zrm, .sogou] {
            let rows = DoublePinyin.keymapRows(for: scheme)
            #expect(rows.count == 3)
            let keys = Set(rows.flatMap { $0 }.map(\.key))
            #expect(alphabet.isSubset(of: keys))
            if scheme == .microsoft || scheme == .sogou {
                #expect(rows[1].map(\.key).contains(";"))
            } else {
                #expect(!keys.contains(";"))
            }
        }
        #expect(DoublePinyin.keymapRows(for: .full).isEmpty)
        #expect(DoublePinyin.keymapRows(for: .wubi86).isEmpty)

        // Sogou controller end-to-end (both handle and inputText) for p; -> 平
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        defer { settings.resetToDefaults() }
        settings.pinyinScheme = .sogou

        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: client)!
        #expect(controller.handle(makeKeyEvent(char: "p", keyCode: 35), client: client))
        #expect(controller.handle(makeKeyEvent(char: ";", keyCode: 41), client: client))
        #expect(client.markedText == "p;")
        #expect(controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client))
        #expect(client.insertedText == "平")
        UserLexicon.shared.rollbackCommit(pinyin: "ping", word: "平")

        client.reset()
        #expect(controller.inputText("p;", client: client))
        #expect(client.markedText == "p;")
        #expect(controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client))
        #expect(client.insertedText == "平")
        UserLexicon.shared.rollbackCommit(pinyin: "ping", word: "平")
    }

    // MARK: - 1.1.0 Wave 3 Tests: Per-App Auto English/Chinese Rules & Priorities
    @Test("ContextDetector and AetherSettings support per-app rules while Shift manual toggle retains highest priority")
    @MainActor
    func perAppAutoInputModePersistenceAndPrecedence() async throws {
        let detector = ContextDetector.shared
        #expect(detector.isTerminalApp(bundleIdentifier: "com.apple.dt.Xcode") == true)
        #expect(detector.isTerminalApp(bundleIdentifier: "com.todesktop.230313mzl4w4u92") == true)
        #expect(detector.isTerminalApp(bundleIdentifier: "dev.zed.Zed") == true)
        #expect(detector.isTerminalApp(bundleIdentifier: "com.jetbrains.intellij") == false)

        // 1. Persistence in isolated UserDefaults
        let suiteName = "AetherKey.AppModeRules." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let isolated = AetherSettings(defaults: defaults)
        isolated.setAppDefaultMode(.english, for: "com.jetbrains.intellij")
        isolated.setAppDefaultMode(.chinese, for: "com.apple.Terminal")
        let reloaded = AetherSettings(defaults: defaults)
        #expect(reloaded.appDefaultMode(for: "com.jetbrains.intellij") == .english)
        #expect(reloaded.appDefaultMode(for: "com.apple.Terminal") == .chinese)
        #expect(detector.resolvedDefaultMode(for: "com.jetbrains.intellij", settings: reloaded) == .english)
        #expect(detector.resolvedDefaultMode(for: "com.apple.Terminal", settings: reloaded) == .chinese)

        reloaded.resetToDefaults()
        #expect(AetherSettings(defaults: defaults).customAppDefaultModes.isEmpty)

        // 2. Controller integration on shared settings
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        defer { settings.resetToDefaults() }

        settings.setAppDefaultMode(.english, for: "com.jetbrains.intellij")
        settings.setAppDefaultMode(.chinese, for: "com.apple.Terminal")

        let ideaClient = MockTextInputClient()
        ideaClient.mockBundleIdentifier = "com.jetbrains.intellij"
        ideaClient.mockUniqueID = "idea-\(UUID().uuidString)"
        let controller = AetherInputController(server: nil, delegate: nil, client: ideaClient)!
        controller.activateServer(ideaClient)
        #expect(!controller.handle(makeKeyEvent(char: "a", keyCode: 0), client: ideaClient))

        let terminalClient = MockTextInputClient()
        terminalClient.mockBundleIdentifier = "com.apple.Terminal"
        terminalClient.mockUniqueID = "terminal-\(UUID().uuidString)"
        controller.activateServer(terminalClient)
        #expect(controller.handle(makeKeyEvent(char: "n", keyCode: 45), client: terminalClient))
        controller.resetComposition(client: terminalClient)

        // 3. Session Shift single-tap manual override takes priority over custom app default rule
        let customBundle = "test.intellij.manual.\(UUID().uuidString)"
        settings.setAppDefaultMode(.english, for: customBundle)
        let customClient = MockTextInputClient()
        customClient.mockBundleIdentifier = customBundle
        customClient.mockUniqueID = "custom-\(UUID().uuidString)"
        controller.activateServer(customClient)
        #expect(!controller.handle(makeKeyEvent(char: "a", keyCode: 0), client: customClient))

        _ = controller.handle(makeFlagsEvent(modifiers: [.shift]), client: customClient)
        try await Task.sleep(for: .milliseconds(35))
        _ = controller.handle(makeFlagsEvent(modifiers: []), client: customClient)
        #expect(controller.handle(makeKeyEvent(char: "n", keyCode: 45), client: customClient))
        controller.resetComposition(client: customClient)

        // Switching away and back preserves the manual Chinese choice over the app's default English rule
        let neutralClient = MockTextInputClient()
        neutralClient.mockBundleIdentifier = "test.neutral.\(UUID().uuidString)"
        controller.activateServer(neutralClient)
        controller.activateServer(customClient)
        #expect(controller.handle(makeKeyEvent(char: "n", keyCode: 45), client: customClient))
        controller.resetComposition(client: customClient)
    }

    // MARK: - 1.1.0 Wave 3 Tests: Vertical Layout, Dynamic Font Size, Traditional Badge & Page Size
    @Test("Vertical candidate layout, dynamic font sizes, fittingSize parity, and Traditional badge work consistently")
    @MainActor
    func verticalLayoutFontSizeFittingSizeAndTraditionalBadge() {
        let candidates5 = ["你好", "世界", "竖排", "测试", "候选"].map { Candidate(text: $0) }
        let candidates2 = ["你好", "世界"].map { Candidate(text: $0) }

        // Default 15pt horizontal row height & panel height remain unchanged
        #expect(CandidatePanelMetrics.rowHeight(for: 15) == 30)
        #expect(CandidatePanelMetrics.height(for: .paging) == 68.5)

        // Vertical height grows monotonically with candidate count and font size
        let h2 = CandidatePanelMetrics.height(for: .paging, orientation: .vertical, candidateCount: 2, fontSize: 15)
        let h5 = CandidatePanelMetrics.height(for: .paging, orientation: .vertical, candidateCount: 5, fontSize: 15)
        #expect(h5 > h2)

        var previousHeight: CGFloat = 0
        var previousRowHeight: CGFloat = 0
        for size: CGFloat in [14, 15, 17, 19] {
            let rowH = CandidatePanelMetrics.rowHeight(for: size)
            let measuredW = CandidatePanelMetrics.contentWidth(
                candidates: candidates5, viewMode: .paging, pinyin: "ni'hao",
                mode: .chinese, currentPage: 1, totalPages: 2,
                layoutOrientation: .vertical, fontSize: size
            )
            let measuredH = CandidatePanelMetrics.height(
                for: .paging, orientation: .vertical, candidateCount: candidates5.count, fontSize: size
            )
            #expect(rowH > previousRowHeight)
            #expect(measuredH > previousHeight)
            previousRowHeight = rowH
            previousHeight = measuredH

            let view = CandidateListView(
                inputString: "nihao", displayPinyin: "ni'hao", mode: .chinese, viewMode: .paging,
                candidates: candidates5, selectedIndex: 0, currentPage: 1, totalPages: 2,
                isTraditional: true, layoutOrientation: .vertical, fontSize: size
            )
            let fitting = NSHostingView(rootView: view).fittingSize
            #expect(abs(fitting.width - (measuredW + CandidatePanelMetrics.outerPadding * 2)) < 1)
            #expect(abs(fitting.height - measuredH) < 1)
        }

        // Local CandidatePanel frame height increases with candidate count and font size in vertical mode
        let localPanel = CandidatePanel()
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let caret = NSRect(x: screen.midX, y: screen.midY, width: 0, height: 22)
        localPanel.state.layoutOrientation = .vertical
        localPanel.state.fontSize = 15
        localPanel.state.candidates = candidates2
        localPanel.show(caretRect: caret)
        let panelH2 = localPanel.frame.height

        localPanel.state.candidates = candidates5
        localPanel.show(caretRect: caret)
        let panelH5 = localPanel.frame.height
        #expect(panelH5 > panelH2)

        var panelFontHeights: [CGFloat] = []
        for size: CGFloat in [14, 15, 17, 19] {
            localPanel.state.fontSize = size
            localPanel.show(caretRect: caret)
            panelFontHeights.append(localPanel.frame.height)
        }
        #expect(panelFontHeights[0] < panelFontHeights[1] && panelFontHeights[1] < panelFontHeights[2] && panelFontHeights[2] < panelFontHeights[3])
        localPanel.dismiss()

        // Controller integration: Traditional enabled updates CandidatePanelHolder.shared.state.isTraditional and view badge "繁"
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        defer { settings.resetToDefaults() }
        settings.isTraditionalChineseEnabled = true
        settings.candidateLayoutOrientation = .vertical

        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: client)!
        #expect(controller.inputText("toufa", client: client))
        let holder = CandidatePanelHolder.shared
        #expect(holder.state.isTraditional == true)
        #expect(holder.state.layoutOrientation == .vertical)

        let renderedListView = CandidateListView(
            inputString: holder.state.inputString,
            displayPinyin: holder.state.displayPinyin,
            mode: holder.state.mode,
            viewMode: holder.state.viewMode,
            candidates: holder.state.candidates,
            selectedIndex: holder.state.selectedIndex,
            currentPage: holder.state.currentPage,
            totalPages: holder.state.totalPages,
            isTraditional: holder.state.isTraditional,
            layoutOrientation: holder.state.layoutOrientation,
            fontSize: holder.state.fontSize
        )
        let viewTreeDump = String(reflecting: renderedListView.body)
        #expect(viewTreeDump.contains("繁"))
        controller.resetComposition(client: client)
    }

    @Test("Configurable candidatePageSize controls totalPages and digit selection without doubling in vertical scroll mode")
    @MainActor
    func candidatePageSizeAndVerticalScrollBehavior() throws {
        let suiteName = "AetherKey.PageSizeClamping." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let clamped = AetherSettings(defaults: defaults)
        clamped.candidatePageSize = 3
        #expect(clamped.candidatePageSize == 5)
        clamped.candidatePageSize = 12
        #expect(clamped.candidatePageSize == 9)
        clamped.candidateFontSize = 10
        #expect(clamped.candidateFontSize == 13)
        clamped.candidateFontSize = 30
        #expect(clamped.candidateFontSize == 22)

        let settings = AetherSettings.shared
        settings.resetToDefaults()
        defer { settings.resetToDefaults() }

        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: client)!
        let panel = CandidatePanelHolder.shared
        defer { controller.resetComposition(client: client) }

        // 1. Page size = 5
        settings.candidatePageSize = 5
        #expect(controller.inputText("shi", client: client))
        #expect(panel.state.candidates.count == 5)
        let totalPages5 = panel.state.totalPages
        #expect(controller.handle(makeKeyEvent(char: "=", keyCode: 24), client: client))
        let page2Fifth = try #require(panel.state.candidates.dropFirst(4).first?.text)
        #expect(controller.handle(makeKeyEvent(char: "5", keyCode: 23), client: client))
        #expect(client.insertedText == page2Fifth)
        UserLexicon.shared.rollbackCommit(pinyin: "shi", word: page2Fifth)

        // 2. Page size = 9
        client.reset()
        settings.candidatePageSize = 9
        #expect(controller.inputText("shi", client: client))
        #expect(panel.state.candidates.count == 9)
        #expect(panel.state.totalPages < totalPages5)
        let page1Ninth = try #require(panel.state.candidates.dropFirst(8).first?.text)
        #expect(controller.handle(makeKeyEvent(char: "9", keyCode: 25), client: client))
        #expect(client.insertedText == page1Ninth)
        UserLexicon.shared.rollbackCommit(pinyin: "shi", word: page1Ninth)

        // 3. Vertical mode + .scroll does NOT double pageSize
        client.reset()
        settings.candidatePageSize = 6
        settings.candidateLayoutOrientation = .vertical
        settings.defaultViewMode = .scroll
        #expect(controller.inputText("shi", client: client))
        #expect(panel.state.viewMode == .scroll)
        #expect(panel.state.candidates.count == 6)
        controller.resetComposition(client: client)

        // Contrast with horizontal .scroll which doubles 6 -> 12
        settings.candidateLayoutOrientation = .horizontal
        #expect(controller.inputText("shi", client: client))
        #expect(panel.state.candidates.count == 12)
        controller.resetComposition(client: client)
    }

    // MARK: - 1.1.0 Wave 3 Tests: Long Sentences, Secondary Homophones, 5-Syllable Prefix, New Typos, Rollbacks & Updater
    @Test("Engine composes 16+ syllable sentences, secondary homophones, 5-syllable partial prefixes, and zero-conflict typos")
    func longSentenceHomophonesFiveSyllablePrefixAndTypos() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let engine = PinyinEngine(userLexicon: UserLexicon(storageURL: tempURL))

        // 1. 16+ syllable long sentence composition
        let sentence17 = "jintiantianqizhenhaowomenyiqiquhangzhouxihuwanba"
        #expect(engine.segmentTokens(rawInput: sentence17).count == 17)
        let res17 = engine.query(rawInput: sentence17)
        #expect(res17.first?.text == "今天天气真好我们一起去杭州西湖玩吧")
        #expect(res17.first?.text.count == 17)

        let sentence16 = "womenjintianwanshangyiqiqubeijingchihuoguohaoma"
        #expect(engine.segmentTokens(rawInput: sentence16).count == 16)
        let res16 = engine.query(rawInput: sentence16)
        #expect(res16.first?.text == "我们今天晚上一起去北京吃火锅好吗")
        #expect(res16.first?.text.count == 16)
        #expect(res16.first?.consumedInputLength == sentence16.count)

        // 2. Secondary homophones preserved alongside top candidate
        let shanxi = engine.query(rawInput: "woqushanxi")
        #expect(shanxi.first?.text == "我去陕西")
        #expect(shanxi.contains { $0.text == "我去山西" })

        let shuijiao = engine.query(rawInput: "woxiangchishuijiao")
        #expect(shuijiao.contains { $0.text == "我想吃水饺" })

        let shijian = engine.query(rawInput: "zhegeshijian")
        #expect(shijian.contains { $0.text == "这个事件" })

        // 3. 5-syllable partial prefix candidate
        let fiveSyl = engine.query(rawInput: "weilaikejichengshangban")
        #expect(fiveSyl.contains { $0.text == "未来科技城" && $0.consumedInputLength == 15 })

        // 4. Zero-conflict typos
        for (typo, expected) in [
            ("womne", "我们"),
            ("zhne", "真"),
            ("yuo", "有"),
            ("jui", "就"),
            ("hau", "好")
        ] {
            #expect(engine.query(rawInput: typo).first?.text == expected, "Typo \(typo) did not rank \(expected) at #1")
        }
    }

    @Test("Cursor-0 Backspace keeps page & highlight, inputText quote Backspace rolls back pairing, and UpdateController initializes")
    @MainActor
    func cursorZeroBackspaceInputTextQuoteRollbackAndUpdateController() throws {
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        SmartPunctuation.shared.resetState()
        defer {
            settings.resetToDefaults()
            SmartPunctuation.shared.resetState()
        }

        let client = MockTextInputClient()
        let controller = AetherInputController(server: nil, delegate: nil, client: client)!
        let panel = CandidatePanelHolder.shared

        // 1. Backspace at cursor index 0 must NOT reset currentPage or selectedIndex
        #expect(controller.inputText("shi", client: client))
        #expect(controller.handle(makeKeyEvent(char: "=", keyCode: 24), client: client))
        #expect(controller.handle(makeKeyEvent(char: "", keyCode: 125), client: client))
        #expect(panel.state.currentPage == 2)
        #expect(panel.state.selectedIndex == 1)

        #expect(controller.handle(makeKeyEvent(char: "", keyCode: 115), client: client)) // Home -> cursor 0
        #expect(client.markedSelection.location == 0)
        #expect(controller.handle(makeKeyEvent(char: "\u{8}", keyCode: 51), client: client))
        #expect(client.markedText == "shi")
        #expect(panel.state.currentPage == 2)
        #expect(panel.state.selectedIndex == 1)

        #expect(controller.handle(makeKeyEvent(char: "\u{8}", keyCode: 51, modifiers: [.option]), client: client))
        #expect(client.markedText == "shi")
        #expect(panel.state.currentPage == 2)
        #expect(panel.state.selectedIndex == 1)
        controller.resetComposition(client: client)

        // 2. inputText smart quote '"' followed by Backspace rolls back quote pairing state
        client.reset()
        #expect(controller.inputText("\"", client: client))
        #expect(client.insertedText == "“")
        client.insertedText = ""
        _ = controller.handle(makeKeyEvent(char: "\u{7F}", keyCode: 51), client: client)
        #expect(controller.inputText("\"", client: client))
        #expect(client.insertedText == "“")

        // 3. UpdateController starts cleanly with 6-hour default check interval and ready updater
        let updater = UpdateController.shared
        #expect(UpdateController.checkInterval == 21_600)
        updater.start()
        #expect(updater.canCheckForUpdates)
    }
}

// MARK: - AetherKey 2.0.0 Regression & Feature Test Suite
//
// These tests live inside the serialized `CompositionEditingTests` suite so they never race with
// other tests that mutate `AetherSettings.shared`. Every engine assertion runs on an isolated
// `UserLexicon` backed by a temporary file, and every settings mutation is reverted via
// `defer { settings.resetToDefaults() }`.

private func v2TempURL(_ name: String = "json") -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("aetherkey-v2-test-\(UUID().uuidString).\(name)")
}

/// Fresh engine with an empty, isolated user lexicon (never touches the shared learned lexicon).
private func v2Engine() -> PinyinEngine {
    PinyinEngine(userLexicon: UserLexicon(storageURL: v2TempURL()))
}

private func v2Top(_ engine: PinyinEngine, _ input: String, _ count: Int = 10) -> [String] {
    Array(engine.query(rawInput: input).prefix(count).map(\.text))
}

@MainActor
private func v2Controller(scheme: PinyinScheme = .full) -> (AetherInputController, MockTextInputClient) {
    AetherSettings.shared.pinyinScheme = scheme
    let client = MockTextInputClient()
    client.mockBundleIdentifier = "test.v2.\(UUID().uuidString)"
    client.mockUniqueID = "v2-\(UUID().uuidString)"
    let controller = AetherInputController(server: nil, delegate: nil, client: client)!
    controller.activateServer(client)
    return (controller, client)
}

@MainActor
private func v2Type(_ text: String, _ controller: AetherInputController, _ client: MockTextInputClient) {
    for char in text {
        let code: UInt16 = char == ";" ? 41 : 0
        _ = controller.handle(makeKeyEvent(char: String(char), keyCode: code), client: client)
    }
}

@MainActor
private func v2TapShift(_ controller: AetherInputController, _ client: MockTextInputClient, keyCode: UInt16) async throws {
    _ = controller.handle(makeFlagsEvent(modifiers: [.shift], keyCode: keyCode), client: client)
    try await Task.sleep(for: .milliseconds(35))
    _ = controller.handle(makeFlagsEvent(modifiers: [], keyCode: keyCode), client: client)
}

/// True when the controller currently treats plain letters as Chinese composition (not English pass-through).
@MainActor
private func v2IsChinese(_ controller: AetherInputController, _ client: MockTextInputClient) -> Bool {
    let handled = controller.handle(makeKeyEvent(char: "a", keyCode: 0), client: client)
    controller.resetComposition(client: client)
    client.reset()
    return handled
}

extension CompositionEditingTests {
    // MARK: a) Lexicon inversion & place override fixes
    @Test("2.0.0 (a): daily words outrank obscure place names and literary variants at #1")
    @MainActor
    func v2LexiconInversionAndPlaceOverrideFixes() {
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        defer { settings.resetToDefaults() }
        let engine = v2Engine()

        let firsts: [(String, String)] = [
            ("xianshi", "显示"), ("yiyang", "一样"), ("kending", "肯定"), ("xiangxi", "详细"),
            ("xingqi", "星期"), ("shiyan", "实验"), ("dali", "大力"), ("weihai", "危害"),
            ("yiwu", "义务"), ("weibo", "微博"), ("jingdong", "京东"), ("dingding", "钉钉"),
            ("xiecheng", "携程"), ("jiekou", "接口"), ("yige", "一个")
        ]
        for (input, expected) in firsts {
            let top = v2Top(engine, input)
            #expect(top.first == expected, "\(input) top: \(top)")
        }

        // `yichang`: 一场 / 异常 own the top two slots; the city 宜昌 must not be #1.
        let yichang = v2Top(engine, "yichang")
        #expect(yichang.prefix(2).contains("一场") || yichang.prefix(2).contains("异常"), "yichang top: \(yichang)")
        #expect(yichang.first != "宜昌", "yichang top: \(yichang)")

        // The removed built-in phrase `一首歌` must not hide behind `yige`.
        #expect(!v2Top(engine, "yige", 5).contains("一首歌"))

        // Place names remain reachable (appended, never deleted).
        #expect(engine.query(rawInput: "xianshi").contains { $0.text == "西安市" })
        #expect(engine.query(rawInput: "yichang").contains { $0.text == "宜昌" })
        #expect(engine.query(rawInput: "dali").contains { $0.text == "大理" })

        // 2022–2026 modern vocabulary.
        let modern: [(String, String)] = [
            ("pinduoduo", "拼多多"), ("gaode", "高德"), ("bawangchaji", "霸王茶姬"),
            ("gongzuoliu", "工作流"), ("tishici", "提示词"), ("zhishiku", "知识库"),
            ("zhinengti", "智能体"), ("feishu", "飞书"), ("doubao", "豆包")
        ]
        for (input, expected) in modern {
            let top = v2Top(engine, input)
            #expect(top.first == expected, "\(input) top: \(top)")
        }
    }

    // MARK: b) Single/double-syllable collision reachability
    @Test("2.0.0 (b): single characters stay #1 while colliding two-char phrases are reachable in the top 5")
    @MainActor
    func v2SingleDoubleSyllableCollisionReachability() {
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        defer { settings.resetToDefaults() }
        let engine = v2Engine()

        for (input, phrase) in [("xian", "西安"), ("qie", "企鹅"), ("tian", "提案"),
                                ("tuan", "图案"), ("yue", "余额"), ("jie", "饥饿")] {
            let top = v2Top(engine, input)
            let primary = PinyinLexicon.syllablesChars[input]?.first
            #expect(top.first?.count == 1, "\(input) #1 must be a single character: \(top)")
            #expect(top.first == primary, "\(input) #1 should be the primary character \(primary ?? "nil"): \(top)")
            #expect(top.prefix(5).contains(phrase), "\(phrase) must be reachable in top 5 of \(input): \(top)")
            // No apostrophe needed: the explicit split is still a valid separate path.
            #expect(!input.contains("'"))
        }
        #expect(v2Top(engine, "xian").first == "现")
    }

    // MARK: c) No Cartesian fake two-char phrases
    @Test("2.0.0 (c): first-syllable primary characters stay on page 1 instead of fake Cartesian pairs")
    @MainActor
    func v2NoCartesianFakeTwoCharPhrases() {
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        defer { settings.resetToDefaults() }
        let engine = v2Engine()

        for (input, primary) in [("women", "我"), ("shenme", "身"), ("ranhou", "然"),
                                 ("keneng", "可"), ("fasong", "发")] {
            let rows = engine.query(rawInput: input)
            let top7 = Array(rows.prefix(7).map(\.text))
            #expect(top7.contains(primary), "\(input) page 1 must contain \(primary): \(top7)")
            // Nonsense `c1 × c2` pairs must not flood the list: at most one pure-fallback 2-char non-dictionary pair.
            let syllables = engine.segmentTokens(rawInput: input).count
            let twoCharRows = rows.prefix(10).filter { $0.text.count == syllables && $0.consumedInputLength == input.count }
            #expect(twoCharRows.count <= 6, "\(input) too many full-length pairs on top 10: \(rows.prefix(10).map(\.text))")
        }
    }

    // MARK: d) Single-char ranking & archaic reading demotion
    @Test("2.0.0 (d): colloquial single characters and abbreviations rank first; archaic readings are demoted")
    @MainActor
    func v2SingleCharRankingAndArchaicDemotion() throws {
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        defer { settings.resetToDefaults() }
        let engine = v2Engine()

        for (input, expected) in [("ma", "吗"), ("e", "额"), ("wang", "王"), ("sh", "是"),
                                  ("wd", "我的"), ("yw", "因为"), ("js", "就是")] {
            let top = v2Top(engine, input)
            #expect(top.first == expected, "\(input) top: \(top)")
        }

        let neng = v2Top(engine, "neng", 3)
        #expect(neng.contains("能"), "neng top3: \(neng)")
        #expect(!neng.contains("而"), "neng top3: \(neng)")
        #expect(!neng.contains("耐"), "neng top3: \(neng)")

        // Re-ranking never drops a syllable or a Unihan character.
        let url = try #require(Bundle.main.url(forResource: "characters", withExtension: "json"))
        let rows = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
        #expect(rows.count == 426)
        #expect(Set(rows.values.flatMap { $0.unicodeScalars.map(\.value) }).count == 44_359)
        // Archaic readings live in the tail of their syllable.
        for (syllable, archaic) in [("neng", "而"), ("neng", "耐"), ("de", "登"), ("wo", "夭")] {
            if let chars = rows[syllable], let index = chars.firstIndex(of: Character(archaic)) {
                let offset = chars.distance(from: chars.startIndex, to: index)
                #expect(offset >= 3, "\(archaic) must be demoted in \(syllable) (offset \(offset))")
            }
        }
    }

    // MARK: e) Lattice + Bigram hard sentences
    @Test("2.0.0 (e): lattice + bigram decoding lands all 12 hard sentences at #1")
    @MainActor
    func v2LatticeBigramHardSentences() {
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        defer { settings.resetToDefaults() }
        let engine = v2Engine()

        let sentences: [(String, String)] = [
            ("mingtianshixingqiyi", "明天是星期一"),
            ("qingshurunidemima", "请输入你的密码"),
            ("nikanxiayoumeiyouwenti", "你看下有没有问题"),
            ("nishizaijiama", "你是在家吗"),
            ("wogangdaogongsi", "我刚到公司"),
            ("woxiangchishuijiao", "我想吃水饺"),
            ("woquxian", "我去西安"),
            ("womingtianquxianshangban", "我明天去西安上班"),
            ("xianshiyixia", "显示一下"),
            ("gongzuoyichang", "工作异常"),
            ("wodekendingmeiwenti", "我的肯定没问题"),
            ("woyihuirjiudao", "我一会儿就到")
        ]
        for (input, expected) in sentences {
            let top = v2Top(engine, input, 4)
            #expect(top.first == expected, "\(input) top: \(top)")
        }
        // Erhua suffixes resolve cleanly without letting consonant mashing through.
        for (input, expected) in [("yihuir", "一会儿"), ("yidianr", "一点儿"), ("meishir", "没事儿"),
                                  ("haowanr", "好玩儿"), ("zher", "这儿"), ("nar", "那儿")] {
            let top = v2Top(engine, input, 4)
            #expect(top.first == expected, "\(input) top: \(top)")
        }
    }

    // MARK: f) English & mixed Chinese-English input
    @Test("2.0.0 (f): high-frequency English terms and mixed Chinese-English phrases surface automatically")
    @MainActor
    func v2EnglishAndMixedInput() {
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        defer { settings.resetToDefaults() }
        #expect(settings.isEnglishMixEnabled)
        let engine = v2Engine()

        // `preferFirst` terms rank #1 with canonical casing.
        for (input, canonical) in [("ok", "OK"), ("app", "App"), ("api", "API"), ("ppt", "PPT"),
                                   ("pdf", "PDF"), ("deepseek", "DeepSeek"), ("chatgpt", "ChatGPT")] {
            let top = v2Top(engine, input, 3)
            #expect(top.first == canonical, "\(input) top3: \(top)")
        }
        // Terms that collide with core Chinese words only need to stay in the top 3.
        let bug = v2Top(engine, "bug", 3)
        #expect(bug.contains { $0.lowercased() == "bug" }, "bug top3: \(bug)")

        // Mixed segments.
        for (input, expected) in [("wodebug", "我的 bug"), ("kanppt", "看 PPT"), ("yongai", "用 AI"),
                                  ("yonggpt", "用 GPT"), ("bzhan", "B站")] {
            let top = v2Top(engine, input, 2)
            #expect(top.contains(expected), "\(input) top2: \(top)")
        }

        // Disabling the setting suppresses automatic English / mixed promotion.
        settings.isEnglishMixEnabled = false
        for (input, promoted) in [("ok", "OK"), ("app", "App"), ("api", "API"), ("deepseek", "DeepSeek"),
                                  ("wodebug", "我的 bug"), ("kanppt", "看 PPT"), ("yongai", "用 AI"),
                                  ("bzhan", "B站")] {
            let top = v2Top(engine, input, 10)
            #expect(!top.contains(promoted), "\(input) must not promote \(promoted) when mix is off: \(top)")
        }
        settings.isEnglishMixEnabled = true
        #expect(v2Top(engine, "kanppt", 2).contains("看 PPT"))
    }

    // MARK: g) U-mode radical decomposition
    @Test("2.0.0 (g): u-mode decomposes radicals in Full Pinyin and never triggers in Double Pinyin")
    @MainActor
    func v2UModeRadicalDecomposition() {
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        defer { settings.resetToDefaults() }

        let cases: [(String, String)] = [("uhuohuo", "炎"), ("umumumu", "森"), ("uriyue", "明"), ("uniuniuniu", "犇")]
        for (input, expected) in cases {
            #expect(UModeChaiziEngine.shared.query(input).first?.text == expected, "\(input)")
        }
        // Parts must be typed after the `u` trigger; a bare `u` is not a query.
        #expect(UModeChaiziEngine.shared.query("u").isEmpty)

        // End-to-end through the real controller in Full Pinyin.
        let panel = CandidatePanelHolder.shared
        for (input, expected) in cases {
            let (controller, client) = v2Controller(scheme: .full)
            v2Type(input, controller, client)
            #expect(panel.state.mode == .uMode, "\(input) mode: \(panel.state.mode)")
            #expect(panel.state.candidates.first?.text == expected, "\(input) candidates: \(panel.state.candidates.map(\.text))")
            _ = controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client)
            #expect(client.insertedText == expected)
            // Composition ends: u-mode is reset back to Chinese.
            v2Type("ni", controller, client)
            #expect(panel.state.mode == .chinese)
            controller.resetComposition(client: client)
        }

        // Double Pinyin: `u` is the `sh` initial, so `u` + final must stay a normal pinyin composition.
        for scheme in [PinyinScheme.flypy, .microsoft] {
            let (controller, client) = v2Controller(scheme: scheme)
            v2Type("u", controller, client)
            #expect(panel.state.mode != .uMode, "\(scheme): lone u")
            v2Type("i", controller, client)   // u + i -> sh + i = shi
            #expect(panel.state.mode != .uMode, "\(scheme): ui entered uMode")
            #expect(panel.state.candidates.contains { $0.text == "是" }, "\(scheme) ui: \(panel.state.candidates.map(\.text))")
            controller.resetComposition(client: client)
            v2Type("uh", controller, client)
            #expect(panel.state.mode != .uMode, "\(scheme): uh entered uMode")
            controller.resetComposition(client: client)
        }
    }

    // MARK: h) SmartPunctuation URL/email/path & auto-pair + paired Backspace
    @Test("2.0.0 (h): SmartPunctuation keeps half-width punctuation inside URLs, emails and identifiers")
    func v2SmartPunctuationContext() {
        let punct = SmartPunctuation.shared
        punct.resetState()
        defer { punct.resetState() }
        #expect(punct.convertWithContext(char: ".", precedingText: "github", autoPairEnabled: true).text == ".")
        #expect(punct.convertWithContext(char: ":", precedingText: "https", autoPairEnabled: true).text == ":")
        #expect(punct.convertWithContext(char: "/", precedingText: "https:", autoPairEnabled: true).text == "/")
        #expect(punct.convertWithContext(char: "/", precedingText: "https:/", autoPairEnabled: true).text == "/")
        #expect(punct.convertWithContext(char: ".", precedingText: "a@b", autoPairEnabled: true).text == ".")
        #expect(punct.convertWithContext(char: "_", precedingText: "foo", autoPairEnabled: true).text == "_")
        #expect(punct.convertWithContext(char: "@", precedingText: "name", autoPairEnabled: true).text == "@")
        // Digits keep decimal points / time colons.
        #expect(punct.convertWithContext(char: ".", precedingText: "3", autoPairEnabled: true).text == ".")
        #expect(punct.convertWithContext(char: ":", precedingText: "12", autoPairEnabled: true).text == ":")
        // Ordinary Chinese context still converts.
        #expect(punct.convertWithContext(char: ".", precedingText: "你好", autoPairEnabled: true).text == "。")
        #expect(punct.convertWithContext(char: ",", precedingText: "hello", autoPairEnabled: true).text == "，")
        #expect(punct.convertWithContext(char: "_", precedingText: "", autoPairEnabled: false).text == "——")

        // Auto-pair table.
        for (open, pair, close) in [("(", "（）", "）"), ("[", "【】", "】"), ("{", "「」", "」"),
                                    ("<", "《》", "》"), ("\"", "“”", "”"), ("'", "‘’", "’")] {
            let output = punct.convertWithContext(char: Character(open), precedingText: "", autoPairEnabled: true)
            #expect(output.text == pair)
            #expect(output.cursorBackOffset == 1)
            #expect(output.autoPairedCloseChar == Character(close))
        }
        let off = punct.convertWithContext(char: "(", precedingText: "", autoPairEnabled: false)
        #expect(off == PunctuationOutput(text: "（", cursorBackOffset: 0, autoPairedCloseChar: nil))
    }

    @Test("2.0.0 (h): auto-paired punctuation moves the caret back and Backspace deletes the pair together")
    @MainActor
    func v2AutoPairPunctuationAndPairedBackspace() {
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        defer { settings.resetToDefaults(); SmartPunctuation.shared.resetState() }
        settings.isSmartPunctuationEnabled = true
        settings.isEnglishPunctuationEnabled = false
        settings.isAutoPairPunctuationEnabled = true
        let open = makeKeyEvent(char: "(", keyCode: 25, modifiers: [.shift])

        // 1. Happy path: inserts （） once, backtracks once, immediate Backspace forward-deletes once.
        do {
            let (controller, client) = v2Controller()
            var backtracks = 0, forwardDeletes = 0
            controller.caretBacktrackHandler = { backtracks += 1; return true }
            controller.forwardDeleteHandler = { forwardDeletes += 1; return true }
            _ = controller.handle(open, client: client)
            #expect(client.insertedText == "（）")
            #expect(backtracks == 1)
            #expect(forwardDeletes == 0)
            _ = controller.handle(makeKeyEvent(char: "\u{7F}", keyCode: 51), client: client)
            #expect(forwardDeletes == 1)
            // A second Backspace is an ordinary delete: no further paired delete.
            _ = controller.handle(makeKeyEvent(char: "\u{7F}", keyCode: 51), client: client)
            #expect(forwardDeletes == 1)
        }

        // 2. Typing anything between the pair cancels the paired Backspace.
        do {
            let (controller, client) = v2Controller()
            var backtracks = 0, forwardDeletes = 0
            controller.caretBacktrackHandler = { backtracks += 1; return true }
            controller.forwardDeleteHandler = { forwardDeletes += 1; return true }
            _ = controller.handle(open, client: client)
            _ = controller.handle(makeKeyEvent(char: "1", keyCode: 18), client: client)
            _ = controller.handle(makeKeyEvent(char: "\u{7F}", keyCode: 51), client: client)
            #expect(backtracks == 1)
            #expect(forwardDeletes == 0)
        }

        // 3. Safe fallback: when the host rejects the backtrack, no paired delete may ever fire.
        do {
            let (controller, client) = v2Controller()
            var backtracks = 0, forwardDeletes = 0
            controller.caretBacktrackHandler = { backtracks += 1; return false }
            controller.forwardDeleteHandler = { forwardDeletes += 1; return true }
            _ = controller.handle(open, client: client)
            #expect(backtracks == 1)
            #expect(client.insertedText.hasPrefix("（"))
            _ = controller.handle(makeKeyEvent(char: "\u{7F}", keyCode: 51), client: client)
            #expect(forwardDeletes == 0)
        }

        // 4. Setting off: plain full-width bracket, no backtrack, no paired delete.
        do {
            settings.isAutoPairPunctuationEnabled = false
            let (controller, client) = v2Controller()
            var backtracks = 0, forwardDeletes = 0
            controller.caretBacktrackHandler = { backtracks += 1; return true }
            controller.forwardDeleteHandler = { forwardDeletes += 1; return true }
            _ = controller.handle(open, client: client)
            #expect(client.insertedText == "（")
            #expect(backtracks == 0)
            _ = controller.handle(makeKeyEvent(char: "\u{7F}", keyCode: 51), client: client)
            #expect(forwardDeletes == 0)
        }

        // 5. English punctuation mode never auto-pairs.
        do {
            settings.isAutoPairPunctuationEnabled = true
            settings.isEnglishPunctuationEnabled = true
            let (controller, client) = v2Controller()
            var backtracks = 0
            controller.caretBacktrackHandler = { backtracks += 1; return true }
            _ = controller.handle(open, client: client)
            #expect(client.insertedText == "(")
            #expect(backtracks == 0)
        }
    }

    // MARK: i) Controller key customization
    @Test("2.0.0 (i): comma/period paging is opt-in")
    @MainActor
    func v2CommaPeriodPaging() {
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        defer { settings.resetToDefaults() }
        let panel = CandidatePanelHolder.shared
        #expect(settings.isCommaPeriodPagingEnabled == false)

        // Default (off): `,` / `.` commit the first candidate then the punctuation.
        do {
            let (controller, client) = v2Controller()
            v2Type("nihao", controller, client)
            let first = panel.state.candidates.first?.text ?? ""
            _ = controller.handle(makeKeyEvent(char: ",", keyCode: 43), client: client)
            #expect(client.insertedText == first + "，")
            #expect(client.markedText.isEmpty)
            client.reset()
            v2Type("nihao", controller, client)
            _ = controller.handle(makeKeyEvent(char: ".", keyCode: 47), client: client)
            #expect(client.insertedText.hasSuffix("。"))
            #expect(client.markedText.isEmpty)
        }

        // Empty buffer always types punctuation regardless of the setting.
        // Enabled: `,` / `.` page during composition.
        settings.isCommaPeriodPagingEnabled = true
        do {
            let (controller, client) = v2Controller()
            v2Type("ji", controller, client)
            #expect(panel.state.totalPages > 1)
            #expect(panel.state.currentPage == 1)
            _ = controller.handle(makeKeyEvent(char: ".", keyCode: 47), client: client)
            #expect(panel.state.currentPage == 2)
            #expect(client.insertedText.isEmpty)
            #expect(client.markedText == "ji")
            _ = controller.handle(makeKeyEvent(char: ",", keyCode: 43), client: client)
            #expect(panel.state.currentPage == 1)
            controller.resetComposition(client: client)
            // Idle (no composition): punctuation still types normally.
            #expect(controller.handle(makeKeyEvent(char: ",", keyCode: 43), client: client))
            #expect(client.insertedText == "，")
        }
    }

    @Test("2.0.0 (i): bracket keys page by default and extract characters with word-to-char")
    @MainActor
    func v2BracketKeyBehavior() {
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        defer { settings.resetToDefaults() }
        let panel = CandidatePanelHolder.shared
        #expect(settings.bracketKeyBehavior == .paging)

        // Default: paging.
        do {
            let (controller, client) = v2Controller()
            v2Type("ji", controller, client)
            _ = controller.handle(makeKeyEvent(char: "]", keyCode: 30), client: client)
            #expect(panel.state.currentPage == 2)
            #expect(client.insertedText.isEmpty)
            _ = controller.handle(makeKeyEvent(char: "[", keyCode: 33), client: client)
            #expect(panel.state.currentPage == 1)
            controller.resetComposition(client: client)
        }

        settings.bracketKeyBehavior = .wordToChar
        // `[` takes the first character, `]` the last character of a multi-char candidate.
        do {
            let (controller, client) = v2Controller()
            v2Type("nihao", controller, client)
            #expect(panel.state.candidates.first?.text == "你好")
            _ = controller.handle(makeKeyEvent(char: "[", keyCode: 33), client: client)
            #expect(client.insertedText == "你")
            #expect(client.markedText.isEmpty)
            client.reset()
            v2Type("nihao", controller, client)
            _ = controller.handle(makeKeyEvent(char: "]", keyCode: 30), client: client)
            #expect(client.insertedText == "好")
            #expect(client.markedText.isEmpty)
        }
        // Single-character candidates fall back to paging.
        do {
            let (controller, client) = v2Controller()
            v2Type("ma", controller, client)
            #expect(panel.state.candidates.first?.text.count == 1)
            _ = controller.handle(makeKeyEvent(char: "]", keyCode: 30), client: client)
            #expect(client.insertedText.isEmpty)
            #expect(panel.state.currentPage == 2)
            _ = controller.handle(makeKeyEvent(char: "[", keyCode: 33), client: client)
            #expect(panel.state.currentPage == 1)
            controller.resetComposition(client: client)
        }
    }

    @Test("2.0.0 (i): semicolon picks the second candidate but still works as the ing final in Microsoft / Sogou")
    @MainActor
    func v2SemicolonSecondCandidate() {
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        defer { settings.resetToDefaults() }
        let panel = CandidatePanelHolder.shared
        #expect(settings.isSemicolonSecondCandidateEnabled == false)

        // Default: `;` is ordinary punctuation after committing the first candidate.
        do {
            let (controller, client) = v2Controller()
            v2Type("nihao", controller, client)
            let first = panel.state.candidates.first?.text ?? ""
            _ = controller.handle(makeKeyEvent(char: ";", keyCode: 41), client: client)
            #expect(client.insertedText == first + "；")
        }

        settings.isSemicolonSecondCandidateEnabled = true
        do {
            let (controller, client) = v2Controller(scheme: .full)
            v2Type("nihao", controller, client)
            let second = try? #require(panel.state.candidates.dropFirst().first?.text)
            _ = controller.handle(makeKeyEvent(char: ";", keyCode: 41), client: client)
            #expect(client.insertedText == second, "inserted: \(client.insertedText)")
            #expect(client.markedText.isEmpty)
        }
        // Microsoft / Sogou: `p;` stays a pinyin composition (ing final), not a candidate commit.
        for scheme in [PinyinScheme.microsoft, .sogou] {
            let (controller, client) = v2Controller(scheme: scheme)
            v2Type("p;", controller, client)
            #expect(client.markedText == "p;", "\(scheme)")
            #expect(client.insertedText.isEmpty, "\(scheme)")
            _ = controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client)
            #expect(client.insertedText == "平", "\(scheme)")
            // After a complete syllable the `;` is a real second-candidate key again.
            client.reset()
            v2Type("nihk", controller, client)   // 你好 in both schemes
            let second = panel.state.candidates.dropFirst().first?.text
            _ = controller.handle(makeKeyEvent(char: ";", keyCode: 41), client: client)
            #expect(client.markedText.isEmpty || client.markedText.hasSuffix(";") || second != nil, "\(scheme)")
            controller.resetComposition(client: client)
        }
    }

    @Test("2.0.0 (i): shiftSwitchMode filters left/right Shift taps")
    @MainActor
    func v2ShiftSwitchMode() async throws {
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        defer { settings.resetToDefaults() }
        #expect(settings.shiftSwitchMode == .both)

        // (mode, left Shift (56) toggles?, right Shift (60) toggles?)
        let table: [(ShiftSwitchMode, Bool, Bool)] = [
            (.both, true, true), (.leftOnly, true, false), (.rightOnly, false, true), (.disabled, false, false)
        ]
        for (mode, leftToggles, rightToggles) in table {
            settings.shiftSwitchMode = mode
            for (keyCode, shouldToggle) in [(UInt16(56), leftToggles), (UInt16(60), rightToggles)] {
                let (controller, client) = v2Controller()
                #expect(v2IsChinese(controller, client))
                try await v2TapShift(controller, client, keyCode: keyCode)
                let stillChinese = v2IsChinese(controller, client)
                #expect(stillChinese == !shouldToggle, "mode \(mode) keyCode \(keyCode)")
            }
        }
    }

    @Test("2.0.0 (i): Caps Lock tap toggles Chinese / English only in toggleChineseEnglish mode")
    @MainActor
    func v2CapsLockSwitchMode() {
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        defer { settings.resetToDefaults() }
        #expect(settings.capsLockSwitchMode == .systemDefault)

        // System default: Caps Lock never toggles the input mode.
        do {
            let (controller, client) = v2Controller()
            _ = controller.handle(makeFlagsEvent(modifiers: [.capsLock], keyCode: 57), client: client)
            #expect(v2IsChinese(controller, client))
            _ = controller.handle(makeFlagsEvent(modifiers: [], keyCode: 57), client: client)
            #expect(v2IsChinese(controller, client))
        }

        settings.capsLockSwitchMode = .toggleChineseEnglish
        do {
            let (controller, client) = v2Controller()
            #expect(v2IsChinese(controller, client))
            _ = controller.handle(makeFlagsEvent(modifiers: [.capsLock], keyCode: 57), client: client)
            #expect(!v2IsChinese(controller, client))
            _ = controller.handle(makeFlagsEvent(modifiers: [], keyCode: 57), client: client)
            #expect(v2IsChinese(controller, client))
            // Other keyCodes (e.g. Shift 56) with caps flags must not be mistaken for Caps Lock.
            _ = controller.handle(makeFlagsEvent(modifiers: [.capsLock], keyCode: 56), client: client)
            #expect(v2IsChinese(controller, client))
            _ = controller.handle(makeFlagsEvent(modifiers: [], keyCode: 56), client: client)
        }
    }

    @Test("2.0.0 (i): switchToEnglishBufferAction decides what happens to the uncommitted code")
    @MainActor
    func v2SwitchToEnglishBufferAction() async throws {
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        defer { settings.resetToDefaults() }
        let panel = CandidatePanelHolder.shared
        #expect(settings.switchToEnglishBufferAction == .commitRaw)

        for action in [SwitchToEnglishBufferAction.commitRaw, .commitSelected, .clear] {
            settings.switchToEnglishBufferAction = action
            let (controller, client) = v2Controller()
            v2Type("nihao", controller, client)
            let selected = panel.state.candidates.first?.text ?? ""
            #expect(!selected.isEmpty)
            try await v2TapShift(controller, client, keyCode: 56)
            switch action {
            case .commitRaw:
                #expect(client.insertedText == "nihao")
            case .commitSelected:
                #expect(client.insertedText == selected)
            case .clear:
                #expect(client.insertedText.isEmpty)
            }
            #expect(client.markedText.isEmpty, "\(action)")
            // The mode really switched to English.
            #expect(!v2IsChinese(controller, client), "\(action)")
        }
    }

    // MARK: j) EmojiSuggestionStyle
    @Test("2.0.0 (j): emoji suggestion style .smartPhrase / .all / .off")
    @MainActor
    func v2EmojiSuggestionStyle() {
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        defer { settings.resetToDefaults() }
        let engine = v2Engine()
        #expect(settings.emojiSuggestionStyle == .smartPhrase)

        func emojiCount(_ input: String, _ limit: Int) -> Int {
            engine.query(rawInput: input).prefix(limit).filter(\.isEmoji).count
        }

        // .smartPhrase (default): single syllables never get emoji noise in the top 10; phrases keep one primary emoji.
        for input in ["ma", "you", "jiu", "xia", "ku", "gou"] {
            #expect(emojiCount(input, 10) == 0, "\(input): \(v2Top(engine, input))")
        }
        let nihao = v2Top(engine, "nihao", 6)
        let nihaoIndex = nihao.firstIndex(of: "你好")
        let ninIndex = nihao.firstIndex(of: "您好")
        let waveIndex = nihao.firstIndex(of: "👋")
        #expect(nihaoIndex == 0, "nihao: \(nihao)")
        #expect(ninIndex != nil && ninIndex! < (waveIndex ?? Int.max), "您好 must precede 👋: \(nihao)")
        #expect(engine.query(rawInput: "nihao").contains { $0.text == "👋" && $0.isEmoji }, "emoji must stay reachable")
        #expect(engine.query(rawInput: "ma").contains { $0.isEmoji }, "single-syllable emoji must stay reachable beyond the top 10")

        // .all: emoji interleaving is restored near the top.
        settings.emojiSuggestionStyle = .all
        for input in ["you", "ma", "nihao"] {
            let top = Array(engine.query(rawInput: input).prefix(5))
            let emojiIndexes = top.enumerated().filter { $0.element.isEmoji }.map(\.offset)
            #expect(emojiIndexes.contains { (1...3).contains($0) }, "\(input) .all emoji positions \(emojiIndexes): \(top.map(\.text))")
            #expect(top.first?.isEmoji == false, "\(input): \(top.map(\.text))")
        }

        // .off: zero emoji anywhere, but ordinary alternatives stay.
        settings.emojiSuggestionStyle = .off
        for input in ["meigui", "nihao", "woaini"] {
            #expect(emojiCount(input, 100) == 0, "\(input): \(v2Top(engine, input, 12))")
        }
        let woaini = v2Top(engine, "woaini", 4)
        #expect(woaini.first == "我爱你", "woaini: \(woaini)")
        #expect(woaini.contains("我爱妳"), "woaini: \(woaini)")

        // Round trip: switching back restores the smart default.
        settings.emojiSuggestionStyle = .smartPhrase
        #expect(emojiCount("ma", 10) == 0)
    }

    // MARK: k) Snippets, Clipboard History, Sync & ToolboxPanel
    @Test("2.0.0 (k): QuickSnippetStore add, pin, search, shortcut match, persistence, export and merge")
    func v2QuickSnippetStore() throws {
        let url = v2TempURL()
        let otherURL = v2TempURL()
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: otherURL) }
        let store = QuickSnippetStore(storageURL: url)
        #expect(store.items.isEmpty)

        let signature = store.add(title: "签名", content: "此致\n敬礼", shortcutCode: "QM")
        let address = store.add(title: "地址", content: "北京市海淀区中关村", shortcutCode: "dz")
        #expect(store.items.count == 2)
        #expect(signature.shortcutCode == "qm", "shortcut codes are normalized to lowercase")
        _ = store.add(title: "空内容", content: "")
        #expect(store.items.count == 2, "empty snippets are rejected")

        // Shortcut matching is exact and case-insensitive.
        #expect(store.matchedByShortcut("QM").map(\.id) == [signature.id])
        #expect(store.matchedByShortcut("dz").map(\.id) == [address.id])
        #expect(store.matchedByShortcut("q").isEmpty)
        #expect(store.matchedByShortcut("").isEmpty)

        // Search covers title, content and shortcut code.
        #expect(store.search("海淀").map(\.id) == [address.id])
        #expect(store.search("签名").map(\.id) == [signature.id])
        #expect(store.search("敬礼").map(\.id) == [signature.id])
        #expect(store.search("DZ").map(\.id) == [address.id])
        #expect(store.search("   ").count == 2)
        #expect(store.search("不存在的关键字").isEmpty)

        // Pinned snippets sort first.
        store.togglePin(id: address.id)
        #expect(store.items.first?.id == address.id)
        #expect(store.items.first?.isPinned == true)
        store.togglePin(id: address.id)
        #expect(store.items.allSatisfy { !$0.isPinned })
        store.togglePin(id: signature.id)
        #expect(store.items.first?.id == signature.id)

        // Update keeps identity.
        var edited = signature
        edited.title = "新签名"
        edited.content = "祝好"
        store.update(edited)
        #expect(store.items.first { $0.id == signature.id }?.title == "新签名")
        #expect(store.items.first { $0.id == signature.id }?.content == "祝好")

        // Persistence round trip.
        let reloaded = QuickSnippetStore(storageURL: url)
        #expect(reloaded.items.map(\.id) == store.items.map(\.id))
        #expect(reloaded.items.map(\.content) == store.items.map(\.content))

        // Export + merge into an empty store, idempotently.
        let data = try store.exportSnippetsData()
        let decoded = try JSONDecoder().decode([QuickSnippet].self, from: data)
        #expect(decoded.count == 2)
        let other = QuickSnippetStore(storageURL: otherURL)
        #expect(other.mergeSnippets(decoded) == 2)
        #expect(other.items.count == 2)
        #expect(other.mergeSnippets(decoded) == 0)
        #expect(other.items.count == 2)

        // Remove.
        store.remove(id: address.id)
        #expect(store.items.map(\.id) == [signature.id])
    }

    @Test("2.0.0 (k): ClipboardHistoryStore deduplicates, caps, pins and ignores sensitive pasteboards")
    @MainActor
    func v2ClipboardHistoryStore() throws {
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        defer { settings.resetToDefaults() }
        let url = v2TempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ClipboardHistoryStore(storageURL: url, maxItems: 3)

        store.recordText("a"); store.recordText("b"); store.recordText("a")
        store.recordText("   \n")
        #expect(store.items.map(\.text) == ["a", "b"], "duplicates move to the front, blanks are ignored")

        store.recordText("c"); store.recordText("d")
        #expect(store.items.map(\.text) == ["d", "c", "a"], "history is capped at maxItems")

        // Pinned entries survive trimming and keep their identity when re-copied.
        let pinned = try #require(store.items.first { $0.text == "a" })
        store.togglePin(id: pinned.id)
        store.recordText("e"); store.recordText("f"); store.recordText("g")
        #expect(store.items.count == 3)
        #expect(store.items.first?.text == "a" && store.items.first?.isPinned == true)
        store.recordText("a")
        #expect(store.items.first { $0.text == "a" }?.id == pinned.id)
        #expect(store.items.first { $0.text == "a" }?.isPinned == true)

        // Search & clear.
        #expect(store.search("g").map(\.text) == ["g"])
        store.clearUnpinned()
        #expect(store.items.map(\.text) == ["a"])
        let reloaded = ClipboardHistoryStore(storageURL: url, maxItems: 3)
        #expect(reloaded.items.map(\.text) == ["a"])
        store.clearAll()
        #expect(store.items.isEmpty)

        // Sensitive pasteboards (password managers, transient / auto-generated content) are always ignored.
        for identifier in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
                           "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword"] {
            let board = NSPasteboard(name: NSPasteboard.Name("aetherkey.test.\(UUID().uuidString)"))
            defer { board.releaseGlobally() }
            board.clearContents()
            board.declareTypes([.string, NSPasteboard.PasteboardType(identifier)], owner: nil)
            board.setString("top-secret-\(identifier)", forType: .string)
            #expect(ClipboardHistoryStore.isSensitivePasteboard(board), "\(identifier)")
            store.capturePasteboardIfNeeded(board)
            #expect(store.items.isEmpty, "\(identifier) must not be recorded")
        }

        // Ordinary text is captured exactly once per change.
        let plain = NSPasteboard(name: NSPasteboard.Name("aetherkey.test.\(UUID().uuidString)"))
        defer { plain.releaseGlobally() }
        plain.clearContents()
        plain.setString("ordinary copy", forType: .string)
        #expect(!ClipboardHistoryStore.isSensitivePasteboard(plain))
        store.capturePasteboardIfNeeded(plain)
        store.capturePasteboardIfNeeded(plain)
        #expect(store.items.map(\.text) == ["ordinary copy"])

        // Disabled history records nothing.
        settings.isClipboardHistoryEnabled = false
        plain.clearContents()
        plain.setString("while disabled", forType: .string)
        store.capturePasteboardIfNeeded(plain)
        #expect(store.items.map(\.text) == ["ordinary copy"])
    }

    @Test("2.0.0 (k): LexiconSyncManager merges two isolated devices through a temporary folder")
    func v2LexiconSyncManagerTwoWayMerge() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aetherkey-v2-sync-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let syncFolder = root.appendingPathComponent("cloud", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let lexiconA = UserLexicon(storageURL: root.appendingPathComponent("a-lexicon.json"))
        let snippetsA = QuickSnippetStore(storageURL: root.appendingPathComponent("a-snippets.json"))
        let lexiconB = UserLexicon(storageURL: root.appendingPathComponent("b-lexicon.json"))
        let snippetsB = QuickSnippetStore(storageURL: root.appendingPathComponent("b-snippets.json"))
        lexiconA.addCustomPhrase(pinyin: "tongbuci", phrase: "设备甲词条")
        snippetsA.add(title: "甲", content: "alpha body", shortcutCode: "aa")
        lexiconB.addCustomPhrase(pinyin: "tongbuci", phrase: "设备乙词条")
        snippetsB.add(title: "乙", content: "beta body", shortcutCode: "bb")

        let manager = LexiconSyncManager()
        let first = try manager.syncNow(lexicon: lexiconA, snippets: snippetsA, folderURL: syncFolder)
        #expect(first.syncedFolderURL == syncFolder)
        #expect(FileManager.default.fileExists(atPath: syncFolder.appendingPathComponent("user_lexicon.json").path))
        #expect(FileManager.default.fileExists(atPath: syncFolder.appendingPathComponent("snippets.json").path))
        #expect(manager.lastSyncAt != nil)
        #expect(!manager.lastSyncMessage.isEmpty)

        // Device B pulls A's data and pushes its own.
        let second = try manager.syncNow(lexicon: lexiconB, snippets: snippetsB, folderURL: syncFolder)
        #expect(second.mergedSnippets == 1)
        #expect(snippetsB.items.count == 2)
        #expect(Set(lexiconB.allCustomPhrases().map(\.phrase)) == ["设备甲词条", "设备乙词条"])

        // Device A syncs again and receives B's contributions.
        let third = try manager.syncNow(lexicon: lexiconA, snippets: snippetsA, folderURL: syncFolder)
        #expect(third.mergedSnippets == 1)
        #expect(Set(snippetsA.items.map(\.content)) == ["alpha body", "beta body"])
        #expect(Set(lexiconA.allCustomPhrases().map(\.phrase)) == ["设备甲词条", "设备乙词条"])

        // A third sync is a no-op merge and stable.
        _ = try manager.syncNow(lexicon: lexiconB, snippets: snippetsB, folderURL: syncFolder)
        #expect(snippetsB.items.count == 2)
        #expect(Set(lexiconB.allCustomPhrases().map(\.phrase)).count == 2)

        // A corrupt remote snippets file fails loudly and leaves local data intact.
        try Data("not json".utf8).write(to: syncFolder.appendingPathComponent("snippets.json"))
        #expect(throws: LexiconSyncManager.SyncError.invalidRemoteSnippetsFormat) {
            _ = try manager.syncNow(lexicon: lexiconA, snippets: snippetsA, folderURL: syncFolder)
        }
        #expect(snippetsA.items.count == 2)
    }

    @Test("2.0.0 (k): ToolboxPanelState filters rows, clamps selection and exposes row text")
    @MainActor
    func v2ToolboxPanelState() {
        let state = ToolboxPanelState()
        #expect(state.activeTab == .snippets)
        #expect(ToolboxTab.allCases.map(\.title) == ["常用语", "剪贴板", "符号与表情"])
        state.snippets = [
            ToolboxSnippetItem(id: UUID(), title: "签名", content: "此致敬礼", shortcutCode: "qm", isPinned: false),
            ToolboxSnippetItem(id: UUID(), title: "地址", content: "北京市海淀区", shortcutCode: "dz", isPinned: true)
        ]
        state.clipboardItems = [
            ToolboxClipboardItem(id: UUID(), text: "clip one", copiedAt: Date(), isPinned: false),
            ToolboxClipboardItem(id: UUID(), text: "clip two", copiedAt: Date(), isPinned: false),
            ToolboxClipboardItem(id: UUID(), text: "other", copiedAt: Date(), isPinned: false)
        ]
        #expect(state.currentRowCount == 2)
        #expect(state.textForRow(at: 1) == "北京市海淀区")
        #expect(state.textForRow(at: 2) == nil)
        state.searchQuery = "dz"
        #expect(state.filteredSnippets.map(\.title) == ["地址"])
        state.searchQuery = ""
        state.activeTab = .clipboard
        #expect(state.currentRowCount == 3)
        state.selectedIndex = 2
        state.searchQuery = "clip"
        #expect(state.currentRowCount == 2)
        #expect(state.selectedIndex == 0, "changing the query resets the selection")
        state.activeTab = .symbols
        #expect(ToolboxPanelState.symbolCategories.count >= 7)
        for category in ["常用标点", "序号", "数学", "箭头", "希腊", "颜文字", "常用 Emoji"] {
            #expect(ToolboxPanelState.symbolCategories.contains(category), "\(category)")
        }
        state.searchQuery = ""
        state.selectedSymbolCategory = "箭头"
        #expect(state.filteredSymbols.contains("→"))
        state.selectedSymbolCategory = "常用 Emoji"
        #expect(state.filteredSymbols.contains("👍"))
    }

    @Test("2.0.0 (k): vjb / vcy / vbq open the toolbox and ⌃⇧V / ⌃⇧E + Esc/↑/↓/Return/1-9 drive it")
    @MainActor
    func v2ToolboxControllerIntegration() {
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        // Never read the real system pasteboard from the toolbox refresh hook.
        settings.isClipboardHistoryEnabled = false
        let toolbox = ToolboxPanelHolder.shared
        defer { toolbox.dismiss(); settings.resetToDefaults() }
        toolbox.dismiss()
        let panel = CandidatePanelHolder.shared

        // V-mode keywords expose a top action candidate, and selecting it opens the matching tab.
        for (code, title, tab) in [("vjb", "打开剪贴板工具箱", ToolboxTab.clipboard),
                                   ("vcy", "打开常用语工具箱", .snippets),
                                   ("vbq", "打开符号与表情面板", .symbols)] {
            let (controller, client) = v2Controller()
            v2Type(code, controller, client)
            let top = panel.state.candidates.first
            #expect(top?.text == title, "\(code): \(panel.state.candidates.map(\.text))")
            #expect(top?.isVMode == true)
            _ = controller.handle(makeKeyEvent(char: " ", keyCode: 49), client: client)
            #expect(client.insertedText.isEmpty, "\(code) must not insert the action title")
            #expect(client.markedText.isEmpty)
            #expect(toolbox.state.isVisible, "\(code)")
            #expect(toolbox.state.activeTab == tab, "\(code)")
            toolbox.dismiss()
        }
        // Wubi does not own the v-mode toolbox shortcuts.
        do {
            let (controller, client) = v2Controller(scheme: .wubi86)
            v2Type("vjb", controller, client)
            #expect(!panel.state.candidates.contains { $0.text == "打开剪贴板工具箱" })
            controller.resetComposition(client: client)
        }

        // ⌃⇧E: symbols tab; navigation + commit.
        let (controller, client) = v2Controller()
        let symbolsKey = makeKeyEvent(char: "e", keyCode: 14, modifiers: [.control, .shift])
        #expect(controller.handle(symbolsKey, client: client))
        #expect(toolbox.state.isVisible)
        #expect(toolbox.state.activeTab == .symbols)
        let symbols = toolbox.state.filteredSymbols
        #expect(symbols.count >= 3)
        #expect(toolbox.state.selectedIndex == 0)
        #expect(controller.handle(makeKeyEvent(char: "", keyCode: 125), client: client))   // ↓
        #expect(toolbox.state.selectedIndex == 1)
        #expect(controller.handle(makeKeyEvent(char: "", keyCode: 125), client: client))
        #expect(toolbox.state.selectedIndex == 2)
        #expect(controller.handle(makeKeyEvent(char: "", keyCode: 126), client: client))   // ↑
        #expect(toolbox.state.selectedIndex == 1)
        #expect(controller.handle(makeKeyEvent(char: "\r", keyCode: 36), client: client))  // Return
        #expect(client.insertedText == symbols[1])
        #expect(!toolbox.state.isVisible)

        // Number keys commit the matching row.
        client.reset()
        #expect(controller.handle(symbolsKey, client: client))
        #expect(controller.handle(makeKeyEvent(char: "3", keyCode: 20), client: client))
        #expect(client.insertedText == symbols[2])
        #expect(!toolbox.state.isVisible)

        // Esc dismisses; pressing the shortcut again toggles it closed.
        client.reset()
        #expect(controller.handle(symbolsKey, client: client))
        #expect(toolbox.state.isVisible)
        #expect(controller.handle(makeKeyEvent(char: "\u{1B}", keyCode: 53), client: client))
        #expect(!toolbox.state.isVisible)
        #expect(controller.handle(symbolsKey, client: client))
        #expect(toolbox.state.isVisible)
        #expect(controller.handle(symbolsKey, client: client))
        #expect(!toolbox.state.isVisible)
        #expect(client.insertedText.isEmpty)

        // ⌃⇧V: clipboard tab, with the same toggle behaviour.
        let clipboardKey = makeKeyEvent(char: "v", keyCode: 9, modifiers: [.control, .shift])
        #expect(controller.handle(clipboardKey, client: client))
        #expect(toolbox.state.isVisible)
        #expect(toolbox.state.activeTab == .clipboard)
        #expect(controller.handle(makeKeyEvent(char: "\u{1B}", keyCode: 53), client: client))
        #expect(!toolbox.state.isVisible)
        // With the toolbox hidden, Esc is an ordinary key again.
        #expect(!controller.handle(makeKeyEvent(char: "\u{1B}", keyCode: 53), client: client))
    }

    // MARK: l) Double Pinyin mixed homophone tie-breaking
    @Test("2.0.0 (l): Double Pinyin layout collisions interleave readings by frequency instead of dumping one reading first")
    @MainActor
    func v2DoublePinyinMixedHomophoneTieBreaking() {
        let settings = AetherSettings.shared
        settings.resetToDefaults()
        defer { settings.resetToDefaults() }

        // Microsoft: `jv` decodes to `jue` (ue alias) while `jy` is the ü spelling of `ju`; neither may swallow the other.
        #expect(DoublePinyin.tokens("jv", scheme: .microsoft)?.first?.readings == ["jue"])
        let jv = DoublePinyin.query("jv", scheme: .microsoft).map(\.text)
        #expect(Array(jv.prefix(3)) == ["决", "绝", "觉"], "jv: \(jv.prefix(8))")
        let ju = DoublePinyin.query("jy", scheme: .microsoft).map(\.text)
        #expect(DoublePinyin.tokens("jy", scheme: .microsoft)?.first?.readings == ["ju"])
        for char in ["局", "具", "句"] {
            #expect(ju.prefix(12).contains(char), "jy must surface \(char): \(ju.prefix(12))")
        }
        #expect(!ju.prefix(12).contains("决"))

        // Genuine collisions: `lo` -> luo / lo, `lt` -> lve / lue in every double pinyin scheme.
        for scheme in [PinyinScheme.flypy, .microsoft, .zrm, .sogou] {
            #expect(Set(DoublePinyin.tokens("lo", scheme: scheme)?.first?.readings ?? []) == ["luo", "lo"], "\(scheme)")
            let lo = DoublePinyin.query("lo", scheme: scheme).map(\.text)
            #expect(Set(lo).count == lo.count, "\(scheme) duplicates")
            let top = Array(lo.prefix(6))
            // High-frequency `luo` characters lead, while the rarer `lo` reading is interleaved on screen one, not buried.
            #expect(top.contains("落") && top.contains("罗"), "\(scheme) lo: \(top)")
            #expect(top.contains("咯"), "\(scheme) lo must interleave the `lo` reading early: \(top)")
            #expect(lo.contains("洛") && lo.contains("萝"))

            #expect(Set(DoublePinyin.tokens("lt", scheme: scheme)?.first?.readings ?? []) == ["lve", "lue"], "\(scheme)")
            let lt = DoublePinyin.query("lt", scheme: scheme).map(\.text)
            #expect(lt.first == "略", "\(scheme) lt: \(lt.prefix(6))")
            #expect(lt.prefix(3).contains("掠"), "\(scheme) lt: \(lt.prefix(6))")
        }
    }
}
