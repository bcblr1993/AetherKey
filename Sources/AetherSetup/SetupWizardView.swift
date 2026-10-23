import SwiftUI
import Combine
import AppKit

public struct SetupWizardView: View {
    @StateObject private var installer: InstallationManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var testText = ""
    @State private var confirmedTyping = false
    @FocusState private var typingFocused: Bool
    private let accent = Color(red: 0.23, green: 0.43, blue: 0.90)
    private let sky = Color(red: 0.51, green: 0.72, blue: 1.0)
    private let titles = ["认识 AetherKey", "安装输入法", "启用与切换", "写下第一句话"]
    private let subtitles = ["从这里，开始轻快表达", "为你的 Mac 准备就绪", "只差最后一次连接", "你好，新的输入体验"]
    private let symbols = ["sparkles", "arrow.down.to.line", "keyboard", "text.cursor"]
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(installer: InstallationManager = .shared) {
        _installer = StateObject(wrappedValue: installer)
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                HStack {
                    Text("安装与设置").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Label(installer.statusMessage, systemImage: installer.isCurrentSource ? "checkmark.circle.fill" : "circle.dotted")
                        .font(.system(size: 11)).foregroundStyle(installer.isCurrentSource ? .green : .secondary)
                }
                .padding(.horizontal, 36).padding(.top, 30)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 26) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(String(format: "%02d / 04", installer.currentStep + 1))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .tracking(2).foregroundStyle(accent)
                            Text(titles[installer.currentStep]).font(.system(size: 30, weight: .semibold))
                            Text(subtitles[installer.currentStep]).font(.system(size: 14)).foregroundStyle(.secondary)
                        }
                        Group {
                            switch installer.currentStep {
                            case 0: welcome
                            case 1: installation
                            case 2: activation
                            default: playground
                            }
                        }
                    }
                    .padding(36).padding(.top, 6)
                    .id(installer.currentStep)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: reduceMotion ? 0 : 12)), removal: .opacity))
                }
                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                LinearGradient(colors: [Color(nsColor: .windowBackgroundColor), accent.opacity(colorScheme == .dark ? 0.035 : 0.025)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .frame(width: 900, height: 650)
        .tint(accent)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: installer.currentStep)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: installer.installPhase)
        .onReceive(timer) { _ in if !installer.isInstalling { installer.checkStatus() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in installer.checkStatus() }
        .onChange(of: installer.isSourceAdded) { _, added in if !added { confirmedTyping = false } }
    }

    private var appIcon: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)).resizable().scaledToFit()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                appIcon.frame(width: 48, height: 48)
                    .shadow(color: accent.opacity(0.12), radius: 10, y: 5)
                VStack(alignment: .leading, spacing: 5) {
                    Text("AetherKey").font(.system(size: 17, weight: .semibold))
                    Text("让表达，轻一点").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8).padding(.bottom, 42)
            ForEach(0..<4) { step in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(step == installer.currentStep
                                  ? AnyShapeStyle(LinearGradient(colors: [sky, accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                                  : AnyShapeStyle(Color.primary.opacity(0.035)))
                        Image(systemName: step < installer.currentStep ? "checkmark" : symbols[step])
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(step == installer.currentStep ? .white : step < installer.currentStep ? accent : .secondary)
                    }.frame(width: 33, height: 33)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(step == installer.currentStep ? 0.3 : 0), lineWidth: 0.7))
                        .shadow(color: accent.opacity(step == installer.currentStep ? 0.18 : 0), radius: 6, y: 3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(titles[step]).font(.system(size: 12, weight: step == installer.currentStep ? .semibold : .regular))
                        Text(["欢迎使用", "安装到当前账户", "连接 macOS", "试试中文输入"][step])
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(11)
                .background(RoundedRectangle(cornerRadius: 15).fill(accent.opacity(step == installer.currentStep ? (colorScheme == .dark ? 0.11 : 0.065) : 0)))
                .opacity(step > installer.currentStep ? 0.6 : 1)
                .padding(.bottom, 9)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Label("仅安装到你的账户", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Text("macOS 14+  ·  Apple Silicon").font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 11)
        }
        .padding(.horizontal, 18).padding(.top, 44).padding(.bottom, 28)
        .frame(width: 238, alignment: .leading)
        .background {
            LinearGradient(colors: [sky.opacity(colorScheme == .dark ? 0.08 : 0.10), accent.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .background(.ultraThinMaterial)
        }
        .overlay(alignment: .trailing) { Rectangle().fill(accent.opacity(0.07)).frame(width: 1) }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 22) {
                ZStack {
                    Circle().fill(sky.opacity(0.10)).frame(width: 138, height: 138)
                    Circle().strokeBorder(sky.opacity(0.13), lineWidth: 1).frame(width: 166, height: 166)
                    appIcon.frame(width: 112, height: 112)
                        .shadow(color: accent.opacity(colorScheme == .dark ? 0.25 : 0.16), radius: 18, y: 12)
                }.frame(width: 168, height: 178)
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("落键，成句。").font(.system(size: 29, weight: .medium))
                        Text("每一次表达，都自然发生。")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 13) {
                        Text("ni hao").foregroundStyle(.secondary)
                        Rectangle().fill(accent.opacity(0.15)).frame(width: 1, height: 14)
                        Text("1  你好").foregroundStyle(accent).fontWeight(.medium)
                    }.font(.system(size: 12)).padding(.horizontal, 15).padding(.vertical, 10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(colorScheme == .dark ? 0.07 : 0.8)))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(LinearGradient(colors: [sky.opacity(0.11), accent.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(sky.opacity(0.12)))
            Text("把安装交给向导，把注意力留给表达。\n只需几步，即可在你的 Mac 上开始使用 AetherKey。")
                .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(6)
            HStack(spacing: 0) {
                welcomeFeature("cursorarrow.click", "双击即开始", "无需手动拖拽")
                welcomeFeature("lock.shield", "轻松安装", "无需管理员密码")
                welcomeFeature("arrow.clockwise", "安心更新", "保留词库与偏好")
            }
        }
    }

    private func welcomeFeature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 15, weight: .regular)).foregroundStyle(accent.opacity(0.8)).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 11, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var installation: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("点击下方按钮，向导会安装输入法并完成系统注册。原有词库与偏好设置会保留。")
                .font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(5)
            VStack(spacing: 0) {
                installRow(0, "准备安装组件", "安装包已包含所需文件，无需额外下载", "shippingbox")
                Divider().padding(.leading, 60)
                installRow(1, "安装到你的账户", "更新时保留词库与偏好", "externaldrive")
                Divider().padding(.leading, 60)
                installRow(2, "连接 macOS", "注册并启动 AetherKey 输入法", "keyboard")
            }.padding(8).background(.background, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.06)))
            if installer.isInstalling {
                ProgressView(value: Double(installer.installPhase), total: 3).accessibilityLabel("安装进度")
                Text("正在安装，请稍候…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let error = installer.errorMessage { notice(error, symbol: "exclamationmark.circle", color: .orange) }
            Label("安装只影响当前用户，无需输入管理员密码。", systemImage: "info.circle")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func installRow(_ phase: Int, _ title: String, _ detail: String, _ symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: installer.installPhase > phase ? "checkmark.circle.fill" : symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(installer.installPhase > phase ? .green : accent)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if installer.isInstalling && installer.installPhase == phase { ProgressView().controlSize(.small) }
        }.padding(16)
    }

    private var activation: some View {
        VStack(alignment: .leading, spacing: 19) {
            Text("在系统键盘设置中添加 AetherKey，然后回到这里切换。向导会自动检测每一步的完成状态。")
                .font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(5)
            HStack(spacing: 12) {
                statusCard(installer.isSourceAdded ? "已加入输入法" : "等待添加输入法", done: installer.isSourceAdded, symbol: "keyboard")
                statusCard(installer.isCurrentSource ? "已切换到 AetherKey" : "等待切换输入法", done: installer.isCurrentSource, symbol: "checkmark.bubble")
            }
            Button {
                if installer.isSourceAdded { installer.autoEnableInputSource() }
                else { installer.openKeyboardSettings() }
            } label: {
                Label(installer.isCurrentSource ? "重新切换到 AetherKey" : installer.isSourceAdded ? "切换到 AetherKey" : "打开键盘设置，添加 AetherKey", systemImage: installer.isSourceAdded ? "keyboard" : "gearshape")
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
            }.buttonStyle(.bordered).controlSize(.large)
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("在系统设置中完成这三步").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button("打开键盘设置 ↗") { installer.openKeyboardSettings() }.buttonStyle(.link).font(.system(size: 12))
                }
                instruction("1", "在「文字输入」中点击「编辑…」，再点击「＋」。")
                instruction("2", "搜索 AetherKey，或在「简体中文」中找到它并添加。")
                instruction("3", "在菜单栏选择 AetherKey，再回到这里继续。")
            }.padding(18).background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 16))
            if let hint = installer.activationHint { notice(hint, symbol: "info.circle", color: .secondary) }
        }
    }

    private func statusCard(_ title: String, done: Bool, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : symbol).foregroundStyle(done ? .green : .secondary)
            Text(title).font(.system(size: 12, weight: .medium))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }

    private func instruction(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(number).font(.system(size: 10, weight: .semibold, design: .monospaced))
                .frame(width: 18, height: 18).background(Color.primary.opacity(0.06), in: Circle())
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var playground: some View {
        VStack(alignment: .leading, spacing: 23) {
            Text("试着输入 nihao，再按空格选词。看到「你好」后，确认输入正常，就可以开始使用了。")
                .font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(5)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("试写区", systemImage: "pencil.line").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Text(installer.isCurrentSource ? "AetherKey 已选中" : "请先切换到 AetherKey")
                        .font(.system(size: 10)).foregroundStyle(installer.isCurrentSource ? .green : .orange)
                }
                TextField("你好，世界", text: $testText, axis: .vertical)
                    .font(.system(size: 26)).textFieldStyle(.plain)
                    .lineLimit(2...3).focused($typingFocused).accessibilityLabel("输入法试写区")
                    .onChange(of: testText) { _, _ in confirmedTyping = false }
                Divider()
                Toggle("我已用 AetherKey 输入中文，输入正常", isOn: $confirmedTyping)
                    .toggleStyle(.checkbox).font(.system(size: 12))
                    .disabled(!installer.isSourceAdded || !testText.contains(where: { $0.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) } }))
            }.padding(23).background(.background, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(accent.opacity(typingFocused ? 0.4 : 0.1)))
            HStack(spacing: 24) {
                shortcut("⇧ Shift", "中英文切换")
                shortcut("⌃ 空格", "切换输入法")
                shortcut("⌥ Tab", "切换候选布局")
            }
            if confirmedTyping {
                notice("设置完成。现在，去写下你的下一个想法吧。", symbol: "checkmark.circle.fill", color: .green)
            } else {
                Text("仍然是英文？轻按 Shift 切回中文，再试一次。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private func shortcut(_ keys: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(keys).font(.system(size: 12, weight: .medium)).padding(.horizontal, 9).padding(.vertical, 6)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func notice(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 12)).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true).lineSpacing(4)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if installer.currentStep > 0 {
                Button("上一步") { installer.currentStep -= 1 }
                    .buttonStyle(.plain).foregroundStyle(.secondary).disabled(installer.isInstalling)
            } else {
                Text("大约一分钟，开始新的输入体验").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if installer.currentStep == 1 && installer.isInstalled && !installer.isInstalling {
                Button("继续已有设置") { installer.currentStep = 2 }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            if installer.currentStep == 3 {
                Button("稍后试用") { NSApplication.shared.terminate(nil) }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Button(action: advance) {
                HStack(spacing: 10) {
                    Text(primaryTitle)
                    if !installer.isInstalling { Image(systemName: installer.currentStep == 3 ? "checkmark" : "arrow.right") }
                }.font(.system(size: 13, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(installer.isInstalling || (installer.currentStep == 2 && (!installer.isInstalled || !installer.isSourceAdded || !installer.isCurrentSource)) || (installer.currentStep == 3 && (!installer.isSourceAdded || !confirmedTyping)))
            .keyboardShortcut(.defaultAction)
        }.padding(.horizontal, 36).padding(.vertical, 22)
            .background(.bar).overlay(alignment: .top) { Divider() }
    }

    private var primaryTitle: String {
        switch installer.currentStep {
        case 0: "开始设置"
        case 1: installer.isInstalling ? "正在安装…" : installer.errorMessage != nil ? "重试安装" : installer.isInstalled ? "安装 / 更新" : "安装 AetherKey"
        case 2: "开始试用"
        default: "完成设置"
        }
    }

    private func advance() {
        switch installer.currentStep {
        case 0: installer.currentStep = 1
        case 1: installer.install()
        case 2: installer.currentStep = 3; typingFocused = true
        default: NSApplication.shared.terminate(nil)
        }
    }
}
