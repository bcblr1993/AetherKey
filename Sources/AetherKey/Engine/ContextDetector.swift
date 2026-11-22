import AppKit

/// Scene perception engine for automatically adapting input behavior based on host applications.
public final class ContextDetector: Sendable {
    public static let shared = ContextDetector()
    
    /// Set of known terminal emulator and code editor bundle IDs where input favors raw English.
    private let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "net.kovidgoyal.kitty",
        "com.mitchellh.ghostty",
        "org.alacritty",
        "com.github.wez.wezterm",
        "dev.warp.Warp-Stable",
        "co.zeit.hyper",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",
        "dev.zed.Zed",
        "com.apple.dt.Xcode",
        "com.sublimetext.4",
        "com.exafunction.windsurf",
        "org.tabby",
        "com.neovide.neovide",
        "com.raphaelamorim.rio"
    ]
    
    /// Browser bundle IDs for address bar detection
    private let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.brave.Browser",
        "company.thebrowser.Browser", // Arc
        "com.microsoft.edgemac",
        "org.mozilla.firefox"
    ]
    
    /// Returns whether the target application is a terminal or code editor environment.
    public func isTerminalApp(bundleIdentifier: String?) -> Bool {
        guard let bundleId = bundleIdentifier else { return false }
        return terminalBundleIDs.contains(bundleId)
    }
    
    /// Checks whether the current context should default to English pass-through.
    public func shouldDefaultToEnglish(bundleIdentifier: String?) -> Bool {
        if let bundleId = bundleIdentifier {
            if terminalBundleIDs.contains(bundleId) {
                return true
            }
        }
        
        if let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            if terminalBundleIDs.contains(frontmost) {
                return true
            }
        }
        return false
    }

    /// Resolves default input mode: user custom rule > terminal/editor auto-English > Chinese.
    public func resolvedDefaultMode(for bundleIdentifier: String?, settings: AetherSettings = .shared) -> InputMode {
        if let bundleId = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !bundleId.isEmpty {
            if let custom = settings.appDefaultMode(for: bundleId) {
                switch custom {
                case .english: return .english
                case .chinese: return .chinese
                }
            }
            if settings.isAutoEnglishInTerminalEnabled && isTerminalApp(bundleIdentifier: bundleId) {
                return .english
            }
        }
        return .chinese
    }
}
