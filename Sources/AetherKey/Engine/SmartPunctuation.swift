import Foundation

/// Smart punctuation engine: Converts ASCII punctuation to Chinese typographic counterparts,
/// with intelligent decimal point retention when typing numbers.
public final class SmartPunctuation: Sendable {
    public static let shared = SmartPunctuation()
    
    private let punctuationMap: [Character: String] = [
        ",": "，",
        ".": "。",
        "?": "？",
        "!": "！",
        ":": "：",
        ";": "；",
        "\\": "、",
        "(": "（",
        ")": "）",
        "[": "【",
        "]": "】",
        "<": "《",
        ">": "》",
        "^": "……",
        "~": "～",
        "$": "￥"
    ]
    
    /// Converts input character to smart punctuation.
    /// If preceding character is a digit and input is '.', preserves half-width '.' as decimal point.
    public func convert(char: Character, precedingChar: Character?) -> String {
        // Decimal point retention rule: e.g. 3.14, 0.05
        if char == "." {
            if let prev = precedingChar, prev.isNumber {
                return "."
            }
            return "。"
        }
        
        // Colon retention in time or ratio: e.g. 12:30
        if char == ":" {
            if let prev = precedingChar, prev.isNumber {
                return ":"
            }
            return "："
        }
        
        return punctuationMap[char] ?? String(char)
    }
    
    public func isPunctuation(_ char: Character) -> Bool {
        return punctuationMap[char] != nil
    }
}
