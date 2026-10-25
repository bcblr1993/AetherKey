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
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
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
    
    public var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.07)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerBar
                
                // Tab Selector
                HStack(spacing: 10) {
                    tabButton(index: 0, title: "通用设置", icon: "slider.horizontal.3")
                    tabButton(index: 1, title: "词库与短语", icon: "character.book.closed.fill")
                    tabButton(index: 2, title: "更新与启动", icon: "arrow.triangle.2.circlepath")
                    tabButton(index: 3, title: "快捷键与关于", icon: "keyboard.fill")
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.02))
                
                // Content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        if selectedTab == 0 {
                            generalSettingsCard
                        } else if selectedTab == 1 {
                            lexiconSettingsCard
                        } else if selectedTab == 2 {
                            UpdateSettingsView()
                        } else {
                            shortcutsCard
                        }
                    }
                    .padding(24)
                }
            }
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 660, minHeight: 540)
        .onAppear {
            refreshStats()
        }
    }
    
    private var headerBar: some View {
        HStack(spacing: 12) {
            Text("⟡")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.accentColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("AetherKey 设置")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                Text("让输入更自然，让表达更流畅")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            
            Spacer()
            
            Button("恢复默认设置") {
                settings.resetToDefaults()
                statusBanner = "已恢复默认设置"
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(Color.white.opacity(0.08)), alignment: .bottom)
    }
    
    private func tabButton(index: Int, title: String, icon: String) -> some View {
        let isSelected = (selectedTab == index)
        return Button {
            selectedTab = index
            refreshStats()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .bold : .medium))
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.white.opacity(0.65))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.white.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Tab 0: General & Typography
    private var generalSettingsCard: some View {
        LiquidGlassContainer(cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("拼音方案").font(.system(size: 13, weight: .semibold))
                    Picker("拼音方案", selection: $settings.pinyinScheme) {
                        ForEach(PinyinScheme.allCases) { scheme in Text(scheme.title).tag(scheme) }
                    }
                    .pickerStyle(.segmented)
                    Text(settings.pinyinScheme == .full ? "默认全拼；也可从输入法菜单切换双拼。" : "每个音节两键；支持整句、拼音中间编辑和候选词管理。微软双拼用分号输入 ing；计算器仍可输入 v 加数字。")
                        .font(.system(size: 11.5)).foregroundStyle(Color.white.opacity(0.5))
                }
                Divider()
                Label("输入与排版", systemImage: "sparkles")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("默认候选框展开模式")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white)
                        Text("打字时也可随时按下 Option + Tab 在「翻页」与「卷轴」间瞬时切换")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                    Spacer()
                    Picker("", selection: $settings.defaultViewMode) {
                        Text("翻页模式 (7词/单行)").tag(CandidateViewMode.paging)
                        Text("卷轴模式 (14词/双行)").tag(CandidateViewMode.scroll)
                    }
                    .frame(width: 200)
                }
                
                Divider().background(Color.white.opacity(0.1))
                
                settingToggleRow(
                    title: "盘古之白自动空格 (Pangu Spacing)",
                    desc: "在中文与英文字母、数字交界处自动插入半角空格，保持极客排版美感。",
                    isOn: $settings.isPanguSpacingEnabled
                )
                
                settingToggleRow(
                    title: "智能中文标点与引号配对 (Smart Punctuation)",
                    desc: "自动配对全角引号 “” 与 ‘’、破折号 ——，并在数字后智能保留半角小数点 (3.14) 与时间冒号 (12:30)。",
                    isOn: $settings.isSmartPunctuationEnabled
                )
                
                settingToggleRow(
                    title: "中文使用英文标点",
                    desc: "默认关闭。开启后保持中文输入，使用 , . ? ! 等英文标点；Ctrl + . 随时切换，不会提交正在编辑的拼音。",
                    isOn: $settings.isEnglishPunctuationEnabled
                )

                settingToggleRow(
                    title: "模糊音智能纠错 (Fuzzy Pinyin)",
                    desc: "自动兼容平翘舌 (z/zh, c/ch, s/sh) 与前后鼻音 (an/ang, en/eng, in/ing) 混输。",
                    isOn: $settings.isFuzzyPinyinEnabled
                )
                
                settingToggleRow(
                    title: "终端与代码编辑器自动切换英文模式",
                    desc: "切入 Terminal、iTerm2、Ghostty、Kitty、VSCode 时自动默认英文直通，避免命令误触发候选框。",
                    isOn: $settings.isAutoEnglishInTerminalEnabled
                )
            }
            .padding(20)
        }
    }
    
    private func settingToggleRow(title: String, desc: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                Text(desc)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
        }
    }
    
    // MARK: - Tab 1: Lexicon & Custom Phrases
    private var lexiconSettingsCard: some View {
        VStack(spacing: 16) {
            LiquidGlassContainer(cornerRadius: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    Label("海量词库与自学习词频", systemImage: "brain.head.profile")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                    
                    HStack(spacing: 16) {
                        statBox(value: "533,828", label: "内置高频词条")
                        statBox(value: "415", label: "标准普通话音节")
                        statBox(value: "\(learnedCount)", label: "用户习得词条")
                        statBox(value: "\(totalChars)", label: "累计上屏字数")
                    }
                    
                    settingToggleRow(
                        title: "动态词频自学习 (Dynamic Word Learning)",
                        desc: "自动记忆您的选词偏好与长句组词习惯，高频用词下次键入自动置顶。",
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
            
            LiquidGlassContainer(cornerRadius: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("自定义短语与专属词库", systemImage: "plus.bubble.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.white)
                    
                    HStack(spacing: 10) {
                        TextField("拼音或简拼 (如: dz 或 gongsi)", text: $customPinyin)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                        
                        TextField("要输出的短语 (如: 北京市海淀区...)", text: $customPhrase)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("添加短语") {
                            guard !customPinyin.isEmpty, !customPhrase.isEmpty else { return }
                            UserLexicon.shared.addCustomPhrase(pinyin: customPinyin, phrase: customPhrase)
                            customPinyin = ""
                            customPhrase = ""
                            refreshStats()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.0, green: 0.65, blue: 0.95))
                    }
                    
                    if !customList.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(customList.enumerated()), id: \.offset) { _, item in
                                HStack {
                                    Text(item.pinyin)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 120, alignment: .leading)
                                    Text(item.phrase)
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(Color.white)
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
                                .background(Color.white.opacity(0.04))
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
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Tab 2: Shortcuts & About
    private var shortcutsCard: some View {
        LiquidGlassContainer(cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 14) {
                Label("快捷键指南与版本信息", systemImage: "command")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
                
                shortcutRow(key: "单击 Shift", desc: "在中 / 英输入模式间瞬间无缝切换")
                shortcutRow(key: "Ctrl + . (⌃.)", desc: "切换中文 / 英文标点，保留当前拼音和候选")
                shortcutRow(key: "Shift + 字母", desc: "中文模式下直接输入大写英文字母")
                shortcutRow(key: "Option + Tab (⌥Tab)", desc: "在「翻页模式 (7词)」与「卷轴模式 (14词)」间切换")
                shortcutRow(key: "空格键 (Space)", desc: "首选词或高亮词极速上屏")
                shortcutRow(key: "回车键 (Return)", desc: "将当前输入的拼音字母原样英文上屏")
                shortcutRow(key: "数字键 1 - 9 / 鼠标点击", desc: "直接选择当前页对应序号的候选词（支持长句分步选词）")
                shortcutRow(key: "- / = 或 [ / ] 或 PgUp/PgDn", desc: "候选词上一页 / 下一页翻页")
                shortcutRow(key: "Tab / 方向键 ↑↓", desc: "在候选词列表中移动高亮焦点")
                shortcutRow(key: "← / → · Home / End", desc: "移动拼音光标，修改中间字母；Option + ← / → 按音节移动")
                shortcutRow(key: "Option + Delete", desc: "删除光标前的一个音节；向前删除键删除光标后的字母")
                shortcutRow(key: "候选词右键菜单", desc: "置顶、取消置顶或忘记当前拼音下的候选词")
                shortcutRow(key: "⌃⌥P / ⌃⌥U / ⌃⌥Delete", desc: "置顶 / 取消置顶 / 忘记当前高亮候选词")
                shortcutRow(key: "v + 算式 / 金额 / date / time", desc: "触发 V 模式：实时四则运算 (v1+2*3)、人民币大写 (v128.5)、日期时间宏 (vdate)")
                
                Divider().background(Color.white.opacity(0.1))
                
                HStack {
                    Text("AetherKey \(UpdateController.version)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.75))
                    Spacer()
                    Text("Bundle ID: com.aethernative.inputmethod.AetherKey")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }
            .padding(20)
        }
    }
    
    private func shortcutRow(key: String, desc: String) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .frame(width: 210, alignment: .leading)
            
            Text(desc)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.8))
            Spacer()
        }
    }
    
    private func refreshStats() {
        customList = UserLexicon.shared.allCustomPhrases()
        learnedCount = UserLexicon.shared.learnedEntryCount
        totalChars = UserLexicon.shared.totalCommittedCharacters
    }
}
