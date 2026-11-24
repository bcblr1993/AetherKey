import AppKit
import Carbon
import Combine

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var cancellables = Set<AnyCancellable>()
    private let didRefreshBundleOnLaunch: Bool

    public init(didRefreshBundleOnLaunch: Bool = false) {
        self.didRefreshBundleOnLaunch = didRefreshBundleOnLaunch
        super.init()
    }

    /// Removes legacy standalone `NSStatusItem` defaults left over from pre-2.0.4 builds
    /// so macOS merges AetherKey exclusively into the system Input Menu dropdown.
    public static func clearLegacyStatusItemDefaults(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "NSStatusItem VisibleCC Item-0")
        defaults.removeObject(forKey: "NSStatusItem Preferred Position Item-0")
        defaults.removeObject(forKey: "NSStatusItem Visible Item-0")
        defaults.removeObject(forKey: "aetherkey.settings.alwaysShowMenuBarIcon")
        defaults.synchronize()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        Self.clearLegacyStatusItemDefaults()

        // Pre-warm the 530k+ lexicon, language model, English mix, U-mode chaizi & Wubi table in background
        DispatchQueue.global(qos: .userInitiated).async {
            PinyinEngine.shared.preload()
            LanguageModel.shared.preload()
            EnglishMixEngine.shared.preload()
            UModeChaiziEngine.shared.preload()
            _ = WubiEngine.shared.entryCount
        }
        invalidateIntlFileCacheModificationPasteboard()
        LoginItemController.shared.start()
        UpdateController.shared.start()
        setupClipboardMonitoring()
        if AetherSettings.shared.isAutoSyncEnabled {
            DispatchQueue.global(qos: .utility).async {
                _ = try? LexiconSyncManager.shared.syncNow()
            }
        }
        if didRefreshBundleOnLaunch {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                _ = await InputMethodRegistrar.registerAndCycleEnable(
                    bundleURL: Bundle.main.bundleURL,
                    forceCycleEnable: false,
                    selectAfterEnable: true
                )
            }
        }
    }

    /// Clears CarbonCore's in-memory `AppleIntlFileCacheModificationDatePasteboard` so sandboxed
    /// extensions like `KeyboardSettings.appex` immediately detect `~/Library/Input Methods/AetherKey.app`.
    private func invalidateIntlFileCacheModificationPasteboard() {
        InputMethodRegistrar.invalidateIntlFileCache()
        TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
    }

    private func setupClipboardMonitoring() {
        if AetherSettings.shared.isClipboardHistoryEnabled {
            ClipboardHistoryStore.shared.startMonitoring()
        }
        AetherSettings.shared.$isClipboardHistoryEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { enabled in
                if enabled {
                    ClipboardHistoryStore.shared.startMonitoring()
                } else {
                    ClipboardHistoryStore.shared.stopMonitoring()
                }
            }
            .store(in: &cancellables)
    }
}
