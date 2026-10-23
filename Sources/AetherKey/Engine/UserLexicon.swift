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
    
    private let storageURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("AetherKey", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("user_lexicon.json")
    }()
    
    private struct PersistedData: Codable {
        var frequencyTable: [String: [String: Int]]
        var customPhrases: [String: [String]]
        var totalCommittedCharsCount: Int
    }
    
    private init() {
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
        if AetherSettings.shared.isUserLearningEnabled {
            var wordMap = frequencyTable[key] ?? [:]
            wordMap[word, default: 0] += 1
            frequencyTable[key] = wordMap
        }
        let snapshot = PersistedData(
            frequencyTable: frequencyTable,
            customPhrases: customPhrases,
            totalCommittedCharsCount: totalCommittedCharsCount
        )
        lock.unlock()
        
        saveToDiskAsync(snapshot)
    }
    
    /// Adds a custom user phrase for a specific pinyin code.
    public func addCustomPhrase(pinyin: String, phrase: String) {
        let key = pinyin.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !trimmedPhrase.isEmpty else { return }
        
        lock.lock()
        var list = customPhrases[key] ?? []
        list.removeAll(where: { $0 == trimmedPhrase })
        list.insert(trimmedPhrase, at: 0)
        customPhrases[key] = list
        
        var wordMap = frequencyTable[key] ?? [:]
        wordMap[trimmedPhrase] = max(wordMap[trimmedPhrase, default: 0], 100)
        frequencyTable[key] = wordMap
        
        let snapshot = PersistedData(
            frequencyTable: frequencyTable,
            customPhrases: customPhrases,
            totalCommittedCharsCount: totalCommittedCharsCount
        )
        lock.unlock()
        
        saveToDiskAsync(snapshot)
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
        let snapshot = PersistedData(
            frequencyTable: frequencyTable,
            customPhrases: customPhrases,
            totalCommittedCharsCount: totalCommittedCharsCount
        )
        lock.unlock()
        
        saveToDiskAsync(snapshot)
    }
    
    /// Returns user-preferred words for the given normalized pinyin key, sorted by descending frequency.
    public func preferredWords(for key: String) -> [String] {
        let normalized = key.lowercased().replacingOccurrences(of: "'", with: "")
        lock.lock()
        defer { lock.unlock() }
        
        var result: [String] = []
        var seen = Set<String>()
        
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
        
        return result
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
        let snapshot = PersistedData(
            frequencyTable: frequencyTable,
            customPhrases: customPhrases,
            totalCommittedCharsCount: totalCommittedCharsCount
        )
        lock.unlock()
        saveToDiskAsync(snapshot)
    }
    
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
        lock.unlock()
    }
    
    private func saveToDiskAsync(_ snapshot: PersistedData) {
        let url = storageURL
        DispatchQueue.global(qos: .utility).async {
            if let encoded = try? JSONEncoder().encode(snapshot) {
                try? encoded.write(to: url, options: .atomic)
            }
        }
    }
}
