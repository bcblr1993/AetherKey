import Foundation

// Generate offline pinyin lookup data from Unicode CLDR 48 Chinese annotations.
// Usage: swift scripts/build_emoji_lexicon.swift annotations.json derived.json Resources/emoji.json
// Sources: https://github.com/unicode-org/cldr-json/tree/48.0.0/cldr-json
// License: Resources/Unicode-LICENSE.txt
struct Annotation: Decodable { let `default`: [String]?; let tts: [String]? }
struct Table: Decodable { let annotations: [String: Annotation] }
struct Source: Decodable { let annotations: Table?; let annotationsDerived: Table? }
struct Entry: Codable, Equatable { let text: String; let name: String }
func pinyin(_ text: String) -> String {
    let digits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
    let expanded = text.map { char -> String in
        if char.isASCII, let digit = char.wholeNumberValue { return digits[digit] }
        return String(char)
    }.joined()
    let latin = expanded.applyingTransform(.toLatin, reverse: false) ?? expanded
    return latin.decomposedStringWithCanonicalMapping.replacingOccurrences(of: "u\u{0308}", with: "v")
        .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        .lowercased().filter { $0.isASCII && $0.isLetter }
}
var entries: [String: [Entry]] = [:]
for path in CommandLine.arguments.dropFirst().dropLast() {
    let source = try JSONDecoder().decode(Source.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    for (raw, annotation) in (source.annotations ?? source.annotationsDerived)!.annotations.sorted(by: { $0.key < $1.key }) {
        guard raw.unicodeScalars.contains(where: { ($0.properties.isEmoji && $0.value > 127) || $0.value == 0x20E3 }) else { continue }
        // CLDR omits the presentation selector for some symbols. Commit them as color emoji.
        let text = raw.unicodeScalars.count == 1 && !raw.unicodeScalars.first!.properties.isEmojiPresentation
            ? raw + "\u{FE0F}" : raw
        let name = annotation.tts?.first ?? annotation.default?.first ?? raw
        let entry = Entry(text: text, name: name)
        for keyword in Set((annotation.default ?? []) + (annotation.tts ?? [])) {
            let key = pinyin(keyword)
            guard !key.isEmpty else { continue }
            if !(entries[key] ?? []).contains(entry) { entries[key, default: []].append(entry) }
        }
    }
}
// Familiar everyday terms, ordered ahead of broader CLDR keyword matches.
let aliases: [(String, String, String)] = [
    ("玫瑰", "🌹", "玫瑰"), ("美国", "🇺🇸", "美国"), ("中国", "🇨🇳", "中国"),
    ("开心", "😄", "开心"), ("微笑", "😊", "微笑"), ("笑哭", "😂", "笑哭"),
    ("爱心", "❤️", "爱心"), ("红心", "❤️", "红心"), ("点赞", "👍", "点赞"),
    ("谢谢", "🙏", "谢谢"), ("生日快乐", "🎂", "生日蛋糕"), ("咖啡", "☕", "咖啡")
]
for (keyword, text, name) in aliases.reversed() {
    let key = pinyin(keyword)
    entries[key, default: []].removeAll { $0.text == text }
    entries[key, default: []].insert(Entry(text: text, name: name), at: 0)
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
try encoder.encode(entries).write(to: URL(fileURLWithPath: CommandLine.arguments.last!))
print("Generated \(entries.count) pinyin keys, \(Set(entries.values.flatMap { $0.map(\.text) }).count) emoji")
