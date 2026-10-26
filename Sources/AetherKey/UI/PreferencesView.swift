import SwiftUI
import AppKit

/// Native Liquid Glass Preferences & User Lexicon Management Window for AetherKey 1.0.
@MainActor
public final class PreferencesWindowController {
    public static let shared = PreferencesWindowController()
    
    private var window: NSWindow?
    
    private init() {}
    
    public func showWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 680),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "AetherKey 设置"
        win.center()
        win.isReleasedWhenClosed = false
        win.contentView = NSHostingView(rootView: PreferencesView())
        win.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.window = win
    }
}

public struct PreferencesView: View {
    @ObservedObject private var settings = AetherSettings.shared
    @State private var selectedTab: Int = 0
    @State private var customPinyin: String = ""
    @State private var customPhrase: String = ""
    @State private var customList: [(pinyin: String, phrase: String)] = []
    @State private var learnedCount: Int = 0
    @State private var totalChars: Int = 0
    @State private var statusBanner: String = ""
    
    public init() {}
    
    private let pages = [("通用设置", "slider.horizontal.3", "按你的习惯，自然输入。"),
                         ("词库与短语", "character.book.closed", "让常用的表达，随手可得。"),
                         ("更新与启动", "arrow.triangle.2.circlepath", "保持最新，随时就绪。"),
                         ("快捷键与关于", "keyboard", "少一点操作，多一点流畅。")]

    public var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    Image(systemName: "a.square.fill")
                        .font(.system(size: 30)).foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AetherKey").font(.system(size: 18, weight: .semibold))
                        Text("输入，自然一点").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 10).padding(.top, 12)
                VStack(spacing: 5) {
                    ForEach(pages.indices, id: \.self) { index in
                        Button {
                            selectedTab = index
                            statusBanner = ""
                            refreshStats()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: pages[index].1).frame(width: 20)
                                Text(pages[index].0).font(.system(size: 13, weight: selectedTab == index ? .semibold : .medium))
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(selectedTab == index ? Color.white : Color.primary.opacity(0.75))
                            .padding(.horizontal, 12).padding(.vertical, 11)
                            .background(selectedTab == index ? Color.accentColor : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 9))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                Spacer()
                Text("版本 \(UpdateController.version)")
                    .font(.system(size: 11)).foregroundStyle(.tertiary).padding(10)
            }
            .padding(14).frame(width: 210)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(pages[selectedTab].0).font(.system(size: 24, weight: .bold))
                        Text(pages[selectedTab].2).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selectedTab == 0 {
                        Button("恢复默认") {
                            settings.resetToDefaults()
                            statusBanner = "已恢复默认设置"
                        }.controlSize(.small)
                    }
                }.padding(.horizontal, 28).padding(.vertical, 24)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 16) {
                        if !statusBanner.isEmpty {
                            Label(statusBanner, systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12)).foregroundStyle(.green)
                        }
                        if selectedTab == 0 { generalSettingsCard }
                        else if selectedTab == 1 { lexiconSettingsCard }
                        else if selectedTab == 2 { UpdateSettingsView() }
                        else { shortcutsCard }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28).padding(.bottom, 28).padding(.top, 2)
                }.id(selectedTab)
            }.background(Color(nsColor: .underPageBackgroundColor))
        }
        .frame(minWidth: 880, minHeight: 640)
        .onAppear { refreshStats() }
    }

    // MARK: - Tab 0: General & Typography
    private var generalSettingsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsGroup("拼音与候选", icon: "character.cursor.ibeam") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("拼音方案").font(.system(size: 13, weight: .medium))
                    Picker("拼音方案", selection: $settings.pinyinScheme) {
                        ForEach(PinyinScheme.allCases) { scheme in Text(scheme.title).tag(scheme) }
                    }.pickerStyle(.segmented).labelsHidden()
                    Text(settings.pinyinScheme == .full ? "逐字母输入拼音，也支持简拼与整句输入。" : "每个音节两键，保留整句输入和拼音中间编辑。微软双拼使用分号输入 ing。")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                HStack(spacing: 16) {
                    Text("候选面板").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Picker("候选面板", selection: $settings.defaultViewMode) {
                        Text("单行 · 7 个候选").tag(CandidateViewMode.paging)
                        Text("双行 · 14 个候选").tag(CandidateViewMode.scroll)
                    }.labelsHidden().frame(width: 180)
                }
                Text("输入时按 ⌥ Tab，也可随时切换面板布局。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Divider()
                settingToggleRow(title: "四方向键选词", desc: "← / ↑ 选上一个，→ / ↓ 选下一个。⌥ ← / → 仍可编辑拼音。", isOn: $settings.isFourArrowSelectionEnabled)
            }
            settingsGroup("标点与排版", icon: "textformat") {
                settingToggleRow(title: "中英文之间自动空格", desc: "在中文与英文字母、数字之间留出半角空格。", isOn: $settings.isPanguSpacingEnabled)
                Divider()
                settingToggleRow(title: "智能标点与引号配对", desc: "自动配对中文引号；保留小数与时间中的英文标点。", isOn: $settings.isSmartPunctuationEnabled)
                Divider()
                settingToggleRow(title: "中文使用英文标点", desc: "保持中文输入，使用英文标点。按 ⌃ . 随时切换。", isOn: $settings.isEnglishPunctuationEnabled)
            }
            settingsGroup("输入习惯", icon: "wand.and.stars") {
                settingToggleRow(title: "模糊音纠错", desc: "兼容 z / zh 等平翘舌、an / ang 等前后鼻音。", isOn: $settings.isFuzzyPinyinEnabled)
                Divider()
                settingToggleRow(title: "终端与代码编辑器默认英文", desc: "进入 Terminal、iTerm2、VS Code 等应用时使用英文模式。", isOn: $settings.isAutoEnglishInTerminalEnabled)
            }
        }
    }

    private func settingsGroup<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary).padding(.leading, 3)
            PreferencesCard { VStack(alignment: .leading, spacing: 14, content: content).padding(18) }
        }
    }

    private func settingToggleRow(title: String, desc: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(desc).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
                .fixedSize().accessibilityLabel(title)
        }
    }

    // MARK: - Tab 1: Lexicon & Custom Phrases
    private var lexiconSettingsCard: some View {
        VStack(spacing: 16) {
            PreferencesCard() {
                VStack(alignment: .leading, spacing: 14) {
                    Label("你的词库", systemImage: "brain.head.profile")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 16) {
                        statBox(value: "533,828", label: "内置高频词条")
                        statBox(value: "415", label: "标准普通话音节")
                        statBox(value: "\(learnedCount)", label: "用户习得词条")
                        statBox(value: "\(totalChars)", label: "累计上屏字数")
                    }
                    
                    settingToggleRow(
                        title: "记住我的选词习惯",
                        desc: "根据你的选词调整排序，让常用词更靠前。",
                        isOn: $settings.isUserLearningEnabled
                    )
                    
                    HStack {
                        Button("清空自学习词频记录") {
                            UserLexicon.shared.clearLearnedFrequencies()
                            refreshStats()
                            statusBanner = "已清空自学习词频"
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        if !statusBanner.isEmpty {
                            Text(statusBanner)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Color.green)
                        }
                    }
                }
                .padding(20)
            }
            
            PreferencesCard() {
                VStack(alignment: .leading, spacing: 12) {
                    Label("自定义短语", systemImage: "plus.bubble.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 10) {
                        TextField("拼音，如 gongsi", text: $customPinyin)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 155)
                        
                        TextField("短语内容，如公司全称", text: $customPhrase)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("添加短语") {
                            guard !customPinyin.isEmpty, !customPhrase.isEmpty else { return }
                            UserLexicon.shared.addCustomPhrase(pinyin: customPinyin, phrase: customPhrase)
                            customPinyin = ""
                            customPhrase = ""
                            refreshStats()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(customPinyin.trimmingCharacters(in: .whitespaces).isEmpty || customPhrase.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    
                    if customList.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "text.badge.plus").font(.system(size: 26)).foregroundStyle(.tertiary)
                            Text("把常用的长句，变成几个字母") .font(.system(size: 13, weight: .medium))
                            Text("例如用 gongsi 输入公司全称；短语仅保存在本机。")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 24)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(customList.enumerated()), id: \.offset) { _, item in
                                HStack {
                                    Text(item.pinyin)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 120, alignment: .leading)
                                    Text(item.phrase)
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Button("删除") {
                                        UserLexicon.shared.removeCustomPhrase(pinyin: item.pinyin, phrase: item.phrase)
                                        refreshStats()
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.red.opacity(0.8))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.primary.opacity(0.035))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
    }
    
    private func statBox(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.accentColor)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Tab 2: Shortcuts & About
    private var shortcutsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsGroup("切换与输入", icon: "keyboard") {
                shortcutRow(key: "Shift", desc: "切换中文 / 英文模式")
                Divider()
                shortcutRow(key: "⌃ .", desc: "切换中文 / 英文标点，保留正在输入的拼音")
                Divider()
                shortcutRow(key: "Shift + 字母", desc: "中文模式下输入大写英文字母")
                Divider()
                shortcutRow(key: "Space / Return", desc: "空格确认候选；回车提交原始拼音")
            }
            settingsGroup("候选与编辑", icon: "text.cursor") {
                shortcutRow(key: "⌥ Tab", desc: "切换单行 / 双行候选面板")
                Divider()
                shortcutRow(key: "数字 / 鼠标点击", desc: "选择当前页对应序号的候选词")
                Divider()
                shortcutRow(key: "- / = · [ / ]", desc: "上一页 / 下一页，也支持 PgUp / PgDn")
                Divider()
                shortcutRow(key: settings.isFourArrowSelectionEnabled ? "Tab · ↑ ↓ ← →" : "Tab · ↑ ↓", desc: "移动候选高亮，空格确认")
                Divider()
                shortcutRow(key: settings.isFourArrowSelectionEnabled ? "⌥ ← / →" : "← / →", desc: settings.isFourArrowSelectionEnabled ? "按音节移动拼音光标；Home / End 到首尾" : "编辑拼音中间字母；⌥ ← / → 按音节移动")
                Divider()
                shortcutRow(key: "⌥ Delete", desc: "删除光标前的一个音节")
            }
            settingsGroup("词库与工具", icon: "wand.and.stars") {
                shortcutRow(key: "候选词右键", desc: "置顶、取消置顶或忘记候选词")
                Divider()
                shortcutRow(key: "⌃⌥ P / U / Delete", desc: "置顶 / 取消置顶 / 忘记当前高亮候选")
                Divider()
                shortcutRow(key: "v + 内容", desc: "算式、金额大写或日期时间，如 v1+2、v128.5、vdate")
            }
            PreferencesCard {
                HStack(spacing: 12) {
                    Image(systemName: "a.square.fill").font(.system(size: 32)).foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("AetherKey").font(.system(size: 15, weight: .semibold))
                        Text("原生拼音 · 本地词库").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(UpdateController.version).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                }.padding(18)
            }
        }
    }

    private func shortcutRow(key: String, desc: String) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 158, alignment: .leading)
            
            Text(desc)
                .font(.system(size: 12.5))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }.padding(.vertical, 2)
    }
    
    private func refreshStats() {
        customList = UserLexicon.shared.allCustomPhrases()
        learnedCount = UserLexicon.shared.learnedEntryCount
        totalChars = UserLexicon.shared.totalCommittedCharacters
    }
}

/// A quiet, opaque surface for settings; candidate panel materials stay independent.
struct PreferencesCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.065), lineWidth: 1))
    }
}
