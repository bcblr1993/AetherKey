import AppKit
import SwiftUI

/// Uses the production candidate view so appearance and interaction can be reviewed safely.
struct PreviewAppView: View {
    @State private var selectedIndex = 0
    @State private var viewMode: CandidateViewMode = .paging
    @State private var currentPage = 1
    @State private var input = CommandLine.arguments.contains("--emoji-preview") ? "meigui" : "ni'hao"
    @State private var selection = "点击候选词，或切换展开模式查看效果"

    private var words: [String] {
        if CommandLine.arguments.contains("--emoji-preview") {
            return PinyinEngine.shared.query(rawInput: input).map(\.text)
        }
        return ["你好", "您好", "你们好", "你好呀", "你好啊", "拟好", "霓裳", "你好吗", "你好世界", "你好朋友", "你好生活", "你好北京", "你好上海", "你好中国"]
    }
    private var candidates: [Candidate] { words.map { Candidate(text: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("AetherKey").font(.system(size: 25, weight: .semibold))
                Text("轻一点的界面，专注每一次表达。")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("浅色 · 点击选词 / 展开 / 翻页").font(.system(size: 11)).foregroundStyle(.secondary)
                sample(scheme: .light, expanded: viewMode)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("深色 · 双行候选").font(.system(size: 11)).foregroundStyle(.secondary)
                sample(scheme: .dark, expanded: .scroll)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("V 模式 · 运算结果").font(.system(size: 11)).foregroundStyle(.secondary)
                CandidateListView(inputString: "v128.5", mode: .vMode,
                    candidates: [Candidate(text: "壹佰贰拾捌元伍角", comment: "人民币大写"), Candidate(text: "128.5")],
                    selectedIndex: 0)
                    .environment(\.colorScheme, .light)
                    .padding(16)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
            }
            HStack {
                TextField("输入拼音预览", text: $input).textFieldStyle(.roundedBorder).frame(width: 180)
                Text(selection).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(width: 800)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.blue)
    }

    private func sample(scheme: ColorScheme, expanded: CandidateViewMode) -> some View {
        CandidateListView(
            inputString: input, mode: .chinese, viewMode: expanded,
            candidates: expanded == .scroll ? candidates : Array(candidates.prefix(7)), selectedIndex: expanded == .scroll ? selectedIndex : min(selectedIndex, 6),
            currentPage: currentPage, totalPages: 3,
            onSelectCandidate: { selectedIndex = $0; selection = "已选择：\(words[$0])" },
            onToggleViewMode: { viewMode = viewMode == .paging ? .scroll : .paging },
            onPageDelta: { currentPage = min(3, max(1, currentPage + $0)) }
        )
        .environment(\.colorScheme, scheme)
        .padding(16)
        .background(scheme == .dark ? Color(red: 0.13, green: 0.14, blue: 0.17) : Color.white,
                    in: RoundedRectangle(cornerRadius: 18))
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let host = NSHostingView(rootView: PreviewAppView())
let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
    styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
window.title = "AetherKey · 候选面板预览"
window.contentView = host
window.center()
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
if let flag = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > flag + 1 {
    let path = CommandLine.arguments[flag + 1]
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        host.layoutSubtreeIfNeeded()
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
        app.terminate(nil)
    }
}
app.run()
