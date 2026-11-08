import Foundation

/// Persistent user dictionary and dynamic word frequency learning engine.
/// Boosts frequently committed words and supports user-defined custom phrases.
public final class UserLexicon: @unchecked Sendable {
    public static let shared = UserLexicon()
    
    private let lock = NSLock()
    /// Mapping: normalized pinyin key -> (word -> score/frequency)
    private var frequencyTable: [String: [String: Int]] = [:]
    /// Custom user-added phrases: normalized pinyin key -> [words]
    private var customPhrases: [String: [String]] = [:]
    private var totalCommittedCharsCount: Int = 0
    private var pinnedWords: [String: [String]] = [:]
    private var forgottenWords: [String: [String]] = [:]
    private let saveQueue = DispatchQueue(label: "com.aethernative.AetherKey.lexicon-save")
    
    private static let defaultStorageURL: URL = {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil || env["XCTestSessionIdentifier"] != nil || env["XCTestBundlePath"] != nil {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("aetherkey-xctest-shared-\(ProcessInfo.processInfo.processIdentifier).json")
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("AetherKey", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("user_lexicon.json")
    }()
    
    private let storageURL: URL

    private struct PersistedData: Codable, Sendable {
        var frequencyTable: [String: [String: Int]]
        var customPhrases: [String: [String]]
        var totalCommittedCharsCount: Int
        var pinnedWords: [String: [String]]?
        var forgottenWords: [String: [String]]?
    }

    public enum ImportMode: String, CaseIterable, Identifiable, Sendable {
        case merge
        case replace

        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .merge: return "合并导入"
            case .replace: return "覆盖恢复"
            }
        }
    }

    public struct ImportSummary: Sendable, Equatable {
        public let mode: ImportMode
        public let customPhraseCount: Int
        public let learnedWordCount: Int
        public let pinnedWordCount: Int
        public let forgottenWordCount: Int
    }

    public enum LexiconTransferError: LocalizedError, Sendable, Equatable {
        case emptyInput
        case invalidFormat

        public var errorDescription: String? {
            switch self {
            case .emptyInput:
                return "词库文件为空，未发现可导入的词条。"
            case .invalidFormat:
                return "无法识别词库文件格式。支持 AetherKey JSON 备份或「编码 词条」文本文件。"
            }
        }
    }
    
    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL
        loadFromDisk()
    }
    
    /// Records a candidate selection to boost its priority in future queries.
    public func recordCommit(pinyin: String, word: String) {
        let key = pinyin.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !word.isEmpty else { return }
        
        lock.lock()
        totalCommittedCharsCount += word.count
        if AetherSettings.shared.isUserLearningEnabled,
           !(forgottenWords[key] ?? []).contains(word),
           Self.isValidLearnableEntry(key: key, word: word) {
            var wordMap = frequencyTable[key] ?? [:]
            wordMap[word, default: 0] += 1
            frequencyTable[key] = wordMap
        }
        persistLocked()
        lock.unlock()
    }

    /// Rolls back a single frequency increment when the user immediately backspaces a mistaken commit.
    public func rollbackCommit(pinyin: String, word: String) {
        let key = pinyin.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !word.isEmpty else { return }

        lock.lock()
        totalCommittedCharsCount = max(0, totalCommittedCharsCount - word.count)
        if var wordMap = frequencyTable[key], let current = wordMap[word] {
            if current <= 1 {
                wordMap.removeValue(forKey: word)
            } else {
                wordMap[word] = current - 1
            }
            if wordMap.isEmpty {
                frequencyTable.removeValue(forKey: key)
            } else {
                frequencyTable[key] = wordMap
            }
            persistLocked()
        }
        lock.unlock()
    }

    /// Filters out random consonant mashing and excessively long one-off sentences from polluting frequencyTable.
    private static func isValidLearnableEntry(key: String, word: String) -> Bool {
        if key.hasPrefix("wubi86:") {
            let code = key.dropFirst("wubi86:".count)
            return (1...4).contains(code.count) && word.count <= 16
        }
        guard word.count <= 12, key.count <= 36 else { return false }
        if word.count >= 2 && (word.contains("哽") || word.contains("鞥")) {
            return false
        }
        let knownGarbagePairs: Set<String> = [
            "houmina:后米娜", "shijain:时间爱你", "baozhneg:保证呢个",
            "xinag:西那个", "xinag:西拿过", "shemme:社么么",
            "xingnegn:新哽鞥", "rangnni:然哽你", "woshnme:我是能么", "gongzuong:工作哽"
        ]
        if knownGarbagePairs.contains("\(key):\(word)") {
            return false
        }
        if key.count >= 6 {
            let vowels: Set<Character> = ["a", "e", "i", "o", "u", "v"]
            let vowelCount = key.filter { vowels.contains($0) }.count
            // Reject consonant mashing where vowels are < 20% of a long key
            if vowelCount * 5 < key.count {
                return false
            }
        }
        return true
    }
    
    /// Adds a custom user phrase for a specific pinyin code.
    public func addCustomPhrase(pinyin: String, phrase: String) {
        let key = pinyin.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !trimmedPhrase.isEmpty else { return }
        
        lock.lock()
        forgottenWords[key]?.removeAll { $0 == trimmedPhrase }
        var list = customPhrases[key] ?? []
        list.removeAll(where: { $0 == trimmedPhrase })
        list.insert(trimmedPhrase, at: 0)
        customPhrases[key] = list
        
        var wordMap = frequencyTable[key] ?? [:]
        wordMap[trimmedPhrase] = max(wordMap[trimmedPhrase, default: 0], 100)
        frequencyTable[key] = wordMap
        
        persistLocked()
        lock.unlock()
    }
    
    /// Removes a custom phrase.
    public func removeCustomPhrase(pinyin: String, phrase: String) {
        let key = pinyin.lowercased().replacingOccurrences(of: "'", with: "")
        lock.lock()
        customPhrases[key]?.removeAll(where: { $0 == phrase })
        if customPhrases[key]?.isEmpty == true {
            customPhrases.removeValue(forKey: key)
        }
        frequencyTable[key]?.removeValue(forKey: phrase)
        persistLocked()
        lock.unlock()
    }
    
    /// Returns user-preferred words for the given normalized pinyin key, sorted by descending frequency.
    public func preferredWords(for key: String) -> [String] {
        let normalized = key.lowercased().replacingOccurrences(of: "'", with: "")
        lock.lock()
        defer { lock.unlock() }
        
        var result: [String] = pinnedWords[normalized] ?? []
        var seen = Set(result)
        
        if let custom = customPhrases[normalized] {
            for w in custom where !seen.contains(w) {
                seen.insert(w)
                result.append(w)
            }
        }
        
        if AetherSettings.shared.isUserLearningEnabled,
           (normalized.count > 1 || normalized.hasPrefix("wubi86:") || ["a", "o", "e"].contains(normalized)),
           let freqMap = frequencyTable[normalized] {
            let sorted = freqMap.sorted { a, b in
                if a.value != b.value { return a.value > b.value }
                return a.key < b.key
            }
            for (word, _) in sorted where !seen.contains(word) {
                seen.insert(word)
                result.append(word)
            }
        }
        
        return result.filter { !(forgottenWords[normalized] ?? []).contains($0) }
    }
    
    /// Returns all custom phrases as (pinyin, phrase) pairs.
    public func allCustomPhrases() -> [(pinyin: String, phrase: String)] {
        lock.lock()
        defer { lock.unlock() }
        var pairs: [(String, String)] = []
        for (k, words) in customPhrases.sorted(by: { $0.key < $1.key }) {
            for w in words {
                pairs.append((k, w))
            }
        }
        return pairs
    }

    /// Returns all pinned words as (pinyin, word) pairs.
    public func allPinnedWords() -> [(pinyin: String, word: String)] {
        lock.lock()
        defer { lock.unlock() }
        var pairs: [(String, String)] = []
        for (k, words) in pinnedWords.sorted(by: { $0.key < $1.key }) {
            for w in words {
                pairs.append((k, w))
            }
        }
        return pairs
    }

    /// Returns all forgotten words as (pinyin, word) pairs.
    public func allForgottenWords() -> [(pinyin: String, word: String)] {
        lock.lock()
        defer { lock.unlock() }
        var pairs: [(String, String)] = []
        for (k, words) in forgottenWords.sorted(by: { $0.key < $1.key }) {
            for w in words {
                pairs.append((k, w))
            }
        }
        return pairs
    }
    
    public var learnedEntryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return frequencyTable.values.reduce(0) { $0 + $1.count }
    }

    public var customPhraseCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return customPhrases.values.reduce(0) { $0 + $1.count }
    }

    public var pinnedEntryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pinnedWords.values.reduce(0) { $0 + $1.count }
    }
    
    public var totalCommittedCharacters: Int {
        lock.lock()
        defer { lock.unlock() }
        return totalCommittedCharsCount
    }
    
    public func clearLearnedFrequencies() {
        lock.lock()
        frequencyTable.removeAll()
        persistLocked()
        lock.unlock()
    }

    // MARK: - Lexicon Export & Import

    /// Exports the full user lexicon (frequencies, custom phrases, pinned & forgotten words) as pretty-printed JSON data.
    public func exportJSONData() throws -> Data {
        lock.lock()
        let snapshot = PersistedData(
            frequencyTable: frequencyTable,
            customPhrases: customPhrases,
            totalCommittedCharsCount: totalCommittedCharsCount,
            pinnedWords: pinnedWords,
            forgottenWords: forgottenWords
        )
        lock.unlock()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(snapshot)
    }

    /// Exports custom phrases as human-editable TSV lines (`code<TAB>phrase`).
    public func exportCustomPhrasesText() -> String {
        let pairs = allCustomPhrases()
        var lines = [
            "# AetherKey 自定义短语词表",
            "# 格式: 编码<TAB>短语（支持全拼如 gongsi，或五笔如 wubi86:gggg）"
        ]
        for (key, phrase) in pairs {
            lines.append("\(key)\t\(phrase)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Exports lexicon to the specified file URL. Uses TSV text for `.txt`/`.tsv` extensions and full JSON backup otherwise.
    public func export(to url: URL) throws {
        let ext = url.pathExtension.lowercased()
        if ext == "txt" || ext == "tsv" {
            let text = exportCustomPhrasesText()
            try Data(text.utf8).write(to: url, options: .atomic)
        } else {
            let data = try exportJSONData()
            try data.write(to: url, options: .atomic)
        }
    }

    /// Imports user lexicon data from a file URL (supports full JSON backup, key-to-words JSON, or TSV/TXT/Rime dict lines).
    @discardableResult
    public func importFile(from url: URL, mode: ImportMode = .merge) throws -> ImportSummary {
        let data = try Data(contentsOf: url)
        return try importData(data, mode: mode)
    }

    /// Imports user lexicon data from raw `Data` in `.merge` or `.replace` mode.
    @discardableResult
    public func importData(_ data: Data, mode: ImportMode = .merge) throws -> ImportSummary {
        guard !data.isEmpty else { throw LexiconTransferError.emptyInput }
        let parsed = try parseImportPayload(data)
        return applyImport(parsed, mode: mode)
    }

    private func parseImportPayload(_ data: Data) throws -> PersistedData {
        // 1. Try full PersistedData JSON backup
        if let full = try? JSONDecoder().decode(PersistedData.self, from: data) {
            return sanitizeSnapshot(full)
        }

        // 2. Try simple [String: [String]] JSON dictionary
        if let dictArray = try? JSONDecoder().decode([String: [String]].self, from: data), !dictArray.isEmpty {
            return sanitizeSnapshot(PersistedData(
                frequencyTable: [:],
                customPhrases: dictArray,
                totalCommittedCharsCount: 0,
                pinnedWords: [:],
                forgottenWords: [:]
            ))
        }

        // 3. Try simple [String: String] JSON dictionary
        if let dictSingle = try? JSONDecoder().decode([String: String].self, from: data), !dictSingle.isEmpty {
            let mapped = dictSingle.mapValues { [$0] }
            return sanitizeSnapshot(PersistedData(
                frequencyTable: [:],
                customPhrases: mapped,
                totalCommittedCharsCount: 0,
                pinnedWords: [:],
                forgottenWords: [:]
            ))
        }

        // 4. Try plain-text / TSV / Rime dict format
        guard let text = String(data: data, encoding: .utf8) else {
            throw LexiconTransferError.invalidFormat
        }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { throw LexiconTransferError.emptyInput }
        if trimmedText.first == "{" || trimmedText.first == "[" {
            throw LexiconTransferError.invalidFormat
        }

        var custom: [String: [String]] = [:]
        var frequencies: [String: [String: Int]] = [:]
        var lines = text.components(separatedBy: .newlines)
        if let yamlEndIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "..." }) {
            lines = Array(lines.dropFirst(yamlEndIndex + 1))
        }

        var parsedCount = 0
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("//") { continue }

            let tabFields = line.split(separator: "\t", omittingEmptySubsequences: true).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            let fields: [String]
            if tabFields.count >= 2 {
                fields = tabFields
            } else if line.contains("=") {
                fields = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
            } else {
                fields = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            }
            guard fields.count >= 2 else { continue }

            let first = fields[0]
            let second = fields[1]
            let codeCandidate: String
            let phraseCandidate: String
            if Self.looksLikeCode(first) && !Self.looksLikeCode(second) {
                codeCandidate = first
                phraseCandidate = second
            } else if !Self.looksLikeCode(first) && Self.looksLikeCode(second) {
                phraseCandidate = first
                codeCandidate = second
            } else {
                codeCandidate = first
                phraseCandidate = second
            }

            let key = Self.normalizeImportedKey(codeCandidate)
            let phrase = phraseCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !phrase.isEmpty else { continue }

            var list = custom[key] ?? []
            if !list.contains(phrase) {
                list.append(phrase)
            }
            custom[key] = list

            let weight = fields.count >= 3 ? (Int(fields[2]) ?? 100) : 100
            var freqMap = frequencies[key] ?? [:]
            freqMap[phrase] = max(freqMap[phrase, default: 0], max(weight, 1))
            frequencies[key] = freqMap
            parsedCount += 1
        }

        guard parsedCount > 0 else { throw LexiconTransferError.invalidFormat }
        return PersistedData(
            frequencyTable: frequencies,
            customPhrases: custom,
            totalCommittedCharsCount: 0,
            pinnedWords: [:],
            forgottenWords: [:]
        )
    }

    private static func looksLikeCode(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let lower = text.lowercased()
        if lower.hasPrefix("wubi86:") {
            let rest = lower.dropFirst("wubi86:".count)
            return !rest.isEmpty && rest.allSatisfy { $0.isASCII && ($0.isLetter || $0.isWhitespace) }
        }
        return lower.allSatisfy { $0.isASCII && ($0.isLetter || $0 == "'" || $0 == " ") }
    }

    private static func normalizeImportedKey(_ raw: String) -> String {
        let lower = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.hasPrefix("wubi86:") {
            let code = lower.dropFirst("wubi86:".count)
                .replacingOccurrences(of: "'", with: "")
                .replacingOccurrences(of: " ", with: "")
            return code.isEmpty ? "" : "wubi86:" + code
        }
        return lower
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private func sanitizeSnapshot(_ raw: PersistedData) -> PersistedData {
        func cleanWordListMap(_ source: [String: [String]]?) -> [String: [String]] {
            guard let source else { return [:] }
            var result: [String: [String]] = [:]
            for (rawKey, words) in source {
                let key = Self.normalizeImportedKey(rawKey)
                guard !key.isEmpty else { continue }
                var list = result[key] ?? []
                for rawWord in words {
                    let word = rawWord.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !word.isEmpty, !list.contains(word) else { continue }
                    list.append(word)
                }
                if !list.isEmpty { result[key] = list }
            }
            return result
        }

        let cleanCustom = cleanWordListMap(raw.customPhrases)
        let cleanPinned = cleanWordListMap(raw.pinnedWords)
        let cleanForgotten = cleanWordListMap(raw.forgottenWords)

        var cleanFreq: [String: [String: Int]] = [:]
        for (rawKey, wordMap) in raw.frequencyTable {
            let key = Self.normalizeImportedKey(rawKey)
            guard !key.isEmpty else { continue }
            let explicitWords = Set((cleanCustom[key] ?? []) + (cleanPinned[key] ?? []))
            var map = cleanFreq[key] ?? [:]
            for (rawWord, score) in wordMap {
                let word = rawWord.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !word.isEmpty, score > 0 else { continue }
                guard explicitWords.contains(word) || Self.isValidLearnableEntry(key: key, word: word) else { continue }
                map[word] = max(map[word, default: 0], score)
            }
            if !map.isEmpty { cleanFreq[key] = map }
        }

        return PersistedData(
            frequencyTable: cleanFreq,
            customPhrases: cleanCustom,
            totalCommittedCharsCount: max(0, raw.totalCommittedCharsCount),
            pinnedWords: cleanPinned,
            forgottenWords: cleanForgotten
        )
    }

    private func applyImport(_ imported: PersistedData, mode: ImportMode) -> ImportSummary {
        lock.lock()
        defer { lock.unlock() }

        switch mode {
        case .replace:
            frequencyTable = imported.frequencyTable
            customPhrases = imported.customPhrases
            totalCommittedCharsCount = imported.totalCommittedCharsCount
            pinnedWords = imported.pinnedWords ?? [:]
            forgottenWords = imported.forgottenWords ?? [:]
            for (key, words) in customPhrases {
                var map = frequencyTable[key] ?? [:]
                for word in words {
                    map[word] = max(map[word, default: 0], 100)
                    forgottenWords[key]?.removeAll { $0 == word }
                }
                frequencyTable[key] = map
            }
            for (key, words) in pinnedWords {
                for word in words {
                    forgottenWords[key]?.removeAll { $0 == word }
                }
            }

        case .merge:
            totalCommittedCharsCount = max(totalCommittedCharsCount, imported.totalCommittedCharsCount)
            for (key, words) in imported.forgottenWords ?? [:] {
                var list = forgottenWords[key] ?? []
                for word in words where !list.contains(word) {
                    list.append(word)
                }
                if !list.isEmpty { forgottenWords[key] = list }
            }
            for (key, words) in imported.customPhrases {
                var list = customPhrases[key] ?? []
                var freqMap = frequencyTable[key] ?? [:]
                for word in words {
                    if !list.contains(word) {
                        list.append(word)
                    }
                    freqMap[word] = max(freqMap[word, default: 0], 100)
                    forgottenWords[key]?.removeAll { $0 == word }
                }
                if !list.isEmpty { customPhrases[key] = list }
                if !freqMap.isEmpty { frequencyTable[key] = freqMap }
            }
            for (key, words) in imported.pinnedWords ?? [:] {
                var list = pinnedWords[key] ?? []
                for word in words {
                    if !list.contains(word) {
                        list.append(word)
                    }
                    forgottenWords[key]?.removeAll { $0 == word }
                }
                if !list.isEmpty { pinnedWords[key] = list }
            }
            for (key, wordMap) in imported.frequencyTable {
                var freqMap = frequencyTable[key] ?? [:]
                let forgotten = Set(forgottenWords[key] ?? [])
                for (word, score) in wordMap where score > 0 && !forgotten.contains(word) {
                    freqMap[word] = max(freqMap[word, default: 0], score)
                }
                if !freqMap.isEmpty { frequencyTable[key] = freqMap }
            }
        }

        persistLocked()
        return ImportSummary(
            mode: mode,
            customPhraseCount: imported.customPhrases.values.reduce(0) { $0 + $1.count },
            learnedWordCount: imported.frequencyTable.values.reduce(0) { $0 + $1.count },
            pinnedWordCount: (imported.pinnedWords ?? [:]).values.reduce(0) { $0 + $1.count },
            forgottenWordCount: (imported.forgottenWords ?? [:]).values.reduce(0) { $0 + $1.count }
        )
    }
    
    private func normalized(_ pinyin: String) -> String {
        pinyin.lowercased().replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Explicit choices outrank context; ordinary frequency learning does not.
    public func isExplicitPreference(_ word: String, for pinyin: String) -> Bool {
        let key = pinyin.lowercased().replacingOccurrences(of: "'", with: "")
        lock.lock(); defer { lock.unlock() }
        return (pinnedWords[key] ?? []).contains(word) || (customPhrases[key] ?? []).contains(word)
    }

    public func isPinned(_ word: String, for pinyin: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return (pinnedWords[normalized(pinyin)] ?? []).contains(word)
    }

    public func isForgotten(_ word: String, for pinyin: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return (forgottenWords[normalized(pinyin)] ?? []).contains(word)
    }

    public func setPinned(_ word: String, for pinyin: String, pinned: Bool) {
        let key = normalized(pinyin)
        guard !key.isEmpty, !word.isEmpty else { return }
        lock.lock()
        pinnedWords[key, default: []].removeAll { $0 == word }
        if pinned {
            pinnedWords[key, default: []].insert(word, at: 0)
            forgottenWords[key]?.removeAll { $0 == word }
            if forgottenWords[key]?.isEmpty == true {
                forgottenWords.removeValue(forKey: key)
            }
        } else if pinnedWords[key]?.isEmpty == true {
            pinnedWords.removeValue(forKey: key)
        }
        persistLocked()
        lock.unlock()
    }

    /// Forget only this reading; other readings and other words remain intact.
    public func forget(_ word: String, for pinyin: String) {
        let key = normalized(pinyin)
        guard !key.isEmpty, !word.isEmpty else { return }
        lock.lock()
        frequencyTable[key]?.removeValue(forKey: word)
        if frequencyTable[key]?.isEmpty == true {
            frequencyTable.removeValue(forKey: key)
        }
        customPhrases[key]?.removeAll { $0 == word }
        if customPhrases[key]?.isEmpty == true {
            customPhrases.removeValue(forKey: key)
        }
        pinnedWords[key]?.removeAll { $0 == word }
        if pinnedWords[key]?.isEmpty == true {
            pinnedWords.removeValue(forKey: key)
        }
        if !(forgottenWords[key] ?? []).contains(word) {
            forgottenWords[key, default: []].append(word)
        }
        persistLocked()
        lock.unlock()
    }

    /// Restores a previously forgotten candidate for the specified reading.
    public func unforget(_ word: String, for pinyin: String) {
        let key = normalized(pinyin)
        guard !key.isEmpty, !word.isEmpty else { return }
        lock.lock()
        forgottenWords[key]?.removeAll { $0 == word }
        if forgottenWords[key]?.isEmpty == true {
            forgottenWords.removeValue(forKey: key)
        }
        persistLocked()
        lock.unlock()
    }

    public func selectionCount(_ word: String, for pinyin: String) -> Int {
        guard AetherSettings.shared.isUserLearningEnabled else { return 0 }
        lock.lock(); defer { lock.unlock() }
        return frequencyTable[normalized(pinyin)]?[word] ?? 0
    }

    /// Enqueue while holding the mutation lock; older snapshots cannot overwrite newer ones.
    private func persistLocked() {
        saveToDiskAsync(PersistedData(
            frequencyTable: frequencyTable, customPhrases: customPhrases,
            totalCommittedCharsCount: totalCommittedCharsCount,
            pinnedWords: pinnedWords, forgottenWords: forgottenWords
        ))
    }

    func flushPendingWrites() { saveQueue.sync {} }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode(PersistedData.self, from: data) else {
            return
        }
        let sanitized = sanitizeSnapshot(decoded)
        lock.lock()
        self.frequencyTable = sanitized.frequencyTable
        self.customPhrases = sanitized.customPhrases
        self.totalCommittedCharsCount = sanitized.totalCommittedCharsCount
        self.pinnedWords = sanitized.pinnedWords ?? [:]
        self.forgottenWords = sanitized.forgottenWords ?? [:]
        lock.unlock()
    }
    
    private func saveToDiskAsync(_ snapshot: PersistedData) {
        let url = storageURL
        saveQueue.async {
            if let encoded = try? JSONEncoder().encode(snapshot) {
                try? encoded.write(to: url, options: .atomic)
            }
        }
    }
}
