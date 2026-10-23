import AppKit
import Foundation
import Carbon

@MainActor
public final class InstallationManager: ObservableObject {
    public static let shared = InstallationManager()
    public static let bundleID = "com.aethernative.inputmethod.AetherKey"

    @Published public var currentStep = 0
    @Published public var isInstalled = false
    @Published public var isRunning = false
    @Published public var isSourceAdded = false
    @Published public var isCurrentSource = false
    @Published public var isInstalling = false
    @Published public var installPhase = 0
    @Published public var errorMessage: String?
    @Published public var activationHint: String?
    @Published public var statusMessage = "准备开始"
    public let isPreview: Bool

    private let targetDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Input Methods")
    private var targetAppURL: URL { targetDir.appendingPathComponent("AetherKey.app") }

    public init(previewStep: Int? = nil) {
        isPreview = previewStep != nil
        if let previewStep {
            currentStep = min(3, max(0, previewStep))
            return
        }
        checkStatus()
    }

    public func checkStatus() {
        guard !isPreview else { return }
        isInstalled = Bundle(url: targetAppURL)?.bundleIdentifier == Self.bundleID
        isRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == Self.bundleID }
        checkInputSourceStatus()
        statusMessage = isCurrentSource ? "已切换到 AetherKey" : isSourceAdded ? "输入法已启用" : isInstalled ? "已安装，等待启用" : "准备开始"
    }

    private func sourceID(_ source: TISInputSource) -> String {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    private func isEnabled(_ source: TISInputSource) -> Bool {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue())
    }

    public func checkInputSourceStatus() {
        let sources = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] ?? []
        // A mode can report its default enabled state even while its parent IME is disabled.
        // Only the parent confirms that the user actually added the input method.
        isSourceAdded = sources.contains { sourceID($0) == Self.bundleID && isEnabled($0) }
        isCurrentSource = TISCopyCurrentKeyboardInputSource().map {
            let id = sourceID($0.takeRetainedValue())
            return id == Self.bundleID || id == Self.bundleID + ".Hans"
        } ?? false
    }

    public func install() {
        guard !isInstalling, !isPreview else { return }
        isInstalling = true
        installPhase = 0
        errorMessage = nil
        Task {
            do {
                guard let source = Bundle.main.url(forResource: "AetherKey", withExtension: "app"),
                      Bundle(url: source)?.bundleIdentifier == Self.bundleID else {
                    throw SetupError.message("安装包缺少输入法组件，请重新下载完整的 AetherKey DMG。")
                }
                installPhase = 1
                // Only stop this input method, never the setup app or unrelated processes.
                let running = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == Self.bundleID }
                running.forEach { _ = $0.terminate() }
                for _ in 0..<20 {
                    if running.allSatisfy(\.isTerminated) { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard running.allSatisfy(\.isTerminated) else {
                    throw SetupError.message("输入法仍在使用中。请先切换到其他输入法，再点击重试。")
                }
                let destination = targetAppURL
                let directory = targetDir
                try await Task.detached(priority: .userInitiated) {
                    let fm = FileManager.default
                    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                    let stage = directory.appendingPathComponent(".AetherKey-stage-" + UUID().uuidString)
                    defer { try? fm.removeItem(at: stage) }
                    try fm.copyItem(at: source, to: stage)
                    if fm.fileExists(atPath: destination.path) {
                        // Keep the previous version recoverable and restore it if replacement fails.
                        let backupDir = directory.appendingPathComponent(".AetherKey-replacement-" + UUID().uuidString)
                        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
                        let backup = backupDir.appendingPathComponent(UUID().uuidString + ".app")
                        try fm.moveItem(at: destination, to: backup)
                        do {
                            try fm.moveItem(at: stage, to: destination)
                            try? fm.removeItem(at: backupDir)
                        }
                        catch {
                            try fm.moveItem(at: backup, to: destination)
                            try? fm.removeItem(at: backupDir)
                            throw error
                        }
                    } else {
                        try fm.moveItem(at: stage, to: destination)
                    }
                }.value
                installPhase = 2
                let registration = TISRegisterInputSource(destination as CFURL)
                guard registration == noErr else {
                    throw SetupError.message("文件已安装，但 macOS 暂未完成注册（\(registration)）。请重试；如仍未出现，可注销并重新登录后继续设置。")
                }
                try await NSWorkspace.shared.openApplication(at: destination, configuration: NSWorkspace.OpenConfiguration())
                installPhase = 3
                checkStatus()
                guard isInstalled else { throw SetupError.message("未能确认安装结果，请重试。") }
                isInstalling = false
                currentStep = 2
            } catch {
                isInstalling = false
                checkStatus()
                errorMessage = error.localizedDescription
            }
        }
    }

    public func autoEnableInputSource() {
        guard !isPreview else { return }
        activationHint = nil
        let sources = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] ?? []
        if let parent = sources.first(where: { sourceID($0) == Self.bundleID }), !isEnabled(parent) {
            _ = TISEnableInputSource(parent)
        }
        // Refresh after enabling the parent: macOS may only now expose its mode.
        let refreshed = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] ?? []
        if let mode = refreshed.first(where: { sourceID($0) == Self.bundleID + ".Hans" }) {
            _ = TISSelectInputSource(mode)
        }
        checkStatus()
        if !isCurrentSource {
            activationHint = isSourceAdded
                ? "已添加。请在菜单栏输入法菜单中选择 AetherKey，或按 Control + 空格切换。"
                : "macOS 尚未启用输入法。请打开键盘设置，按下方步骤添加；若搜索不到，注销并重新登录后再次打开安装向导。"
        }
    }

    public func openKeyboardSettings() {
        guard !isPreview else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

private enum SetupError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): return text } }
}
