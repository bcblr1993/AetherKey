import Foundation

/// Output produced by context-aware punctuation conversion, supporting cursor back-step for auto-paired brackets/quotes.
public struct PunctuationOutput: Sendable, Equatable {
    public let text: String
    public let cursorBackOffset: Int
    public let autoPairedCloseChar: Character?

    public init(text: String, cursorBackOffset: Int = 0, autoPairedCloseChar: Character? = nil) {
        self.text = text
        self.cursorBackOffset = cursorBackOffset
        self.autoPairedCloseChar = autoPairedCloseChar
    }
}

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
    
    /// Context-aware punctuation conversion:
    /// - Keeps half-width `.`, `:`, `/`, `_`, `@` inside URLs, emails, domains, file paths, identifiers, and numbers.
    /// - When `autoPairEnabled` is true, emits paired Chinese brackets/quotes with `cursorBackOffset = 1`.
    public func convertWithContext(
        char: Character,
        precedingText: String,
        autoPairEnabled: Bool
    ) -> PunctuationOutput {
        if char == "@" {
            lock.lock(); lastConvertedPair = nil; lock.unlock()
            return PunctuationOutput(text: "@", cursorBackOffset: 0, autoPairedCloseChar: nil)
        }

        if (char == "." || char == ":" || char == "/" || char == "_"),
           Self.shouldKeepHalfWidth(char: char, precedingText: precedingText) {
            lock.lock(); lastConvertedPair = nil; lock.unlock()
            return PunctuationOutput(text: String(char), cursorBackOffset: 0, autoPairedCloseChar: nil)
        }

        if autoPairEnabled {
            switch char {
            case "(":
                lock.lock(); lastConvertedPair = nil; lock.unlock()
                return PunctuationOutput(text: "（）", cursorBackOffset: 1, autoPairedCloseChar: "）")
            case "[":
                lock.lock(); lastConvertedPair = nil; lock.unlock()
                return PunctuationOutput(text: "【】", cursorBackOffset: 1, autoPairedCloseChar: "】")
            case "{":
                lock.lock(); lastConvertedPair = nil; lock.unlock()
                return PunctuationOutput(text: "「」", cursorBackOffset: 1, autoPairedCloseChar: "」")
            case "<":
                lock.lock(); lastConvertedPair = nil; lock.unlock()
                return PunctuationOutput(text: "《》", cursorBackOffset: 1, autoPairedCloseChar: "》")
            case "\"":
                lock.lock(); lastConvertedPair = nil; lock.unlock()
                return PunctuationOutput(text: "“”", cursorBackOffset: 1, autoPairedCloseChar: "”")
            case "'":
                lock.lock(); lastConvertedPair = nil; lock.unlock()
                return PunctuationOutput(text: "‘’", cursorBackOffset: 1, autoPairedCloseChar: "’")
            default:
                break
            }
        }

        let converted = convert(char: char, precedingChar: precedingText.last)
        return PunctuationOutput(text: converted, cursorBackOffset: 0, autoPairedCloseChar: nil)
    }

    private static func shouldKeepHalfWidth(char: Character, precedingText: String) -> Bool {
        if (char == "." || char == ":"), let last = precedingText.last, last.isNumber {
            return true
        }

        let trailingSegment = trailingASCIIToken(in: precedingText)
        guard !trailingSegment.isEmpty else { return false }

        let lower = trailingSegment.lowercased()
        if lower.contains("http://") || lower.contains("https://") || lower.contains("www.") || lower.contains("://") {
            return true
        }

        if char == "/", isURLSchemePrefixBeforeSlash(lower) {
            return true
        }

        if let atIndex = trailingSegment.lastIndex(of: "@"),
           atIndex > trailingSegment.startIndex,
           trailingSegment.index(after: atIndex) < trailingSegment.endIndex {
            return true
        }

        return trailingIdentifierCount(in: precedingText) >= 2
    }

    private static func trailingASCIIToken(in text: String) -> String {
        var chars: [Character] = []
        for ch in text.reversed() {
            guard ch.isASCII, !ch.isWhitespace, !ch.isNewline else { break }
            chars.append(ch)
        }
        return String(chars.reversed())
    }

    private static func trailingIdentifierCount(in text: String) -> Int {
        var count = 0
        for ch in text.reversed() {
            guard ch.isASCII else { break }
            if ch.isLetter || ch.isNumber || ch == "." || ch == "_" || ch == "/" || ch == "-" {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    private static func isURLSchemePrefixBeforeSlash(_ lowerToken: String) -> Bool {
        if lowerToken.hasSuffix(":/") {
            let prefix = lowerToken.dropLast(2)
            return prefix.count >= 2 && prefix.allSatisfy { $0.isASCII && $0.isLetter }
        }
        if lowerToken.hasSuffix(":") {
            let prefix = lowerToken.dropLast(1)
            return prefix.count >= 2 && prefix.allSatisfy { $0.isASCII && $0.isLetter }
        }
        return false
    }

    public func isPunctuation(_ char: Character) -> Bool {
        return punctuationMap[char] != nil
    }
}
