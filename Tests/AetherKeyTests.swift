import Foundation
import Testing
import AppKit

@testable import AetherKey

@Suite("AetherKey Core Engine Test Suite")
struct AetherKeyEngineTests {
    
    @Test("Scenario 1: IMK Bundle Metadata & Chinese Language Categorization")
    func testBundleLanguageCategorization() {
        let currentFile = URL(fileURLWithPath: #filePath)
        let projectRoot = currentFile.deletingLastPathComponent().deletingLastPathComponent()
        let plistURL = projectRoot.appendingPathComponent("Resources/Info.plist")
        guard let plistData = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            Issue.record("Failed to read Resources/Info.plist at \(plistURL.path)")
            return
        }
        
        // 1. Language region
        #expect(plist["CFBundleDevelopmentRegion"] as? String == "zh-Hans")
        
        // 2. Character Repertoire must be Hans (Simplified Chinese)
        let repertoires = plist["tsInputMethodCharacterRepertoireKey"] as? [String]
        #expect(repertoires?.contains("Hans") == true)
        
        // 3. ComponentInputModeDict
        guard let modeDict = plist["ComponentInputModeDict"] as? [String: Any],
              let modeList = modeDict["tsInputModeListKey"] as? [String: Any],
              let hansMode = modeList["com.aethernative.inputmethod.AetherKey.Hans"] as? [String: Any] else {
            Issue.record("Missing com.aethernative.inputmethod.AetherKey.Hans in ComponentInputModeDict")
            return
        }
        
        #expect(hansMode["TISIntendedLanguage"] as? String == "zh-Hans")
        #expect(hansMode["TISInputSourceID"] as? String == "com.aethernative.inputmethod.AetherKey.Hans")
        #expect(hansMode["tsInputModeScriptKey"] as? String == "smUnicodeScript")
        
        // 4. Visible Modes Array
        let visibleModes = modeDict["tsVisibleInputModeOrderedArrayKey"] as? [String]
        #expect(visibleModes?.contains("com.aethernative.inputmethod.AetherKey.Hans") == true)
        
        // 5. Localization files exist
        let zhHansURL = projectRoot.appendingPathComponent("Resources/zh-Hans.lproj/InfoPlist.strings")
        let zhCNURL = projectRoot.appendingPathComponent("Resources/zh_CN.lproj/InfoPlist.strings")
        #expect(FileManager.default.fileExists(atPath: zhHansURL.path))
        #expect(FileManager.default.fileExists(atPath: zhCNURL.path))
    }
    
    @Test("Scenario 2: Pangu Spacing verifies CJK and alphanumeric boundary spacing")
    func testPanguSpacing() {
        let pangu = PanguSpacing.shared
        
        // CJK + Latin
        #expect(pangu.spacing("使用Swift开发") == "使用 Swift 开发")
        
        // Latin + CJK
        #expect(pangu.spacing("AetherKey输入法") == "AetherKey 输入法")
        
        // CJK + Digits + CJK
        #expect(pangu.spacing("第1版本发布") == "第 1 版本发布")
        
        // Numbers + CJK
        #expect(pangu.spacing("100个候选词") == "100 个候选词")
        
        // Pure English untouched
        #expect(pangu.spacing("Liquid Glass Aesthetics") == "Liquid Glass Aesthetics")
        
        // Contextual space prepending
        #expect(pangu.shouldPrependSpace(preceding: "S", committing: "苹果") == true)
        #expect(pangu.shouldPrependSpace(preceding: "你", committing: "Apple") == true)
        #expect(pangu.shouldPrependSpace(preceding: "好", committing: "世界") == false)
    }

    @Test("Scenario 3: Smart Punctuation handles Chinese quotes and decimal points")
    func testSmartPunctuation() {
        let punct = SmartPunctuation.shared
        
        // Normal Chinese mode conversions
        #expect(punct.convert(char: ",", precedingChar: nil) == "，")
        #expect(punct.convert(char: ".", precedingChar: nil) == "。")
        #expect(punct.convert(char: "?", precedingChar: nil) == "？")
        #expect(punct.convert(char: "!", precedingChar: nil) == "！")
        #expect(punct.convert(char: "\\", precedingChar: nil) == "、")
        #expect(punct.convert(char: "(", precedingChar: nil) == "（")
        #expect(punct.convert(char: ")", precedingChar: nil) == "）")
        
        // Decimal point retention after numbers
        #expect(punct.convert(char: ".", precedingChar: "3") == ".")
        #expect(punct.convert(char: ".", precedingChar: "0") == ".")
        #expect(punct.convert(char: ".", precedingChar: "a") == "。")
        
        // Ratio/time colon retention
        #expect(punct.convert(char: ":", precedingChar: "1") == ":")
        #expect(punct.convert(char: ":", precedingChar: "字") == "：")
    }

    @Test("Scenario 4: V-Mode evaluates mathematical expressions, macros and RMB")
    func testVModeCalculator() {
        let vCalc = VModeCalculator.shared
        
        // Math evaluation: Addition & Multiplication
        let mathCandidates = vCalc.candidates(for: "v1+2*3")
        #expect(!mathCandidates.isEmpty)
        #expect(mathCandidates.first?.text == "7")
        
        // Power operator
        let powCandidates = vCalc.candidates(for: "v2^8")
        #expect(powCandidates.first?.text == "256")
        
        // Division
        let divCandidates = vCalc.candidates(for: "v10/4")
        #expect(divCandidates.first?.text == "2.5")
        
        // Date macros
        let dateCandidates = vCalc.candidates(for: "vdate")
        #expect(!dateCandidates.isEmpty)
        #expect(dateCandidates.first?.text.contains("年") == true)
        
        // Weekday macro
        let weekCandidates = vCalc.candidates(for: "vweek")
        #expect(!weekCandidates.isEmpty)
        #expect(weekCandidates.contains(where: { $0.text.contains("星期") }))
        
        // RMB capitalization
        let rmbCandidates = vCalc.candidates(for: "v128.5")
        #expect(!rmbCandidates.isEmpty)
        #expect(rmbCandidates.contains(where: { $0.text.contains("壹佰贰拾捌元伍角整") }))
        
        let rmbThousand = vCalc.convertToRMB(amount: 1000)
        #expect(rmbThousand == "壹仟元整")
    }

    @Test("Scenario 5: Pinyin Engine matches exact words, abbreviations, and tech terms")
    func testPinyinEngine() {
        let engine = PinyinEngine.shared
        
        // Exact pinyin match
        let zhongwen = engine.query(rawInput: "zhongwen")
        #expect(zhongwen.contains(where: { $0.text == "中文" }))
        
        // Super abbreviation (简拼)
        let nihao = engine.query(rawInput: "nh")
        #expect(nihao.contains(where: { $0.text == "你好" }))
        
        let shuru = engine.query(rawInput: "srf")
        #expect(shuru.contains(where: { $0.text == "输入法" }))
        
        let zhongguo = engine.query(rawInput: "zg")
        #expect(zhongguo.contains(where: { $0.text == "中国" }))
        
        let beijing = engine.query(rawInput: "bj")
        #expect(beijing.contains(where: { $0.text == "北京" }))
        
        // Tech & Aether terms
        let aether = engine.query(rawInput: "aetherkey")
        #expect(aether.contains(where: { $0.text == "AetherKey" }))
        
        let liquidGlass = engine.query(rawInput: "ytbl")
        #expect(liquidGlass.contains(where: { $0.text == "液态玻璃" }))
        
        let glowCapsule = engine.query(rawInput: "wgjn")
        #expect(glowCapsule.contains(where: { $0.text == "微光胶囊" }))
        
        let zeroLag = engine.query(rawInput: "lkd")
        #expect(zeroLag.contains(where: { $0.text == "零卡顿" }))
    }

    @Test("Scenario 6: Context Detector identifies terminals and editors")
    func testContextDetector() {
        let detector = ContextDetector.shared
        
        // Terminal bundle identifiers
        #expect(detector.isTerminalApp(bundleIdentifier: "com.apple.Terminal") == true)
        #expect(detector.isTerminalApp(bundleIdentifier: "com.googlecode.iterm2") == true)
        #expect(detector.isTerminalApp(bundleIdentifier: "net.kovidgoyal.kitty") == true)
        #expect(detector.isTerminalApp(bundleIdentifier: "com.microsoft.VSCode") == true)
        
        // Non-terminal apps
        #expect(detector.isTerminalApp(bundleIdentifier: "com.apple.Notes") == false)
        #expect(detector.isTerminalApp(bundleIdentifier: "com.apple.Safari") == false)
        #expect(detector.isTerminalApp(bundleIdentifier: "com.apple.TextEdit") == false)
    }

    @Test("Scenario 7: Candidate Panel Non-Activating Window Specs")
    @MainActor
    func testCandidatePanelSpecs() {
        let panel = CandidatePanel()
        
        // Must never steal key or main window focus from host app
        #expect(panel.canBecomeKey == false)
        #expect(panel.canBecomeMain == false)
        #expect(panel.isFloatingPanel == true)
        #expect(panel.level == .popUpMenu)
        #expect(panel.isOpaque == false)
        #expect(panel.hasShadow == false)
    }
}
