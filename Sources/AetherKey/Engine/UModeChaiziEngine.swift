import Foundation
import os

/// U-mode radical decomposition (拆字) and 5-stroke (`h/s/p/n/z`) character lookup engine
/// backed by `Resources/chaizi.json`.
public final class UModeChaiziEngine: Sendable {
    public static let shared = UModeChaiziEngine()

    public struct Entry: Decodable, Sendable, Equatable {
        public let c: String
        public let d: String
        public let p: String

        public init(c: String, d: String, p: String) {
            self.c = c
            self.d = d
            self.p = p
        }
    }

    private struct RawPayload: Decodable {
        let parts: [String: [Entry]]?
        let strokes: [String: [String]]?
    }

    private struct ChaiziData: Sendable {
        let parts: [String: [Entry]]
        let sortedPartKeys: [String]
        let strokes: [String: [String]]
        let sortedStrokeKeys: [String]
    }

    private static let sourceRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private static let strokeCharacters: Set<Character> = ["h", "s", "p", "n", "z"]

    private let customResourceURL: URL?
    private let state = OSAllocatedUnfairLock<ChaiziData?>(initialState: nil)

    public init(resourceURL: URL? = nil) {
        self.customResourceURL = resourceURL
    }

    /// Preloads `chaizi.json` into memory.
    public func preload() {
        _ = loadDataIfNeeded()
    }

    /// Queries U-mode radical decomposition and 5-stroke candidates for inputs like `"uhuohuo"` or `"uhs"`.
    public func query(_ rawInput: String) -> [Candidate] {
        guard rawInput.lowercased().hasPrefix("u"), rawInput.count > 1 else { return [] }

        let body = String(rawInput.dropFirst())
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return [] }

        let data = loadDataIfNeeded()
        let isStrokeQuery = body.allSatisfy { Self.strokeCharacters.contains($0) }
        let maxCandidates = 36

        var results: [Candidate] = []
        var seenChars = Set<String>()

        func appendPartEntry(_ entry: Entry) {
            guard results.count < maxCandidates, !entry.c.isEmpty else { return }
            guard seenChars.insert(entry.c).inserted else { return }
            let comment: String?
            if !entry.d.isEmpty && !entry.p.isEmpty {
                comment = "\(entry.d) · \(entry.p)"
            } else if !entry.d.isEmpty {
                comment = entry.d
            } else if !entry.p.isEmpty {
                comment = entry.p
            } else {
                comment = nil
            }
            results.append(Candidate(
                text: entry.c,
                comment: comment,
                consumedInputLength: rawInput.count
            ))
        }

        func appendStrokeChar(_ char: String) {
            guard results.count < maxCandidates, !char.isEmpty else { return }
            guard seenChars.insert(char).inserted else { return }
            results.append(Candidate(
                text: char,
                comment: "笔画",
                consumedInputLength: rawInput.count
            ))
        }

        // 1. Exact decomposition matches
        for entry in data.parts[body] ?? [] {
            appendPartEntry(entry)
        }

        // 2. Exact 5-stroke matches when query uses only h/s/p/n/z
        if isStrokeQuery {
            for char in data.strokes[body] ?? [] {
                appendStrokeChar(char)
            }
        }

        // 3. Prefix decomposition matches (shorter keys first)
        if results.count < maxCandidates {
            for key in data.sortedPartKeys where key != body && key.hasPrefix(body) {
                for entry in data.parts[key] ?? [] {
                    appendPartEntry(entry)
                    if results.count >= maxCandidates { break }
                }
                if results.count >= maxCandidates { break }
            }
        }

        // 4. Prefix 5-stroke matches
        if isStrokeQuery, results.count < maxCandidates {
            for key in data.sortedStrokeKeys where key != body && key.hasPrefix(body) {
                for char in data.strokes[key] ?? [] {
                    appendStrokeChar(char)
                    if results.count >= maxCandidates { break }
                }
                if results.count >= maxCandidates { break }
            }
        }

        // 5. Raw literal fallback
        results.append(Candidate(
            text: rawInput,
            comment: "英",
            consumedInputLength: rawInput.count
        ))

        return results
    }

    private func loadDataIfNeeded() -> ChaiziData {
        if let existing = state.withLock({ $0 }) {
            return existing
        }
        let loaded = Self.buildData(customURL: customResourceURL)
        return state.withLock { current in
            if let existing = current {
                return existing
            }
            current = loaded
            return loaded
        }
    }

    private static func buildData(customURL: URL?) -> ChaiziData {
        let payload = readPayloadFromDisk(customURL: customURL)

        var parts: [String: [Entry]] = [:]
        for (rawKey, entries) in payload?.parts ?? [:] {
            let key = rawKey.lowercased()
            guard !key.isEmpty else { continue }
            var list = parts[key] ?? []
            var seen = Set(list.map(\.c))
            for entry in entries where !entry.c.isEmpty && seen.insert(entry.c).inserted {
                list.append(entry)
            }
            if !list.isEmpty {
                parts[key] = list
            }
        }

        for (key, entries) in fallbackParts {
            var list = parts[key] ?? []
            var seen = Set(list.map(\.c))
            for entry in entries where seen.insert(entry.c).inserted {
                list.append(entry)
            }
            parts[key] = list
        }

        var strokes: [String: [String]] = [:]
        for (rawKey, chars) in payload?.strokes ?? [:] {
            let key = rawKey.lowercased()
            guard !key.isEmpty else { continue }
            var list = strokes[key] ?? []
            var seen = Set(list)
            for ch in chars where !ch.isEmpty && seen.insert(ch).inserted {
                list.append(ch)
            }
            if !list.isEmpty {
                strokes[key] = list
            }
        }

        for (key, chars) in fallbackStrokes {
            var list = strokes[key] ?? []
            var seen = Set(list)
            for ch in chars where seen.insert(ch).inserted {
                list.append(ch)
            }
            strokes[key] = list
        }

        let sortedPartKeys = parts.keys.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count < rhs.count }
            return lhs < rhs
        }
        let sortedStrokeKeys = strokes.keys.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count < rhs.count }
            return lhs < rhs
        }

        return ChaiziData(
            parts: parts,
            sortedPartKeys: sortedPartKeys,
            strokes: strokes,
            sortedStrokeKeys: sortedStrokeKeys
        )
    }

    private static func readPayloadFromDisk(customURL: URL?) -> RawPayload? {
        var candidates: [URL?] = []
        if let customURL {
            candidates.append(customURL)
        } else {
            candidates.append(Bundle.main.url(forResource: "chaizi", withExtension: "json"))
            candidates.append(Bundle(for: UModeChaiziEngine.self).url(forResource: "chaizi", withExtension: "json"))
            candidates.append(sourceRoot.appendingPathComponent("Resources/chaizi.json"))
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

    private static let fallbackParts: [String: [Entry]] = [
        "huohuo": [Entry(c: "炎", d: "火+火", p: "yán")],
        "huohuohuo": [Entry(c: "焱", d: "火+火+火", p: "yàn")],
        "mumu": [Entry(c: "林", d: "木+木", p: "lín")],
        "mumumu": [Entry(c: "森", d: "木+木+木", p: "sēn")],
        "shuishui": [Entry(c: "沝", d: "水+水", p: "zhuǐ")],
        "shuishuishui": [Entry(c: "淼", d: "水+水+水", p: "miǎo")],
        "jinjin": [Entry(c: "鍂", d: "金+金", p: "jīn")],
        "jinjinjin": [Entry(c: "鑫", d: "金+金+金", p: "xīn")],
        "tututu": [Entry(c: "垚", d: "土+土+土", p: "yáo")],
        "shishishi": [Entry(c: "磊", d: "石+石+石", p: "lěi")],
        "niuniuniu": [Entry(c: "犇", d: "牛+牛+牛", p: "bēn")],
        "longlonglong": [Entry(c: "龘", d: "龍+龍+龍", p: "dá")],
        "ririri": [Entry(c: "晶", d: "日+日+日", p: "jīng")],
        "riyue": [Entry(c: "明", d: "日+月", p: "míng")],
        "koushi": [Entry(c: "古", d: "十+口", p: "gǔ")],
        "shikou": [Entry(c: "古", d: "十+口", p: "gǔ")],
        "renren": [Entry(c: "从", d: "人+人", p: "cóng")],
        "renrenren": [Entry(c: "众", d: "人+人+人", p: "zhòng")],
        "nvzi": [Entry(c: "好", d: "女+子", p: "hǎo")],
        "tianli": [Entry(c: "男", d: "田+力", p: "nán")],
        "xiaoda": [Entry(c: "尖", d: "小+大", p: "jiān")],
        "shanshi": [Entry(c: "岩", d: "山+石", p: "yán")],
        "jiji": [Entry(c: "喆", d: "吉+吉", p: "zhé")],
        "yueyue": [Entry(c: "朋", d: "月+月", p: "péng")],
        "koukoukou": [Entry(c: "品", d: "口+口+口", p: "pǐn")],
        "baishui": [Entry(c: "泉", d: "白+水", p: "quán")],
        "renmu": [Entry(c: "休", d: "亻+木", p: "xiū")],
        "shoumu": [Entry(c: "看", d: "手+目", p: "kàn")],
        "mushui": [Entry(c: "沐", d: "氵+木", p: "mù")],
        "baimu": [Entry(c: "柏", d: "木+白", p: "bǎi")],
        "checheche": [Entry(c: "轰", d: "车+车+车", p: "hōng")]
    ]

    private static let fallbackStrokes: [String: [String]] = [
        "h": ["一"],
        "hh": ["二", "丁"],
        "hhh": ["三", "王"],
        "s": ["丨"],
        "p": ["丿", "人"],
        "n": ["丶"],
        "z": ["乙", "了"],
        "hs": ["十", "七"],
        "hsp": ["木", "才"],
        "hsn": ["寸"]
    ]
}
