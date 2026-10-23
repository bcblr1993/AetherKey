import AppKit
import Combine
import ServiceManagement

@MainActor
public final class LoginItemController: ObservableObject {
    public static let shared = LoginItemController()
    @Published public private(set) var isEnabled = false
    @Published public private(set) var needsApproval = false
    @Published public private(set) var message = ""
    private let configuredKey = "aetherkey.loginItemConfigured"

    public func start() {
        refresh()
        if !UserDefaults.standard.bool(forKey: configuredKey) {
            setEnabled(true)
        }
    }

    public func refresh() {
        let status = SMAppService.mainApp.status
        needsApproval = status == .requiresApproval
        isEnabled = status == .enabled || needsApproval
        message = needsApproval ? "等待系统允许，请在登录项中启用 AetherKey。" : status == .enabled ? "已启用，登录后在后台启动。" : "未启用，需要时可从输入法菜单启动。"
    }

    public func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            UserDefaults.standard.set(true, forKey: configuredKey)
            refresh()
        } catch {
            refresh()
            message = "未能更改登录启动状态，请在系统设置中检查。"
        }
    }

    public func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
