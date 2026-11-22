import Foundation
import Combine

/// Configurable fuzzy pinyin equivalence rules.
public struct FuzzyPinyinRules: OptionSet, Codable, Sendable, Equatable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let zhZ = FuzzyPinyinRules(rawValue: 1 << 0)
    public static let chC = FuzzyPinyinRules(rawValue: 1 << 1)
    public static let shS = FuzzyPinyinRules(rawValue: 1 << 2)
    public static let lN = FuzzyPinyinRules(rawValue: 1 << 3)
    public static let fH = FuzzyPinyinRules(rawValue: 1 << 4)
    public static let rL = FuzzyPinyinRules(rawValue: 1 << 5)
    public static let anAng = FuzzyPinyinRules(rawValue: 1 << 6)
    public static let enEng = FuzzyPinyinRules(rawValue: 1 << 7)
    public static let inIng = FuzzyPinyinRules(rawValue: 1 << 8)
    public static let ianIang = FuzzyPinyinRules(rawValue: 1 << 9)
    public static let uanUang = FuzzyPinyinRules(rawValue: 1 << 10)

    public static let defaultRules: FuzzyPinyinRules = [
        .zhZ, .chC, .shS, .anAng, .enEng, .inIng, .ianIang, .uanUang
    ]

    public static let allRules: FuzzyPinyinRules = [
        .zhZ, .chC, .shS, .lN, .fH, .rL, .anAng, .enEng, .inIng, .ianIang, .uanUang
    ]

    public static let ruleMetadata: [(rule: FuzzyPinyinRules, title: String, subtitle: String)] = [
        (.zhZ, "zh ↔ z", "平翘舌（知资不分）"),
        (.chC, "ch ↔ c", "平翘舌（吃次不分）"),
        (.shS, "sh ↔ s", "平翘舌（十私不分）"),
        (.lN, "l ↔ n", "鼻边音（蓝南不分）"),
        (.fH, "f ↔ h", "唇齿音（飞灰不分）"),
        (.rL, "r ↔ l", "卷舌音（热乐不分）"),
        (.anAng, "an ↔ ang", "前后鼻音（安昂不分）"),
        (.enEng, "en ↔ eng", "前后鼻音（恩嗯不分）"),
        (.inIng, "in ↔ ing", "前后鼻音（音英不分）"),
        (.ianIang, "ian ↔ iang", "前后鼻音（烟央不分）"),
        (.uanUang, "uan ↔ uang", "前后鼻音（弯汪不分）")
    ]
}

/// Per-application default input mode preference.
public enum AppDefaultInputMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case english
    case chinese

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .english: return "英文"
        case .chinese: return "中文"
        }
    }
}

/// Centralized user preferences and runtime configuration for AetherKey.
public final class AetherSettings: ObservableObject, @unchecked Sendable {
    public static let shared = AetherSettings()
    
    private let defaults: UserDefaults
    
    private enum Keys {
        static let fourArrowSelection = "aetherkey.settings.fourArrowSelection"
        static let pinyinScheme = "aetherkey.settings.pinyinScheme"
        static let panguSpacing = "aetherkey.settings.panguSpacing"
        static let englishPunctuation = "aetherkey.settings.englishPunctuation"
        static let smartPunctuation = "aetherkey.settings.smartPunctuation"
        static let fuzzyPinyin = "aetherkey.settings.fuzzyPinyin"
        static let fuzzyPinyinRules = "aetherkey.settings.fuzzyPinyinRules"
        static let autoEnglishInTerminal = "aetherkey.settings.autoEnglishInTerminal"
        static let userLearning = "aetherkey.settings.userLearning"
        static let defaultViewMode = "aetherkey.settings.defaultViewMode"
        static let traditionalChinese = "aetherkey.settings.traditionalChinese"
        static let candidatePageSize = "aetherkey.settings.candidatePageSize"
        static let candidateFontSize = "aetherkey.settings.candidateFontSize"
        static let candidateLayoutOrientation = "aetherkey.settings.candidateLayoutOrientation"
        static let customAppDefaultModes = "aetherkey.settings.customAppDefaultModes"
    }
    
    @Published public var isFourArrowSelectionEnabled: Bool {
        didSet { defaults.set(isFourArrowSelectionEnabled, forKey: Keys.fourArrowSelection) }
    }

    @Published public var pinyinScheme: PinyinScheme {
        didSet { defaults.set(pinyinScheme.rawValue, forKey: Keys.pinyinScheme) }
    }

    @Published public var isPanguSpacingEnabled: Bool {
        didSet { defaults.set(isPanguSpacingEnabled, forKey: Keys.panguSpacing) }
    }
    
    @Published public var isSmartPunctuationEnabled: Bool {
        didSet { defaults.set(isSmartPunctuationEnabled, forKey: Keys.smartPunctuation) }
    }
    
    /// Keep Chinese composition while emitting ASCII punctuation. Off by default.
    @Published public var isEnglishPunctuationEnabled: Bool {
        didSet {
            defaults.set(isEnglishPunctuationEnabled, forKey: Keys.englishPunctuation)
            if oldValue != isEnglishPunctuationEnabled { SmartPunctuation.shared.resetState() }
        }
    }

    public var usesChinesePunctuation: Bool {
        isSmartPunctuationEnabled && !isEnglishPunctuationEnabled
    }

    @Published public var isTraditionalChineseEnabled: Bool {
        didSet { defaults.set(isTraditionalChineseEnabled, forKey: Keys.traditionalChinese) }
    }

    @Published public var isFuzzyPinyinEnabled: Bool {
        didSet { defaults.set(isFuzzyPinyinEnabled, forKey: Keys.fuzzyPinyin) }
    }

    @Published public var fuzzyPinyinRules: FuzzyPinyinRules {
        didSet { defaults.set(fuzzyPinyinRules.rawValue, forKey: Keys.fuzzyPinyinRules) }
    }
    
    @Published public var isAutoEnglishInTerminalEnabled: Bool {
        didSet { defaults.set(isAutoEnglishInTerminalEnabled, forKey: Keys.autoEnglishInTerminal) }
    }
    
    @Published public var isUserLearningEnabled: Bool {
        didSet { defaults.set(isUserLearningEnabled, forKey: Keys.userLearning) }
    }
    
    @Published public var defaultViewMode: CandidateViewMode {
        didSet { defaults.set(defaultViewMode.rawValue, forKey: Keys.defaultViewMode) }
    }

    @Published public var candidatePageSize: Int {
        didSet {
            let clamped = Self.clampedPageSize(candidatePageSize)
            if candidatePageSize != clamped {
                candidatePageSize = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.candidatePageSize)
        }
    }

    @Published public var candidateFontSize: CGFloat {
        didSet {
            let clamped = Self.clampedFontSize(candidateFontSize)
            if candidateFontSize != clamped {
                candidateFontSize = clamped
                return
            }
            defaults.set(Double(clamped), forKey: Keys.candidateFontSize)
        }
    }

    @Published public var candidateLayoutOrientation: CandidateLayoutOrientation {
        didSet { defaults.set(candidateLayoutOrientation.rawValue, forKey: Keys.candidateLayoutOrientation) }
    }

    @Published public var customAppDefaultModes: [String: AppDefaultInputMode] {
        didSet {
            let rawMap = customAppDefaultModes.mapValues(\.rawValue)
            defaults.set(rawMap, forKey: Keys.customAppDefaultModes)
        }
    }
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isFourArrowSelectionEnabled = defaults.bool(forKey: Keys.fourArrowSelection)
        self.isEnglishPunctuationEnabled = defaults.bool(forKey: Keys.englishPunctuation)
        self.isTraditionalChineseEnabled = defaults.bool(forKey: Keys.traditionalChinese)
        self.pinyinScheme = PinyinScheme(rawValue: defaults.string(forKey: Keys.pinyinScheme) ?? "full") ?? .full
        if defaults.object(forKey: Keys.panguSpacing) == nil {
            defaults.set(true, forKey: Keys.panguSpacing)
        }
        if defaults.object(forKey: Keys.smartPunctuation) == nil {
            defaults.set(true, forKey: Keys.smartPunctuation)
        }
        if defaults.object(forKey: Keys.fuzzyPinyin) == nil {
            defaults.set(true, forKey: Keys.fuzzyPinyin)
        }
        if defaults.object(forKey: Keys.autoEnglishInTerminal) == nil {
            defaults.set(true, forKey: Keys.autoEnglishInTerminal)
        }
        if defaults.object(forKey: Keys.userLearning) == nil {
            defaults.set(true, forKey: Keys.userLearning)
        }
        
        self.isPanguSpacingEnabled = defaults.bool(forKey: Keys.panguSpacing)
        self.isSmartPunctuationEnabled = defaults.bool(forKey: Keys.smartPunctuation)
        self.isFuzzyPinyinEnabled = defaults.bool(forKey: Keys.fuzzyPinyin)
        if let rawRules = defaults.object(forKey: Keys.fuzzyPinyinRules) as? NSNumber {
            self.fuzzyPinyinRules = FuzzyPinyinRules(rawValue: rawRules.intValue)
        } else {
            self.fuzzyPinyinRules = .defaultRules
        }
        self.isAutoEnglishInTerminalEnabled = defaults.bool(forKey: Keys.autoEnglishInTerminal)
        self.isUserLearningEnabled = defaults.bool(forKey: Keys.userLearning)
        
        let modeRaw = defaults.string(forKey: Keys.defaultViewMode) ?? CandidateViewMode.paging.rawValue
        self.defaultViewMode = CandidateViewMode(rawValue: modeRaw) ?? .paging

        let storedPageSize = (defaults.object(forKey: Keys.candidatePageSize) as? NSNumber)?.intValue ?? 7
        self.candidatePageSize = Self.clampedPageSize(storedPageSize)

        let storedFontSize = (defaults.object(forKey: Keys.candidateFontSize) as? NSNumber)?.doubleValue ?? 15.0
        self.candidateFontSize = Self.clampedFontSize(storedFontSize.isFinite ? CGFloat(storedFontSize) : 15)

        let orientationRaw = defaults.string(forKey: Keys.candidateLayoutOrientation) ?? CandidateLayoutOrientation.horizontal.rawValue
        self.candidateLayoutOrientation = CandidateLayoutOrientation(rawValue: orientationRaw) ?? .horizontal

        if let rawMap = defaults.dictionary(forKey: Keys.customAppDefaultModes) as? [String: String] {
            var decoded: [String: AppDefaultInputMode] = [:]
            for (bundleId, modeValue) in rawMap {
                if let mode = AppDefaultInputMode(rawValue: modeValue) {
                    decoded[bundleId] = mode
                }
            }
            self.customAppDefaultModes = decoded
        } else if let data = defaults.data(forKey: Keys.customAppDefaultModes),
                  let decoded = try? JSONDecoder().decode([String: AppDefaultInputMode].self, from: data) {
            self.customAppDefaultModes = decoded
        } else {
            self.customAppDefaultModes = [:]
        }
    }

    public func appDefaultMode(for bundleIdentifier: String) -> AppDefaultInputMode? {
        let key = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return customAppDefaultModes[key]
    }

    public func setAppDefaultMode(_ mode: AppDefaultInputMode?, for bundleIdentifier: String) {
        let key = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        var updated = customAppDefaultModes
        if let mode {
            updated[key] = mode
        } else {
            updated.removeValue(forKey: key)
        }
        if updated != customAppDefaultModes {
            customAppDefaultModes = updated
        }
    }
    
    public func resetToDefaults() {
        isFourArrowSelectionEnabled = false
        pinyinScheme = .full
        isPanguSpacingEnabled = true
        isSmartPunctuationEnabled = true
        isEnglishPunctuationEnabled = false
        isTraditionalChineseEnabled = false
        isFuzzyPinyinEnabled = true
        fuzzyPinyinRules = .defaultRules
        isAutoEnglishInTerminalEnabled = true
        isUserLearningEnabled = true
        defaultViewMode = .paging
        candidatePageSize = 7
        candidateFontSize = 15
        candidateLayoutOrientation = .horizontal
        customAppDefaultModes = [:]
    }

    private static func clampedPageSize(_ value: Int) -> Int {
        min(9, max(5, value))
    }

    private static func clampedFontSize(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 15 }
        return min(22, max(13, value))
    }
}
