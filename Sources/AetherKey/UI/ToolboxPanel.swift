import AppKit
import SwiftUI
import QuartzCore

/// Available feature tabs inside the floating ToolboxPanel.
public enum ToolboxTab: String, CaseIterable, Identifiable, Sendable {
    case snippets
    case clipboard
    case symbols

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .snippets: return "常用语"
        case .clipboard: return "剪贴板"
        case .symbols: return "符号与表情"
        }
    }

    var systemImage: String {
        switch self {
        case .snippets: return "text.quote"
        case .clipboard: return "doc.on.clipboard"
        case .symbols: return "face.smiling"
        }
    }
}

/// Decoupled quick-snippet item displayed in the ToolboxPanel.
public struct ToolboxSnippetItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let content: String
    public let shortcutCode: String
    public let isPinned: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        content: String,
        shortcutCode: String = "",
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.shortcutCode = shortcutCode
        self.isPinned = isPinned
    }
}

/// Decoupled clipboard history item displayed in the ToolboxPanel.
public struct ToolboxClipboardItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let copiedAt: Date
    public let isPinned: Bool

    public init(
        id: UUID = UUID(),
        text: String,
        copiedAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
        self.isPinned = isPinned
    }
}

private struct ToolboxSymbolEntry: Equatable, Sendable {
    let text: String
    let label: String
    let keywords: String
}

private enum ToolboxSymbolCatalog {
    static let categories: [String] = [
        "常用标点",
        "序号",
        "数学",
        "箭头",
        "希腊",
        "颜文字",
        "常用 Emoji"
    ]

    static let entriesByCategory: [String: [ToolboxSymbolEntry]] = [
        "常用标点": [
            ToolboxSymbolEntry(text: "，", label: "中文逗号", keywords: "douhao comma 逗号 标点"),
            ToolboxSymbolEntry(text: "。", label: "中文句号", keywords: "juhao period 句号 标点"),
            ToolboxSymbolEntry(text: "、", label: "顿号", keywords: "dunhao 顿号 标点"),
            ToolboxSymbolEntry(text: "；", label: "中文分号", keywords: "fenhao semicolon 分号"),
            ToolboxSymbolEntry(text: "：", label: "中文冒号", keywords: "maohao colon 冒号"),
            ToolboxSymbolEntry(text: "？", label: "中文问号", keywords: "wenhao question 问号"),
            ToolboxSymbolEntry(text: "！", label: "中文感叹号", keywords: "gantanhao exclamation 感叹号"),
            ToolboxSymbolEntry(text: "“", label: "左双引号", keywords: "yinhao quote 引号"),
            ToolboxSymbolEntry(text: "”", label: "右双引号", keywords: "yinhao quote 引号"),
            ToolboxSymbolEntry(text: "‘", label: "左单引号", keywords: "yinhao quote 单引号"),
            ToolboxSymbolEntry(text: "’", label: "右单引号", keywords: "yinhao quote 单引号"),
            ToolboxSymbolEntry(text: "（", label: "左圆括号", keywords: "kuohao paren 括号"),
            ToolboxSymbolEntry(text: "）", label: "右圆括号", keywords: "kuohao paren 括号"),
            ToolboxSymbolEntry(text: "【", label: "左方头括号", keywords: "kuohao bracket 方括号"),
            ToolboxSymbolEntry(text: "】", label: "右方头括号", keywords: "kuohao bracket 方括号"),
            ToolboxSymbolEntry(text: "《", label: "左书名号", keywords: "shuminghao 书名号"),
            ToolboxSymbolEntry(text: "》", label: "右书名号", keywords: "shuminghao 书名号"),
            ToolboxSymbolEntry(text: "「", label: "左直角引号", keywords: "yinhao 直角引号"),
            ToolboxSymbolEntry(text: "」", label: "右直角引号", keywords: "yinhao 直角引号"),
            ToolboxSymbolEntry(text: "『", label: "左双直角引号", keywords: "yinhao 双直角引号"),
            ToolboxSymbolEntry(text: "』", label: "右双直角引号", keywords: "yinhao 双直角引号"),
            ToolboxSymbolEntry(text: "——", label: "破折号", keywords: "pozhehao dash 破折号"),
            ToolboxSymbolEntry(text: "……", label: "省略号", keywords: "shenglvehao ellipsis 省略号"),
            ToolboxSymbolEntry(text: "·", label: "间隔号", keywords: "jiangehao dot 点"),
            ToolboxSymbolEntry(text: "～", label: "波浪号", keywords: "bolang tilde 波浪"),
            ToolboxSymbolEntry(text: "｜", label: "全角竖线", keywords: "shuxian pipe 竖线"),
            ToolboxSymbolEntry(text: "／", label: "全角斜杠", keywords: "xiegang slash 斜杠"),
            ToolboxSymbolEntry(text: "＼", label: "全角反斜杠", keywords: "fanxiegang backslash 反斜杠"),
            ToolboxSymbolEntry(text: "＠", label: "全角艾特", keywords: "aite at"),
            ToolboxSymbolEntry(text: "＃", label: "全角井号", keywords: "jinghao hash 井号"),
            ToolboxSymbolEntry(text: "￥", label: "人民币符号", keywords: "rmb yuan 人民币 货币"),
            ToolboxSymbolEntry(text: "％", label: "百分号", keywords: "baifenhao percent 百分号"),
            ToolboxSymbolEntry(text: "＆", label: "和号", keywords: "hehao and 符号"),
            ToolboxSymbolEntry(text: "＊", label: "星号", keywords: "xinghao star 星号"),
            ToolboxSymbolEntry(text: "※", label: "参考标记", keywords: "cankao 星标"),
            ToolboxSymbolEntry(text: "§", label: "章节符", keywords: "zhangjie section 章节"),
            ToolboxSymbolEntry(text: "°", label: "度", keywords: "du degree 度数"),
            ToolboxSymbolEntry(text: "℃", label: "摄氏度", keywords: "sheshidu celsius 温度"),
            ToolboxSymbolEntry(text: "℉", label: "华氏度", keywords: "huashidu fahrenheit 温度"),
            ToolboxSymbolEntry(text: "‰", label: "千分号", keywords: "qianfenhao permille 千分"),
            ToolboxSymbolEntry(text: "—", label: "长破折", keywords: "emdash 破折"),
            ToolboxSymbolEntry(text: "–", label: "短连接", keywords: "endash 连接符"),
            ToolboxSymbolEntry(text: "•", label: "项目圆点", keywords: "bullet 圆点 列表")
        ],
        "序号": [
            ToolboxSymbolEntry(text: "①", label: "序号 1", keywords: "xuhao 1 yi 一"),
            ToolboxSymbolEntry(text: "②", label: "序号 2", keywords: "xuhao 2 er 二"),
            ToolboxSymbolEntry(text: "③", label: "序号 3", keywords: "xuhao 3 san 三"),
            ToolboxSymbolEntry(text: "④", label: "序号 4", keywords: "xuhao 4 si 四"),
            ToolboxSymbolEntry(text: "⑤", label: "序号 5", keywords: "xuhao 5 wu 五"),
            ToolboxSymbolEntry(text: "⑥", label: "序号 6", keywords: "xuhao 6 liu 六"),
            ToolboxSymbolEntry(text: "⑦", label: "序号 7", keywords: "xuhao 7 qi 七"),
            ToolboxSymbolEntry(text: "⑧", label: "序号 8", keywords: "xuhao 8 ba 八"),
            ToolboxSymbolEntry(text: "⑨", label: "序号 9", keywords: "xuhao 9 jiu 九"),
            ToolboxSymbolEntry(text: "⑩", label: "序号 10", keywords: "xuhao 10 shi 十"),
            ToolboxSymbolEntry(text: "⑪", label: "序号 11", keywords: "xuhao 11"),
            ToolboxSymbolEntry(text: "⑫", label: "序号 12", keywords: "xuhao 12"),
            ToolboxSymbolEntry(text: "⑬", label: "序号 13", keywords: "xuhao 13"),
            ToolboxSymbolEntry(text: "⑭", label: "序号 14", keywords: "xuhao 14"),
            ToolboxSymbolEntry(text: "⑮", label: "序号 15", keywords: "xuhao 15"),
            ToolboxSymbolEntry(text: "⑯", label: "序号 16", keywords: "xuhao 16"),
            ToolboxSymbolEntry(text: "⑰", label: "序号 17", keywords: "xuhao 17"),
            ToolboxSymbolEntry(text: "⑱", label: "序号 18", keywords: "xuhao 18"),
            ToolboxSymbolEntry(text: "⑲", label: "序号 19", keywords: "xuhao 19"),
            ToolboxSymbolEntry(text: "⑳", label: "序号 20", keywords: "xuhao 20"),
            ToolboxSymbolEntry(text: "⑴", label: "括号序号 1", keywords: "xuhao 1 paren"),
            ToolboxSymbolEntry(text: "⑵", label: "括号序号 2", keywords: "xuhao 2 paren"),
            ToolboxSymbolEntry(text: "⑶", label: "括号序号 3", keywords: "xuhao 3 paren"),
            ToolboxSymbolEntry(text: "⑷", label: "括号序号 4", keywords: "xuhao 4 paren"),
            ToolboxSymbolEntry(text: "⑸", label: "括号序号 5", keywords: "xuhao 5 paren"),
            ToolboxSymbolEntry(text: "⑹", label: "括号序号 6", keywords: "xuhao 6 paren"),
            ToolboxSymbolEntry(text: "⑺", label: "括号序号 7", keywords: "xuhao 7 paren"),
            ToolboxSymbolEntry(text: "⑻", label: "括号序号 8", keywords: "xuhao 8 paren"),
            ToolboxSymbolEntry(text: "⑼", label: "括号序号 9", keywords: "xuhao 9 paren"),
            ToolboxSymbolEntry(text: "⑽", label: "括号序号 10", keywords: "xuhao 10 paren"),
            ToolboxSymbolEntry(text: "Ⅰ", label: "罗马数字 I", keywords: "luoma roman 1 I"),
            ToolboxSymbolEntry(text: "Ⅱ", label: "罗马数字 II", keywords: "luoma roman 2 II"),
            ToolboxSymbolEntry(text: "Ⅲ", label: "罗马数字 III", keywords: "luoma roman 3 III"),
            ToolboxSymbolEntry(text: "Ⅳ", label: "罗马数字 IV", keywords: "luoma roman 4 IV"),
            ToolboxSymbolEntry(text: "Ⅴ", label: "罗马数字 V", keywords: "luoma roman 5 V"),
            ToolboxSymbolEntry(text: "Ⅵ", label: "罗马数字 VI", keywords: "luoma roman 6 VI"),
            ToolboxSymbolEntry(text: "Ⅶ", label: "罗马数字 VII", keywords: "luoma roman 7 VII"),
            ToolboxSymbolEntry(text: "Ⅷ", label: "罗马数字 VIII", keywords: "luoma roman 8 VIII"),
            ToolboxSymbolEntry(text: "Ⅸ", label: "罗马数字 IX", keywords: "luoma roman 9 IX"),
            ToolboxSymbolEntry(text: "Ⅹ", label: "罗马数字 X", keywords: "luoma roman 10 X"),
            ToolboxSymbolEntry(text: "❶", label: "实心序号 1", keywords: "xuhao 1 black"),
            ToolboxSymbolEntry(text: "❷", label: "实心序号 2", keywords: "xuhao 2 black"),
            ToolboxSymbolEntry(text: "❸", label: "实心序号 3", keywords: "xuhao 3 black"),
            ToolboxSymbolEntry(text: "❹", label: "实心序号 4", keywords: "xuhao 4 black"),
            ToolboxSymbolEntry(text: "❺", label: "实心序号 5", keywords: "xuhao 5 black"),
            ToolboxSymbolEntry(text: "❻", label: "实心序号 6", keywords: "xuhao 6 black"),
            ToolboxSymbolEntry(text: "❼", label: "实心序号 7", keywords: "xuhao 7 black"),
            ToolboxSymbolEntry(text: "❽", label: "实心序号 8", keywords: "xuhao 8 black"),
            ToolboxSymbolEntry(text: "❾", label: "实心序号 9", keywords: "xuhao 9 black"),
            ToolboxSymbolEntry(text: "❿", label: "实心序号 10", keywords: "xuhao 10 black")
        ],
        "数学": [
            ToolboxSymbolEntry(text: "×", label: "乘号", keywords: "cheng multiply times 乘"),
            ToolboxSymbolEntry(text: "÷", label: "除号", keywords: "chu divide 除"),
            ToolboxSymbolEntry(text: "±", label: "正负号", keywords: "zhengfu plusminus 加减"),
            ToolboxSymbolEntry(text: "≈", label: "约等于", keywords: "yuedengyu approx 约等于"),
            ToolboxSymbolEntry(text: "≠", label: "不等于", keywords: "budengyu notequal 不等"),
            ToolboxSymbolEntry(text: "≤", label: "小于等于", keywords: "xiaoyudengyu le 小于等于"),
            ToolboxSymbolEntry(text: "≥", label: "大于等于", keywords: "dayudengyu ge 大于等于"),
            ToolboxSymbolEntry(text: "∞", label: "无穷大", keywords: "wuqiong infinity 无穷"),
            ToolboxSymbolEntry(text: "√", label: "根号", keywords: "genhao sqrt 平方根"),
            ToolboxSymbolEntry(text: "∑", label: "求和", keywords: "qiuhe sum sigma 求和"),
            ToolboxSymbolEntry(text: "∫", label: "积分", keywords: "jifen integral 积分"),
            ToolboxSymbolEntry(text: "∂", label: "偏导", keywords: "piandao partial 偏微分"),
            ToolboxSymbolEntry(text: "Δ", label: "增量 Delta", keywords: "delta zengliang 变化"),
            ToolboxSymbolEntry(text: "π", label: "圆周率 pi", keywords: "pi pai 圆周率"),
            ToolboxSymbolEntry(text: "∏", label: "求积", keywords: "qiuji product 求积"),
            ToolboxSymbolEntry(text: "∈", label: "属于", keywords: "shuyu in 集合"),
            ToolboxSymbolEntry(text: "∉", label: "不属于", keywords: "bushuyu notin 集合"),
            ToolboxSymbolEntry(text: "⊂", label: "真子集", keywords: "ziji subset 子集"),
            ToolboxSymbolEntry(text: "⊃", label: "真超集", keywords: "chaoji superset"),
            ToolboxSymbolEntry(text: "⊆", label: "子集", keywords: "ziji subseteq"),
            ToolboxSymbolEntry(text: "⊇", label: "超集", keywords: "chaoji supseteq"),
            ToolboxSymbolEntry(text: "∪", label: "并集", keywords: "bingji union"),
            ToolboxSymbolEntry(text: "∩", label: "交集", keywords: "jiaoji intersection"),
            ToolboxSymbolEntry(text: "∧", label: "逻辑与", keywords: "and 逻辑"),
            ToolboxSymbolEntry(text: "∨", label: "逻辑或", keywords: "or 逻辑"),
            ToolboxSymbolEntry(text: "¬", label: "逻辑非", keywords: "not 逻辑"),
            ToolboxSymbolEntry(text: "∀", label: "全称量词", keywords: "forall 任意"),
            ToolboxSymbolEntry(text: "∃", label: "存在量词", keywords: "exists 存在"),
            ToolboxSymbolEntry(text: "∴", label: "所以", keywords: "suoyi therefore"),
            ToolboxSymbolEntry(text: "∵", label: "因为", keywords: "yinwei because"),
            ToolboxSymbolEntry(text: "≡", label: "恒等于", keywords: "hengdengyu equivalent"),
            ToolboxSymbolEntry(text: "∝", label: "正比于", keywords: "zhengbi proportional"),
            ToolboxSymbolEntry(text: "∠", label: "角", keywords: "jiao angle"),
            ToolboxSymbolEntry(text: "⊥", label: "垂直", keywords: "chuizhi perpendicular"),
            ToolboxSymbolEntry(text: "∥", label: "平行", keywords: "pingxing parallel"),
            ToolboxSymbolEntry(text: "′", label: "分 / 撇", keywords: "prime 撇"),
            ToolboxSymbolEntry(text: "″", label: "秒 / 双撇", keywords: "doubleprime 双撇"),
            ToolboxSymbolEntry(text: "²", label: "平方", keywords: "pingfang square 2"),
            ToolboxSymbolEntry(text: "³", label: "立方", keywords: "lifang cube 3")
        ],
        "箭头": [
            ToolboxSymbolEntry(text: "→", label: "右箭头", keywords: "you right arrow 箭头"),
            ToolboxSymbolEntry(text: "←", label: "左箭头", keywords: "zuo left arrow 箭头"),
            ToolboxSymbolEntry(text: "↑", label: "上箭头", keywords: "shang up arrow 箭头"),
            ToolboxSymbolEntry(text: "↓", label: "下箭头", keywords: "xia down arrow 箭头"),
            ToolboxSymbolEntry(text: "↔", label: "左右双向", keywords: "shuangxiang leftright arrow"),
            ToolboxSymbolEntry(text: "⇒", label: "右双箭头", keywords: "tuidao implies arrow 推导"),
            ToolboxSymbolEntry(text: "⇔", label: "等价双向", keywords: "dengjia iff arrow 等价"),
            ToolboxSymbolEntry(text: "↗", label: "右上箭头", keywords: "youshang northeast arrow"),
            ToolboxSymbolEntry(text: "↘", label: "右下箭头", keywords: "youxia southeast arrow"),
            ToolboxSymbolEntry(text: "↙", label: "左下箭头", keywords: "zuoxia southwest arrow"),
            ToolboxSymbolEntry(text: "↖", label: "左上箭头", keywords: "zuoshang northwest arrow"),
            ToolboxSymbolEntry(text: "↕", label: "上下双向", keywords: "shangxia updown arrow"),
            ToolboxSymbolEntry(text: "⇐", label: "左双箭头", keywords: "left double arrow"),
            ToolboxSymbolEntry(text: "⇑", label: "上双箭头", keywords: "up double arrow"),
            ToolboxSymbolEntry(text: "⇓", label: "下双箭头", keywords: "down double arrow"),
            ToolboxSymbolEntry(text: "↩", label: "折返左箭头", keywords: "return back 换行"),
            ToolboxSymbolEntry(text: "↪", label: "折返右箭头", keywords: "forward arrow"),
            ToolboxSymbolEntry(text: "↻", label: "顺时针刷新", keywords: "refresh rotate 刷新"),
            ToolboxSymbolEntry(text: "↺", label: "逆时针撤销", keywords: "undo rotate 撤销"),
            ToolboxSymbolEntry(text: "➜", label: "粗右箭头", keywords: "arrow right 指向"),
            ToolboxSymbolEntry(text: "➤", label: "三角箭头", keywords: "arrow triangle 指向"),
            ToolboxSymbolEntry(text: "➔", label: "粗体箭头", keywords: "arrow bold"),
            ToolboxSymbolEntry(text: "⟶", label: "长右箭头", keywords: "long right arrow"),
            ToolboxSymbolEntry(text: "⟵", label: "长左箭头", keywords: "long left arrow"),
            ToolboxSymbolEntry(text: "⟷", label: "长双向箭头", keywords: "long bidirectional arrow")
        ],
        "希腊": [
            ToolboxSymbolEntry(text: "α", label: "Alpha", keywords: "alpha aerfa 阿尔法"),
            ToolboxSymbolEntry(text: "β", label: "Beta", keywords: "beta beita 贝塔"),
            ToolboxSymbolEntry(text: "γ", label: "Gamma", keywords: "gamma gama 伽马"),
            ToolboxSymbolEntry(text: "δ", label: "Delta", keywords: "delta deerta 德尔塔"),
            ToolboxSymbolEntry(text: "ε", label: "Epsilon", keywords: "epsilon"),
            ToolboxSymbolEntry(text: "θ", label: "Theta", keywords: "theta xita 西塔"),
            ToolboxSymbolEntry(text: "λ", label: "Lambda", keywords: "lambda lamuda 拉姆达"),
            ToolboxSymbolEntry(text: "μ", label: "Mu", keywords: "mu miu 缪 微"),
            ToolboxSymbolEntry(text: "π", label: "Pi", keywords: "pi pai 派"),
            ToolboxSymbolEntry(text: "σ", label: "Sigma", keywords: "sigma xigema 西格玛"),
            ToolboxSymbolEntry(text: "φ", label: "Phi", keywords: "phi fai 斐"),
            ToolboxSymbolEntry(text: "ω", label: "Omega", keywords: "omega oumeiga 欧米伽"),
            ToolboxSymbolEntry(text: "Δ", label: "大写 Delta", keywords: "delta capital"),
            ToolboxSymbolEntry(text: "Ω", label: "大写 Omega", keywords: "omega ohm 欧姆"),
            ToolboxSymbolEntry(text: "ζ", label: "Zeta", keywords: "zeta"),
            ToolboxSymbolEntry(text: "η", label: "Eta", keywords: "eta"),
            ToolboxSymbolEntry(text: "ι", label: "Iota", keywords: "iota"),
            ToolboxSymbolEntry(text: "κ", label: "Kappa", keywords: "kappa"),
            ToolboxSymbolEntry(text: "ν", label: "Nu", keywords: "nu"),
            ToolboxSymbolEntry(text: "ξ", label: "Xi", keywords: "xi"),
            ToolboxSymbolEntry(text: "ρ", label: "Rho", keywords: "rho"),
            ToolboxSymbolEntry(text: "τ", label: "Tau", keywords: "tau"),
            ToolboxSymbolEntry(text: "υ", label: "Upsilon", keywords: "upsilon"),
            ToolboxSymbolEntry(text: "χ", label: "Chi", keywords: "chi"),
            ToolboxSymbolEntry(text: "ψ", label: "Psi", keywords: "psi"),
            ToolboxSymbolEntry(text: "Α", label: "大写 Alpha", keywords: "alpha capital"),
            ToolboxSymbolEntry(text: "Β", label: "大写 Beta", keywords: "beta capital"),
            ToolboxSymbolEntry(text: "Γ", label: "大写 Gamma", keywords: "gamma capital"),
            ToolboxSymbolEntry(text: "Ε", label: "大写 Epsilon", keywords: "epsilon capital"),
            ToolboxSymbolEntry(text: "Ζ", label: "大写 Zeta", keywords: "zeta capital"),
            ToolboxSymbolEntry(text: "Η", label: "大写 Eta", keywords: "eta capital"),
            ToolboxSymbolEntry(text: "Θ", label: "大写 Theta", keywords: "theta capital"),
            ToolboxSymbolEntry(text: "Ι", label: "大写 Iota", keywords: "iota capital"),
            ToolboxSymbolEntry(text: "Κ", label: "大写 Kappa", keywords: "kappa capital"),
            ToolboxSymbolEntry(text: "Λ", label: "大写 Lambda", keywords: "lambda capital"),
            ToolboxSymbolEntry(text: "Μ", label: "大写 Mu", keywords: "mu capital"),
            ToolboxSymbolEntry(text: "Ν", label: "大写 Nu", keywords: "nu capital"),
            ToolboxSymbolEntry(text: "Ξ", label: "大写 Xi", keywords: "xi capital"),
            ToolboxSymbolEntry(text: "Ο", label: "大写 Omicron", keywords: "omicron capital"),
            ToolboxSymbolEntry(text: "Π", label: "大写 Pi", keywords: "pi capital"),
            ToolboxSymbolEntry(text: "Ρ", label: "大写 Rho", keywords: "rho capital"),
            ToolboxSymbolEntry(text: "Σ", label: "大写 Sigma", keywords: "sigma capital"),
            ToolboxSymbolEntry(text: "Τ", label: "大写 Tau", keywords: "tau capital"),
            ToolboxSymbolEntry(text: "Υ", label: "大写 Upsilon", keywords: "upsilon capital"),
            ToolboxSymbolEntry(text: "Φ", label: "大写 Phi", keywords: "phi capital"),
            ToolboxSymbolEntry(text: "Χ", label: "大写 Chi", keywords: "chi capital"),
            ToolboxSymbolEntry(text: "Ψ", label: "大写 Psi", keywords: "psi capital")
        ],
        "颜文字": [
            ToolboxSymbolEntry(text: "(◕‿◕)", label: "微笑", keywords: "weixiao smile happy 开心 颜文字"),
            ToolboxSymbolEntry(text: #"¯\_(ツ)_/¯"#, label: "摊手", keywords: "tanshou shrug 无奈 摊手"),
            ToolboxSymbolEntry(text: "(╯°□°)╯︵ ┻━┻", label: "掀桌", keywords: "xianzhuo tableflip 生气 掀桌"),
            ToolboxSymbolEntry(text: "(つ´ω`)つ", label: "抱抱", keywords: "baobao hug 贴贴 抱抱"),
            ToolboxSymbolEntry(text: "(ง •̀_•́)ง", label: "加油", keywords: "jiayou fight 努力 加油"),
            ToolboxSymbolEntry(text: "ヾ(≧▽≦*)o", label: "超开心", keywords: "kaixin happy 兴奋"),
            ToolboxSymbolEntry(text: "(｡･ω･｡)", label: "卖萌", keywords: "maimeng cute 可爱"),
            ToolboxSymbolEntry(text: #"(*/ω＼*)"#, label: "害羞", keywords: "haixiu shy 捂脸"),
            ToolboxSymbolEntry(text: "(╥﹏╥)", label: "大哭", keywords: "daku cry 哭泣"),
            ToolboxSymbolEntry(text: "(⊙_⊙)", label: "震惊", keywords: "zhenjing surprised 惊讶"),
            ToolboxSymbolEntry(text: "(๑•̀ㅂ•́)و✧", label: "干劲满满", keywords: "ganjin fight 加油"),
            ToolboxSymbolEntry(text: "ヽ(✿ﾟ▽ﾟ)ノ", label: "撒花", keywords: "sahua happy 欢呼"),
            ToolboxSymbolEntry(text: "(￣▽￣)ノ", label: "打招呼", keywords: "hi wave 挥手"),
            ToolboxSymbolEntry(text: "(っ˘̩╭╮˘̩)っ", label: "委屈", keywords: "weiqu sad 难过"),
            ToolboxSymbolEntry(text: "(´･ω･`)", label: "呆萌", keywords: "daimeng 呆"),
            ToolboxSymbolEntry(text: "o(*￣▽￣*)ブ", label: "得意", keywords: "deyi smug 耶"),
            ToolboxSymbolEntry(text: "(☆▽☆)", label: "星星眼", keywords: "xingxingyan excited 期待"),
            ToolboxSymbolEntry(text: "(¬_¬)", label: "斜眼", keywords: "xieyan sideeye 无语"),
            ToolboxSymbolEntry(text: "(づ｡◕‿‿◕｡)づ", label: "求抱", keywords: "qiubao hug 抱"),
            ToolboxSymbolEntry(text: "┬─┬ノ( º _ ºノ)", label: "放回桌子", keywords: "putback table 冷静")
        ],
        "常用 Emoji": [
            ToolboxSymbolEntry(text: "👍", label: "赞", keywords: "zan thumbs up good 赞 棒"),
            ToolboxSymbolEntry(text: "❤️", label: "红心", keywords: "heart love xin ai 爱 心"),
            ToolboxSymbolEntry(text: "😂", label: "笑哭", keywords: "xiaoku laugh joy 笑哭"),
            ToolboxSymbolEntry(text: "🎉", label: "庆祝", keywords: "qingzhu party celebrate 庆祝 撒花"),
            ToolboxSymbolEntry(text: "🔥", label: "火热", keywords: "huo fire hot 火 厉害"),
            ToolboxSymbolEntry(text: "✨", label: "闪亮", keywords: "sparkles shanliang 闪亮 亮点"),
            ToolboxSymbolEntry(text: "🤔", label: "思考", keywords: "sikao think 思考 疑惑"),
            ToolboxSymbolEntry(text: "😭", label: "大哭", keywords: "daku cry 哭"),
            ToolboxSymbolEntry(text: "🙌", label: "举手欢呼", keywords: "huanhu praise 万岁"),
            ToolboxSymbolEntry(text: "🚀", label: "火箭", keywords: "huojian rocket launch 发布 上线"),
            ToolboxSymbolEntry(text: "✅", label: "完成", keywords: "wancheng check done ok 对勾 完成"),
            ToolboxSymbolEntry(text: "❌", label: "错误", keywords: "cuowu cross error 叉 错误"),
            ToolboxSymbolEntry(text: "⚠️", label: "警告", keywords: "jinggao warning alert 注意 警告"),
            ToolboxSymbolEntry(text: "💡", label: "灵感", keywords: "linggan idea bulb 想法 提示"),
            ToolboxSymbolEntry(text: "📌", label: "置顶", keywords: "zhiding pin 标记 置顶"),
            ToolboxSymbolEntry(text: "👏", label: "鼓掌", keywords: "guzhang clap 鼓掌"),
            ToolboxSymbolEntry(text: "🙏", label: "感谢", keywords: "ganxie thanks pray 谢谢 拜托"),
            ToolboxSymbolEntry(text: "💪", label: "加油", keywords: "jiayou muscle strong 力量"),
            ToolboxSymbolEntry(text: "🎯", label: "目标", keywords: "mubiao target 精准"),
            ToolboxSymbolEntry(text: "👀", label: "关注", keywords: "guanzhu eyes look 围观"),
            ToolboxSymbolEntry(text: "😎", label: "酷", keywords: "ku cool 墨镜"),
            ToolboxSymbolEntry(text: "🥳", label: "派对", keywords: "paidui party 开心"),
            ToolboxSymbolEntry(text: "😅", label: "汗颜", keywords: "hanyan sweat 尴尬"),
            ToolboxSymbolEntry(text: "🤯", label: "震撼", keywords: "zhenhan mindblown 惊呆"),
            ToolboxSymbolEntry(text: "💯", label: "满分", keywords: "manfen 100 满分"),
            ToolboxSymbolEntry(text: "🫶", label: "比心", keywords: "bixin heart hands 比心"),
            ToolboxSymbolEntry(text: "🫡", label: "收到", keywords: "shoudao salute 敬礼 收到"),
            ToolboxSymbolEntry(text: "🌟", label: "星标", keywords: "xingbiao star 优秀"),
            ToolboxSymbolEntry(text: "📝", label: "笔记", keywords: "biji note 记录"),
            ToolboxSymbolEntry(text: "⚡️", label: "闪电", keywords: "shandian lightning 快"),
            ToolboxSymbolEntry(text: "☕️", label: "咖啡", keywords: "kafei coffee 摸鱼")
        ]
    ]

    static func entries(for category: String, query: String) -> [ToolboxSymbolEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeCategory = categories.contains(category) ? category : categories[0]
        if trimmed.isEmpty {
            return entriesByCategory[activeCategory] ?? []
        }

        let orderedCategories = [activeCategory] + categories.filter { $0 != activeCategory }
        var seen = Set<String>()
        var results: [ToolboxSymbolEntry] = []
        for cat in orderedCategories {
            guard let list = entriesByCategory[cat] else { continue }
            for entry in list where !seen.contains(entry.text) {
                if entry.text.localizedCaseInsensitiveContains(trimmed)
                    || entry.label.localizedCaseInsensitiveContains(trimmed)
                    || entry.keywords.localizedCaseInsensitiveContains(trimmed) {
                    seen.insert(entry.text)
                    results.append(entry)
                }
            }
        }
        return results
    }
}

/// Observable state backing the floating ToolboxPanel UI.
@MainActor
public final class ToolboxPanelState: ObservableObject {
    public static let symbolCategories: [String] = ToolboxSymbolCatalog.categories

    @Published public var activeTab: ToolboxTab = .snippets {
        didSet {
            if oldValue != activeTab { selectedIndex = 0 }
        }
    }
    @Published public var searchQuery: String = "" {
        didSet {
            if oldValue != searchQuery { selectedIndex = 0 }
        }
    }
    @Published public var selectedIndex: Int = 0
    @Published public var selectedSymbolCategory: String = "常用标点" {
        didSet {
            if oldValue != selectedSymbolCategory { selectedIndex = 0 }
        }
    }
    @Published public var snippets: [ToolboxSnippetItem] = [] {
        didSet { clampSelectionIfNeeded() }
    }
    @Published public var clipboardItems: [ToolboxClipboardItem] = [] {
        didSet { clampSelectionIfNeeded() }
    }
    @Published public var isVisible: Bool = false

    @Published var panelSize: NSSize = NSSize(width: 392, height: 420)

    public var onCommitText: ((String) -> Void)?
    public var onPinClipboard: ((UUID) -> Void)?
    public var onDeleteClipboard: ((UUID) -> Void)?
    public var onClearClipboard: (() -> Void)?
    public var onClose: (() -> Void)?
    public var onRefresh: (() -> Void)?

    public init() {}

    public var filteredSnippets: [ToolboxSnippetItem] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return snippets }
        return snippets.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.content.localizedCaseInsensitiveContains(q)
                || $0.shortcutCode.localizedCaseInsensitiveContains(q)
        }
    }

    public var filteredClipboardItems: [ToolboxClipboardItem] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return clipboardItems }
        return clipboardItems.filter {
            $0.text.localizedCaseInsensitiveContains(q)
        }
    }

    public var filteredSymbols: [String] {
        ToolboxSymbolCatalog.entries(for: selectedSymbolCategory, query: searchQuery).map(\.text)
    }

    fileprivate var filteredSymbolEntries: [ToolboxSymbolEntry] {
        ToolboxSymbolCatalog.entries(for: selectedSymbolCategory, query: searchQuery)
    }

    public var currentRowCount: Int {
        switch activeTab {
        case .snippets:
            return filteredSnippets.count
        case .clipboard:
            return filteredClipboardItems.count
        case .symbols:
            return filteredSymbols.count
        }
    }

    public func textForRow(at index: Int) -> String? {
        guard index >= 0 else { return nil }
        switch activeTab {
        case .snippets:
            let items = filteredSnippets
            return index < items.count ? items[index].content : nil
        case .clipboard:
            let items = filteredClipboardItems
            return index < items.count ? items[index].text : nil
        case .symbols:
            let items = filteredSymbols
            return index < items.count ? items[index] : nil
        }
    }

    private func clampSelectionIfNeeded() {
        let count = currentRowCount
        if count == 0 {
            if selectedIndex != 0 { selectedIndex = 0 }
        } else if selectedIndex >= count {
            selectedIndex = count - 1
        } else if selectedIndex < 0 {
            selectedIndex = 0
        }
    }
}

@MainActor
public enum ToolboxPanelHolder {
    public static let shared = ToolboxPanel()
}

/// Non-activating floating toolbox window providing quick snippets, clipboard history, and symbols/emojis.
public final class ToolboxPanel: NSPanel, @unchecked Sendable {
    public static let symbolCategories: [String] = ToolboxSymbolCatalog.categories
    private static let defaultSize = NSSize(width: 392, height: 420)

    public let state = ToolboxPanelState()
    private var hostingView: NSHostingView<ToolboxPanelRootView>!
    private var presentationGeneration = 0
    private var fadeTimer: DispatchSourceTimer?
    private var fadeCompletion: (() -> Void)?

    public init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        setupPanel()
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    private func setupPanel() {
        isFloatingPanel = true
        level = .popUpMenu
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let root = ToolboxPanelRootView(
            state: state,
            onCommitRow: { [weak self] text in
                self?.commit(text: text)
            },
            onDismissAction: { [weak self] in
                guard let self else { return }
                self.dismiss()
                self.state.onClose?()
            }
        )
        hostingView = NSHostingView(rootView: root)
        hostingView.wantsLayer = true
        hostingView.layer?.drawsAsynchronously = true
        contentView = hostingView
    }

    public func show(tab: ToolboxTab? = nil, anchorRect: NSRect?, clientWindowLevel: CGWindowLevel? = nil) {
        if let tab {
            state.activeTab = tab
        }
        state.onRefresh?()
        if state.currentRowCount == 0 {
            state.selectedIndex = 0
        } else if state.selectedIndex >= state.currentRowCount {
            state.selectedIndex = state.currentRowCount - 1
        }

        StatusHUDHolder.shared.hideImmediately()
        let desiredLevel = CandidateCaretGeometry.effectiveWindowLevel(for: clientWindowLevel)
        if level != desiredLevel { level = desiredLevel }

        let wasVisible = state.isVisible
        state.isVisible = true
        updatePosition(anchorRect: anchorRect)

        guard !wasVisible else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !isVisible { alphaValue = reduceMotion ? 1 : 0 }
        orderFrontRegardless()
        fade(to: 1, duration: reduceMotion ? 0 : 0.13)
    }

    public func dismiss() {
        guard state.isVisible else { return }
        state.isVisible = false
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        fade(to: 0, duration: reduceMotion ? 0 : 0.08) { [weak self] in
            guard let self, !self.state.isVisible else { return }
            self.orderOut(nil)
            self.alphaValue = 1
        }
    }

    public func moveSelection(delta: Int) {
        let count = state.currentRowCount
        guard count > 0 else {
            state.selectedIndex = 0
            return
        }
        let clampedCurrent = min(max(state.selectedIndex, 0), count - 1)
        state.selectedIndex = min(max(clampedCurrent + delta, 0), count - 1)
    }

    @discardableResult
    public func commitSelected() -> Bool {
        guard let text = state.textForRow(at: state.selectedIndex) else { return false }
        commit(text: text)
        return true
    }

    @discardableResult
    public func commitNumber(_ digit: Int) -> Bool {
        guard (1...9).contains(digit) else { return false }
        guard let text = state.textForRow(at: digit - 1) else { return false }
        commit(text: text)
        return true
    }

    private func commit(text: String) {
        state.onCommitText?(text)
        dismiss()
    }

    private func updatePosition(anchorRect: NSRect?) {
        let mouse = NSEvent.mouseLocation
        let caret = (anchorRect.flatMap { CandidateCaretGeometry.isUsable($0) ? $0 : nil })
            ?? NSRect(x: mouse.x, y: mouse.y, width: 0, height: 22)
        let screen = CandidatePanel.targetScreen(for: caret)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let margin: CGFloat = 8
        let gap: CGFloat = 8
        let width = min(Self.defaultSize.width, max(240, screen.width - margin * 2))
        let height = min(Self.defaultSize.height, max(240, screen.height - margin * 2))
        let resolvedSize = NSSize(width: width, height: height)
        if state.panelSize != resolvedSize {
            state.panelSize = resolvedSize
        }
        hostingView.layoutSubtreeIfNeeded()

        let spaceBelow = caret.minY - screen.minY - gap - margin
        let spaceAbove = screen.maxY - caret.maxY - gap - margin
        let showAbove = spaceBelow < height && spaceAbove > spaceBelow
        let rawY = showAbove ? caret.maxY + gap : caret.minY - height - gap
        let target = NSRect(
            x: min(max(caret.minX, screen.minX + margin), screen.maxX - width - margin),
            y: min(max(rawY, screen.minY + margin), screen.maxY - height - margin),
            width: width,
            height: height
        )
        if frame != target {
            setFrame(target, display: true, animate: false)
        }
    }

    private func fade(to target: CGFloat, duration: TimeInterval, completion: (() -> Void)? = nil) {
        fadeTimer?.cancel()
        fadeTimer = nil
        fadeCompletion = completion
        presentationGeneration += 1
        guard duration > 0 else {
            alphaValue = target
            fadeCompletion = nil
            completion?()
            return
        }
        let generation = presentationGeneration
        let initialAlpha = alphaValue
        let start = CACurrentMediaTime()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        fadeTimer = timer
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.presentationGeneration == generation else { return }
                let progress = min(1, (CACurrentMediaTime() - start) / duration)
                let eased = 1 - pow(1 - progress, 3)
                self.alphaValue = initialAlpha + (target - initialAlpha) * eased
                if progress >= 1 {
                    self.fadeTimer?.cancel()
                    self.fadeTimer = nil
                    let completion = self.fadeCompletion
                    self.fadeCompletion = nil
                    completion?()
                }
            }
        }
        timer.resume()
    }
}

private struct ToolboxPanelRootView: View {
    @ObservedObject var state: ToolboxPanelState
    let onCommitRow: (String) -> Void
    let onDismissAction: () -> Void

    @State private var hoveredRowIndex: Int?

    @MainActor
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    @MainActor
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    var body: some View {
        LiquidGlassContainer(cornerRadius: 13) {
            VStack(spacing: 0) {
                headerBar
                searchBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                hairlineDivider
                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                hairlineDivider
                footerBar
            }
            .frame(width: state.panelSize.width, height: state.panelSize.height)
        }
        .fixedSize()
        .transaction { $0.animation = nil }
        .onChange(of: state.activeTab) { _, _ in
            hoveredRowIndex = nil
        }
        .onChange(of: state.selectedSymbolCategory) { _, _ in
            hoveredRowIndex = nil
        }
        .onChange(of: state.searchQuery) { _, _ in
            hoveredRowIndex = nil
        }
    }

    private var hairlineDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(ToolboxTab.allCases) { tab in
                    let isSelected = state.activeTab == tab
                    Button {
                        state.activeTab = tab
                        state.selectedIndex = 0
                        if tab != .symbols {
                            state.onRefresh?()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 10.5, weight: .medium))
                            Text(tab.title)
                                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.78))
                        .padding(.horizontal, 10)
                        .frame(height: 25)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                    .fill(Color.accentColor)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2.5)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            )

            Spacer(minLength: 4)

            Button {
                onDismissAction()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.05), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("关闭工具箱 · Esc")
            .accessibilityLabel("关闭工具箱")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var searchPlaceholder: String {
        switch state.activeTab {
        case .snippets:
            return "筛选常用语、内容或快捷码…"
        case .clipboard:
            return "筛选剪贴板历史…"
        case .symbols:
            return "筛选符号、希腊字母或 Emoji…"
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(searchPlaceholder, text: $state.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))

            if !state.searchQuery.isEmpty {
                Button {
                    state.searchQuery = ""
                    state.selectedIndex = 0
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清空筛选")
                .accessibilityLabel("清空筛选")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 29)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var contentArea: some View {
        switch state.activeTab {
        case .snippets:
            snippetsContent
        case .clipboard:
            clipboardContent
        case .symbols:
            symbolsContent
        }
    }

    @ViewBuilder
    private var snippetsContent: some View {
        let items = state.filteredSnippets
        if items.isEmpty {
            emptyStateView(
                icon: "text.bubble",
                title: state.searchQuery.isEmpty ? "暂无常用语" : "未找到匹配的常用语",
                subtitle: state.searchQuery.isEmpty ? "可在设置中添加常用短语与快捷码" : "尝试更换关键词或清空筛选"
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            snippetRow(index: index, item: item)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .onChange(of: state.selectedIndex) { _, target in
                    proxy.scrollTo(target, anchor: .center)
                }
            }
        }
    }

    private func snippetRow(index: Int, item: ToolboxSnippetItem) -> some View {
        let selected = index == state.selectedIndex
        let hovered = hoveredRowIndex == index
        return Button {
            onCommitRow(item.content)
        } label: {
            HStack(alignment: .center, spacing: 8) {
                indexBadge(index: index, selected: selected)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(item.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .lineLimit(1)

                        if item.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.accentColor)
                        }

                        if !item.shortcutCode.isEmpty {
                            Text(item.shortcutCode)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(selected ? Color.white.opacity(0.9) : Color.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    (selected ? Color.white : Color.primary).opacity(selected ? 0.18 : 0.06),
                                    in: Capsule()
                                )
                        }
                    }

                    Text(item.content)
                        .font(.system(size: 11.5))
                        .foregroundStyle(selected ? Color.white.opacity(0.82) : Color.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 4)

                if selected || hovered {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary.opacity(0.7))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor : Color.primary.opacity(hovered ? 0.06 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredRowIndex = hovering ? index : (hoveredRowIndex == index ? nil : hoveredRowIndex)
        }
        .accessibilityLabel("\(index < 9 ? "\(index + 1) " : "")\(item.title) \(item.content)")
    }

    private var clipboardContent: some View {
        let items = state.filteredClipboardItems
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                let pinnedCount = items.filter(\.isPinned).count
                Text(pinnedCount > 0 ? "置顶 \(pinnedCount) · 共 \(items.count) 条" : "共 \(items.count) 条记录")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    state.onRefresh?()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("刷新剪贴板")
                .accessibilityLabel("刷新剪贴板")

                Button {
                    state.onClearClipboard?()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                        Text("清空")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(state.clipboardItems.isEmpty ? Color.secondary.opacity(0.4) : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(state.clipboardItems.isEmpty)
                .help("清空未置顶剪贴板记录")
                .accessibilityLabel("清空剪贴板")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            hairlineDivider

            if items.isEmpty {
                emptyStateView(
                    icon: "doc.on.clipboard",
                    title: state.searchQuery.isEmpty ? "暂无剪贴板记录" : "未找到匹配的剪贴板内容",
                    subtitle: state.searchQuery.isEmpty ? "复制文本后会自动出现在这里" : "尝试更换关键词或清空筛选"
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                clipboardRow(index: index, item: item)
                                    .id(index)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    .onChange(of: state.selectedIndex) { _, target in
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
        }
    }

    private func clipboardRow(index: Int, item: ToolboxClipboardItem) -> some View {
        let selected = index == state.selectedIndex
        let hovered = hoveredRowIndex == index
        return HStack(alignment: .center, spacing: 6) {
            Button {
                onCommitRow(item.text)
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    indexBadge(index: index, selected: selected)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.text)
                            .font(.system(size: 12))
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
                            Text(formattedTimestamp(item.copiedAt))
                            Text("·")
                            Text("\(item.text.count) 字")
                            if item.isPinned {
                                Text("· 已置顶")
                            }
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(selected ? Color.white.opacity(0.75) : Color.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 2) {
                Button {
                    state.onPinClipboard?(item.id)
                } label: {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 10.5))
                        .foregroundStyle(
                            selected
                                ? Color.white.opacity(item.isPinned ? 1 : 0.78)
                                : (item.isPinned ? Color.accentColor : Color.secondary)
                        )
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.isPinned ? "取消置顶" : "置顶")
                .accessibilityLabel(item.isPinned ? "取消置顶" : "置顶")

                Button {
                    state.onDeleteClipboard?(item.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10.5))
                        .foregroundStyle(selected ? Color.white.opacity(0.82) : Color.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("删除此条记录")
                .accessibilityLabel("删除")
            }
            .opacity((hovered || selected || item.isPinned) ? 1 : 0.45)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.accentColor : Color.primary.opacity(hovered ? 0.06 : 0))
        )
        .contextMenu {
            Button("插入文本", systemImage: "text.insert") {
                onCommitRow(item.text)
            }
            Button(item.isPinned ? "取消置顶" : "置顶", systemImage: item.isPinned ? "pin.slash" : "pin") {
                state.onPinClipboard?(item.id)
            }
            Button("删除", systemImage: "trash", role: .destructive) {
                state.onDeleteClipboard?(item.id)
            }
            Divider()
            Button("清空未置顶记录", systemImage: "trash.slash") {
                state.onClearClipboard?()
            }
        }
        .onHover { hovering in
            hoveredRowIndex = hovering ? index : (hoveredRowIndex == index ? nil : hoveredRowIndex)
        }
        .accessibilityLabel("\(index < 9 ? "\(index + 1) " : "")\(item.text)")
    }

    private var symbolsContent: some View {
        let entries = state.filteredSymbolEntries
        let hasWideEntries = entries.contains { $0.text.count > 3 }
        let columns = [
            GridItem(
                .adaptive(minimum: hasWideEntries ? 108 : 42, maximum: hasWideEntries ? 176 : 52),
                spacing: 6
            )
        ]

        return VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(ToolboxSymbolCatalog.categories, id: \.self) { category in
                        let active = state.selectedSymbolCategory == category && state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        Button {
                            if !state.searchQuery.isEmpty {
                                state.searchQuery = ""
                            }
                            state.selectedSymbolCategory = category
                            state.selectedIndex = 0
                        } label: {
                            Text(category)
                                .font(.system(size: 11, weight: active ? .semibold : .medium))
                                .foregroundStyle(active ? Color.white : Color.primary.opacity(0.78))
                                .padding(.horizontal, 8)
                                .frame(height: 22)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(active ? Color.accentColor : Color.primary.opacity(0.055))
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }

            hairlineDivider

            if entries.isEmpty {
                emptyStateView(
                    icon: "sparkles",
                    title: "未找到匹配的符号",
                    subtitle: "尝试搜索符号本身或中文名称，如“箭头”、“π”、“赞”"
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(Array(entries.enumerated()), id: \.element.text) { index, entry in
                                symbolCell(index: index, entry: entry, isWide: hasWideEntries || entry.text.count > 3)
                                    .id(index)
                            }
                        }
                        .padding(10)
                    }
                    .onChange(of: state.selectedIndex) { _, target in
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
        }
    }

    private func symbolCell(index: Int, entry: ToolboxSymbolEntry, isWide: Bool) -> some View {
        let selected = index == state.selectedIndex
        let hovered = hoveredRowIndex == index
        return Button {
            onCommitRow(entry.text)
        } label: {
            ZStack(alignment: .topLeading) {
                Text(entry.text)
                    .font(.system(size: isWide ? 12 : 16, weight: .medium))
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, isWide ? 8 : 4)
                    .frame(maxWidth: .infinity, minHeight: isWide ? 34 : 38)

                if index < 9 {
                    Text("\(index + 1)")
                        .font(.system(size: 8.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(selected ? Color.white.opacity(0.75) : Color.secondary.opacity(0.65))
                        .padding(.top, 2.5)
                        .padding(.leading, 4)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        selected
                            ? Color.accentColor
                            : Color.primary.opacity(hovered ? 0.08 : 0.035)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(entry.label) · \(entry.text)")
        .onHover { hovering in
            hoveredRowIndex = hovering ? index : (hoveredRowIndex == index ? nil : hoveredRowIndex)
        }
        .accessibilityLabel("\(index < 9 ? "\(index + 1) " : "")\(entry.label) \(entry.text)")
    }

    private func indexBadge(index: Int, selected: Bool) -> some View {
        Group {
            if index < 9 {
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(selected ? Color.white.opacity(0.9) : Color.secondary)
                    .frame(width: 18, height: 18)
                    .background(
                        (selected ? Color.white : Color.primary).opacity(selected ? 0.18 : 0.06),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
            } else {
                Text("·")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(selected ? Color.white.opacity(0.65) : Color.secondary.opacity(0.5))
                    .frame(width: 18, height: 18)
            }
        }
    }

    private func emptyStateView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.secondary.opacity(0.7))
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footerBar: some View {
        HStack(spacing: 8) {
            Text("↑↓ 选择 · Return/1–9 上屏 · Esc 关闭")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            let count = state.currentRowCount
            if count > 0 {
                let current = min(max(state.selectedIndex, 0), count - 1) + 1
                Text("\(current)/\(count)")
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
    }

    @MainActor
    private func formattedTimestamp(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 {
            return "刚刚"
        }
        if elapsed < 3600 {
            return "\(Int(elapsed / 60)) 分钟前"
        }
        if Calendar.current.isDateInToday(date) {
            return Self.timeFormatter.string(from: date)
        }
        return Self.dateFormatter.string(from: date)
    }
}
