import Foundation

/// Text stays first. Interleave emoji according to `AetherSettings.shared.emojiSuggestionStyle`.
/// Apple's private ranking model is not exposed. Phrase overrides below record
/// observed macOS Pinyin behavior, rather than claiming to reproduce that model.
enum CandidateRanking {
    static func merge(text: [Candidate], input: String) -> [Candidate] {
        let key = input.lowercased().filter { $0 != "'" && !$0.isWhitespace }
        var text = text
        let style = AetherSettings.shared.emojiSuggestionStyle

        // macOS 27 Pinyin, verified in TextEdit on 2026-10-23:
        // 我爱你 / 🤟 / 我爱妳 / 😘. Preserve the user's first text choice.
        if key == "woaini" {
            let alternative = "我爱妳"
            if !text.contains(where: { $0.text == alternative }) {
                text.insert(Candidate(text: alternative, consumedInputLength: input.count), at: min(1, text.count))
            } else if let index = text.firstIndex(where: { $0.text == alternative }), index > 1 {
                text.insert(text.remove(at: index), at: 1)
            }
        }

        if style == .off {
            return text
        }

        var matches = EmojiLexicon.matches(for: input)
        var primary = EmojiLexicon.primaryMatches(for: input)

        if key == "woaini" {
            primary = [EmojiLexicon.Entry(text: "🤟", name: "爱你手势"),
                       EmojiLexicon.Entry(text: "😘", name: "飞吻")]
            for entry in primary where !matches.contains(where: { $0.text == entry.text }) { matches.append(entry) }
        }

        guard !matches.isEmpty else { return text }
        // A weak keyword can still offer one useful suggestion, but cannot fill
        // the first page with loosely related hearts, skin tones, or symbols.
        if primary.isEmpty, let first = matches.first { primary = [first] }

        var result: [Candidate] = []
        var seen = Set<String>()
        func append(_ candidate: Candidate) {
            let canonical = candidate.text.replacingOccurrences(of: "\u{FE0F}", with: "")
            if seen.insert(canonical).inserted { result.append(candidate) }
        }
        func emoji(_ entry: EmojiLexicon.Entry) -> Candidate {
            Candidate(text: entry.text, isEmoji: true, consumedInputLength: input.count)
        }

        if style == .all || key == "woaini" {
            let promoted = Array(primary.prefix(2))
            for (index, candidate) in text.enumerated() {
                append(candidate)
                if index < promoted.count { append(emoji(promoted[index])) }
            }
            for entry in promoted { append(emoji(entry)) }
            for entry in matches { append(emoji(entry)) }
            return result
        }

        // `.smartPhrase`: never put emojis in top positions for single-syllable inputs.
        let isSingleSyllable = !input.contains("'")
            && (PinyinLexicon.allSyllables.contains(key) || PinyinLexicon.syllablesChars[key] != nil)
        if isSingleSyllable {
            let insertAfter = min(10, text.count)
            for candidate in text.prefix(insertAfter) { append(candidate) }
            for entry in primary { append(emoji(entry)) }
            for entry in matches { append(emoji(entry)) }
            for candidate in text.dropFirst(insertAfter) { append(candidate) }
            return result
        }

        // Multi-syllable phrases under `.smartPhrase`: insert at most 1 primary emoji
        // at index 2 if >= 2 common phrases lead, else at index 1.
        let lm = LanguageModel.shared
        let hasTwoTopPhrases: Bool = {
            guard text.count >= 2 else { return false }
            let first = text[0]
            let second = text[1]
            let firstFull = first.consumedInputLength == 0 || first.consumedInputLength == input.count
            let secondFull = second.consumedInputLength == 0 || second.consumedInputLength == input.count
            guard firstFull, secondFull,
                  first.comment != "英", second.comment != "英",
                  first.text.count >= 2, second.text.count >= 2 else {
                return false
            }
            let s0 = lm.unigramScore(for: first.text)
            let s1 = lm.unigramScore(for: second.text)
            let inCore = PinyinLexicon.builtinCorePhrases[key]?.prefix(2).contains(second.text) == true
            return (s1 >= -520.0 && s1 >= s0 - 120.0) || inCore
        }()

        let promotedSlot = min(hasTwoTopPhrases ? 2 : 1, text.count)
        for (index, candidate) in text.enumerated() {
            if index == promotedSlot, let topEmoji = primary.first {
                append(emoji(topEmoji))
            }
            append(candidate)
        }
        if text.count <= promotedSlot, let topEmoji = primary.first {
            append(emoji(topEmoji))
        }
        for entry in primary.dropFirst() { append(emoji(entry)) }
        for entry in matches { append(emoji(entry)) }
        return result
    }
}
