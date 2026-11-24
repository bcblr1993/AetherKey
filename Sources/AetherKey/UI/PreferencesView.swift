import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
    private struct CustomPhraseItem: Identifiable, Hashable {
        let pinyin: String
        let phrase: String
        var id: String { "\(pinyin)\u{0}\(phrase)" }
    }

    private struct LexiconWordItem: Identifiable, Hashable {
        let pinyin: String
        let word: String
        var id: String { "\(pinyin)\u{0}\(word)" }
    }

    @ObservedObject private var settings = AetherSettings.shared
    @ObservedObject private var snippetStore = QuickSnippetStore.shared
    @ObservedObject private var clipboardStore = ClipboardHistoryStore.shared
    @ObservedObject private var syncManager = LexiconSyncManager.shared
    @State private var selectedTab: Int = 0
    @State private var customPinyin: String = ""
    @State private var customPhrase: String = ""
    @State private var phraseSearchText: String = ""
    @State private var editingSnippetID: UUID? = nil
    @State private var snippetTitle: String = ""
    @State private var snippetShortcut: String = ""
    @State private var snippetContent: String = ""
    @State private var customList: [CustomPhraseItem] = []
    @State private var pinnedList: [LexiconWordItem] = []
    @State private var forgottenList: [LexiconWordItem] = []
    @State private var learnedCount: Int = 0
    @State private var totalChars: Int = 0
    @State private var importMode: UserLexicon.ImportMode = .merge
    @State private var statusBanner: String = ""
    @State private var isStatusError: Bool = false
    
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
                            isStatusError = false
                            statusBanner = "已恢复默认设置"
                        }.controlSize(.small)
                    }
                }.padding(.horizontal, 28).padding(.vertical, 24)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 16) {
                        if !statusBanner.isEmpty {
                            Label(statusBanner, systemImage: isStatusError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(isStatusError ? .red : .green)
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
        .onChange(of: settings.pinyinScheme) { refreshStats() }
    }

    // MARK: - Tab 0: General & Typography
    private var generalSettingsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsGroup("输入方案", icon: "character.cursor.ibeam") {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(PinyinScheme.allCases) { scheme in
                            let selected = settings.pinyinScheme == scheme
                            Button {
                                settings.pinyinScheme = scheme
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(scheme.title)
                                        .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                                        .foregroundStyle(selected ? Color.accentColor : Color.primary)
                                    Text(schemeSubtitle(for: scheme))
                                        .font(.system(size: 10))
                                        .foregroundStyle(selected ? Color.accentColor.opacity(0.85) : Color.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(selected ? Color.accentColor.opacity(0.11) : Color.primary.opacity(0.035))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(selected ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.06), lineWidth: 1)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text(schemeDescription(for: settings.pinyinScheme))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if settings.pinyinScheme.isDoublePinyin {
                        doublePinyinKeymapView(for: settings.pinyinScheme)
                    }
                }
            }

            settingsGroup("候选面板", icon: "rectangle.grid.1x2") {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("面板方向").font(.system(size: 13, weight: .medium))
                        Text("切换候选栏为横向排列或纵向列表。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("面板方向", selection: $settings.candidateLayoutOrientation) {
                        ForEach(CandidateLayoutOrientation.allCases) { orientation in
                            Text(orientation.title).tag(orientation)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 150)
                }
                Divider()
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("候选面板").font(.system(size: 13, weight: .medium))
                        Text(settings.candidateLayoutOrientation == .vertical
                             ? "竖排模式下每页直接展示所选候选个数；横排模式下按 ⌥ Tab 切换单行/双行。"
                             : "输入时按 ⌥ Tab，也可随时切换单行/双行面板布局。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Picker("候选面板", selection: $settings.defaultViewMode) {
                        Text("单行 · \(settings.candidatePageSize) 个候选").tag(CandidateViewMode.paging)
                        Text("双行 · \(settings.candidatePageSize * 2) 个候选").tag(CandidateViewMode.scroll)
                    }.labelsHidden().frame(width: 180)
                }
                Divider()
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("每页候选数").font(.system(size: 13, weight: .medium))
                        Text(settings.candidateLayoutOrientation == .vertical
                             ? "竖排模式下每页直接展示 \(settings.candidatePageSize) 个候选词。"
                             : "单行每页展示 \(settings.candidatePageSize) 个，双行展开时展示 \(settings.candidatePageSize * 2) 个。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Stepper(value: $settings.candidatePageSize, in: 5...9) {
                        Text("\(settings.candidatePageSize) 个")
                            .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                            .frame(minWidth: 34, alignment: .trailing)
                    }
                }
                Divider()
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("候选字号").font(.system(size: 13, weight: .medium))
                        Text("调节候选词文字大小，行高与面板宽度自动适配。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach([14, 15, 16, 17, 18, 19], id: \.self) { size in
                            let selected = Int(settings.candidateFontSize.rounded()) == size
                            Button {
                                settings.candidateFontSize = CGFloat(size)
                            } label: {
                                Text("\(size)")
                                    .font(.system(size: 11.5, weight: selected ? .semibold : .regular, design: .monospaced))
                                    .foregroundStyle(selected ? Color.white : Color.primary)
                                    .frame(width: 28, height: 24)
                                    .background(
                                        selected ? Color.accentColor : Color.primary.opacity(0.055),
                                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("候选字号 \(size) pt")
                        }
                        Text("pt")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 2)
                    }
                }
                Divider()
                settingToggleRow(title: "四方向键选词", desc: "← / ↑ 选上一个，→ / ↓ 选下一个。⌥ ← / → 仍可编辑输入编码。", isOn: $settings.isFourArrowSelectionEnabled)
                Divider()
                settingToggleRow(
                    title: "在菜单栏常驻 AetherKey 快捷图标",
                    desc: "默认在系统输入法启用后隐藏独立图标避免重复；开启后即使切换到其他输入法，也能从菜单栏直接打开设置或切回 AetherKey。",
                    isOn: $settings.isAlwaysShowMenuBarIconEnabled
                )
            }

            settingsGroup("排序与中英混输", icon: "sparkles") {
                settingToggleRow(
                    title: "中英混输与高频英文词",
                    desc: "支持在中文模式下直接输入 MacBook、API、B站、ChatGPT 等中英混输与英文高频词汇。",
                    isOn: $settings.isEnglishMixEnabled
                )
                Divider()
                settingPickerRow(
                    title: "Emoji 候选策略",
                    desc: "控制输入中文词语时是否在候选栏中联想到对应 Emoji。",
                    selection: $settings.emojiSuggestionStyle,
                    options: EmojiSuggestionStyle.allCases,
                    labelFor: \.title,
                    width: 195
                )
            }

            settingsGroup("简繁与标点", icon: "textformat") {
                settingToggleRow(title: "输出繁体中文", desc: "将中文候选与输出转为繁体中文，并与简体共享词频和置顶。输入或空缓冲时按 ⌃⇧F 随时切换。", isOn: $settings.isTraditionalChineseEnabled)
                Divider()
                settingToggleRow(title: "中英文之间自动空格", desc: "在中文与英文字母、数字之间留出半角空格。", isOn: $settings.isPanguSpacingEnabled)
                Divider()
                settingToggleRow(title: "智能标点与引号配对", desc: "自动配对中文引号；保留小数、网址、邮箱与时间中的英文标点。", isOn: $settings.isSmartPunctuationEnabled)
                Divider()
                settingToggleRow(title: "成对标点自动补全与光标置中", desc: "输入（）、【】、「」、《》、“” 时自动补全右半并将光标移至中间；紧接退格可成对删除（需辅助功能按键权限）。", isOn: $settings.isAutoPairPunctuationEnabled)
                Divider()
                settingToggleRow(title: "中文使用英文标点", desc: "保持中文输入，使用英文标点。按 ⌃ . 随时切换。", isOn: $settings.isEnglishPunctuationEnabled)
            }

            settingsGroup("按键与切换习惯", icon: "switch.2") {
                settingPickerRow(
                    title: "Shift 切换范围",
                    desc: "设置左 Shift、右 Shift 或双侧 Shift 单击切换中英文。",
                    selection: $settings.shiftSwitchMode,
                    options: ShiftSwitchMode.allCases,
                    labelFor: \.title,
                    width: 185
                )
                Divider()
                settingPickerRow(
                    title: "Caps Lock 切换模式",
                    desc: "可保持系统大写锁定，或设为短按直接切换中英文模式。",
                    selection: $settings.capsLockSwitchMode,
                    options: CapsLockSwitchMode.allCases,
                    labelFor: \.title,
                    width: 195
                )
                Divider()
                settingPickerRow(
                    title: "切为英文时未上屏编码",
                    desc: "输入过程中按 Shift / Caps Lock 切至英文时如何处理候选栏中的编码。",
                    selection: $settings.switchToEnglishBufferAction,
                    options: SwitchToEnglishBufferAction.allCases,
                    labelFor: \.title,
                    width: 185
                )
                Divider()
                settingToggleRow(
                    title: "逗号/句号 (, / .) 翻页",
                    desc: "候选词显示时按逗号/句号快速翻页；关闭后直接作为标点上屏。",
                    isOn: $settings.isCommaPeriodPagingEnabled
                )
                Divider()
                settingPickerRow(
                    title: "[ / ] 键行为",
                    desc: "「以词定字」可将当前多字候选词的首字（[）或末字（]）直接上屏；单字候选仍用于翻页。",
                    selection: $settings.bracketKeyBehavior,
                    options: BracketKeyBehavior.allCases,
                    labelFor: \.title,
                    width: 175,
                    segmented: true
                )
                Divider()
                settingToggleRow(
                    title: "分号 (;) 快速选第 2 候选",
                    desc: "候选词大于等于 2 个时按分号直接上屏第 2 候选（微软/搜狗双拼在韵母位仍优先输入 ing）。",
                    isOn: $settings.isSemicolonSecondCandidateEnabled
                )
            }

            settingsGroup("输入习惯与模糊音", icon: "wand.and.stars") {
                settingToggleRow(title: "模糊音纠错", desc: settings.pinyinScheme == .wubi86 ? "用于拼音方案，五笔编码不启用模糊音纠错。" : "启用后可按下方规则自定义平翘舌、鼻边音与前后鼻音纠错。", isOn: $settings.isFuzzyPinyinEnabled)
                    .disabled(settings.pinyinScheme == .wubi86)

                if settings.isFuzzyPinyinEnabled && settings.pinyinScheme != .wubi86 {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("模糊音规则")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("恢复默认组合") {
                                settings.fuzzyPinyinRules = .defaultRules
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11))
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 8) {
                            ForEach(FuzzyPinyinRules.ruleMetadata, id: \.title) { item in
                                Toggle(isOn: fuzzyRuleBinding(item.rule)) {
                                    HStack(spacing: 6) {
                                        Text(item.title)
                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        Text(item.subtitle)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .toggleStyle(.checkbox)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            settingsGroup("按应用自动中英文", icon: "app.badge.checkmark") {
                settingToggleRow(title: "终端与代码编辑器默认英文", desc: "已内置 Terminal、iTerm2、VS Code、Cursor、Zed、Xcode 等常见工具；其他 IDE（如 IntelliJ IDEA）可在下方按需添加。", isOn: $settings.isAutoEnglishInTerminalEnabled)
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("自定义应用规则").font(.system(size: 13, weight: .medium))
                        Text("切入所选应用的新输入上下文时，自动设定默认中英文模式（优先级高于内置终端规则）。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("添加应用…") {
                        addAppDefaultModeRule()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                let sortedRules = settings.customAppDefaultModes.sorted { $0.key < $1.key }
                if sortedRules.isEmpty {
                    Text("暂未添加自定义应用规则。点击「添加应用…」选择 /Applications 中的 .app 即可配置。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 6) {
                        ForEach(sortedRules, id: \.key) { bundleId, mode in
                            appRuleRow(bundleId: bundleId, mode: mode)
                        }
                    }
                }
            }
        }
    }

    private func schemeSubtitle(for scheme: PinyinScheme) -> String {
        switch scheme {
        case .full: return "整句 · 简拼"
        case .flypy: return "两键双拼"
        case .microsoft: return "分号 ; 韵母"
        case .zrm: return "经典双拼"
        case .sogou: return "分号 ; 韵母"
        case .wubi86: return "四码顶字"
        }
    }

    private func schemeDescription(for scheme: PinyinScheme) -> String {
        switch scheme {
        case .full:
            return "逐字母输入拼音，支持简拼、声母缩写与整句智能选词。"
        case .flypy:
            return "小鹤双拼：每音节两键，保留整句输入和拼音中间编辑。zh / ch / sh 分别位于 V / I / U。"
        case .microsoft:
            return "微软双拼：每音节两键，保留整句输入和拼音中间编辑。使用分号 ; 输入韵母 ing。"
        case .zrm:
            return "自然码双拼：每音节两键，保留整句输入和拼音中间编辑。单字母零声母采用双写（如 aa / ee / oo）。"
        case .sogou:
            return "搜狗双拼：每音节两键，键位与微软双拼兼容，支持使用分号 ; 输入韵母 ing。"
        case .wubi86:
            return "五笔 86：最多四码，空格选词；满四码后继续输入顶字。z + 拼音反查编码，如 znihao。"
        }
    }

    private func doublePinyinKeymapView(for scheme: PinyinScheme) -> some View {
        let rows = DoublePinyin.keymapRows(for: scheme)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("双拼键位速查（\(scheme.title)）")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("蓝色标注为复合声母 zh / ch / sh")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    let leadingInset: CGFloat = rowIndex == 1 ? (row.count == 10 ? 10 : 18) : (rowIndex == 2 ? 42 : 0)
                    HStack(spacing: 4) {
                        ForEach(row, id: \.key) { mapping in
                            keycapView(mapping)
                        }
                    }
                    .padding(.leading, leadingInset)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }

    private func keycapView(_ mapping: DoublePinyin.KeyMapping) -> some View {
        let specialInitial: String? = {
            guard let initial = mapping.initial, ["zh", "ch", "sh"].contains(initial) else { return nil }
            return initial
        }()
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Text(mapping.key)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if let specialInitial {
                    Text(specialInitial)
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                }
            }
            if mapping.finals.isEmpty {
                Text(" ")
                    .font(.system(size: 8.5))
            } else {
                Text(mapping.finals.joined(separator: "\n"))
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .frame(width: 49, height: 42, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75))
    }

    private func fuzzyRuleBinding(_ rule: FuzzyPinyinRules) -> Binding<Bool> {
        Binding(
            get: { settings.fuzzyPinyinRules.contains(rule) },
            set: { enabled in
                var updated = settings.fuzzyPinyinRules
                if enabled {
                    updated.insert(rule)
                } else {
                    updated.remove(rule)
                }
                settings.fuzzyPinyinRules = updated
            }
        )
    }

    private func appRuleRow(bundleId: String, mode: AppDefaultInputMode) -> some View {
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        let appName = appURL.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleId
        let appIcon = appURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
        let modeBinding = Binding<AppDefaultInputMode>(
            get: { settings.appDefaultMode(for: bundleId) ?? mode },
            set: { settings.setAppDefaultMode($0, for: bundleId) }
        )
        return HStack(spacing: 10) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(appName)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                if appName != bundleId {
                    Text(bundleId)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Picker("默认模式", selection: modeBinding) {
                ForEach(AppDefaultInputMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 110)

            Button {
                settings.setAppDefaultMode(nil, for: bundleId)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.red.opacity(0.8))
            }
            .buttonStyle(.borderless)
            .help("删除此应用规则")
            .accessibilityLabel("删除 \(appName) 规则")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
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

    @ViewBuilder
    private func settingPickerRow<T: Hashable, Options: RandomAccessCollection>(
        title: String,
        desc: String,
        selection: Binding<T>,
        options: Options,
        labelFor: @escaping (Options.Element) -> String,
        width: CGFloat = 185,
        segmented: Bool = false
    ) -> some View where Options.Element: Identifiable, Options.Element == T {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(desc).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if segmented {
                Picker(title, selection: selection) {
                    ForEach(options) { item in
                        Text(labelFor(item)).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: width)
            } else {
                Picker(title, selection: selection) {
                    ForEach(options) { item in
                        Text(labelFor(item)).tag(item)
                    }
                }
                .labelsHidden()
                .frame(width: width)
            }
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
                        statBox(value: settings.pinyinScheme == .wubi86 ? WubiEngine.shared.entryCount.formatted() : PinyinLexicon.entryCount.formatted(), label: settings.pinyinScheme == .wubi86 ? "五笔字词编码" : "内置高频词条")
                        statBox(value: settings.pinyinScheme == .wubi86 ? WubiEngine.shared.characterCount.formatted() : "\(PinyinLexicon.allSyllables.count)", label: settings.pinyinScheme == .wubi86 ? "五笔单字覆盖" : "标准普通话音节")
                        statBox(value: "\(learnedCount)", label: "用户习得词条")
                        statBox(value: "\(totalChars)", label: "累计上屏字数")
                    }
                    
                    settingToggleRow(
                        title: "记住我的选词习惯",
                        desc: "根据你的选词调整排序，让常用词更靠前。",
                        isOn: $settings.isUserLearningEnabled
                    )

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Text("词库备份与迁移").font(.system(size: 13, weight: .medium))
                            Spacer()
                            Picker("导入方式", selection: $importMode) {
                                ForEach(UserLexicon.ImportMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 160)
                        }

                        Text("支持完整 JSON 词库备份（含自学习词频、自定义短语、置顶与忽略记录），也支持导入「编码 词条」纯文本或 Rime 词表。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 10) {
                            Button("导入词库…") {
                                importLexiconFromFile()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Button("导出完整备份 (.json)…") {
                                exportLexiconFile(asPlainText: false)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("导出短语词表 (.txt)…") {
                                exportLexiconFile(asPlainText: true)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Spacer()

                            Button("清空自学习词频记录") {
                                UserLexicon.shared.clearLearnedFrequencies()
                                refreshStats()
                                isStatusError = false
                                statusBanner = "已清空自学习词频"
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
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
                        TextField(settings.pinyinScheme == .wubi86 ? "五笔码，如 wqvb" : "拼音，如 gongsi", text: $customPinyin)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 155)
                        
                        TextField("短语内容，如公司全称", text: $customPhrase)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("添加短语") {
                            guard !customPinyin.isEmpty, !customPhrase.isEmpty else { return }
                            UserLexicon.shared.addCustomPhrase(pinyin: customPhraseKey, phrase: customPhrase)
                            customPinyin = ""
                            customPhrase = ""
                            refreshStats()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isCustomCodeValid || customPhrase.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    
                    if customList.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "text.badge.plus").font(.system(size: 26)).foregroundStyle(.tertiary)
                            Text("把常用的长句，变成几个字母") .font(.system(size: 13, weight: .medium))
                            Text(settings.pinyinScheme == .wubi86 ? "使用 1–4 位五笔码保存短语；五笔与拼音短语互不干扰。" : "例如用 gongsi 输入公司全称；短语仅保存在本机。")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 24)
                    } else {
                        if customList.count > 8 {
                            TextField("搜索已添加的编码或短语…", text: $phraseSearchText)
                                .textFieldStyle(.roundedBorder)
                        }
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(filteredCustomList) { item in
                                HStack {
                                    Text(item.pinyin.replacingOccurrences(of: "wubi86:", with: ""))
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

            if !pinnedList.isEmpty || !forgottenList.isEmpty {
                PreferencesCard() {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("候选偏好管理（置顶与已忽略词条）", systemImage: "pin.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)

                        if !pinnedList.isEmpty {
                            Text("已置顶词条 (\(pinnedList.count))")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(pinnedList) { item in
                                    HStack {
                                        Text(item.pinyin.replacingOccurrences(of: "wubi86:", with: ""))
                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(Color.accentColor)
                                            .frame(width: 120, alignment: .leading)
                                        Text(item.word)
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Button("取消置顶") {
                                            UserLexicon.shared.setPinned(item.word, for: item.pinyin, pinned: false)
                                            refreshStats()
                                        }
                                        .buttonStyle(.borderless)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.secondary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.primary.opacity(0.035))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }

                        if !forgottenList.isEmpty {
                            Text("已忽略词条 (\(forgottenList.count))")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(forgottenList) { item in
                                    HStack {
                                        Text(item.pinyin.replacingOccurrences(of: "wubi86:", with: ""))
                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 120, alignment: .leading)
                                        Text(item.word)
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Button("恢复候选") {
                                            UserLexicon.shared.unforget(item.word, for: item.pinyin)
                                            refreshStats()
                                        }
                                        .buttonStyle(.borderless)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.accentColor)
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

            quickSnippetsCard
            clipboardHistoryCard
            syncSettingsCard
        }
    }

    private var quickSnippetsCard: some View {
        PreferencesCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("常用语（支持多行模板）", systemImage: "text.quote")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Button("打开工具箱面板") {
                        AetherInputController.presentToolbox(tab: .snippets, copyToPasteboard: true)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Text("支持保留换行与缩进的多行模板（如邮箱签名、收件地址、固定回复）。填写可选快捷码后，输入时也可直接从候选中上屏，或按 ⌃⇧V / vcy 打开工具箱。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    TextField("标题（可选，默认取首行）", text: $snippetTitle)
                        .textFieldStyle(.roundedBorder)
                    TextField("快捷码（可选，如 yx）", text: $snippetShortcut)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                }

                ZStack(alignment: .topLeading) {
                    if snippetContent.isEmpty {
                        Text("输入常用语内容，支持多行文本与模板…")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $snippetContent)
                        .font(.system(size: 12))
                        .scrollContentBackground(.hidden)
                        .padding(4)
                }
                .frame(minHeight: 68, maxHeight: 110)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75))

                HStack(spacing: 8) {
                    Spacer()
                    if editingSnippetID != nil {
                        Button("取消编辑") {
                            resetSnippetForm()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Button(editingSnippetID == nil ? "添加常用语" : "保存修改") {
                        saveSnippetForm()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(snippetContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if snippetStore.items.isEmpty {
                    Text("暂未添加常用语。添加后可在 ⌃⇧V 工具箱或通过快捷码快速插入。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(snippetStore.items) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Button {
                                    snippetStore.togglePin(id: item.id)
                                } label: {
                                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(item.isPinned ? Color.accentColor : Color.secondary)
                                        .frame(width: 22, height: 22)
                                }
                                .buttonStyle(.borderless)
                                .help(item.isPinned ? "取消置顶" : "置顶常用语")

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(item.title)
                                            .font(.system(size: 12.5, weight: .semibold))
                                        if !item.shortcutCode.isEmpty {
                                            Text(item.shortcutCode)
                                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                                .foregroundStyle(Color.accentColor)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(Color.accentColor.opacity(0.10), in: Capsule())
                                        }
                                    }
                                    Text(item.content)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Button("编辑") {
                                    editingSnippetID = item.id
                                    snippetTitle = item.title
                                    snippetShortcut = item.shortcutCode
                                    snippetContent = item.content
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.accentColor)

                                Button("删除") {
                                    if editingSnippetID == item.id {
                                        resetSnippetForm()
                                    }
                                    snippetStore.remove(id: item.id)
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.red.opacity(0.8))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private var clipboardHistoryCard: some View {
        PreferencesCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("剪贴板历史", systemImage: "doc.on.clipboard")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Button("打开剪贴板面板") {
                        AetherInputController.presentToolbox(tab: .clipboard, copyToPasteboard: true)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                settingToggleRow(
                    title: "记录纯文本剪贴板历史（最多 50 条）",
                    desc: "复制文本后自动收录，输入时按 ⌃⇧V 或 vjb 即可筛选、置顶与快速粘贴。",
                    isOn: $settings.isClipboardHistoryEnabled
                )

                HStack(spacing: 10) {
                    let pinnedCount = clipboardStore.items.filter(\.isPinned).count
                    Text("当前共有 \(clipboardStore.items.count) 条记录（已置顶 \(pinnedCount) 条）")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("清空未置顶") {
                        clipboardStore.clearUnpinned()
                        isStatusError = false
                        statusBanner = "已清空未置顶的剪贴板记录"
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(clipboardStore.items.allSatisfy(\.isPinned))

                    Button("全部清空") {
                        clipboardStore.clearAll()
                        isStatusError = false
                        statusBanner = "已清空全部剪贴板历史记录"
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(clipboardStore.items.isEmpty)
                }

                Label("隐私保护：自动跳过来自 1Password、系统钥匙串及标记 Concealed / Transient / AutoGenerated 的敏感剪贴板内容，仅保存纯文本。", systemImage: "lock.shield")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
    }

    private var syncSettingsCard: some View {
        let configuredPath = settings.syncFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let iCloudURL = syncManager.defaultICloudDirectoryURL()
        return PreferencesCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("跨设备本地 / iCloud 同步", systemImage: "icloud.and.arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("当前同步目录").font(.system(size: 12, weight: .medium))
                    if !configuredPath.isEmpty {
                        Text(configuredPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    } else if let iCloudURL {
                        Text("自动使用 iCloud Drive：\(iCloudURL.path)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.accentColor)
                            .textSelection(.enabled)
                    } else {
                        Text("未配置同步目录（本机未检测到 iCloud Drive 目录）")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 10) {
                    Button("选择同步目录…") {
                        chooseSyncFolder()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if let iCloudURL {
                        Button("使用 iCloud Drive") {
                            settings.syncFolderPath = iCloudURL.path
                            isStatusError = false
                            statusBanner = "已设为同步至 iCloud Drive：\(iCloudURL.path)"
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if !configuredPath.isEmpty {
                        Button("清除自定义目录") {
                            settings.syncFolderPath = ""
                            isStatusError = false
                            statusBanner = iCloudURL != nil ? "已恢复自动检测 iCloud Drive" : "已清除同步目录配置"
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("立即双向同步") {
                        performManualSync()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Divider()

                settingToggleRow(
                    title: "启动时自动双向同步",
                    desc: "AetherKey 启动时自动在后台与同步目录中的 user_lexicon.json 及 snippets.json 进行合并。",
                    isOn: $settings.isAutoSyncEnabled
                )

                if !syncManager.lastSyncMessage.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(syncManager.lastSyncMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(20)
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
    
    // MARK: - Tab 3: Shortcuts & About
    private var shortcutsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsGroup("切换与输入", icon: "keyboard") {
                shortcutRow(key: "Shift", desc: "切换中文 / 英文模式（可在设置中限定左/右 Shift）")
                Divider()
                shortcutRow(key: "Caps Lock", desc: "默认大写锁定；可在设置中设为短按切换中英文")
                Divider()
                shortcutRow(key: "⌃ .", desc: "切换中文 / 英文标点，保留正在编辑的编码")
                Divider()
                shortcutRow(key: "⌃⇧F", desc: "切换简体 / 繁体中文输出，保留正在编辑的编码")
                Divider()
                shortcutRow(key: "⌃⇧V", desc: "打开 / 关闭剪贴板历史与常用语工具箱面板")
                Divider()
                shortcutRow(key: "⌃⇧E", desc: "打开 / 关闭符号与表情面板")
                Divider()
                shortcutRow(key: "Shift + 字母", desc: "中文模式下输入大写英文字母")
                Divider()
                shortcutRow(key: "Space / Return", desc: "空格确认候选；回车提交原始编码")
            }
            settingsGroup("候选与编辑", icon: "text.cursor") {
                shortcutRow(key: "⌥ Tab", desc: "切换单行 / 双行候选面板（横排模式下）")
                Divider()
                shortcutRow(key: "数字 / 鼠标点击", desc: "选择当前页对应序号的候选词")
                Divider()
                shortcutRow(key: "- / = · [ / ]", desc: "上一页 / 下一页（可在设置开启 , / . 翻页），也支持 PgUp / PgDn")
                Divider()
                shortcutRow(key: "[ / ]", desc: "默认候选翻页，也可设为以词定字（取多字候选首字 / 末字）")
                Divider()
                shortcutRow(key: ";", desc: "微软 / 搜狗双拼输入韵母 ing；开启设置后在候选时快速选第 2 候选")
                Divider()
                shortcutRow(key: settings.isFourArrowSelectionEnabled ? "Tab · ↑ ↓ ← →" : "Tab · ↑ ↓", desc: "移动候选高亮，空格确认")
                Divider()
                shortcutRow(key: settings.isFourArrowSelectionEnabled ? "⌥ ← / →" : "← / →", desc: settings.pinyinScheme == .wubi86 ? "逐码编辑五笔；Home / End 到首尾" : settings.isFourArrowSelectionEnabled ? "按音节移动拼音光标；Home / End 到首尾" : "编辑拼音中间字母；⌥ ← / → 按音节移动")
                Divider()
                shortcutRow(key: "⌥ Delete", desc: settings.pinyinScheme == .wubi86 ? "删除光标前的一位编码" : "删除光标前的一个音节")
            }
            settingsGroup("词库与工具", icon: "wand.and.stars") {
                shortcutRow(key: "候选词右键", desc: "置顶、取消置顶或忘记候选词")
                Divider()
                shortcutRow(key: "⌃⌥ P / U / Delete", desc: "置顶 / 取消置顶 / 忘记当前高亮候选")
                Divider()
                if settings.pinyinScheme == .wubi86 {
                    shortcutRow(key: "第 5 码", desc: "满四码后继续输入，确认当前候选并开始下一字词")
                    Divider()
                    shortcutRow(key: "z + 拼音", desc: "拼音反查汉字与词组，候选旁显示五笔编码")
                } else {
                    if settings.pinyinScheme == .full {
                        shortcutRow(key: "u + 部件/笔画", desc: "U 模式拆字与五笔画（h/s/p/n/z）反查生僻字，如 uhuohuo、uhs")
                        Divider()
                    }
                    shortcutRow(key: "vjb / vcy / vbq", desc: "快速打开剪贴板（vjb）、常用语（vcy）、符号与表情（vbq）面板")
                    Divider()
                    shortcutRow(key: "v + 算式 / 数字", desc: "算式求值、人民币大写与中文数字，如 v1+2、v128.5、v123")
                    Divider()
                    shortcutRow(key: "v + 宏关键词", desc: "日期时间、UUID 与常用符号：vnow、vts、vuuid、varrow、vmath、vgreek、vfh")
                }
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
    
    private var customPhraseKey: String {
        let code = customPinyin.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return settings.pinyinScheme == .wubi86 ? WubiEngine.learningKey(code) : code
    }

    private var isCustomCodeValid: Bool {
        let code = customPinyin.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if settings.pinyinScheme == .wubi86 {
            return (1...4).contains(code.count) && code.allSatisfy { $0 >= "a" && $0 <= "y" }
        }
        return !code.isEmpty
    }

    private var filteredCustomList: [CustomPhraseItem] {
        let query = phraseSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return customList }
        return customList.filter {
            $0.pinyin.lowercased().contains(query) || $0.phrase.lowercased().contains(query)
        }
    }

    private func refreshStats() {
        let isWubi = settings.pinyinScheme == .wubi86
        var seenCustom = Set<String>()
        customList = UserLexicon.shared.allCustomPhrases()
            .filter { $0.pinyin.hasPrefix("wubi86:") == isWubi }
            .map { CustomPhraseItem(pinyin: $0.pinyin, phrase: $0.phrase) }
            .filter { seenCustom.insert($0.id).inserted }
        var seenPinned = Set<String>()
        pinnedList = UserLexicon.shared.allPinnedWords()
            .filter { $0.pinyin.hasPrefix("wubi86:") == isWubi }
            .map { LexiconWordItem(pinyin: $0.pinyin, word: $0.word) }
            .filter { seenPinned.insert($0.id).inserted }
        var seenForgotten = Set<String>()
        forgottenList = UserLexicon.shared.allForgottenWords()
            .filter { $0.pinyin.hasPrefix("wubi86:") == isWubi }
            .map { LexiconWordItem(pinyin: $0.pinyin, word: $0.word) }
            .filter { seenForgotten.insert($0.id).inserted }
        learnedCount = UserLexicon.shared.learnedEntryCount
        totalChars = UserLexicon.shared.totalCommittedCharacters
    }

    private func addAppDefaultModeRule() {
        let panel = NSOpenPanel()
        panel.title = "选择要配置默认输入模式的应用"
        panel.prompt = "添加应用"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundleId = Bundle(url: url)?.bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines), !bundleId.isEmpty else {
            isStatusError = true
            statusBanner = "未能读取所选应用的 Bundle ID"
            return
        }
        let defaultMode = settings.appDefaultMode(for: bundleId) ?? .english
        settings.setAppDefaultMode(defaultMode, for: bundleId)
        isStatusError = false
        let appName = FileManager.default.displayName(atPath: url.path)
        statusBanner = "已添加 \(appName)（\(bundleId)）：默认\(defaultMode.title)"
    }

    private func exportLexiconFile(asPlainText: Bool) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        if asPlainText {
            panel.title = "导出自定义短语词表"
            panel.nameFieldStringValue = "AetherKey-自定义短语.txt"
            panel.allowedContentTypes = [.plainText, .tabSeparatedText]
        } else {
            panel.title = "导出 AetherKey 词库备份"
            panel.nameFieldStringValue = "AetherKey-词库备份.json"
            panel.allowedContentTypes = [.json]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try UserLexicon.shared.export(to: url)
            isStatusError = false
            if asPlainText {
                statusBanner = "已导出短语词表至 \(url.lastPathComponent)"
            } else {
                statusBanner = "已导出词库备份至 \(url.lastPathComponent)（\(learnedCount) 条词频，\(UserLexicon.shared.customPhraseCount) 条短语）"
            }
        } catch {
            isStatusError = true
            statusBanner = "导出失败：\(error.localizedDescription)"
        }
    }

    private func importLexiconFromFile() {
        let panel = NSOpenPanel()
        panel.title = "导入词库备份或短语词表"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json, .plainText, .tabSeparatedText, .yaml]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let summary = try UserLexicon.shared.importFile(from: url, mode: importMode)
            refreshStats()
            isStatusError = false
            statusBanner = "已\(summary.mode.title)：\(summary.customPhraseCount) 条短语、\(summary.learnedWordCount) 条词频、\(summary.pinnedWordCount) 条置顶"
        } catch {
            isStatusError = true
            statusBanner = "导入失败：\(error.localizedDescription)"
        }
    }

    private func resetSnippetForm() {
        editingSnippetID = nil
        snippetTitle = ""
        snippetShortcut = ""
        snippetContent = ""
    }

    private func saveSnippetForm() {
        let rawContent = snippetContent
        guard !rawContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let editingID = editingSnippetID,
           var existing = snippetStore.items.first(where: { $0.id == editingID }) {
            let trimmedTitle = snippetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.title = trimmedTitle.isEmpty
                ? String(rawContent.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
                : trimmedTitle
            existing.shortcutCode = snippetShortcut
            existing.content = rawContent
            snippetStore.update(existing)
            isStatusError = false
            statusBanner = "已更新常用语「\(existing.title)」"
        } else {
            let added = snippetStore.add(
                title: snippetTitle,
                content: rawContent,
                shortcutCode: snippetShortcut
            )
            isStatusError = false
            statusBanner = "已添加常用语「\(added.title)」"
        }
        resetSnippetForm()
    }

    private func chooseSyncFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择 AetherKey 跨设备同步目录"
        panel.prompt = "选择目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.syncFolderPath = url.path
        isStatusError = false
        statusBanner = "已配置同步目录：\(url.path)"
    }

    private func performManualSync() {
        do {
            let result = try syncManager.syncNow()
            refreshStats()
            isStatusError = false
            statusBanner = "同步完成（\(result.syncedFolderURL.lastPathComponent)）：词库短语 \(result.mergedCustomPhrases) 条，学习词 \(result.mergedLearnedWords) 条，常用语 \(result.mergedSnippets) 条"
        } catch {
            isStatusError = true
            statusBanner = "同步失败：\(error.localizedDescription)"
        }
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
