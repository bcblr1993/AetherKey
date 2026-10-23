import Foundation

/// Offline Chinese emoji keywords from Unicode CLDR. AppKit/SwiftUI renders the
/// Unicode text with the system Apple Color Emoji font, just like native input.
public enum EmojiLexicon {
    public struct Entry: Decodable, Sendable {
        public let text: String
        public let name: String
    }

    private static let fallbackEntries: [String: [Entry]] = {
        let bundles = [Bundle.main, Bundle(for: PinyinEngine.self)]
        for bundle in bundles {
            if let url = bundle.url(forResource: "emoji", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode([String: [Entry]].self, from: data) {
                return decoded
            }
        }
        return [:]
    }()

    /// Read the installed OS's names and replacement keywords with Foundation.
    /// No private framework linking or copied Apple assets; CLDR remains the
    /// fallback if a future OS moves or changes these optional data files.
    private static let systemEntries = loadSystemEntries()
    private static let systemReplacements = loadSystemEntries(includeNames: false)

    /// Apple's replacement choices and exact names outrank broad CLDR keywords.
    static func primaryMatches(for input: String) -> [Entry] {
        let key = input.lowercased().filter { $0 != "'" && !$0.isWhitespace }
        let replacements = systemReplacements[key] ?? []
        let exact = matches(for: input).filter { pinyinKey($0.name) == key }
        var seen = Set<String>()
        return (replacements + exact).filter {
            seen.insert($0.text.replacingOccurrences(of: "\u{FE0F}", with: "")).inserted
        }
    }

    static func pinyinKey(_ text: String) -> String {
        let digits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        let expanded = text.map { char -> String in
            if char.isASCII, let digit = char.wholeNumberValue { return digits[digit] }
            return String(char)
        }.joined()
        let latin = expanded.applyingTransform(.toLatin, reverse: false) ?? expanded
        return latin.decomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "u\u{0308}", with: "v")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().filter { $0.isASCII && $0.isLetter }
    }

    static func loadSystemEntries(
        directory: URL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/CoreEmoji.framework/Resources/zh_CN.lproj"),
        includeNames: Bool = true
    ) -> [String: [Entry]] {
        func read<T>(_ file: String, as type: T.Type) -> T? {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(file)) else { return nil }
            return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? T
        }
        let names = read("AppleName.strings", as: [String: String].self) ?? [:]
        let replacements = read("FindReplaceReranking.plist", as: [String: [String]].self) ?? [:]
        var result: [String: [Entry]] = [:]
        func add(_ rawText: String, keyword: String) {
            // Regional name metadata suffixes are not part of the Unicode emoji.
            let text = String(rawText.split(separator: "@", maxSplits: 1).first ?? "")
            // Some replacement tables contain isolated variation selectors.
            guard text.count == 1,
                  text.unicodeScalars.contains(where: { ($0.value > 127 && $0.properties.isEmoji) || $0.value == 0x20E3 }) else { return }
            let key = pinyinKey(keyword)
            guard !key.isEmpty else { return }
            if !(result[key] ?? []).contains(where: { $0.text == text }) {
                result[key, default: []].append(Entry(text: text, name: names[text] ?? keyword))
            }
        }
        // Apple's replacement choices take precedence over name-only matches.
        for (keyword, texts) in replacements.sorted(by: { $0.key < $1.key }) {
            for text in texts { add(text, keyword: keyword) }
        }
        if includeNames {
            for (text, name) in names.sorted(by: { $0.key < $1.key }) { add(text, keyword: name) }
        }
        return result
    }

    public static func matches(for input: String) -> [Entry] {
        let key = input.lowercased().filter { $0 != "'" && !$0.isWhitespace }
        // Exact keywords only: never consume the rest of a sentence for an emoji.
        var seen = Set<String>()
        return ((systemEntries[key] ?? []) + (fallbackEntries[key] ?? [])).filter {
            // CLDR and Apple may differ only by the emoji presentation selector.
            seen.insert($0.text.replacingOccurrences(of: "\u{FE0F}", with: "")).inserted
        }
    }
}
