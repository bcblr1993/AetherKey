import Foundation

/// Table lookup only: the LGPL-3.0 Rime table is shipped unmodified and replaceable.
/// No Rime code or runtime dependency is linked into AetherKey.
public final class WubiEngine: @unchecked Sendable {
    public static let shared = WubiEngine()
    public static func learningKey(_ code: String) -> String { "wubi86:" + code.lowercased() }

    private struct Entry {
        let text: String
        let code: String
        let weight: UInt64
    }
    private var exact: [String: [Entry]] = [:]
    private var completions: [String: [Entry]] = [:]
    private var characterCodes: [Character: String] = [:]
    private let userLexicon: UserLexicon
    public private(set) var entryCount = 0
    public var characterCount: Int { characterCodes.count }

    init(userLexicon: UserLexicon = .shared, tableURL: URL? = nil) {
        self.userLexicon = userLexicon
        let url = tableURL ?? Bundle.main.url(forResource: "wubi86.dict", withExtension: "yaml", subdirectory: "Wubi86")
        guard let url, let source = try? String(contentsOf: url, encoding: .utf8) else { return }
        var rows: [Entry] = []
        var inTable = false
        for line in source.split(separator: "\n") {
            if line == "..." { inTable = true; continue }
            guard inTable, !line.hasPrefix("#") else { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 3, (1...4).contains(fields[1].count),
                  fields[1].allSatisfy({ $0 >= "a" && $0 <= "y" }),
                  let weight = UInt64(fields[2]), !fields[0].isEmpty else { continue }
            rows.append(Entry(text: String(fields[0]), code: String(fields[1]), weight: weight))
        }
        // Stable lexical tie-breaks make ordering independent of Dictionary iteration.
        rows.sort {
            if $0.weight != $1.weight { return $0.weight > $1.weight }
            if $0.code != $1.code { return $0.code < $1.code }
            return $0.text < $1.text
        }
        entryCount = rows.count
        for row in rows {
            exact[row.code, default: []].append(row)
            if row.text.count == 1, let char = row.text.first,
               row.code.count > (characterCodes[char]?.count ?? 0) {
                characterCodes[char] = row.code
            }
            // Bound incomplete-code suggestions without truncating any exact code.
            for length in 1..<row.code.count {
                let prefix = String(row.code.prefix(length))
                if (completions[prefix]?.count ?? 0) < 128 {
                    completions[prefix, default: []].append(row)
                }
            }
        }
    }

    /// Standard 86 phrase encoding: 2+2, 1+1+2, or first three + final character.
    public func code(for text: String) -> String? {
        let chars = Array(text)
        guard !chars.isEmpty else { return nil }
        let codes = chars.compactMap { characterCodes[$0] }
        guard codes.count == chars.count else { return nil }
        switch codes.count {
        case 1: return codes[0]
        case 2: return String(codes[0].prefix(2)) + String(codes[1].prefix(2))
        case 3: return String(codes[0].prefix(1)) + String(codes[1].prefix(1)) + String(codes[2].prefix(2))
        default: return codes.prefix(3).map { String($0.prefix(1)) }.joined() + String(codes.last!.prefix(1))
        }
    }

    public func query(_ input: String) -> [Candidate] {
        let raw = input.lowercased()
        guard !raw.isEmpty else { return [] }
        let key = Self.learningKey(raw)
        var result: [Candidate] = []
        var seen = Set<String>()
        func append(_ text: String, comment: String?) {
            guard !userLexicon.isForgotten(text, for: key), seen.insert(text).inserted else { return }
            result.append(Candidate(text: text, comment: comment, pinyin: key, consumedInputLength: raw.count))
        }
        for word in userLexicon.preferredWords(for: key) { append(word, comment: code(for: word)) }
        if raw.hasPrefix("z") {
            // z is not a Wubi root: reuse the local pinyin engine for reverse lookup.
            let pinyin = String(raw.dropFirst())
            if !pinyin.isEmpty {
                for candidate in PinyinEngine.shared.query(rawInput: pinyin)
                    where candidate.comment != "英" && !candidate.isEmoji &&
                          (candidate.consumedInputLength == 0 || candidate.consumedInputLength == pinyin.count) {
                    if let code = code(for: candidate.text) { append(candidate.text, comment: code) }
                }
            }
        } else if (1...4).contains(raw.count), raw.allSatisfy({ $0 >= "a" && $0 <= "y" }) {
            for entry in exact[raw] ?? [] { append(entry.text, comment: nil) }
            for entry in completions[raw] ?? [] { append(entry.text, comment: entry.code) }
        }
        result.append(Candidate(text: raw, comment: "英", consumedInputLength: raw.count))
        return result
    }
}
