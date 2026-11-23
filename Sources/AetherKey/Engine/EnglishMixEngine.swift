import Foundation
import os

/// Offline English & Chinese-English mixed-input lexicon engine backed by `Resources/english_lexicon.json`.
public final class EnglishMixEngine: Sendable {
    public static let shared = EnglishMixEngine()

    public struct EnglishMatch: Sendable, Equatable {
        public let text: String
        public let weight: Int
        public let preferFirst: Bool

        public init(text: String, weight: Int, preferFirst: Bool) {
            self.text = text
            self.weight = weight
            self.preferFirst = preferFirst
        }
    }

    private struct RawWordEntry: Decodable {
        let k: String
        let t: String
        let w: Int
        let p: Bool
    }

    private struct RawPayload: Decodable {
        let words: [RawWordEntry]?
        let mixed: [String: String]?
    }

    private struct IndexedWord: Sendable {
        let key: String
        let match: EnglishMatch
    }

    private struct LexiconData: Sendable {
        let exactMap: [String: [EnglishMatch]]
        let prefix2Buckets: [String: [IndexedWord]]
        let mixedMap: [String: String]
        let mixEligibleKeys: Set<String>
    }

    private static let sourceRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private let customResourceURL: URL?
    private let state = OSAllocatedUnfairLock<LexiconData?>(initialState: nil)

    public init(resourceURL: URL? = nil) {
        self.customResourceURL = resourceURL
    }

    /// Preloads `english_lexicon.json` into memory.
    public func preload() {
        _ = loadLexiconIfNeeded()
    }

    /// Returns exact case-canonical English matches for `input`, sorted by preference and weight.
    public func exactMatches(for input: String) -> [EnglishMatch] {
        let key = Self.normalizeKey(input)
        guard !key.isEmpty else { return [] }
        return loadLexiconIfNeeded().exactMap[key] ?? []
    }

    /// Returns prefix-completion English matches where lexicon key strictly starts with `input`.
    public func prefixMatches(for input: String, limit: Int = 5) -> [EnglishMatch] {
        let key = Self.normalizeKey(input)
        guard key.count >= 2, limit > 0, Self.isASCIIAlphanumeric(key) else { return [] }
        let data = loadLexiconIfNeeded()
        let bucketKey = String(key.prefix(2))
        guard let bucket = data.prefix2Buckets[bucketKey] else { return [] }

        var results: [EnglishMatch] = []
        var seen = Set<String>()
        for item in bucket {
            guard item.key != key, item.key.hasPrefix(key) else { continue }
            let dedupKey = item.match.text.lowercased()
            guard seen.insert(dedupKey).inserted else { continue }
            results.append(item.match)
            if results.count >= limit { break }
        }
        return results
    }

    /// Returns an exact built-in mixed Chinese+English phrase such as `bzhan -> B站` or `upzhu -> UP主`.
    public func mixedPhraseMatch(for input: String) -> String? {
        let key = Self.normalizeKey(input)
        guard !key.isEmpty else { return nil }
        return loadLexiconIfNeeded().mixedMap[key]
    }

    /// Segments mixed Chinese+English or English+Chinese buffer sequences (e.g. `wodebug -> 我的 bug`,
    /// `appxiazai -> App 下载`), using `pinyinSolver` to decode Chinese pinyin slices.
    /// `pinyinSolver` should return `nil` when the given slice cannot be decoded as full Chinese pinyin.
    public func segmentMixedCandidates(for input: String, pinyinSolver: (String) -> String?) -> [String] {
        let (key, explicitBoundaries) = Self.normalizeWithBoundaries(input)
        guard key.count >= 3, key.count <= 32, Self.isASCIIAlphanumeric(key) else { return [] }

        let data = loadLexiconIfNeeded()
        let usePangu = AetherSettings.shared.isPanguSpacingEnabled
        var scored: [(text: String, score: Int)] = []
        var pinyinCache: [String: String?] = [:]

        func solvePinyin(_ slice: String) -> String? {
            if let cached = pinyinCache[slice] { return cached }
            guard slice.allSatisfy({ $0.isASCII && $0.isLetter }) else {
                pinyinCache[slice] = nil
                return nil
            }
            guard let resolved = pinyinSolver(slice),
                  !resolved.isEmpty,
                  resolved.lowercased() != slice,
                  Self.containsCJK(resolved) else {
                pinyinCache[slice] = nil
                return nil
            }
            pinyinCache[slice] = resolved
            return resolved
        }

        // 1. Chinese prefix + English suffix (e.g. wodebug -> 我的 bug, kanppt -> 看 PPT)
        if key.count >= 3 {
            for split in 1...(key.count - 2) {
                let zhPart = String(key.prefix(split))
                let enPart = String(key.suffix(key.count - split))
                guard data.mixEligibleKeys.contains(enPart),
                      let enMatch = data.exactMap[enPart]?.first,
                      let zhText = solvePinyin(zhPart) else {
                    continue
                }
                let combined = Self.joinSegments(zhText, enMatch.text, pangu: usePangu)
                let zhBonus = zhText.count == 2 ? 120 : (zhText.count >= 3 ? 90 : 30)
                let score = enMatch.weight
                    + zhBonus
                    + (zhPart.count >= 2 ? 40 : 0)
                    + (explicitBoundaries.contains(split) ? 350 : 0)
                scored.append((combined, score))
            }
        }

        // 2. English prefix + Chinese suffix (e.g. appxiazai -> App 下载, macdiannao -> Mac 电脑)
        if key.count >= 3 {
            for split in 2...(key.count - 1) {
                let enPart = String(key.prefix(split))
                let zhPart = String(key.suffix(key.count - split))
                guard data.mixEligibleKeys.contains(enPart),
                      let enMatch = data.exactMap[enPart]?.first,
                      let zhText = solvePinyin(zhPart) else {
                    continue
                }
                let combined = Self.joinSegments(enMatch.text, zhText, pangu: usePangu)
                let zhBonus = zhText.count == 2 ? 120 : (zhText.count >= 3 ? 90 : 30)
                let score = enMatch.weight
                    + zhBonus
                    + (zhPart.count >= 2 ? 40 : 0)
                    + (explicitBoundaries.contains(split) ? 350 : 0)
                scored.append((combined, score))
            }
        }

        // 3. Chinese + English + Chinese (e.g. xiubugle -> 修 bug 了)
        if key.count >= 5 {
            for start in 1...(key.count - 3) {
                for end in (start + 2)...(key.count - 1) {
                    let enPart = String(key[key.index(key.startIndex, offsetBy: start)..<key.index(key.startIndex, offsetBy: end)])
                    guard data.mixEligibleKeys.contains(enPart),
                          let enMatch = data.exactMap[enPart]?.first,
                          enMatch.preferFirst || enMatch.text != enMatch.text.lowercased() || Self.curatedFallbackKeys.contains(enPart) else {
                        continue
                    }
                    let zhLeftPart = String(key.prefix(start))
                    let zhRightPart = String(key.suffix(key.count - end))
                    guard let zhLeft = solvePinyin(zhLeftPart),
                          let zhRight = solvePinyin(zhRightPart) else {
                        continue
                    }
                    let firstJoin = Self.joinSegments(zhLeft, enMatch.text, pangu: usePangu)
                    let combined = Self.joinSegments(firstJoin, zhRight, pangu: usePangu)
                    let boundaryBonus = (explicitBoundaries.contains(start) ? 200 : 0)
                        + (explicitBoundaries.contains(end) ? 200 : 0)
                    let score = enMatch.weight + (zhLeft.count + zhRight.count) * 15 - 120 + boundaryBonus
                    scored.append((combined, score))
                }
            }
        }

        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.text < rhs.text
        }

        var results: [String] = []
        var seen = Set<String>()
        for item in scored where seen.insert(item.text).inserted {
            results.append(item.text)
            if results.count >= 6 { break }
        }
        return results
    }

    private func loadLexiconIfNeeded() -> LexiconData {
        if let existing = state.withLock({ $0 }) {
            return existing
        }
        let loaded = Self.buildLexiconData(customURL: customResourceURL)
        return state.withLock { current in
            if let existing = current {
                return existing
            }
            current = loaded
            return loaded
        }
    }

    private static func buildLexiconData(customURL: URL?) -> LexiconData {
        let payload = readPayloadFromDisk(customURL: customURL)

        var exactMap: [String: [EnglishMatch]] = [:]
        var indexedWords: [IndexedWord] = []
        var mixEligibleKeys = Set<String>()
        var seenEntries = Set<String>()

        func insert(key rawKey: String, match: EnglishMatch) {
            let key = rawKey.lowercased()
            guard !key.isEmpty, !match.text.isEmpty else { return }
            let dedup = "\(key)\t\(match.text)"
            guard seenEntries.insert(dedup).inserted else { return }
            exactMap[key, default: []].append(match)
            indexedWords.append(IndexedWord(key: key, match: match))
            if isMixEligible(key: key, match: match) {
                mixEligibleKeys.insert(key)
            }
        }

        for entry in payload?.words ?? [] {
            insert(key: entry.k, match: EnglishMatch(text: entry.t, weight: entry.w, preferFirst: entry.p))
        }
        // Supplement curated tech/office terms if JSON is absent or lacks any core entry
        for fallback in fallbackWords where exactMap[fallback.k] == nil {
            insert(key: fallback.k, match: EnglishMatch(text: fallback.t, weight: fallback.w, preferFirst: fallback.p))
        }

        for (key, list) in exactMap {
            exactMap[key] = list.sorted { lhs, rhs in
                if lhs.preferFirst != rhs.preferFirst { return lhs.preferFirst && !rhs.preferFirst }
                if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
                return lhs.text < rhs.text
            }
        }

        var prefix2Buckets: [String: [IndexedWord]] = [:]
        for item in indexedWords where item.key.count >= 2 {
            let bucketKey = String(item.key.prefix(2))
            prefix2Buckets[bucketKey, default: []].append(item)
        }
        for (bucketKey, list) in prefix2Buckets {
            prefix2Buckets[bucketKey] = list.sorted { lhs, rhs in
                if lhs.match.weight != rhs.match.weight { return lhs.match.weight > rhs.match.weight }
                if lhs.key.count != rhs.key.count { return lhs.key.count < rhs.key.count }
                return lhs.match.text < rhs.match.text
            }
        }

        var mixedMap = fallbackMixedPhrases
        for (k, v) in payload?.mixed ?? [:] {
            let normalized = normalizeKey(k)
            if !normalized.isEmpty, !v.isEmpty {
                mixedMap[normalized] = v
            }
        }

        return LexiconData(
            exactMap: exactMap,
            prefix2Buckets: prefix2Buckets,
            mixedMap: mixedMap,
            mixEligibleKeys: mixEligibleKeys
        )
    }

    private static func readPayloadFromDisk(customURL: URL?) -> RawPayload? {
        var candidates: [URL?] = []
        if let customURL {
            candidates.append(customURL)
        } else {
            candidates.append(Bundle.main.url(forResource: "english_lexicon", withExtension: "json"))
            candidates.append(Bundle(for: EnglishMixEngine.self).url(forResource: "english_lexicon", withExtension: "json"))
            candidates.append(sourceRoot.appendingPathComponent("Resources/english_lexicon.json"))
        }

        for case let url? in candidates {
            guard FileManager.default.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url),
                  !data.isEmpty,
                  let decoded = try? JSONDecoder().decode(RawPayload.self, from: data) else {
                continue
            }
            return decoded
        }
        return nil
    }

    private static func normalizeKey(_ input: String) -> String {
        input.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeWithBoundaries(_ input: String) -> (String, Set<Int>) {
        var normalized = ""
        var boundaries = Set<Int>()
        for ch in input.lowercased() {
            if ch == "'" {
                if !normalized.isEmpty {
                    boundaries.insert(normalized.count)
                }
            } else if !ch.isWhitespace {
                normalized.append(ch)
            }
        }
        return (normalized, boundaries)
    }

    private static func isASCIIAlphanumeric(_ text: String) -> Bool {
        text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            let v = scalar.value
            return (0x4E00...0x9FFF).contains(v)
                || (0x3400...0x4DBF).contains(v)
                || (0x20000...0x323AF).contains(v)
                || (0xF900...0xFAFF).contains(v)
        }
    }

    private static func joinSegments(_ left: String, _ right: String, pangu: Bool) -> String {
        guard pangu else { return left + right }
        return left + PanguSpacing.shared.formatCommitText(preceding: left.last, committing: right)
    }

    private static func isMixEligible(key: String, match: EnglishMatch) -> Bool {
        if match.preferFirst { return true }
        if match.text != match.text.lowercased() { return true }
        if curatedFallbackKeys.contains(key) { return true }
        return key.count >= 4 && match.weight >= 700 && !pinyinCollisionSyllables.contains(key)
    }

    private static let fallbackWords: [(k: String, t: String, w: Int, p: Bool)] = [
        ("ok", "OK", 990, true),
        ("app", "App", 985, true),
        ("api", "API", 980, true),
        ("ppt", "PPT", 975, true),
        ("pdf", "PDF", 975, true),
        ("wifi", "WiFi", 970, true),
        ("bug", "bug", 970, false),
        ("ai", "AI", 965, false),
        ("gpt", "GPT", 965, true),
        ("llm", "LLM", 955, true),
        ("mac", "Mac", 950, false),
        ("macos", "macOS", 950, true),
        ("iphone", "iPhone", 950, true),
        ("ipad", "iPad", 945, true),
        ("wechat", "WeChat", 940, true),
        ("github", "GitHub", 945, true),
        ("vscode", "VSCode", 935, true),
        ("python", "Python", 940, true),
        ("swift", "Swift", 935, true),
        ("docker", "Docker", 930, true),
        ("json", "JSON", 925, false),
        ("http", "HTTP", 930, true),
        ("https", "HTTPS", 930, true),
        ("url", "URL", 925, true),
        ("chatgpt", "ChatGPT", 950, true),
        ("openai", "OpenAI", 940, true),
        ("claude", "Claude", 940, true),
        ("gemini", "Gemini", 935, false),
        ("deepseek", "DeepSeek", 940, true),
        ("cursor", "Cursor", 930, true),
        ("pr", "PR", 910, false),
        ("mr", "MR", 890, false),
        ("ui", "UI", 915, false),
        ("ux", "UX", 900, false),
        ("pm", "PM", 905, false),
        ("ceo", "CEO", 910, false),
        ("cto", "CTO", 895, false),
        ("kpi", "KPI", 905, true),
        ("okr", "OKR", 905, true),
        ("todo", "TODO", 900, false),
        ("demo", "demo", 900, false),
        ("debug", "debug", 860, true),
        ("commit", "commit", 880, true),
        ("deploy", "deploy", 850, false),
        ("merge", "merge", 850, false),
        ("branch", "branch", 845, false),
        ("email", "email", 915, false),
        ("code", "code", 880, false),
        ("xcode", "Xcode", 920, true),
        ("bilibili", "Bilibili", 880, false),
        ("linux", "Linux", 910, true),
        ("windows", "Windows", 910, true),
        ("android", "Android", 910, true),
        ("ios", "iOS", 920, true),
        ("react", "React", 895, true),
        ("vue", "Vue", 880, false),
        ("node", "Node", 885, false),
        ("rust", "Rust", 885, false),
        ("sql", "SQL", 910, true),
        ("redis", "Redis", 890, true),
        ("git", "git", 895, false),
        ("ssh", "SSH", 905, true),
        ("vpn", "VPN", 910, true),
        ("cpu", "CPU", 915, true),
        ("gpu", "GPU", 915, true),
        ("icloud", "iCloud", 915, true),
        ("airdrop", "AirDrop", 905, true),
        ("hello", "hello", 870, false),
        ("world", "world", 865, false),
        ("thanks", "thanks", 860, false),
        ("sorry", "sorry", 860, false),
        ("good", "good", 855, false),
        ("nice", "nice", 855, false),
        ("test", "test", 865, false),
        ("fix", "fix", 855, false),
        ("file", "file", 850, false),
        ("data", "data", 860, false),
        ("user", "user", 855, false),
        ("time", "time", 855, false)
    ]

    private static let curatedFallbackKeys: Set<String> = Set(fallbackWords.map(\.k))

    private static let fallbackMixedPhrases: [String: String] = [
        "bzhan": "B站",
        "azhan": "A站",
        "upzhu": "UP主",
        "cp": "CP",
        "p0": "P0",
        "p1": "P1",
        "p2": "P2"
    ]

    private static let pinyinCollisionSyllables: Set<String> = [
        "bang", "chang", "cheng", "chong", "chuang", "dang", "dian", "ding", "dong",
        "fang", "feng", "gang", "gong", "guan", "guang", "hang", "heng", "hong", "huan",
        "huang", "jiang", "jiao", "jing", "juan", "kang", "kong", "kuan", "kuang",
        "lang", "leng", "lian", "liang", "liao", "ling", "long", "luan", "mang",
        "meng", "mian", "miao", "ming", "nang", "neng", "nian", "niang", "niao",
        "ning", "nong", "pang", "peng", "pian", "piao", "ping", "qian", "qiang",
        "qiao", "qing", "quan", "rang", "reng", "rong", "ruan", "sang", "seng",
        "shan", "shang", "shao", "shen", "sheng", "shou", "shua", "shuan", "shuang",
        "shui", "shun", "shuo", "song", "suan", "tang", "teng", "tian", "tiao",
        "ting", "tong", "tuan", "wang", "weng", "xian", "xiang", "xiao", "xing",
        "xiong", "xuan", "yang", "ying", "yong", "yuan", "zang", "zeng", "zhan",
        "zhang", "zhao", "zhen", "zheng", "zhong", "zhou", "zhua", "zhuan", "zhuang",
        "zhui", "zhun", "zhuo", "zong", "zuan",
        // Common English words that collide with multi-syllable pinyin strings
        "women", "nide", "wode", "tade", "meiyou", "keyi", "shanghai", "beijing",
        "xian", "jintian", "mingtian", "diannao", "shouji", "gongsi", "xianzai"
    ]
}
