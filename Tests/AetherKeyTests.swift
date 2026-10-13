import Foundation
import Testing

@testable import AetherKey

@Suite("AetherKey Core Engine Test Suite")
struct AetherKeyEngineTests {
    
    @Test("Pangu Spacing verifies CJK and alphanumeric boundary spacing")
    func testPanguSpacing() {
        let pangu = PanguSpacing.shared
        
        // CJK + Latin
        #expect(pangu.spacing("使用Swift开发") == "使用 Swift 开发")
        
        // Latin + CJK
        #expect(pangu.spacing("AetherKey输入法") == "AetherKey 输入法")
        
        // CJK + Digits + CJK
        #expect(pangu.spacing("第1版本发布") == "第 1 版本发布")
        
        // Pure English untouched
        #expect(pangu.spacing("Liquid Glass Aesthetics") == "Liquid Glass Aesthetics")
        
        // Contextual space prepending
        #expect(pangu.shouldPrependSpace(preceding: "S", committing: "苹果") == true)
        #expect(pangu.shouldPrependSpace(preceding: "你", committing: "Apple") == true)
        #expect(pangu.shouldPrependSpace(preceding: "好", committing: "世界") == false)
    }

    @Test("Smart Punctuation handles Chinese quotes and decimal points")
    func testSmartPunctuation() {
        let punct = SmartPunctuation.shared
        
        // Normal Chinese mode conversions
        #expect(punct.convert(char: ",", precedingChar: nil) == "，")
        #expect(punct.convert(char: ".", precedingChar: nil) == "。")
        #expect(punct.convert(char: "?", precedingChar: nil) == "？")
        #expect(punct.convert(char: "!", precedingChar: nil) == "！")
        
        // Decimal point retention after numbers
        #expect(punct.convert(char: ".", precedingChar: "3") == ".")
        #expect(punct.convert(char: ".", precedingChar: "0") == ".")
        #expect(punct.convert(char: ".", precedingChar: "a") == "。")
        
        // Ratio/time colon retention
        #expect(punct.convert(char: ":", precedingChar: "1") == ":")
        #expect(punct.convert(char: ":", precedingChar: "字") == "：")
    }

    @Test("V-Mode evaluates mathematical expressions and macros")
    func testVModeCalculator() {
        let vCalc = VModeCalculator.shared
        
        // Math evaluation
        let mathCandidates = vCalc.candidates(for: "v1+2*3")
        #expect(!mathCandidates.isEmpty)
        #expect(mathCandidates.first?.text == "7")
        
        // Power operator
        let powCandidates = vCalc.candidates(for: "v2^8")
        #expect(powCandidates.first?.text == "256")
        
        // Date macro
        let dateCandidates = vCalc.candidates(for: "vdate")
        #expect(!dateCandidates.isEmpty)
        #expect(dateCandidates.first?.text.contains("年") == true)
        
        // RMB capitalization
        let rmbCandidates = vCalc.candidates(for: "v128.5")
        #expect(!rmbCandidates.isEmpty)
        #expect(rmbCandidates.contains(where: { $0.text.contains("壹佰贰拾捌元伍角整") }))
    }

    @Test("Pinyin Engine matches exact words, abbreviations, and tech terms")
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
        
        // Tech & Aether terms
        let aether = engine.query(rawInput: "aetherkey")
        #expect(aether.contains(where: { $0.text == "AetherKey" }))
        
        let liquidGlass = engine.query(rawInput: "ytbl")
        #expect(liquidGlass.contains(where: { $0.text == "液态玻璃" }))
        
        let glowCapsule = engine.query(rawInput: "wgjn")
        #expect(glowCapsule.contains(where: { $0.text == "微光胶囊" }))
    }
}
