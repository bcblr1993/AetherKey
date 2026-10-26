import Foundation
import Combine

/// Centralized user preferences and runtime configuration for AetherKey 1.0.
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
        static let autoEnglishInTerminal = "aetherkey.settings.autoEnglishInTerminal"
        static let userLearning = "aetherkey.settings.userLearning"
        static let defaultViewMode = "aetherkey.settings.defaultViewMode"
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

    @Published public var isFuzzyPinyinEnabled: Bool {
        didSet { defaults.set(isFuzzyPinyinEnabled, forKey: Keys.fuzzyPinyin) }
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
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isFourArrowSelectionEnabled = defaults.bool(forKey: Keys.fourArrowSelection)
        self.isEnglishPunctuationEnabled = defaults.bool(forKey: Keys.englishPunctuation)
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
        self.isAutoEnglishInTerminalEnabled = defaults.bool(forKey: Keys.autoEnglishInTerminal)
        self.isUserLearningEnabled = defaults.bool(forKey: Keys.userLearning)
        
        let modeRaw = defaults.string(forKey: Keys.defaultViewMode) ?? CandidateViewMode.paging.rawValue
        self.defaultViewMode = CandidateViewMode(rawValue: modeRaw) ?? .paging
    }
    
    public func resetToDefaults() {
        isFourArrowSelectionEnabled = false
        pinyinScheme = .full
        isPanguSpacingEnabled = true
        isSmartPunctuationEnabled = true
        isEnglishPunctuationEnabled = false
        isFuzzyPinyinEnabled = true
        isAutoEnglishInTerminalEnabled = true
        isUserLearningEnabled = true
        defaultViewMode = .paging
    }
}
