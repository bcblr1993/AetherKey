import Foundation

/// Text stays first. Interleave up to two relevant emoji with text alternatives;
/// broad keyword matches stay available after the ordinary text candidates.
/// Apple's private ranking model is not exposed. Phrase overrides below record
/// observed macOS Pinyin behavior, rather than claiming to reproduce that model.
enum CandidateRanking {
    static func merge(text: [Candidate], input: String) -> [Candidate] {
        let key = input.lowercased().filter { $0 != "'" && !$0.isWhitespace }
        var text = text
        var matches = EmojiLexicon.matches(for: input)
        var primary = EmojiLexicon.primaryMatches(for: input)

        // macOS 27 Pinyin, verified in TextEdit on 2026-10-23:
        // 我爱你 / 🤟 / 我爱妳 / 😘. Preserve the user's first text choice.
        if key == "woaini" {
            let alternative = "我爱妳"
            if !text.contains(where: { $0.text == alternative }) {
                text.insert(Candidate(text: alternative, consumedInputLength: input.count), at: min(1, text.count))
            } else if let index = text.firstIndex(where: { $0.text == alternative }), index > 1 {
                text.insert(text.remove(at: index), at: 1)
            }
            primary = [EmojiLexicon.Entry(text: "🤟", name: "爱你手势"),
                       EmojiLexicon.Entry(text: "😘", name: "飞吻")]
            for entry in primary where !matches.contains(where: { $0.text == entry.text }) { matches.append(entry) }
        }

        guard !matches.isEmpty else { return text }
        // A weak keyword can still offer one useful suggestion, but cannot fill
        // the first page with loosely related hearts, skin tones, or symbols.
        if primary.isEmpty, let first = matches.first { primary = [first] }
        let promoted = Array(primary.prefix(2))
        var result: [Candidate] = []
        var seen = Set<String>()
        func append(_ candidate: Candidate) {
            let canonical = candidate.text.replacingOccurrences(of: "\u{FE0F}", with: "")
            if seen.insert(canonical).inserted { result.append(candidate) }
        }
        func emoji(_ entry: EmojiLexicon.Entry) -> Candidate {
            Candidate(text: entry.text, isEmoji: true, consumedInputLength: input.count)
        }
        for (index, candidate) in text.enumerated() {
            append(candidate)
            if index < promoted.count { append(emoji(promoted[index])) }
        }
        for entry in promoted { append(emoji(entry)) }
        for entry in matches { append(emoji(entry)) }
        return result
    }
}
