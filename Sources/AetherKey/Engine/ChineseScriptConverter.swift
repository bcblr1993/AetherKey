import Foundation

/// Converts Simplified Chinese candidates and text to Traditional Chinese using
/// Foundation's ICU transform with curated phrase overrides for one-to-many cases.
public final class ChineseScriptConverter: Sendable {
    public static let shared = ChineseScriptConverter()

    private static let hansToHant = StringTransform(rawValue: "Hans-Hant")

    private static let phraseOverrides: [String: String] = [
        "回复": "回覆",
        "反复": "反覆",
        "复习": "複習",
        "复印": "複印",
        "复查": "複查",
        "复试": "複試",
        "复合": "複合",
        "复审": "複審",
        "腕表": "腕錶",
        "怀表": "懷錶",
        "秒表": "秒錶",
        "电表": "電錶",
        "水表": "水錶",
        "仪表": "儀錶",
        "台风": "颱風"
    ]

    private static let maxOverrideLength = phraseOverrides.keys.map(\.count).max() ?? 0

    private init() {}

    public func toTraditional(_ text: String) -> String {
        guard !text.isEmpty, !text.unicodeScalars.allSatisfy(\.isASCII) else {
            return text
        }

        var result = ""
        result.reserveCapacity(text.count)
        var plainStart = text.startIndex
        var cursor = text.startIndex

        while cursor < text.endIndex {
            var matchedEnd: String.Index?
            var matchedReplacement: String?

            if Self.maxOverrideLength > 0 {
                var probe = cursor
                var slices: [String.Index] = []
                slices.reserveCapacity(Self.maxOverrideLength)
                for _ in 0..<Self.maxOverrideLength {
                    guard probe < text.endIndex else { break }
                    probe = text.index(after: probe)
                    slices.append(probe)
                }
                for endIdx in slices.reversed() {
                    let sub = String(text[cursor..<endIdx])
                    if let replacement = Self.phraseOverrides[sub] {
                        matchedEnd = endIdx
                        matchedReplacement = replacement
                        break
                    }
                }
            }

            if let endIdx = matchedEnd, let replacement = matchedReplacement {
                if plainStart < cursor {
                    result.append(transformSegment(String(text[plainStart..<cursor])))
                }
                result.append(replacement)
                cursor = endIdx
                plainStart = cursor
            } else {
                cursor = text.index(after: cursor)
            }
        }

        if plainStart < text.endIndex {
            result.append(transformSegment(String(text[plainStart..<text.endIndex])))
        }
        return result
    }

    public func convertCandidates(_ candidates: [Candidate], toTraditional: Bool) -> [Candidate] {
        guard toTraditional else { return candidates }

        var result: [Candidate] = []
        result.reserveCapacity(candidates.count)
        var seen = Set<String>()

        for candidate in candidates {
            if candidate.comment == "英" || candidate.isEmoji || candidate.isVMode {
                if seen.insert(candidate.text).inserted {
                    result.append(candidate)
                }
                continue
            }

            let converted = self.toTraditional(candidate.text)
            guard seen.insert(converted).inserted else { continue }
            result.append(
                Candidate(
                    id: candidate.id,
                    text: converted,
                    comment: candidate.comment,
                    pinyin: candidate.pinyin,
                    isVMode: candidate.isVMode,
                    isEmoji: candidate.isEmoji,
                    consumedInputLength: candidate.consumedInputLength,
                    rawText: candidate.rawText ?? candidate.text
                )
            )
        }
        return result
    }

    private func transformSegment(_ segment: String) -> String {
        guard !segment.isEmpty, !segment.unicodeScalars.allSatisfy(\.isASCII) else {
            return segment
        }
        return segment.applyingTransform(Self.hansToHant, reverse: false) ?? segment
    }
}
