import AppKit

/// Scene perception engine for automatically adapting input behavior based on host applications.
public final class ContextDetector: Sendable {
    public static let shared = ContextDetector()
    
    /// Set of known terminal emulator bundle IDs where CLI input favors raw English.
    private let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "net.kovidgoyal.kitty",
        "com.mitchellh.ghostty",
        "org.alacritty",
        "com.github.wez.wezterm",
        "dev.warp.Warp-Stable",
        "co.zeit.hyper",
        "com.microsoft.VSCode" // Often in terminal or code editing
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
    
    /// Returns whether the target application is a terminal environment.
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
}
