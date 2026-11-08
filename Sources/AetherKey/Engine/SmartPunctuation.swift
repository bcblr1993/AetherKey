import Foundation

/// Smart punctuation engine: Converts ASCII punctuation to Chinese typographic counterparts,
/// with stateful quote pairing (“” / ‘’) and intelligent decimal/colon retention when typing numbers.
public final class SmartPunctuation: @unchecked Sendable {
    public static let shared = SmartPunctuation()
    
    private let lock = NSLock()
    private var isDoubleQuoteOpen: Bool = false
    private var isSingleQuoteOpen: Bool = false
    private var isOpenCornerBracketInner: Bool = false
    private var isCloseCornerBracketInner: Bool = false
    private enum PairKind { case doubleQuote, singleQuote, openCorner, closeCorner }
    private var lastConvertedPair: PairKind? = nil
    
    /// Aligned with Sogou Pinyin's `symbolset2.plist` (`jian-ban` Simplified Chinese punctuation table)
    private let punctuationMap: [Character: String] = [
        ",": "，",
        ".": "。",
        "?": "？",
        "!": "！",
        ":": "：",
        ";": "；",
        "/": "、",
        "\\": "、",
        "(": "（",
        ")": "）",
        "[": "【",
        "]": "】",
        "{": "「",
        "}": "」",
        "<": "《",
        ">": "》",
        "^": "……",
        "_": "——",
        "~": "～",
        "`": "·",
        "$": "￥",
        "\"": "“",
        "'": "‘"
    ]
    
    /// Resets quote pairing state (e.g. when starting a new session or test).
    public func resetState() {
        lock.lock()
        isDoubleQuoteOpen = false
        isSingleQuoteOpen = false
        isOpenCornerBracketInner = false
        isCloseCornerBracketInner = false
        lastConvertedPair = nil
        lock.unlock()
    }

    /// Reverts the most recent paired quote/bracket toggle when the user immediately backspaces it.
    public func rollbackLastQuoteIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard let last = lastConvertedPair else { return }
        switch last {
        case .doubleQuote: isDoubleQuoteOpen.toggle()
        case .singleQuote: isSingleQuoteOpen.toggle()
        case .openCorner: isOpenCornerBracketInner.toggle()
        case .closeCorner: isCloseCornerBracketInner.toggle()
        }
        lastConvertedPair = nil
    }
    
    /// Converts input character to smart punctuation.
    /// - Preserves half-width '.' or ':' after a digit (e.g. 3.14, 12:30).
    /// - Alternates opening and closing curly quotes for '"' and '\''.
    public func convert(char: Character, precedingChar: Character?) -> String {
        // Decimal point retention rule: e.g. 3.14, 0.05
        if char == "." {
            lock.lock(); lastConvertedPair = nil; lock.unlock()
            if let prev = precedingChar, prev.isNumber {
                return "."
            }
            return "。"
        }
        
        // Colon retention in time or ratio: e.g. 12:30
        if char == ":" {
            lock.lock(); lastConvertedPair = nil; lock.unlock()
            if let prev = precedingChar, prev.isNumber {
                return ":"
            }
            return "："
        }
        
        // Stateful double quote pairing: “ ... ”
        if char == "\"" {
            lock.lock()
            let result = isDoubleQuoteOpen ? "”" : "“"
            isDoubleQuoteOpen.toggle()
            lastConvertedPair = .doubleQuote
            lock.unlock()
            return result
        }
        
        // Stateful single quote pairing: ‘ ... ’
        if char == "'" {
            lock.lock()
            let result = isSingleQuoteOpen ? "’" : "‘"
            isSingleQuoteOpen.toggle()
            lastConvertedPair = .singleQuote
            lock.unlock()
            return result
        }
        
        // Sogou-style corner bracket alternation: { -> 「 / 『, } -> 」 / 』
        if char == "{" {
            lock.lock()
            let result = isOpenCornerBracketInner ? "『" : "「"
            isOpenCornerBracketInner.toggle()
            lastConvertedPair = .openCorner
            lock.unlock()
            return result
        }
        if char == "}" {
            lock.lock()
            let result = isCloseCornerBracketInner ? "』" : "」"
            isCloseCornerBracketInner.toggle()
            lastConvertedPair = .closeCorner
            lock.unlock()
            return result
        }
        
        lock.lock(); lastConvertedPair = nil; lock.unlock()
        return punctuationMap[char] ?? String(char)
    }
    
    public func isPunctuation(_ char: Character) -> Bool {
        return punctuationMap[char] != nil
    }
}
