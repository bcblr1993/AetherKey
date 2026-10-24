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
        if AetherSettings.shared.isUserLearningEnabled, !(forgottenWords[key] ?? []).contains(word) {
            var wordMap = frequencyTable[key] ?? [:]
            wordMap[word, default: 0] += 1
            frequencyTable[key] = wordMap
        }
        persistLocked()
        lock.unlock()
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
        
        if AetherSettings.shared.isUserLearningEnabled, let freqMap = frequencyTable[normalized] {
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
    
    public var learnedEntryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return frequencyTable.values.reduce(0) { $0 + $1.count }
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
    
    private func normalized(_ pinyin: String) -> String {
        pinyin.lowercased().replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
        customPhrases[key]?.removeAll { $0 == word }
        pinnedWords[key]?.removeAll { $0 == word }
        if !(forgottenWords[key] ?? []).contains(word) {
            forgottenWords[key, default: []].append(word)
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
        lock.lock()
        self.frequencyTable = decoded.frequencyTable
        self.customPhrases = decoded.customPhrases
        self.totalCommittedCharsCount = decoded.totalCommittedCharsCount
        self.pinnedWords = decoded.pinnedWords ?? [:]
        self.forgottenWords = decoded.forgottenWords ?? [:]
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
