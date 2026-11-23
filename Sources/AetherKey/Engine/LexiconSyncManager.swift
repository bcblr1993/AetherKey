import Combine
import Foundation

/// Synchronizes `UserLexicon` and `QuickSnippetStore` with a user-selected directory or iCloud Drive folder.
public final class LexiconSyncManager: ObservableObject, @unchecked Sendable {
    public static let shared = LexiconSyncManager()

    public struct SyncResult: Sendable, Equatable {
        public let syncedFolderURL: URL
        public let mergedCustomPhrases: Int
        public let mergedLearnedWords: Int
        public let mergedSnippets: Int
        public let timestamp: Date

        public init(
            syncedFolderURL: URL,
            mergedCustomPhrases: Int,
            mergedLearnedWords: Int,
            mergedSnippets: Int,
            timestamp: Date = Date()
        ) {
            self.syncedFolderURL = syncedFolderURL
            self.mergedCustomPhrases = mergedCustomPhrases
            self.mergedLearnedWords = mergedLearnedWords
            self.mergedSnippets = mergedSnippets
            self.timestamp = timestamp
        }
    }

    public enum SyncError: LocalizedError, Sendable, Equatable {
        case missingSyncFolder
        case invalidRemoteSnippetsFormat

        public var errorDescription: String? {
            switch self {
            case .missingSyncFolder:
                return "未配置同步目录且未检测到 iCloud Drive，请先在设置中选择同步文件夹。"
            case .invalidRemoteSnippetsFormat:
                return "同步目录中的 snippets.json 格式无效，无法合并常用语。"
            }
        }
    }

    private let lock = NSLock()

    @Published public private(set) var lastSyncAt: Date?
    @Published public private(set) var lastSyncMessage: String = ""

    public init() {}

    /// Returns `<iCloudDrive>/AetherKey` when the system iCloud Drive root exists on disk.
    public func defaultICloudDirectoryURL() -> URL? {
        let cloudDocs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cloudDocs.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return cloudDocs.appendingPathComponent("AetherKey", isDirectory: true)
    }

    /// Performs a two-way merge between local stores and `user_lexicon.json` / `snippets.json` in the target folder.
    @discardableResult
    public func syncNow(
        lexicon: UserLexicon = .shared,
        snippets: QuickSnippetStore = .shared,
        folderURL: URL? = nil
    ) throws -> SyncResult {
        do {
            let targetFolder = try resolveSyncFolderURL(explicit: folderURL)
            try FileManager.default.createDirectory(at: targetFolder, withIntermediateDirectories: true)

            let remoteLexiconURL = targetFolder.appendingPathComponent("user_lexicon.json")
            let remoteSnippetsURL = targetFolder.appendingPathComponent("snippets.json")

            var mergedCustomPhrases = 0
            var mergedLearnedWords = 0
            var mergedSnippets = 0

            if FileManager.default.fileExists(atPath: remoteLexiconURL.path) {
                let remoteData = try Data(contentsOf: remoteLexiconURL)
                if !remoteData.isEmpty {
                    let summary = try lexicon.importData(remoteData, mode: .merge)
                    mergedCustomPhrases = summary.customPhraseCount
                    mergedLearnedWords = summary.learnedWordCount
                }
            }

            if FileManager.default.fileExists(atPath: remoteSnippetsURL.path) {
                let remoteSnippetsData = try Data(contentsOf: remoteSnippetsURL)
                if !remoteSnippetsData.isEmpty {
                    guard let remoteSnippets = try? JSONDecoder().decode([QuickSnippet].self, from: remoteSnippetsData) else {
                        throw SyncError.invalidRemoteSnippetsFormat
                    }
                    mergedSnippets = snippets.mergeSnippets(remoteSnippets)
                }
            }

            let mergedLexiconData = try lexicon.exportJSONData()
            try mergedLexiconData.write(to: remoteLexiconURL, options: .atomic)

            let mergedSnippetsData = try snippets.exportSnippetsData()
            try mergedSnippetsData.write(to: remoteSnippetsURL, options: .atomic)

            let now = Date()
            let result = SyncResult(
                syncedFolderURL: targetFolder,
                mergedCustomPhrases: mergedCustomPhrases,
                mergedLearnedWords: mergedLearnedWords,
                mergedSnippets: mergedSnippets,
                timestamp: now
            )

            let summaryMessage = "同步完成：合并短语 \(mergedCustomPhrases) 条，学习词 \(mergedLearnedWords) 条，常用语 \(mergedSnippets) 条。"
            lock.lock()
            lastSyncAt = now
            lastSyncMessage = summaryMessage
            lock.unlock()

            return result
        } catch {
            lock.lock()
            lastSyncMessage = error.localizedDescription
            lock.unlock()
            throw error
        }
    }

    private func resolveSyncFolderURL(explicit folderURL: URL?) throws -> URL {
        if let folderURL {
            return folderURL
        }
        let configured = AetherSettings.shared.syncFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty {
            let expanded = (configured as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        if let icloudURL = defaultICloudDirectoryURL() {
            return icloudURL
        }
        throw SyncError.missingSyncFolder
    }
}
