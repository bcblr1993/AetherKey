import SwiftUI
import AppKit

public struct SetupWizardView: View {
    @StateObject private var installer = InstallationManager.shared
    
    // Interactive Playground State
    @State private var sampleInput: String = "zhongwen"
    @State private var selectedIndex: Int = 0
    @State private var candidates: [Candidate] = [
        Candidate(text: "中文", pinyin: "zhong'wen"),
        Candidate(text: "中国", pinyin: "zhong'guo"),
        Candidate(text: "中午", pinyin: "zhong'wu"),
        Candidate(text: "终文", pinyin: "zhong'wen"),
        Candidate(text: "AetherKey", comment: "原生极速")
    ]
    @State private var inputMode: InputMode = .chinese
    @State private var testTypingText: String = ""

    public init() {}

    public var body: some View {
        ZStack {
            // Dark futuristic background
            Color(red: 0.06, green: 0.06, blue: 0.08)
                .ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    // Header Banner
                    headerSection
                    
                    // Step 1: Installation Card
                    installCard
                    
                    // Step 2: System Settings Activation Guide
                    settingsGuideCard
                    
                    // Step 3: Interactive Visual & Typing Playground
                    playgroundCard
                    
                    // Footer
                    footerSection
                }
                .padding(28)
            }
        }
        .frame(minWidth: 720, minHeight: 640)
        .onAppear {
            installer.checkStatus()
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0))
                
                Text("AetherKey 安装与设置向导")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
            }
            
            Text("Apple Silicon 原生极速输入法 · AetherNative 科技美学与 120Hz 物理微动效")
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.55))
        }
    }

    // MARK: - Step 1: Install Card
    private var installCard: some View {
        LiquidGlassContainer(cornerRadius: 12) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("步骤 1：部署输入法核心服务", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                    
                    Spacer()
                    
                    // Live Status Pill
                    HStack(spacing: 6) {
                        Circle()
                            .fill(installer.isRunning ? Color.green : (installer.isInstalled ? Color.yellow : Color.red))
                            .frame(width: 8, height: 8)
                        Text(installer.statusMessage)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                
                Text("将 AetherKey.app 部署至 macOS 系统输入法目录（~/Library/Input Methods），并重置 LaunchServices 与信任签名。")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.65))
                
                HStack {
                    Button {
                        installer.install()
                    } label: {
                        HStack(spacing: 8) {
                            if installer.isInstalling {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "bolt.fill")
                            }
                            Text(installer.isInstalled ? "重新安装 / 升级 AetherKey" : "一键安装 AetherKey 到系统")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.0, green: 0.65, blue: 0.95))
                    .disabled(installer.isInstalling)
                    
                    Button("刷新状态") {
                        installer.checkStatus()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(Color.white.opacity(0.8))
                }
            }
            .padding(18)
        }
    }

    // MARK: - Step 2: Keyboard Settings Guide
    private var settingsGuideCard: some View {
        LiquidGlassContainer(cornerRadius: 12) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("步骤 2：在系统设置中启用", systemImage: "gearshape.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                    
                    Spacer()
                    
                    Button("打开系统键盘设置 ↗") {
                        installer.openKeyboardSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.white.opacity(0.18))
                }
                
                // Visual 3-step pills
                HStack(spacing: 8) {
                    stepBadge(number: "1", title: "点击输入法列表编辑", icon: "pencil")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.3))
                    stepBadge(number: "2", title: "选择“简体中文”", icon: "globe")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.3))
                    stepBadge(number: "3", title: "勾选“AetherKey”", icon: "checkmark.circle.fill")
                }
                
                Text("提示：添加后在任何应用中单击 Shift 键即可在中文与英文间瞬时切换。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.85))
            }
            .padding(18)
        }
    }

    private func stepBadge(number: String, title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Text(number)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.white))
            
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Step 3: Interactive Playground
    private var playgroundCard: some View {
        LiquidGlassContainer(cornerRadius: 12) {
            VStack(alignment: .leading, spacing: 16) {
                Label("步骤 3：AetherNative 视觉与动效体验台", systemImage: "sparkle.magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                
                Text("在此实时预览液态玻璃底色、0.5pt 刀锋描边与 120Hz 丝滑微光胶囊物理动效：")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.65))
                
                // Live Floating Candidate Strip
                HStack {
                    Spacer()
                    CandidateListView(
                        inputString: sampleInput,
                        mode: inputMode,
                        candidates: candidates,
                        selectedIndex: selectedIndex,
                        currentPage: 1,
                        totalPages: 2
                    )
                    Spacer()
                }
                .padding(.vertical, 8)
                
                // Interactive Buttons
                HStack(spacing: 8) {
                    Button("全拼: zhongwen") {
                        sampleInput = "zhongwen"
                        inputMode = .chinese
                        candidates = PinyinEngine.shared.query(rawInput: "zhongwen")
                        selectedIndex = 0
                    }
                    Button("简拼: nh (你好)") {
                        sampleInput = "nh"
                        inputMode = .chinese
                        candidates = PinyinEngine.shared.query(rawInput: "nh")
                        selectedIndex = 0
                    }
                    Button("液态玻璃: ytbl") {
                        sampleInput = "ytbl"
                        inputMode = .chinese
                        candidates = PinyinEngine.shared.query(rawInput: "ytbl")
                        selectedIndex = 0
                    }
                    Button("v算式: v1+2*3") {
                        sampleInput = "v1+2*3"
                        inputMode = .vMode
                        candidates = VModeCalculator.shared.candidates(for: "v1+2*3")
                        selectedIndex = 0
                    }
                    Button("v宏: vdate") {
                        sampleInput = "vdate"
                        inputMode = .vMode
                        candidates = VModeCalculator.shared.candidates(for: "vdate")
                        selectedIndex = 0
                    }
                }
                .controlSize(.small)
                
                // Typing test field with Pangu Spacing
                VStack(alignment: .leading, spacing: 6) {
                    Text("盘古空格（中英文自动补齐半角空格）与智能标点实时打字测试：")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                    
                    TextField("在此键入内容，如: AetherKey体验Apple Silicon威力", text: $testTypingText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13.5))
                        .onChange(of: testTypingText) { _, newVal in
                            let spaced = PanguSpacing.shared.spacing(newVal)
                            if spaced != newVal {
                                testTypingText = spaced
                            }
                        }
                }
            }
            .padding(18)
        }
    }

    // MARK: - Footer
    private var footerSection: some View {
        HStack(spacing: 20) {
            Label("Apple Silicon 原生优化", systemImage: "cpu")
            Label("ProMotion 120Hz 弹簧阻尼", systemImage: "bolt.fill")
            Label("静止 0% CPU 占用", systemImage: "leaf.fill")
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(Color.white.opacity(0.40))
    }
}
