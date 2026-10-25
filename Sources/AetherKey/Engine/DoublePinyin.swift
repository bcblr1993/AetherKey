import Foundation

public enum PinyinScheme: String, CaseIterable, Sendable, Identifiable {
    case full, flypy, microsoft
    public var id: String { rawValue }
    public var title: String {
        switch self { case .full: "全拼"; case .flypy: "小鹤双拼"; case .microsoft: "微软双拼" }
    }
}

/// Converts two-key syllables to the existing engine's reading while retaining keystroke offsets.
/// Key assignments checked against the published Flypy and Microsoft layouts; no external engine is used.
public enum DoublePinyin {
    public struct Token: Sendable {
        public let readings: [String]
        public var reading: String { readings[0] }
        public let rawEnd: Int
    }
    private static let flypyFinals: [String: String] = [
        "a":"a", "o":"o", "e":"e", "i":"i", "u":"u", "v":"v",
        "ai":"d", "ei":"w", "ao":"c", "ou":"z", "an":"j", "en":"f", "ang":"h", "eng":"g", "er":"r",
        "ia":"x", "ie":"p", "iao":"n", "iu":"q", "ian":"m", "in":"b", "iang":"l", "ing":"k", "iong":"s",
        "ua":"x", "uo":"o", "uai":"k", "ui":"v", "uan":"r", "un":"y", "uang":"l", "ong":"s", "ve":"t", "ue":"t"
    ]
    private static let microsoftFinals: [String: String] = [
        "a":"a", "o":"o", "e":"e", "i":"i", "u":"u", "v":"y",
        "ai":"l", "ei":"z", "ao":"k", "ou":"b", "an":"j", "en":"f", "ang":"h", "eng":"g", "er":"r",
        "ia":"w", "ie":"x", "iao":"c", "iu":"q", "ian":"m", "in":"n", "iang":"d", "ing":";", "iong":"s",
        "ua":"w", "uo":"o", "uai":"y", "ui":"v", "uan":"r", "un":"p", "uang":"d", "ong":"s", "ve":"t", "ue":"t"
    ]
    public static func codes(for syllable: String, scheme: PinyinScheme) -> [String] {
        guard scheme != .full else { return [syllable] }
        let finals = scheme == .flypy ? flypyFinals : microsoftFinals
        let initials = ["zh", "ch", "sh", "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h", "j", "q", "x", "r", "z", "c", "s", "y", "w"]
        if let initial = initials.first(where: { syllable.hasPrefix($0) }) {
            let final = String(syllable.dropFirst(initial.count))
            guard let key = finals[final] else { return [] }
            let first = ["zh":"v", "ch":"i", "sh":"u"][initial] ?? initial
            var result = [first + key]
            if scheme == .microsoft && ["ue", "ve"].contains(final) { result.append(first + "v") }
            if ["ju", "qu", "xu", "yu"].contains(syllable) { result.append(first + (scheme == .flypy ? "v" : "y")) }
            return result
        }
        guard "aoe".contains(syllable.prefix(1)), let key = finals[syllable] else { return [] }
        if scheme == .flypy {
            if syllable.count == 1 { return [syllable + syllable] }
            if syllable == "ang" { return ["ah"] }; if syllable == "eng" { return ["eg"] }
            return [syllable]
        }
        var result = ["o" + key]
        if syllable.hasPrefix("a") || syllable.hasPrefix("e") { result.append(String(syllable.prefix(1)) + key) }
        return result
    }
    private static func makeTable(_ scheme: PinyinScheme) -> [String: [String]] {
        var table: [String: [String]] = [:]
        for syllable in PinyinLexicon.syllablesChars.keys.sorted() {
            for code in codes(for: syllable, scheme: scheme) { table[code, default: []].insert(syllable, at: 0) }
        }
        return table
    }
    private static let flypyTable = makeTable(.flypy)
    private static let microsoftTable = makeTable(.microsoft)
    public static func tokens(_ raw: String, scheme: PinyinScheme) -> [Token]? {
        let chars = Array(raw.lowercased())
        let table = scheme == .flypy ? flypyTable : microsoftTable
        var result: [Token] = []; var i = 0
        while i < chars.count {
            if chars[i] == "'" { i += 1; continue }
            let end = min(i + 2, chars.count)
            let readings: [String]
            if end - i == 1 || chars[i + 1] == "'" {
                let first = String(chars[i])
                guard first != ";" else { return nil }
                readings = [["v":"zh", "i":"ch", "u":"sh"][first] ?? first]
                i += 1
            } else {
                guard let decoded = table[String(chars[i..<end])] else { return nil }
                readings = decoded; i = end
            }
            while i < chars.count && chars[i] == "'" { i += 1 }
            result.append(Token(readings: readings, rawEnd: i))
        }
        return result
    }
    public static func reading(_ raw: String, scheme: PinyinScheme) -> String {
        if scheme == .full { return raw }
        return tokens(raw, scheme: scheme)?.map(\.reading).joined(separator: "'") ?? raw
    }
    public static func query(_ raw: String, scheme: PinyinScheme) -> [Candidate] {
        guard scheme != .full else { return PinyinEngine.shared.query(rawInput: raw) }
        guard let tokens = tokens(raw, scheme: scheme), !tokens.isEmpty else {
            return [Candidate(text: raw, comment: "英", consumedInputLength: raw.count)]
        }
        // Preserve genuine layout collisions (for example lo/luo) instead of dropping rare readings.
        var variants: [[String]] = [[]]
        for token in tokens {
            variants = Array(variants.flatMap { prefix in token.readings.map { prefix + [$0] } }.prefix(16))
        }
        var result: [Candidate] = []; var seen = Set<String>()
        for syllables in variants {
            let decoded = syllables.joined(separator: "'")
            var boundaries: [(end: Int, raw: Int)] = []; var end = 0
            for (index, syllable) in syllables.enumerated() {
                end += syllable.count
                boundaries.append((end + (index < tokens.count - 1 ? 1 : 0), tokens[index].rawEnd))
                if index < tokens.count - 1 { end += 1 }
            }
            for candidate in PinyinEngine.shared.query(rawInput: decoded) where candidate.comment != "英" {
                let consumed = candidate.consumedInputLength > 0 ? candidate.consumedInputLength : decoded.count
                guard let boundary = boundaries.first(where: { $0.end >= consumed }), seen.insert(candidate.text).inserted else { continue }
                result.append(Candidate(text: candidate.text, comment: candidate.comment,
                                        pinyin: String(decoded.prefix(consumed)), isEmoji: candidate.isEmoji,
                                        consumedInputLength: boundary.raw))
            }
        }
        result.append(Candidate(text: raw, comment: "英", consumedInputLength: raw.count))
        return result
    }
}
