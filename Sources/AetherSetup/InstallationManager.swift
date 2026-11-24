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
    @Published public var isUninstalling = false
    @Published public var isRepairing = false
    @Published public var installPhase = 0
    @Published public var errorMessage: String?
    @Published public var noticeMessage: String?
    @Published public var activationHint: String?
    @Published public var statusMessage = "准备开始"
    public let isPreview: Bool

    public var isBusy: Bool { isInstalling || isUninstalling || isRepairing }

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
        guard !isBusy, !isPreview else { return }
        isInstalling = true
        installPhase = 0
        errorMessage = nil
        noticeMessage = nil
        activationHint = nil
        Task {
            do {
                guard let source = Bundle.main.url(forResource: "AetherKey", withExtension: "app"),
                      Bundle(url: source)?.bundleIdentifier == Self.bundleID,
                      FileManager.default.fileExists(atPath: source.appendingPathComponent("Contents/MacOS/AetherKey").path) else {
                    throw SetupError.message("安装包缺少输入法组件，请重新下载完整的 AetherKey DMG。")
                }
                installPhase = 1
                // Switch away from AetherKey before replacing the bundle so macOS releases active IMK clients.
                InputMethodRegistrar.switchAwayFromAetherKeyIfActive()
                let running = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == Self.bundleID }
                running.forEach { _ = $0.terminate() }

                let destination = targetAppURL
                let directory = targetDir
                try await Task.detached(priority: .userInitiated) {
                    _ = InputMethodRegistrar.terminateRunningAetherKeyProcesses()
                    let fm = FileManager.default
                    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                    if let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                        for item in items where item.lastPathComponent.hasPrefix(".AetherKey-") {
                            try? fm.removeItem(at: item)
                        }
                    }

                    let stage = directory.appendingPathComponent(".AetherKey-stage-" + UUID().uuidString)
                    defer { try? fm.removeItem(at: stage) }
                    try fm.copyItem(at: source, to: stage)
                    InputMethodRegistrar.clearQuarantineAttribute(at: stage)

                    if fm.fileExists(atPath: destination.path) {
                        // Keep the previous version recoverable and restore it if replacement fails.
                        let backupDir = directory.appendingPathComponent(".AetherKey-replacement-" + UUID().uuidString)
                        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
                        let backup = backupDir.appendingPathComponent(UUID().uuidString + ".app")
                        try fm.moveItem(at: destination, to: backup)
                        do {
                            try fm.moveItem(at: stage, to: destination)
                            try? fm.removeItem(at: backupDir)
                        } catch {
                            try fm.moveItem(at: backup, to: destination)
                            try? fm.removeItem(at: backupDir)
                            throw error
                        }
                    } else {
                        try fm.moveItem(at: stage, to: destination)
                    }
                }.value

                installPhase = 2
                await Task.detached(priority: .userInitiated) {
                    InputMethodRegistrar.invalidateIntlFileCache()
                    InputMethodRegistrar.registerWithLaunchServices(bundleURL: destination)
                    InputMethodRegistrar.restartStaleSystemInputAgentsSynchronously()
                }.value

                if let fingerprint = InputMethodRegistrar.bundleFingerprint(at: destination) {
                    InputMethodRegistrar.recordRegisteredFingerprint(fingerprint)
                }

                let cycleResult = await InputMethodRegistrar.registerAndCycleEnable(
                    bundleURL: destination,
                    forceCycleEnable: false,
                    selectAfterEnable: false
                )
                guard cycleResult.registered == noErr else {
                    throw SetupError.message("文件已安装，但 macOS 暂未完成注册（\(cycleResult.registered)）。请重试；如仍未出现，可注销并重新登录后继续设置。")
                }

                try await launchInstalledApp(destination)
                try? await Task.sleep(for: .milliseconds(400))
                _ = await InputMethodRegistrar.selectAetherKeyWithRetry()

                installPhase = 3
                checkStatus()
                guard isInstalled else { throw SetupError.message("未能确认安装结果，请重试。") }
                isInstalling = false
                noticeMessage = "已完成安装并刷新系统输入法服务。"
                currentStep = 2
            } catch {
                isInstalling = false
                checkStatus()
                errorMessage = error.localizedDescription
            }
        }
    }

    public func uninstall() {
        guard !isBusy, !isPreview else { return }
        isUninstalling = true
        errorMessage = nil
        noticeMessage = nil
        activationHint = nil
        Task {
            do {
                InputMethodRegistrar.switchAwayFromAetherKeyIfActive()
                InputMethodRegistrar.disableInputSources()
                let running = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == Self.bundleID }
                running.forEach { _ = $0.terminate() }

                let destination = targetAppURL
                let directory = targetDir
                try await Task.detached(priority: .userInitiated) {
                    _ = InputMethodRegistrar.terminateRunningAetherKeyProcesses()
                    InputMethodRegistrar.unregisterWithLaunchServices(bundleURL: destination)
                    let fm = FileManager.default
                    if fm.fileExists(atPath: destination.path) {
                        try fm.removeItem(at: destination)
                    }
                    if let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                        for item in items where item.lastPathComponent.hasPrefix(".AetherKey-") {
                            try? fm.removeItem(at: item)
                        }
                    }
                    InputMethodRegistrar.clearRecordedFingerprint()
                    InputMethodRegistrar.invalidateIntlFileCache()
                    InputMethodRegistrar.restartStaleSystemInputAgentsSynchronously()
                }.value

                installPhase = 0
                isUninstalling = false
                checkStatus()
                noticeMessage = "已卸载 AetherKey（个人词库与偏好已保留），随时可重新安装。"
            } catch {
                isUninstalling = false
                checkStatus()
                errorMessage = "卸载未完成：\(error.localizedDescription)"
            }
        }
    }

    public func repairRegistration() {
        guard !isBusy, !isPreview else { return }
        isRepairing = true
        activationHint = nil
        Task {
            let ok = await InputMethodRegistrar.refreshSystemAndReenable(
                bundleURL: targetAppURL,
                selectAfterRefresh: true
            )
            if FileManager.default.fileExists(atPath: targetAppURL.path),
               !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == Self.bundleID }) {
                try? await launchInstalledApp(targetAppURL)
            }
            isRepairing = false
            checkStatus()
            activationHint = ok
                ? "已刷新系统输入法服务，并切换到 AetherKey。"
                : "已刷新系统输入法服务；若系统顶部输入法列表中仍未显示，请在键盘设置中点「−」移除 AetherKey 后再点「＋」添加一次即可。"
        }
    }

    public func autoEnableInputSource() {
        guard !isPreview else { return }
        activationHint = nil
        Task {
            _ = await InputMethodRegistrar.registerAndCycleEnable(
                bundleURL: targetAppURL,
                forceCycleEnable: false,
                selectAfterEnable: true
            )
            checkStatus()
            if !isCurrentSource {
                activationHint = isSourceAdded
                    ? "已启用，请按 Control + 空格切换。若顶部输入法下拉列表中未出现，请在键盘设置移除后再添加一次「AetherKey 拼音」。"
                    : "macOS 尚未启用输入法。请打开键盘设置，按下方步骤添加；若搜索不到，点击下方刷新服务或注销后重试。"
            }
        }
    }

    private func launchInstalledApp(_ url: URL) async throws {
        do {
            try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            try await Task.sleep(for: .milliseconds(400))
            try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
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
