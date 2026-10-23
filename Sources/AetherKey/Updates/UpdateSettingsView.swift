import SwiftUI
import AppKit

@MainActor
public struct UpdateSettingsView: View {
    @ObservedObject private var updater = UpdateController.shared
    @ObservedObject private var login = LoginItemController.shared
    private var status: String {
        switch updater.state {
        case .notChecked: "随时检查，保持最新"
        case .checking: "正在检查更新…"
        case .current: "当前没有可安装的新版本"
        case .available: "发现新版本 \(updater.availableVersion ?? "")"
        case .failed: "暂时无法检查，请稍后重试"
        }
    }

    public var body: some View {
        LiquidGlassContainer(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(.blue).padding(12)
                        .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("应用更新").font(.system(size: 17, weight: .semibold))
                        Text("当前版本 \(UpdateController.version)").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(updater.availableVersion == nil ? "检查更新…" : "查看新版本…") { updater.checkForUpdates() }
                        .buttonStyle(.borderedProminent).disabled(!updater.canCheckForUpdates)
                }
                HStack {
                    if updater.state == .checking { ProgressView().controlSize(.small) }
                    else { Image(systemName: updater.state == .available ? "sparkles" : "checkmark.shield").foregroundStyle(updater.state == .available ? .blue : .secondary) }
                    Text(status).font(.system(size: 13, weight: .medium))
                }
                Divider()
                Toggle("每 6 小时自动检查更新", isOn: $updater.automaticallyChecksForUpdates).toggleStyle(.switch)
                HStack(alignment: .top) {
                    timeLabel("最近检查", date: updater.lastCheckedAt, empty: "尚未检查")
                    Spacer()
                    timeLabel("下次计划检查", date: updater.automaticallyChecksForUpdates ? updater.nextCheckAt : nil,
                              empty: updater.automaticallyChecksForUpdates ? "正在安排" : "已关闭自动检查")
                }
                Text("发现新版会显示版本号与更新说明，由你确认下载和安装。休眠或退出后，检查时间会顺延。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Divider()
                Toggle("登录后自动启动", isOn: Binding(get: { login.isEnabled }, set: { login.setEnabled($0) })).toggleStyle(.switch)
                HStack {
                    Text(login.message).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    if login.needsApproval { Button("打开系统设置") { login.openSystemSettings() }.controlSize(.small) }
                }
            }.padding(20)
        }
        .onAppear { login.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.refresh() }
    }

    private func timeLabel(_ title: String, date: Date?, empty: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            if let date { Text(date, format: .dateTime.month().day().hour().minute()).font(.system(size: 12, weight: .medium)) }
            else { Text(empty).font(.system(size: 12)).foregroundStyle(.secondary) }
        }
    }
}
