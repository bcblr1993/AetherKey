import AppKit
import Combine
import Foundation

/// User-defined reusable text snippet with optional quick-trigger shortcut code.
public struct QuickSnippet: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var content: String
    public var shortcutCode: String
    public var isPinned: Bool
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        content: String,
        shortcutCode: String = "",
        isPinned: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.shortcutCode = shortcutCode
        self.isPinned = isPinned
        self.updatedAt = updatedAt
    }
}

/// Recorded clipboard text entry with pin status and capture timestamp.
public struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let copiedAt: Date
    public var isPinned: Bool

    public init(
        id: UUID = UUID(),
        text: String,
        copiedAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
        self.isPinned = isPinned
    }
}

/// Persistent store for quick snippets / canned phrases (常用语).
public final class QuickSnippetStore: ObservableObject, @unchecked Sendable {
    public static let shared = QuickSnippetStore()

    private static let defaultStorageURL: URL = {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil
            || env["XCTestSessionIdentifier"] != nil
            || env["XCTestBundlePath"] != nil {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("aetherkey-xctest-snippets-\(ProcessInfo.processInfo.processIdentifier).json")
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("AetherKey", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("snippets.json")
    }()

    private let lock = NSLock()
    private let storageURL: URL

    @Published public private(set) var items: [QuickSnippet] = []

    public init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL
        loadFromDisk()
    }

    @discardableResult
    public func add(
        title: String,
        content: String,
        shortcutCode: String = "",
        isPinned: Bool = false
    ) -> QuickSnippet {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCode = Self.normalizeShortcut(shortcutCode)
        let effectiveTitle = trimmedTitle.isEmpty
            ? String(content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
            : trimmedTitle
        let snippet = QuickSnippet(
            title: effectiveTitle,
            content: content,
            shortcutCode: normalizedCode,
            isPinned: isPinned,
            updatedAt: Date()
        )
        guard !content.isEmpty else { return snippet }

        lock.lock()
        var next = items
        next.append(snippet)
        next = Self.sorted(next)
        items = next
        persistLocked(next)
        lock.unlock()
        return snippet
    }

    public func update(_ snippet: QuickSnippet) {
        lock.lock()
        var next = items
        if let idx = next.firstIndex(where: { $0.id == snippet.id }) {
            var updated = snippet
            updated.title = snippet.title.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.shortcutCode = Self.normalizeShortcut(snippet.shortcutCode)
            updated.updatedAt = Date()
            next[idx] = updated
            next = Self.sorted(next)
            items = next
            persistLocked(next)
        }
        lock.unlock()
    }

    public func remove(id: UUID) {
        lock.lock()
        var next = items
        next.removeAll { $0.id == id }
        items = next
        persistLocked(next)
        lock.unlock()
    }

    public func togglePin(id: UUID) {
        lock.lock()
        var next = items
        if let idx = next.firstIndex(where: { $0.id == id }) {
            next[idx].isPinned.toggle()
            next[idx].updatedAt = Date()
            next = Self.sorted(next)
            items = next
            persistLocked(next)
        }
        lock.unlock()
    }

    public func search(_ query: String) -> [QuickSnippet] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        let snapshot = items
        lock.unlock()
        guard !trimmed.isEmpty else { return snapshot }
        return snapshot.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.content.localizedCaseInsensitiveContains(trimmed)
                || $0.shortcutCode.localizedCaseInsensitiveContains(trimmed)
        }
    }

    public func matchedByShortcut(_ code: String) -> [QuickSnippet] {
        let normalized = Self.normalizeShortcut(code)
        guard !normalized.isEmpty else { return [] }
        lock.lock()
        let snapshot = items
        lock.unlock()
        return snapshot.filter { !$0.shortcutCode.isEmpty && $0.shortcutCode.lowercased() == normalized }
    }

    public func exportSnippetsData() throws -> Data {
        lock.lock()
        let snapshot = items
        lock.unlock()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(snapshot)
    }

    @discardableResult
    public func mergeSnippets(_ incoming: [QuickSnippet]) -> Int {
        guard !incoming.isEmpty else { return 0 }
        lock.lock()
        var next = items
        var mergedCount = 0

        for rawItem in incoming where !rawItem.content.isEmpty {
            var item = rawItem
            item.shortcutCode = Self.normalizeShortcut(rawItem.shortcutCode)

            if let idx = next.firstIndex(where: { $0.id == item.id }) {
                let existing = next[idx]
                if item.updatedAt > existing.updatedAt {
                    next[idx] = item
                    mergedCount += 1
                } else if item.isPinned && !existing.isPinned {
                    next[idx].isPinned = true
                    mergedCount += 1
                }
            } else if let dupIdx = next.firstIndex(where: {
                $0.content == item.content && $0.shortcutCode == item.shortcutCode
            }) {
                let existing = next[dupIdx]
                var changed = false
                if item.updatedAt > existing.updatedAt {
                    next[dupIdx].title = item.title
                    next[dupIdx].updatedAt = item.updatedAt
                    changed = true
                }
                if item.isPinned && !existing.isPinned {
                    next[dupIdx].isPinned = true
                    changed = true
                }
                if changed { mergedCount += 1 }
            } else {
                next.append(item)
                mergedCount += 1
            }
        }

        next = Self.sorted(next)
        items = next
        persistLocked(next)
        lock.unlock()
        return mergedCount
    }

    private static func normalizeShortcut(_ code: String) -> String {
        code.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sorted(_ list: [QuickSnippet]) -> [QuickSnippet] {
        list.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              !data.isEmpty,
              let decoded = try? JSONDecoder().decode([QuickSnippet].self, from: data) else {
            return
        }
        let sorted = Self.sorted(decoded)
        lock.lock()
        items = sorted
        lock.unlock()
    }

    private func persistLocked(_ snapshot: [QuickSnippet]) {
        let dir = storageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }
}

/// Persistent store for clipboard history with sensitive-pasteboard filtering (e.g. password managers).
public final class ClipboardHistoryStore: ObservableObject, @unchecked Sendable {
    public static let shared = ClipboardHistoryStore()

    private static let defaultStorageURL: URL = {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil
            || env["XCTestSessionIdentifier"] != nil
            || env["XCTestBundlePath"] != nil {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("aetherkey-xctest-clipboard-\(ProcessInfo.processInfo.processIdentifier).json")
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("AetherKey", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("clipboard_history.json")
    }()

    private static let sensitiveTypeIdentifiers: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword"
    ]

    private let lock = NSLock()
    private let storageURL: URL
    private let maxItems: Int
    private let monitorQueue = DispatchQueue(label: "com.aethernative.AetherKey.clipboard-monitor", qos: .utility)
    private var monitorTimer: DispatchSourceTimer?
    private var lastChangeCounts: [String: Int] = [:]

    @Published public private(set) var items: [ClipboardItem] = []

    public init(storageURL: URL? = nil, maxItems: Int = 50) {
        self.storageURL = storageURL ?? Self.defaultStorageURL
        self.maxItems = max(1, maxItems)
        loadFromDisk()
    }

    deinit {
        stopMonitoring()
    }

    public func startMonitoring() {
        lock.lock()
        if monitorTimer != nil {
            lock.unlock()
            return
        }
        let generalName = NSPasteboard.general.name.rawValue
        lastChangeCounts[generalName] = NSPasteboard.general.changeCount

        let timer = DispatchSource.makeTimerSource(queue: monitorQueue)
        timer.schedule(deadline: .now() + .milliseconds(750), repeating: .milliseconds(750), leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            self?.capturePasteboardIfNeeded(.general)
        }
        monitorTimer = timer
        lock.unlock()
        timer.resume()
    }

    public func stopMonitoring() {
        lock.lock()
        let timer = monitorTimer
        monitorTimer = nil
        lock.unlock()
        timer?.cancel()
    }

    public func capturePasteboardIfNeeded(_ pasteboard: NSPasteboard = .general) {
        guard AetherSettings.shared.isClipboardHistoryEnabled else { return }

        let pbName = pasteboard.name.rawValue
        let currentCount = pasteboard.changeCount
        lock.lock()
        if lastChangeCounts[pbName] == currentCount {
            lock.unlock()
            return
        }
        lastChangeCounts[pbName] = currentCount
        lock.unlock()

        guard !Self.isSensitivePasteboard(pasteboard) else { return }
        guard let text = pasteboard.string(forType: .string) else { return }
        recordText(text)
    }

    public static func isSensitivePasteboard(_ pasteboard: NSPasteboard) -> Bool {
        var allTypes = pasteboard.types ?? []
        if let pbItems = pasteboard.pasteboardItems {
            for item in pbItems {
                allTypes.append(contentsOf: item.types)
            }
        }
        for type in allTypes {
            let identifier = type.rawValue
            if sensitiveTypeIdentifiers.contains(identifier) {
                return true
            }
            if identifier.hasPrefix("com.agilebits.onepassword") {
                return true
            }
        }
        return false
    }

    public func recordText(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= 100_000 else {
            return
        }

        lock.lock()
        var next = items
        var preservedPin = false
        var preservedID = UUID()
        if let existingIdx = next.firstIndex(where: { $0.text == text }) {
            preservedPin = next[existingIdx].isPinned
            preservedID = next[existingIdx].id
            next.remove(at: existingIdx)
        }
        next.insert(
            ClipboardItem(id: preservedID, text: text, copiedAt: Date(), isPinned: preservedPin),
            at: 0
        )
        next = Self.sortedAndTrimmed(next, maxItems: maxItems)
        items = next
        persistLocked(next)
        lock.unlock()
    }

    public func togglePin(id: UUID) {
        lock.lock()
        var next = items
        if let idx = next.firstIndex(where: { $0.id == id }) {
            next[idx].isPinned.toggle()
            next = Self.sortedAndTrimmed(next, maxItems: maxItems)
            items = next
            persistLocked(next)
        }
        lock.unlock()
    }

    public func remove(id: UUID) {
        lock.lock()
        var next = items
        next.removeAll { $0.id == id }
        items = next
        persistLocked(next)
        lock.unlock()
    }

    public func clearUnpinned() {
        lock.lock()
        let next = items.filter(\.isPinned)
        items = next
        persistLocked(next)
        lock.unlock()
    }

    public func clearAll() {
        lock.lock()
        items = []
        persistLocked([])
        lock.unlock()
    }

    public func search(_ query: String) -> [ClipboardItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        let snapshot = items
        lock.unlock()
        guard !trimmed.isEmpty else { return snapshot }
        return snapshot.filter { $0.text.localizedCaseInsensitiveContains(trimmed) }
    }

    private static func sortedAndTrimmed(_ list: [ClipboardItem], maxItems: Int) -> [ClipboardItem] {
        var sorted = list.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            if lhs.copiedAt != rhs.copiedAt { return lhs.copiedAt > rhs.copiedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        if sorted.count > maxItems {
            for idx in stride(from: sorted.count - 1, through: 0, by: -1) {
                guard sorted.count > maxItems else { break }
                if !sorted[idx].isPinned {
                    sorted.remove(at: idx)
                }
            }
            if sorted.count > maxItems {
                sorted = Array(sorted.prefix(maxItems))
            }
        }
        return sorted
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              !data.isEmpty,
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) else {
            return
        }
        let sorted = Self.sortedAndTrimmed(decoded, maxItems: maxItems)
        lock.lock()
        items = sorted
        lock.unlock()
    }

    private func persistLocked(_ snapshot: [ClipboardItem]) {
        let dir = storageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }
}
