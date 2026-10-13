import AppKit
import Foundation

@MainActor
public final class InstallationManager: ObservableObject {
    public static let shared = InstallationManager()
    
    @Published public var isInstalled: Bool = false
    @Published public var isRunning: Bool = false
    @Published public var statusMessage: String = "准备就绪"
    @Published public var isInstalling: Bool = false
    
    private let targetDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Input Methods")
    private var targetAppURL: URL {
        targetDir.appendingPathComponent("AetherKey.app")
    }

    public init() {
        checkStatus()
    }

    public func checkStatus() {
        let fileExists = FileManager.default.fileExists(atPath: targetAppURL.path)
        self.isInstalled = fileExists
        
        // Check if process is running
        let runningApps = NSWorkspace.shared.runningApplications
        self.isRunning = runningApps.contains { $0.bundleIdentifier == "com.aethernative.inputmethod.AetherKey" }
        
        if isInstalled && isRunning {
            statusMessage = "AetherKey 服务运行正常"
        } else if isInstalled {
            statusMessage = "已安装至输入法目录，未激活服务"
        } else {
            statusMessage = "尚未安装 AetherKey"
        }
    }

    public func install() {
        isInstalling = true
        statusMessage = "正在部署 AetherKey..."
        
        Task.detached(priority: .userInitiated) {
            // Find AetherKey.app source
            var sourceURL: URL?
            
            // 1. Bundle resource
            if let bundled = Bundle.main.url(forResource: "AetherKey", withExtension: "app") {
                sourceURL = bundled
            }
            
            // 2. Relative to executable
            if sourceURL == nil {
                let execURL = Bundle.main.bundleURL
                let candidate1 = execURL.deletingLastPathComponent().appendingPathComponent("AetherKey.app")
                let candidate2 = execURL.deletingLastPathComponent().appendingPathComponent("build/AetherKey.app")
                let candidate3 = URL(fileURLWithPath: "/Volumes/AetherKey/build/AetherKey.app")
                let candidate4 = URL(fileURLWithPath: "/tmp/aetherkey_install/AetherKey.app")
                
                for candidate in [candidate1, candidate2, candidate3, candidate4] {
                    if FileManager.default.fileExists(atPath: candidate.path) {
                        sourceURL = candidate
                        break
                    }
                }
            }
            
            // 3. Download from host if in VM and not found
            if sourceURL == nil {
                let tmpZip = URL(fileURLWithPath: "/tmp/AetherKey_dl.zip")
                let tmpUnzip = URL(fileURLWithPath: "/tmp/AetherKey_unzip")
                
                let curlProc = Process()
                curlProc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                curlProc.arguments = ["-fsSL", "http://192.168.64.1:8000/AetherKey.zip", "-o", tmpZip.path]
                try? curlProc.run()
                curlProc.waitUntilExit()
                
                if curlProc.terminationStatus == 0 {
                    let unzipProc = Process()
                    unzipProc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                    unzipProc.arguments = ["-q", "-o", tmpZip.path, "-d", tmpUnzip.path]
                    try? unzipProc.run()
                    unzipProc.waitUntilExit()
                    
                    let candidate = tmpUnzip.appendingPathComponent("AetherKey.app")
                    if FileManager.default.fileExists(atPath: candidate.path) {
                        sourceURL = candidate
                    }
                }
            }
            
            guard let validSource = sourceURL else {
                await MainActor.run {
                    self.isInstalling = false
                    self.statusMessage = "❌ 未找到构建包，请检查网络或构建产物"
                }
                return
            }
            
            // Kill existing process
            let pkill = Process()
            pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            pkill.arguments = ["-9", "-f", "AetherKey"]
            try? pkill.run()
            pkill.waitUntilExit()
            
            // Copy to target directory
            let targetDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Input Methods")
            try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            
            let targetApp = targetDir.appendingPathComponent("AetherKey.app")
            try? FileManager.default.removeItem(at: targetApp)
            
            do {
                try FileManager.default.copyItem(at: validSource, to: targetApp)
            } catch {
                await MainActor.run {
                    self.isInstalling = false
                    self.statusMessage = "❌ 文件写入失败: \(error.localizedDescription)"
                }
                return
            }
            
            // lsregister
            let lsregister = Process()
            lsregister.executableURL = URL(fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister")
            lsregister.arguments = ["-f", "-R", "-trusted", targetApp.path]
            try? lsregister.run()
            lsregister.waitUntilExit()
            
            // codesign
            let codesign = Process()
            codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            codesign.arguments = ["--force", "--deep", "--sign", "-", targetApp.path]
            try? codesign.run()
            codesign.waitUntilExit()
            
            // Launch service
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = [targetApp.path]
            try? open.run()
            open.waitUntilExit()
            
            try? await Task.sleep(nanoseconds: 800_000_000)
            
            await MainActor.run {
                self.isInstalling = false
                self.checkStatus()
                self.statusMessage = "✓ 安装完成！请在系统设置中启用"
            }
        }
    }

    public func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        } else {
            let prefURL = URL(fileURLWithPath: "/System/Library/PreferencePanes/Keyboard.prefPane")
            NSWorkspace.shared.open(prefURL)
        }
    }
}
