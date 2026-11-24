import Carbon
import Darwin
import Foundation

/// Manages LaunchServices, Carbon TIS registration, bundle inode fingerprinting,
/// and macOS input-agent refresh so AetherKey remains visible and selectable across
/// upgrades, repeated installs, and uninstall/reinstall cycles.
public enum InputMethodRegistrar {
    public static let bundleID = "com.aethernative.inputmethod.AetherKey"
    public static let hansModeID = "com.aethernative.inputmethod.AetherKey.Hans"
    public static let lastRegisteredFingerprintKey = "aetherkey.lastRegisteredBundleFingerprint"

    private static let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    // MARK: - Bundle Identity & Fingerprinting

    /// Returns `true` only when `bundleURL` is installed in the user or system `Input Methods` directory.
    public static func isInstalledInputMethodPath(
        _ bundleURL: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        let normalized = bundleURL.standardizedFileURL.resolvingSymlinksInPath().path
        let userTarget = homeDirectory
            .appendingPathComponent("Library/Input Methods/AetherKey.app")
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        let systemTarget = URL(fileURLWithPath: "/Library/Input Methods/AetherKey.app")
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        return normalized == userTarget || normalized == systemTarget
    }

    /// Computes a deterministic fingerprint combining version, build, directory inode, and binary inode.
    public static func bundleFingerprint(at bundleURL: URL) -> String? {
        let fm = FileManager.default
        let resolvedBundleURL = bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        let executableURL = resolvedBundleURL.appendingPathComponent("Contents/MacOS/AetherKey")
        let infoPlistURL = resolvedBundleURL.appendingPathComponent("Contents/Info.plist")

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: resolvedBundleURL.path, isDirectory: &isDir), isDir.boolValue,
              fm.fileExists(atPath: executableURL.path),
              fm.fileExists(atPath: infoPlistURL.path),
              let plistData = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let bundleAttrs = try? fm.attributesOfItem(atPath: resolvedBundleURL.path),
              let execAttrs = try? fm.attributesOfItem(atPath: executableURL.path),
              let dirInode = (bundleAttrs[.systemFileNumber] as? NSNumber)?.uint64Value,
              let execInode = (execAttrs[.systemFileNumber] as? NSNumber)?.uint64Value else {
            return nil
        }

        let shortVersion = (plist["CFBundleShortVersionString"] as? String) ?? ""
        let buildVersion = (plist["CFBundleVersion"] as? String) ?? ""
        return "\(shortVersion)|\(buildVersion)|\(dirInode)|\(execInode)"
    }

    /// Returns `true` when the active bundle differs from the last registered version/inode fingerprint.
    public static func shouldRefreshForBundleChange(
        currentFingerprint: String?,
        lastRecordedFingerprint: String?
    ) -> Bool {
        guard let currentFingerprint, !currentFingerprint.isEmpty else {
            return false
        }
        return currentFingerprint != lastRecordedFingerprint
    }

    /// Returns `.standard` when running inside `AetherKey.app` (where `UserDefaults(suiteName: bundleID)`
    /// returns `nil`), and `UserDefaults(suiteName: bundleID)` from other processes such as `AetherSetup`.
    public static func sharedDefaults() -> UserDefaults? {
        if Bundle.main.bundleIdentifier == bundleID {
            return .standard
        }
        return UserDefaults(suiteName: bundleID)
    }

    public static func recordRegisteredFingerprint(
        _ fingerprint: String,
        defaults: UserDefaults? = sharedDefaults()
    ) {
        defaults?.set(fingerprint, forKey: lastRegisteredFingerprintKey)
        defaults?.synchronize()
    }

    public static func lastRecordedFingerprint(
        defaults: UserDefaults? = sharedDefaults()
    ) -> String? {
        defaults?.string(forKey: lastRegisteredFingerprintKey)
    }

    public static func clearRecordedFingerprint(
        defaults: UserDefaults? = sharedDefaults()
    ) {
        defaults?.removeObject(forKey: lastRegisteredFingerprintKey)
        defaults?.synchronize()
    }

    // MARK: - Current-User Process Inspection & Safe Signaling

    /// Enumerates PIDs owned by the current UID whose resolved executable path matches `matching`.
    public static func findCurrentUserProcessIDs(matching: (String) -> Bool) -> [pid_t] {
        let myUID = getuid()
        let estimatedBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard estimatedBytes > 0 else { return [] }

        let capacity = Int(estimatedBytes) / MemoryLayout<pid_t>.size + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let bytesWritten = proc_pidListBytes(&pids)
        guard bytesWritten > 0 else { return [] }

        let count = Int(bytesWritten) / MemoryLayout<pid_t>.size
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        var result: [pid_t] = []
        result.reserveCapacity(8)

        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }
            var info = proc_bsdinfo()
            let infoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, infoSize) == infoSize,
                  info.pbi_uid == myUID else {
                continue
            }
            let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            guard pathLen > 0 else { continue }
            let rawBytes = pathBuffer.prefix(Int(pathLen)).map { UInt8(bitPattern: $0) }
            let path = String(decoding: rawBytes, as: UTF8.self)
            if matching(path) {
                result.append(pid)
            }
        }
        return result
    }

    private static func proc_pidListBytes(_ pids: inout [pid_t]) -> Int32 {
        let byteCapacity = Int32(pids.count * MemoryLayout<pid_t>.size)
        return pids.withUnsafeMutableBufferPointer { buf in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buf.baseAddress, byteCapacity)
        }
    }

    private static func isProcessAlive(_ pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let infoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, infoSize) == infoSize
    }

    /// Returns PIDs of other running `AetherKey.app` instances installed in `Input Methods`.
    public static func findRunningAetherKeyPIDs() -> [pid_t] {
        let selfPID = getpid()
        return findCurrentUserProcessIDs { path in
            path.hasSuffix("/Library/Input Methods/AetherKey.app/Contents/MacOS/AetherKey")
        }.filter { $0 != selfPID }
    }

    /// Gracefully terminates all other running installed `AetherKey` processes, falling back to `SIGKILL`.
    @discardableResult
    public static func terminateRunningAetherKeyProcesses() -> [pid_t] {
        let initialPIDs = findRunningAetherKeyPIDs()
        guard !initialPIDs.isEmpty else { return [] }

        for pid in initialPIDs {
            _ = kill(pid, SIGTERM)
        }
        for _ in 0..<12 {
            if !initialPIDs.contains(where: isProcessAlive) {
                return initialPIDs
            }
            usleep(100_000)
        }

        let survivors = initialPIDs.filter(isProcessAlive)
        for pid in survivors {
            _ = kill(pid, SIGKILL)
        }
        for _ in 0..<8 {
            if !survivors.contains(where: isProcessAlive) {
                break
            }
            usleep(100_000)
        }
        return initialPIDs
    }

    // MARK: - Bundle Attributes, LaunchServices & Input Agent Refresh

    public static func clearQuarantineAttribute(at bundleURL: URL) {
        runProcessBestEffort(
            executablePath: "/usr/bin/xattr",
            arguments: ["-dr", "com.apple.quarantine", bundleURL.path],
            timeoutSeconds: 5
        )
    }

    public static func invalidateIntlFileCache() {
        var pb: Pasteboard?
        if PasteboardCreate("AppleIntlFileCacheModificationDatePasteboard" as CFString, &pb) == noErr,
           let pb {
            PasteboardClear(pb)
            PasteboardSynchronize(pb)
        }
    }

    public static func registerWithLaunchServices(bundleURL: URL) {
        guard FileManager.default.fileExists(atPath: lsregisterPath) else { return }
        runProcessBestEffort(
            executablePath: lsregisterPath,
            arguments: ["-f", bundleURL.path],
            timeoutSeconds: 5
        )
    }

    public static func unregisterWithLaunchServices(bundleURL: URL) {
        guard FileManager.default.fileExists(atPath: lsregisterPath) else { return }
        runProcessBestEffort(
            executablePath: lsregisterPath,
            arguments: ["-u", bundleURL.path],
            timeoutSeconds: 5
        )
    }

    /// Restarts the current user's stale system input agents (`imklaunchagent`, `TextInputSwitcher`,
    /// `TextInputMenuAgent`) so they drop deleted bundle inodes and reload fresh metadata/icons.
    public static func restartStaleSystemInputAgentsSynchronously() {
        let imkPathPrefix = "/System/Library/Frameworks/InputMethodKit.framework/"
        let switcherPath = "/System/Library/CoreServices/TextInputSwitcher.app/Contents/MacOS/TextInputSwitcher"
        let menuAgentPath = "/System/Library/CoreServices/TextInputMenuAgent.app/Contents/MacOS/TextInputMenuAgent"

        let imkPIDs = findCurrentUserProcessIDs { path in
            path.hasPrefix(imkPathPrefix) && path.hasSuffix("/imklaunchagent")
        }
        let switcherPIDs = findCurrentUserProcessIDs { $0 == switcherPath }
        let menuAgentPIDs = findCurrentUserProcessIDs { $0 == menuAgentPath }

        for pid in imkPIDs {
            _ = kill(pid, SIGKILL)
        }
        // TextInputSwitcher ignores SIGTERM under launchd/xpc transaction hold, so kill immediately.
        for pid in switcherPIDs {
            _ = kill(pid, SIGKILL)
        }
        for pid in menuAgentPIDs {
            _ = kill(pid, SIGTERM)
        }

        if !menuAgentPIDs.isEmpty {
            for _ in 0..<6 {
                if !menuAgentPIDs.contains(where: isProcessAlive) {
                    break
                }
                usleep(100_000)
            }
            for pid in menuAgentPIDs where isProcessAlive(pid) {
                _ = kill(pid, SIGKILL)
            }
        }

        let killedMenuSet = Set(menuAgentPIDs)
        for _ in 0..<20 {
            let currentMenu = findCurrentUserProcessIDs { $0 == menuAgentPath }
            if currentMenu.contains(where: { !killedMenuSet.contains($0) }) {
                break
            }
            usleep(100_000)
        }
    }

    /// Synchronous pre-`IMKServer` preparation used at launch when the bundle fingerprint changed.
    public static func prepareFreshSystemAgentsSynchronously(bundleURL: URL) {
        invalidateIntlFileCache()
        registerWithLaunchServices(bundleURL: bundleURL)
        restartStaleSystemInputAgentsSynchronously()
        _ = TISRegisterInputSource(bundleURL as CFURL)
    }

    // MARK: - Carbon TIS Operations (@MainActor)

    @MainActor
    public static func isAetherKeyEnabled() -> Bool {
        let sources = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] ?? []
        let parentEnabled = sources.first(where: { sourceID($0) == bundleID }).map(isEnabled) ?? false
        let modeEnabled = sources.first(where: { sourceID($0) == hansModeID }).map(isEnabled) ?? false
        return parentEnabled && modeEnabled
    }

    @MainActor
    public static func isAetherKeyCurrent() -> Bool {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return false
        }
        let id = sourceID(current)
        return id == bundleID || id == hansModeID
    }

    @MainActor
    public static func switchAwayFromAetherKeyIfActive() {
        guard isAetherKeyCurrent() else { return }
        if let asciiLayout = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
           TISSelectInputSource(asciiLayout) == noErr {
            return
        }
        let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] ?? []
        if let abc = sources.first(where: { sourceID($0) == "com.apple.keylayout.ABC" }) {
            _ = TISSelectInputSource(abc)
        }
    }

    @MainActor
    public static func disableInputSources() {
        let sources = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] ?? []
        if let mode = sources.first(where: { sourceID($0) == hansModeID }) {
            _ = TISDisableInputSource(mode)
        }
        if let parent = sources.first(where: { sourceID($0) == bundleID }) {
            _ = TISDisableInputSource(parent)
        }
    }

    @MainActor
    public static func registerAndCycleEnable(
        bundleURL: URL,
        forceCycleEnable: Bool,
        selectAfterEnable: Bool
    ) async -> (registered: OSStatus, enabled: Bool, selected: Bool) {
        invalidateIntlFileCache()
        let regStatus = TISRegisterInputSource(bundleURL as CFURL)

        if forceCycleEnable {
            disableInputSources()
            try? await Task.sleep(for: .milliseconds(250))

            let parentList = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] ?? []
            if let parent = parentList.first(where: { sourceID($0) == bundleID }) {
                _ = TISEnableInputSource(parent)
            }
            try? await Task.sleep(for: .milliseconds(200))

            let modeList = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] ?? []
            if let mode = modeList.first(where: { sourceID($0) == hansModeID }) {
                _ = TISEnableInputSource(mode)
            }
        } else if !isAetherKeyEnabled() {
            let parentList = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] ?? []
            if let parent = parentList.first(where: { sourceID($0) == bundleID }), !isEnabled(parent) {
                _ = TISEnableInputSource(parent)
            }
            try? await Task.sleep(for: .milliseconds(200))

            let modeList = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] ?? []
            if let mode = modeList.first(where: { sourceID($0) == hansModeID }), !isEnabled(mode) {
                _ = TISEnableInputSource(mode)
            }
        }

        try? await Task.sleep(for: .milliseconds(350))
        let enabled = isAetherKeyEnabled()
        var selected = isAetherKeyCurrent()
        if selectAfterEnable {
            selected = await selectAetherKeyWithRetry()
        }
        return (registered: regStatus, enabled: enabled, selected: selected)
    }

    @MainActor
    public static func selectAetherKeyWithRetry(
        attempts: Int = 6,
        delayMilliseconds: UInt64 = 400
    ) async -> Bool {
        for _ in 0..<max(1, attempts) {
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            let enabledSources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] ?? []
            let allSources = enabledSources.contains(where: { sourceID($0) == hansModeID })
                ? enabledSources
                : (TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] ?? [])
            if let mode = allSources.first(where: { sourceID($0) == hansModeID }),
               TISSelectInputSource(mode) == noErr,
               isAetherKeyCurrent() {
                return true
            }
        }
        return isAetherKeyCurrent()
    }

    @MainActor
    public static func refreshSystemAndReenable(
        bundleURL: URL,
        selectAfterRefresh: Bool
    ) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            invalidateIntlFileCache()
            registerWithLaunchServices(bundleURL: bundleURL)
            restartStaleSystemInputAgentsSynchronously()
        }.value

        if let fingerprint = bundleFingerprint(at: bundleURL),
           isInstalledInputMethodPath(bundleURL) {
            recordRegisteredFingerprint(fingerprint)
        }
        let result = await registerAndCycleEnable(
            bundleURL: bundleURL,
            forceCycleEnable: false,
            selectAfterEnable: selectAfterRefresh
        )
        return result.registered == noErr && result.enabled && (!selectAfterRefresh || result.selected)
    }

    // MARK: - Private Helpers

    @MainActor
    private static func sourceID(_ source: TISInputSource) -> String {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    @MainActor
    private static func isEnabled(_ source: TISInputSource) -> Bool {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue())
    }

    private static func runProcessBestEffort(
        executablePath: String,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            return
        }

        if finished.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 1)
        }
    }
}
