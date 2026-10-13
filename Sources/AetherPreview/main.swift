import AppKit
import SwiftUI

@MainActor
struct PreviewAppView: View {
    @State private var inputText: String = "zhongwen"
    @State private var selectedIndex: Int = 0
    @State private var candidates: [Candidate] = [
        Candidate(text: "中文", pinyin: "zhong'wen"),
        Candidate(text: "中国", pinyin: "zhong'guo"),
        Candidate(text: "中午", pinyin: "zhong'wu"),
        Candidate(text: "终文", pinyin: "zhong'wen"),
        Candidate(text: "AetherKey", comment: "科技输入法")
    ]
    @State private var inputMode: InputMode = .chinese
    @State private var outputBuffer: String = "使用 Swift 6 开发 macOS 原生极速输入法。"
    @State private var typedInput: String = ""

    var body: some View {
        ZStack {
            // Dark futuristic background canvas
            Color(red: 0.05, green: 0.05, blue: 0.07)
                .ignoresSafeArea()
            
            VStack(spacing: 28) {
                // Title
                VStack(spacing: 6) {
                    Text("AetherKey · 科技美学与原生极速")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                    Text("AetherNative Liquid Glass · 0.5pt 刀锋微光 · 120fps GPU 弹簧阻尼")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                
                // Live Candidate Panel Widget
                VStack(alignment: .leading, spacing: 10) {
                    Text("候选窗口实时渲染预览 (Candidate Floating Panel)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.40))
                    
                    CandidateListView(
                        inputString: inputText,
                        mode: inputMode,
                        candidates: candidates,
                        selectedIndex: selectedIndex,
                        currentPage: 1,
                        totalPages: 3
                    )
                }
                
                // Interactive Controls
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        Button("切换上一词 (↑ / ←)") {
                            if selectedIndex > 0 {
                                selectedIndex -= 1
                            } else {
                                selectedIndex = candidates.count - 1
                            }
                        }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                        
                        Button("切换下一词 (↓ / →)") {
                            if selectedIndex < candidates.count - 1 {
                                selectedIndex += 1
                            } else {
                                selectedIndex = 0
                            }
                        }
                        .keyboardShortcut(.rightArrow, modifiers: [])
                        
                        Button("切换模式: \(inputMode.badgeTitle)") {
                            inputMode = (inputMode == .chinese ? .english : (inputMode == .english ? .vMode : .chinese))
                        }
                    }
                    
                    // Quick sample queries
                    HStack(spacing: 8) {
                        Button("全拼: zhongwen") {
                            inputText = "zhongwen"
                            inputMode = .chinese
                            candidates = PinyinEngine.shared.query(rawInput: "zhongwen")
                            selectedIndex = 0
                        }
                        Button("简拼: nh (你好)") {
                            inputText = "nh"
                            inputMode = .chinese
                            candidates = PinyinEngine.shared.query(rawInput: "nh")
                            selectedIndex = 0
                        }
                        Button("液态玻璃: ytbl") {
                            inputText = "ytbl"
                            inputMode = .chinese
                            candidates = PinyinEngine.shared.query(rawInput: "ytbl")
                            selectedIndex = 0
                        }
                        Button("v模式: v1+2*3") {
                            inputText = "v1+2*3"
                            inputMode = .vMode
                            candidates = VModeCalculator.shared.candidates(for: "v1+2*3")
                            selectedIndex = 0
                        }
                        Button("v日期: vdate") {
                            inputText = "vdate"
                            inputMode = .vMode
                            candidates = VModeCalculator.shared.candidates(for: "vdate")
                            selectedIndex = 0
                        }
                    }
                }
                
                // Interactive Typing Box demonstrating Pangu Spacing & Smart Punctuation
                VStack(alignment: .leading, spacing: 8) {
                    Text("盘古空格 & 智能标点演示输入框:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                    
                    TextField("在此输入文字，体验自动补全空格与标点...", text: $typedInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14))
                        .frame(width: 480)
                        .onChange(of: typedInput) { _, newValue in
                            let spaced = PanguSpacing.shared.spacing(newValue)
                            if spaced != newValue {
                                typedInput = spaced
                            }
                        }
                }
                
                // Status footer
                HStack(spacing: 16) {
                    Label("Apple Silicon 原生优化", systemImage: "cpu")
                    Label("120Hz ProMotion 友好", systemImage: "bolt.fill")
                    Label("静止 0% CPU 占用", systemImage: "leaf.fill")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.40))
            }
            .padding(32)
        }
        .frame(minWidth: 620, minHeight: 460)
    }
}

let app = NSApplication.shared
let window = NSWindow(
    contentRect: NSRect(x: 100, y: 100, width: 660, height: 500),
    styleMask: [.titled, .closable, .miniaturizable, .resizable],
    backing: .buffered,
    defer: false
)
window.title = "AetherKey 动效与交互预览"
window.center()
window.contentView = NSHostingView(rootView: PreviewAppView())
window.makeKeyAndOrderFront(nil)
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
