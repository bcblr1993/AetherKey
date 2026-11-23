import Foundation

public enum PinyinScheme: String, CaseIterable, Sendable, Identifiable {
    case full, flypy, microsoft, zrm, sogou, wubi86
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .full: "全拼"
        case .flypy: "小鹤双拼"
        case .microsoft: "微软双拼"
        case .zrm: "自然码双拼"
        case .sogou: "搜狗双拼"
        case .wubi86: "五笔 86"
        }
    }
    public var isDoublePinyin: Bool {
        switch self {
        case .flypy, .microsoft, .zrm, .sogou: return true
        case .full, .wubi86: return false
        }
    }
}

/// Converts two-key syllables to the existing engine's reading while retaining keystroke offsets.
/// Key assignments checked against the published Flypy, Microsoft, ZRM, and Sogou layouts; no external engine is used.
public enum DoublePinyin {
    public struct Token: Sendable {
        public let readings: [String]
        public var reading: String { readings[0] }
        public let rawEnd: Int
    }

    public struct KeyMapping: Sendable, Equatable {
        public let key: String
        public let initial: String?
        public let finals: [String]
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
    private static let zrmFinals: [String: String] = [
        "a":"a", "o":"o", "e":"e", "i":"i", "u":"u", "v":"v",
        "ai":"l", "ei":"z", "ao":"k", "ou":"b", "an":"j", "en":"f", "ang":"h", "eng":"g", "er":"r",
        "ia":"w", "ie":"x", "iao":"c", "iu":"q", "ian":"m", "in":"n", "iang":"d", "ing":"y", "iong":"s",
        "ua":"w", "uo":"o", "uai":"y", "ui":"v", "uan":"r", "un":"p", "uang":"d", "ong":"s", "ve":"t", "ue":"t"
    ]
    private static let sogouFinals: [String: String] = [
        "a":"a", "o":"o", "e":"e", "i":"i", "u":"u", "v":"y",
        "ai":"l", "ei":"z", "ao":"k", "ou":"b", "an":"j", "en":"f", "ang":"h", "eng":"g", "er":"r",
        "ia":"w", "ie":"x", "iao":"c", "iu":"q", "ian":"m", "in":"n", "iang":"d", "ing":";", "iong":"s",
        "ua":"w", "uo":"o", "uai":"y", "ui":"v", "uan":"r", "un":"p", "uang":"d", "ong":"s", "ve":"t", "ue":"t"
    ]

    private static func finalsMap(for scheme: PinyinScheme) -> [String: String] {
        switch scheme {
        case .flypy: return flypyFinals
        case .microsoft: return microsoftFinals
        case .zrm: return zrmFinals
        case .sogou: return sogouFinals
        case .full, .wubi86: return [:]
        }
    }

    public static func codes(for syllable: String, scheme: PinyinScheme) -> [String] {
        guard scheme.isDoublePinyin else {
            return scheme == .full ? [syllable] : []
        }
        let finals = finalsMap(for: scheme)
        let initials = ["zh", "ch", "sh", "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h", "j", "q", "x", "r", "z", "c", "s", "y", "w"]
        if let initial = initials.first(where: { syllable.hasPrefix($0) }) {
            let final = String(syllable.dropFirst(initial.count))
            guard let key = finals[final] else { return [] }
            let first = ["zh":"v", "ch":"i", "sh":"u"][initial] ?? initial
            var result = [first + key]
            if scheme == .microsoft && ["ue", "ve"].contains(final) { result.append(first + "v") }
            if ["ju", "qu", "xu", "yu"].contains(syllable) { result.append(first + (finals["v"] ?? "v")) }
            return result
        }
        guard "aoe".contains(syllable.prefix(1)), let key = finals[syllable] else { return [] }
        if scheme == .flypy || scheme == .zrm {
            if syllable.count == 1 { return [syllable + syllable] }
            if syllable == "ang" { return ["ah"] }
            if syllable == "eng" { return ["eg"] }
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
    private static let zrmTable = makeTable(.zrm)
    private static let sogouTable = makeTable(.sogou)

    public static func tokens(_ raw: String, scheme: PinyinScheme) -> [Token]? {
        guard scheme.isDoublePinyin else { return nil }
        let chars = Array(raw.lowercased())
        let table: [String: [String]]
        switch scheme {
        case .flypy: table = flypyTable
        case .microsoft: table = microsoftTable
        case .zrm: table = zrmTable
        case .sogou: table = sogouTable
        case .full, .wubi86: return nil
        }
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
        if !scheme.isDoublePinyin { return raw }
        return tokens(raw, scheme: scheme)?.map(\.reading).joined(separator: "'") ?? raw
    }

    public static func keymapRows(for scheme: PinyinScheme) -> [[KeyMapping]] {
        guard scheme.isDoublePinyin else { return [] }
        let finals = finalsMap(for: scheme)
        let canonicalOrder = [
            "a", "o", "e", "i", "u", "v",
            "ai", "ei", "ao", "ou", "an", "en", "ang", "eng", "er",
            "ia", "ie", "iao", "iu", "ian", "in", "iang", "ing", "iong",
            "ua", "uo", "uai", "ui", "uan", "un", "uang", "ong", "ue", "ve"
        ]
        var finalsByKey: [String: [String]] = [:]
        for final in canonicalOrder {
            guard let key = finals[final] else { continue }
            if final == "ve", finals["ue"] == key { continue }
            finalsByKey[key, default: []].append(final)
        }
        if scheme == .microsoft {
            var vFinals = finalsByKey["v"] ?? []
            if !vFinals.contains("ve") { vFinals.append("ve") }
            finalsByKey["v"] = vFinals
        }

        let initialMap: [String: String] = [
            "q": "q", "w": "w", "r": "r", "t": "t", "y": "y", "u": "sh", "i": "ch", "p": "p",
            "s": "s", "d": "d", "f": "f", "g": "g", "h": "h", "j": "j", "k": "k", "l": "l",
            "z": "z", "x": "x", "c": "c", "v": "zh", "b": "b", "n": "n", "m": "m"
        ]
        let hasSemicolon = (scheme == .microsoft || scheme == .sogou)
        let rows: [[String]] = [
            ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
            hasSemicolon
                ? ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";"]
                : ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
            ["z", "x", "c", "v", "b", "n", "m"]
        ]
        return rows.map { row in
            row.map { k in
                KeyMapping(
                    key: k == ";" ? ";" : k.uppercased(),
                    initial: initialMap[k],
                    finals: finalsByKey[k] ?? []
                )
            }
        }
    }

    private static func abbreviationWords(for stripped: String) -> [String] {
        (PinyinLexicon.commonAbbreviations[stripped] ?? [])
            + Array((PinyinLexicon.weightedAbbreviations[stripped] ?? []).prefix(6))
    }

    public static func query(_ raw: String, scheme: PinyinScheme, precedingText: String = "") -> [Candidate] {
        if scheme == .wubi86 { return WubiEngine.shared.query(raw) }
        guard scheme != .full else { return PinyinEngine.shared.query(rawInput: raw, precedingText: precedingText) }
        let stripped = raw.lowercased().replacingOccurrences(of: "'", with: "")
        guard let tokens = tokens(raw, scheme: scheme), !tokens.isEmpty else {
            var fallback: [Candidate] = []
            var seen = Set<String>()
            for word in abbreviationWords(for: stripped) where !UserLexicon.shared.isForgotten(word, for: stripped) && seen.insert(word).inserted {
                fallback.append(Candidate(text: word, pinyin: stripped, consumedInputLength: raw.count))
            }
            fallback.append(Candidate(text: raw, comment: "英", consumedInputLength: raw.count))
            return fallback
        }
        // Preserve genuine layout collisions (for example lo/luo, Microsoft jv -> ju/jue)
        // instead of dropping rare readings, and rank across variants via LanguageModel.
        var variants: [[String]] = [[]]
        for token in tokens {
            variants = Array(variants.flatMap { prefix in token.readings.map { prefix + [$0] } }.prefix(16))
        }

        if variants.count <= 1, let syllables = variants.first {
            let decoded = syllables.joined(separator: "'")
            var boundaries: [(end: Int, raw: Int)] = []; var end = 0
            for (index, syllable) in syllables.enumerated() {
                end += syllable.count
                boundaries.append((end + (index < tokens.count - 1 ? 1 : 0), tokens[index].rawEnd))
                if index < tokens.count - 1 { end += 1 }
            }
            var result: [Candidate] = []; var seen = Set<String>()
            for candidate in PinyinEngine.shared.query(rawInput: decoded, precedingText: precedingText) where candidate.comment != "英" {
                let consumed = candidate.consumedInputLength > 0 ? candidate.consumedInputLength : decoded.count
                guard let boundary = boundaries.first(where: { $0.end >= consumed }), seen.insert(candidate.text).inserted else { continue }
                result.append(Candidate(text: candidate.text, comment: candidate.comment,
                                        pinyin: String(decoded.prefix(consumed)), isEmoji: candidate.isEmoji,
                                        consumedInputLength: boundary.raw))
            }
            if stripped.count >= 3 {
                for word in abbreviationWords(for: stripped) where !UserLexicon.shared.isForgotten(word, for: stripped) && seen.insert(word).inserted {
                    result.append(Candidate(text: word, pinyin: stripped, consumedInputLength: raw.count))
                }
            }
            result.append(Candidate(text: raw, comment: "英", consumedInputLength: raw.count))
            return result
        }

        struct RankedEntry {
            let tier: Int
            let primaryScore: Double
            let rankInVariant: Int
            let variantIndex: Int
            let candidate: Candidate
        }

        let lm = LanguageModel.shared
        let userLexicon = UserLexicon.shared
        let isSingleToken = (tokens.count == 1)
        var ranked: [RankedEntry] = []

        for (variantIdx, syllables) in variants.enumerated() {
            let decoded = syllables.joined(separator: "'")
            var boundaries: [(end: Int, raw: Int)] = []; var end = 0
            for (index, syllable) in syllables.enumerated() {
                end += syllable.count
                boundaries.append((end + (index < tokens.count - 1 ? 1 : 0), tokens[index].rawEnd))
                if index < tokens.count - 1 { end += 1 }
            }
            let contextMatches = precedingText.isEmpty
                ? Set<String>()
                : Set(PinyinContext.continuations(input: decoded, precedingText: precedingText))
            let rawCandidates = PinyinEngine.shared.query(rawInput: decoded, precedingText: precedingText)
            for (candIdx, candidate) in rawCandidates.enumerated() where candidate.comment != "英" {
                let consumed = candidate.consumedInputLength > 0 ? candidate.consumedInputLength : decoded.count
                guard let boundary = boundaries.first(where: { $0.end >= consumed }) else { continue }
                let readingPrefix = String(decoded.prefix(consumed))
                let mapped = Candidate(
                    text: candidate.text,
                    comment: candidate.comment,
                    pinyin: readingPrefix,
                    isEmoji: candidate.isEmoji,
                    consumedInputLength: boundary.raw
                )
                let isFullInput = (boundary.raw == raw.count)
                let canonical = mapped.canonicalText
                let weight = lm.wordWeight(for: candidate.text)

                let tier: Int
                let primaryScore: Double
                if candidate.isEmoji {
                    tier = (!isSingleToken && candIdx <= 2) ? 4 : (isSingleToken ? 4 : 7)
                    primaryScore = isSingleToken ? (420.0 - Double(candIdx)) : Double(100 - candIdx)
                } else if isFullInput && userLexicon.isPinned(canonical, for: readingPrefix) {
                    tier = 0
                    primaryScore = weight
                } else if isFullInput && userLexicon.isExplicitPreference(canonical, for: readingPrefix) {
                    tier = 1
                    primaryScore = weight
                } else if isFullInput && contextMatches.contains(candidate.text) {
                    tier = 2
                    primaryScore = weight
                } else if isFullInput && userLexicon.selectionCount(canonical, for: readingPrefix) > 0 {
                    tier = 3
                    primaryScore = weight + log1p(Double(userLexicon.selectionCount(canonical, for: readingPrefix))) * 25.0
                } else if isFullInput && (isSingleToken || candidate.text.count >= 2) {
                    tier = 4
                    if candidate.text.count == 1 {
                        // Preserve reading-primary ordering from PinyinLexicon while interleaving variants by LM weight
                        primaryScore = weight - Double(candIdx) * 25.0
                    } else {
                        primaryScore = weight - Double(candIdx) * 1.5
                    }
                } else if !isFullInput && candidate.text.count >= 2 {
                    tier = 5
                    primaryScore = Double(boundary.raw) * 1000.0 + weight
                } else {
                    tier = 6
                    primaryScore = weight
                }

                ranked.append(RankedEntry(
                    tier: tier,
                    primaryScore: primaryScore,
                    rankInVariant: candIdx,
                    variantIndex: variantIdx,
                    candidate: mapped
                ))
            }
        }

        ranked.sort { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            if lhs.primaryScore != rhs.primaryScore { return lhs.primaryScore > rhs.primaryScore }
            if lhs.rankInVariant != rhs.rankInVariant { return lhs.rankInVariant < rhs.rankInVariant }
            return lhs.variantIndex < rhs.variantIndex
        }

        var result: [Candidate] = []; var seen = Set<String>()
        result.reserveCapacity(ranked.count + 8)
        for entry in ranked where seen.insert(entry.candidate.text).inserted {
            result.append(entry.candidate)
        }
        if stripped.count >= 3 {
            for word in abbreviationWords(for: stripped) where !userLexicon.isForgotten(word, for: stripped) && seen.insert(word).inserted {
                result.append(Candidate(text: word, pinyin: stripped, consumedInputLength: raw.count))
            }
        }
        result.append(Candidate(text: raw, comment: "英", consumedInputLength: raw.count))
        return result
    }
}
